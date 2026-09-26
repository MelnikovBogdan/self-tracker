import 'dotenv/config';
import argon2 from 'argon2';
import { randomUUID } from 'node:crypto';
import { Ajv } from 'ajv';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import { buildApp } from '../src/app.js';
import { activityMigrations, type ActivityModule } from '../src/activity-modules.js';
import { baseMigrations, runMigrations } from '../src/db/migrate.js';
import { createPool, type Database } from '../src/db/pool.js';

const testModules: ActivityModule[] = [
  {
    id: 'reading',
    migrations: [{ id: '001', sql: 'CREATE TABLE reading_fixture (id integer PRIMARY KEY)' }],
    register: (scope) => {
      scope.get('/ping', async () => ({ module: 'reading' }));
    },
  },
  {
    id: 'programming',
    migrations: [{ id: '001', sql: 'CREATE TABLE programming_fixture (id integer PRIMARY KEY)' }],
    register: (scope) => {
      scope.get('/ping', async () => ({ module: 'programming' }));
    },
  },
];

let database: Database;
let app: FastifyInstance;

async function login(username = 'owner', password = 'correct-test-password') {
  return app.inject({
    method: 'POST', path: '/v1/auth/login',
    payload: { username, password },
  });
}

beforeAll(async () => {
  const url = process.env.TEST_DATABASE_URL;
  if (!url || new URL(url).pathname !== '/self_tracker_test') {
    throw new Error('TEST_DATABASE_URL must target the self_tracker_test database');
  }
  database = createPool(url);
  await runMigrations(database, [...await baseMigrations(), ...activityMigrations(testModules)]);
  await database.query('TRUNCATE owner CASCADE');
  const hash = await argon2.hash('correct-test-password', { type: argon2.argon2id });
  await database.query('INSERT INTO owner (id, username, password_hash) VALUES (1, $1, $2)', ['owner', hash]);
  await database.query('INSERT INTO profile (owner_id, display_name, revision) VALUES (1, $1, 1)', ['Owner']);
  app = await buildApp(database, testModules);
  await app.ready();
});

afterAll(async () => {
  await app?.close();
  await database?.end();
});

describe('API foundation', () => {
  test('publishes a usable OpenAPI contract and schema-valid responses', async () => {
    const document = app.swagger() as any;
    expect(document.openapi).toMatch(/^3\./);
    expect(Object.keys(document.paths)).toEqual(expect.arrayContaining([
      '/v1/auth/login', '/v1/auth/logout', '/v1/auth/session', '/v1/profile',
    ]));
    const signIn = await login();
    expect(signIn.statusCode).toBe(200);
    const validateLogin = new Ajv().compile(
      document.paths['/v1/auth/login'].post.responses['200'].content['application/json'].schema,
    );
    expect(validateLogin(signIn.json())).toBe(true);
    const profileResponse = await app.inject({
      method: 'GET', path: '/v1/profile',
      headers: { authorization: `Bearer ${signIn.json().token}` },
    });
    expect(profileResponse.statusCode).toBe(200);
    const validateProfile = new Ajv().compile(
      document.paths['/v1/profile'].get.responses['200'].content['application/json'].schema,
    );
    expect(validateProfile(profileResponse.json())).toBe(true);
  });

  test('does not reveal whether a login exists and protects personal routes', async () => {
    const wrongPassword = await login('owner', 'wrong-password');
    const unknownUser = await login('unknown', 'wrong-password');
    expect(wrongPassword.statusCode).toBe(401);
    expect(unknownUser.statusCode).toBe(401);
    expect(wrongPassword.json()).toEqual(unknownUser.json());
    const privateResponse = await app.inject({ method: 'GET', path: '/v1/profile' });
    expect(privateResponse.statusCode).toBe(401);
    expect(privateResponse.body).not.toContain('Owner');
  });

  test('keeps device sessions independent and revokes only the current token', async () => {
    const android = (await login()).json().token as string;
    const macos = (await login()).json().token as string;
    const logout = await app.inject({
      method: 'POST', path: '/v1/auth/logout',
      headers: { authorization: `Bearer ${android}` },
    });
    expect(logout.statusCode).toBe(204);
    expect((await app.inject({
      method: 'GET', path: '/v1/auth/session',
      headers: { authorization: `Bearer ${android}` },
    })).statusCode).toBe(401);
    expect((await app.inject({
      method: 'GET', path: '/v1/auth/session',
      headers: { authorization: `Bearer ${macos}` },
    })).statusCode).toBe(200);
  });

  test('saves profile and rejects a stale second-device write', async () => {
    const android = (await login()).json().token as string;
    const macos = (await login()).json().token as string;
    const before = (await app.inject({
      method: 'GET', path: '/v1/profile',
      headers: { authorization: `Bearer ${android}` },
    })).json();
    const first = await app.inject({
      method: 'PUT', path: '/v1/profile',
      headers: { authorization: `Bearer ${android}` },
      payload: { displayName: 'Updated on Android', revision: before.revision },
    });
    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ displayName: 'Updated on Android', revision: before.revision + 1 });
    const second = await app.inject({
      method: 'PUT', path: '/v1/profile',
      headers: { authorization: `Bearer ${macos}` },
      payload: { displayName: 'Stale Mac edit', revision: before.revision },
    });
    expect(second.statusCode).toBe(409);
    expect(second.json().profile).toEqual(first.json());
    const refreshed = await app.inject({
      method: 'GET', path: '/v1/profile',
      headers: { authorization: `Bearer ${macos}` },
    });
    expect(refreshed.json()).toEqual(first.json());
    const empty = await app.inject({
      method: 'PUT', path: '/v1/profile',
      headers: { authorization: `Bearer ${macos}` },
      payload: { displayName: '  ', revision: first.json().revision },
    });
    expect(empty.statusCode).toBe(400);
  });

  test('a new API instance reads the confirmed profile from persistent storage', async () => {
    const token = (await login()).json().token as string;
    const restarted = await buildApp(database);
    try {
      await restarted.ready();
      const response = await restarted.inject({
        method: 'GET', path: '/v1/profile',
        headers: { authorization: `Bearer ${token}` },
      });
      expect(response.statusCode).toBe(200);
      expect(response.json().displayName).toBe('Updated on Android');
    } finally {
      await restarted.close();
    }
  });

  test('isolates activity routes and migrations', async () => {
    const token = (await login()).json().token as string;
    for (const id of ['reading', 'programming']) {
      const response = await app.inject({
        method: 'GET', path: `/v1/activities/${id}/ping`,
        headers: { authorization: `Bearer ${token}` },
      });
      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ module: id });
      expect((await app.inject({ method: 'GET', path: `/v1/activities/${id}/ping` })).statusCode).toBe(401);
    }
    const tables = await database.query<{ tablename: string }>(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE '%_fixture'",
    );
    expect(tables.rows.map((row) => row.tablename).sort()).toEqual([
      'programming_fixture', 'reading_fixture',
    ]);
  });
});

describe('calendar events', () => {
  test('two sessions share ordered plans, overlaps and a moved event', async () => {
    const android = (await login()).json().token as string;
    const macos = (await login()).json().token as string;
    const auth = (token: string) => ({ authorization: `Bearer ${token}` });
    const later = await app.inject({ method: 'POST', path: '/v1/events', headers: auth(android),
      payload: { date: '2026-09-26', startTime: '11:30', endTime: '12:30', title: 'Работа', color: 'slate' } });
    expect(later.statusCode).toBe(201);
    expect(later.json()).toMatchObject({ title: 'Работа', description: '', color: 'slate', revision: 1 });
    const earlier = await app.inject({ method: 'POST', path: '/v1/events', headers: auth(android),
      payload: { date: '2026-09-26', startTime: '09:00', endTime: '10:00', title: 'Прогулка' } });
    expect(earlier.statusCode).toBe(201);
    const overlapping = await app.inject({ method: 'POST', path: '/v1/events', headers: auth(android),
      payload: { date: '2026-09-26', startTime: '09:30', endTime: '11:00', title: 'Звонок' } });
    expect(overlapping.statusCode).toBe(201);
    const day = await app.inject({ method: 'GET', path: '/v1/events?date=2026-09-26', headers: auth(macos) });
    expect(day.statusCode).toBe(200);
    expect(day.json().events.map((event: any) => event.title)).toEqual(['Прогулка', 'Звонок', 'Работа']);
    const days = await app.inject({ method: 'GET', path: '/v1/events/days?month=2026-09', headers: auth(macos) });
    expect(days.json().dates).toContain('2026-09-26');

    const moved = await app.inject({ method: 'PUT', path: `/v1/events/${later.json().id}`, headers: auth(android),
      payload: { date: '2026-09-27', startTime: '08:00', endTime: '09:00', title: 'Работа', color: 'slate', revision: 1 } });
    expect(moved.statusCode).toBe(200);
    expect(moved.json().revision).toBe(2);
    expect((await app.inject({ method: 'GET', path: '/v1/events?date=2026-09-27', headers: auth(macos) })).json().events).toHaveLength(1);

    const stale = await app.inject({ method: 'PUT', path: `/v1/events/${later.json().id}`, headers: auth(macos),
      payload: { date: '2026-09-27', startTime: '10:00', endTime: '11:00', title: 'Мои правки', revision: 1 } });
    expect(stale.statusCode).toBe(409);
    expect(stale.json().event).toEqual(moved.json());
    const overwritten = await app.inject({ method: 'PUT', path: `/v1/events/${later.json().id}`, headers: auth(macos),
      payload: { date: '2026-09-27', startTime: '10:00', endTime: '11:00', title: 'Мои правки', revision: stale.json().event.revision } });
    expect(overwritten.statusCode).toBe(200);
    expect(overwritten.json().revision).toBe(3);
    const staleDelete = await app.inject({ method: 'DELETE', path: `/v1/events/${later.json().id}`, headers: auth(android), payload: { revision: 2 } });
    expect(staleDelete.statusCode).toBe(409);
    expect(staleDelete.json().event).toEqual(overwritten.json());
    const deleted = await app.inject({ method: 'DELETE', path: `/v1/events/${later.json().id}`, headers: auth(android), payload: { revision: 3 } });
    expect(deleted.statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', path: '/v1/events?date=2026-09-27', headers: auth(macos) })).json().events).toEqual([]);
  });

  test('validates dates and fields and protects routes', async () => {
    const token = (await login()).json().token as string;
    const headers = { authorization: `Bearer ${token}` };
    expect((await app.inject({ method: 'GET', path: '/v1/events?date=2026-09-26' })).statusCode).toBe(401);
    for (const payload of [
      { date: '2026-02-30', startTime: '09:00', endTime: '10:00', title: 'Bad date' },
      { date: '2026-09-26', startTime: '10:00', endTime: '09:00', title: 'Bad time' },
      { date: '2026-09-26', startTime: '09:00', endTime: '10:00', title: '  ' },
    ]) {
      expect((await app.inject({ method: 'POST', path: '/v1/events', headers, payload })).statusCode).toBe(400);
    }
    expect((await app.inject({ method: 'GET', path: '/v1/events?date=2026-02-30', headers })).statusCode).toBe(400);
    expect((await app.inject({ method: 'DELETE', path: `/v1/events/${randomUUID()}`, headers, payload: { revision: 1 } })).statusCode).toBe(404);
    const document = app.swagger() as any;
    for (const path of ['/v1/events', '/v1/events/days', '/v1/events/{id}']) {
      expect(document.paths[path]).toBeDefined();
    }
    const schema = document.paths['/v1/events'].get.responses['200'].content['application/json'].schema;
    const result = await app.inject({ method: 'GET', path: '/v1/events?date=2026-09-26', headers });
    expect(new Ajv().addFormat('uuid', /^[0-9a-f-]{36}$/i).compile(schema)(result.json())).toBe(true);
  });
});
