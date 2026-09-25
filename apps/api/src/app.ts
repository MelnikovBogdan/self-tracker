import argon2 from 'argon2';
import swagger from '@fastify/swagger';
import Fastify, { type FastifyError, type FastifyInstance, type preHandlerHookHandler } from 'fastify';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { Database } from './db/pool.js';
import { type ActivityModule, validateActivityModules } from './activity-modules.js';

declare module 'fastify' {
  interface FastifyRequest {
    ownerId?: number;
    sessionId?: string;
  }
}

type ProfileRow = { display_name: string; revision: number };

const errorSchema = {
  type: 'object',
  required: ['error'],
  properties: { error: { type: 'string' } },
} as const;

const profileSchema = {
  type: 'object',
  required: ['displayName', 'revision'],
  properties: {
    displayName: { type: 'string' },
    revision: { type: 'integer' },
  },
} as const;

function profile(row: ProfileRow) {
  return { displayName: row.display_name, revision: row.revision };
}

function tokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export async function buildApp(database: Database, modules: ActivityModule[] = []): Promise<FastifyInstance> {
  validateActivityModules(modules);
  const app = Fastify({ logger: false });
  const dummyHash = await argon2.hash('nonexistent-owner-password', { type: argon2.argon2id });

  await app.register(swagger, {
    openapi: {
      info: { title: 'Self Tracker API', version: '0.1.0' },
      components: {
        securitySchemes: {
          bearerAuth: { type: 'http', scheme: 'bearer' },
        },
      },
    },
  });

  app.setErrorHandler((error: FastifyError, _request, reply) => {
    if (error.validation) {
      reply.code(400).send({ error: 'Invalid request' });
      return;
    }
    app.log.error(error);
    reply.code(500).send({ error: 'Internal server error' });
  });

  const authenticate: preHandlerHookHandler = async (request, reply) => {
    const authorization = request.headers.authorization;
    if (!authorization?.startsWith('Bearer ')) {
      reply.code(401).send({ error: 'Unauthorized' });
      return;
    }
    const token = authorization.slice('Bearer '.length);
    const result = await database.query<{ id: string; owner_id: number }>(
      'SELECT id, owner_id FROM sessions WHERE token_hash = $1 AND expires_at > now()',
      [tokenHash(token)],
    );
    if (!result.rows[0]) {
      reply.code(401).send({ error: 'Unauthorized' });
      return;
    }
    request.ownerId = result.rows[0].owner_id;
    request.sessionId = result.rows[0].id;
  };

  app.get('/health', { schema: { hide: true } }, async () => ({ status: 'ok' }));
  app.get('/openapi.json', { schema: { hide: true } }, async () => app.swagger());

  app.post<{ Body: { username: string; password: string } }>('/v1/auth/login', {
    schema: {
      tags: ['auth'],
      body: {
        type: 'object',
        required: ['username', 'password'],
        additionalProperties: false,
        properties: {
          username: { type: 'string', minLength: 1, maxLength: 120 },
          password: { type: 'string', minLength: 1, maxLength: 1024 },
        },
      },
      response: {
        200: {
          type: 'object',
          required: ['token', 'expiresAt'],
          properties: { token: { type: 'string' }, expiresAt: { type: 'string' } },
        },
        401: errorSchema,
      },
    },
  }, async (request, reply) => {
    const result = await database.query<{ id: number; password_hash: string }>(
      'SELECT id, password_hash FROM owner WHERE username = $1',
      [request.body.username],
    );
    const owner = result.rows[0];
    const valid = await argon2.verify(owner?.password_hash ?? dummyHash, request.body.password);
    if (!owner || !valid) return reply.code(401).send({ error: 'Invalid credentials' });

    const token = randomBytes(32).toString('base64url');
    const sessionId = randomUUID();
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await database.query(
      'INSERT INTO sessions (id, owner_id, token_hash, expires_at) VALUES ($1, $2, $3, $4)',
      [sessionId, owner.id, tokenHash(token), expiresAt],
    );
    return { token, expiresAt: expiresAt.toISOString() };
  });

  app.get('/v1/auth/session', {
    preHandler: authenticate,
    schema: {
      tags: ['auth'], security: [{ bearerAuth: [] }],
      response: {
        200: { type: 'object', required: ['username'], properties: { username: { type: 'string' } } },
        401: errorSchema,
      },
    },
  }, async (request) => {
    const result = await database.query<{ username: string }>('SELECT username FROM owner WHERE id = $1', [request.ownerId]);
    return { username: result.rows[0].username };
  });

  app.post('/v1/auth/logout', {
    preHandler: authenticate,
    schema: {
      tags: ['auth'], security: [{ bearerAuth: [] }],
      response: { 204: { type: 'null' }, 401: errorSchema },
    },
  }, async (request, reply) => {
    await database.query('DELETE FROM sessions WHERE id = $1', [request.sessionId]);
    return reply.code(204).send();
  });

  app.get('/v1/profile', {
    preHandler: authenticate,
    schema: {
      tags: ['profile'], security: [{ bearerAuth: [] }],
      response: { 200: profileSchema, 401: errorSchema },
    },
  }, async (request) => {
    const result = await database.query<ProfileRow>(
      'SELECT display_name, revision FROM profile WHERE owner_id = $1',
      [request.ownerId],
    );
    return profile(result.rows[0]);
  });

  app.put<{ Body: { displayName: string; revision: number } }>('/v1/profile', {
    preHandler: authenticate,
    schema: {
      tags: ['profile'], security: [{ bearerAuth: [] }],
      body: {
        type: 'object',
        required: ['displayName', 'revision'],
        additionalProperties: false,
        properties: {
          displayName: { type: 'string', minLength: 1, maxLength: 120 },
          revision: { type: 'integer', minimum: 1 },
        },
      },
      response: {
        200: profileSchema,
        400: errorSchema,
        401: errorSchema,
        409: {
          type: 'object',
          required: ['error', 'profile'],
          properties: { error: { type: 'string' }, profile: profileSchema },
        },
      },
    },
  }, async (request, reply) => {
    const displayName = request.body.displayName.trim();
    if (!displayName) return reply.code(400).send({ error: 'Display name is required' });
    const updated = await database.query<ProfileRow>(
      `UPDATE profile SET display_name = $1, revision = revision + 1, updated_at = now()
       WHERE owner_id = $2 AND revision = $3 RETURNING display_name, revision`,
      [displayName, request.ownerId, request.body.revision],
    );
    if (updated.rows[0]) return profile(updated.rows[0]);
    const current = await database.query<ProfileRow>(
      'SELECT display_name, revision FROM profile WHERE owner_id = $1',
      [request.ownerId],
    );
    return reply.code(409).send({ error: 'Profile was changed on another device', profile: profile(current.rows[0]) });
  });

  for (const module of modules) {
    await app.register(async (scope) => {
      scope.addHook('preHandler', authenticate);
      await module.register(scope);
    }, { prefix: `/v1/activities/${module.id}` });
  }

  return app;
}
