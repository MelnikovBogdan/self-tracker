import { randomUUID } from 'node:crypto';
import type { FastifyInstance, preHandlerHookHandler } from 'fastify';
import type { Database } from './db/pool.js';

type EventRow = {
  id: string;
  date: string;
  start_time: string;
  end_time: string;
  title: string;
  description: string;
  color: string;
  revision: number;
};

type EventInput = {
  date: string;
  startTime: string;
  endTime: string;
  title: string;
  description?: string;
  color?: string;
};

type UpdateInput = EventInput & { revision: number };

const errorSchema = { type: 'object', required: ['error'], properties: { error: { type: 'string' } } } as const;
const eventSchema = {
  type: 'object',
  required: ['id', 'date', 'startTime', 'endTime', 'title', 'description', 'color', 'revision'],
  properties: {
    id: { type: 'string', format: 'uuid' },
    date: { type: 'string' },
    startTime: { type: 'string' },
    endTime: { type: 'string' },
    title: { type: 'string' },
    description: { type: 'string' },
    color: { type: 'string' },
    revision: { type: 'integer' },
  },
} as const;
const conflictSchema = {
  type: 'object', required: ['error', 'event'],
  properties: { error: { type: 'string' }, event: eventSchema },
} as const;
const bodySchema = {
  type: 'object',
  required: ['date', 'startTime', 'endTime', 'title'],
  additionalProperties: false,
  properties: {
    date: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
    startTime: { type: 'string', pattern: '^([01]\\d|2[0-3]):[0-5]\\d$' },
    endTime: { type: 'string', pattern: '^([01]\\d|2[0-3]):[0-5]\\d$' },
    title: { type: 'string', minLength: 1, maxLength: 120 },
    description: { type: 'string', maxLength: 2000 },
    color: { type: 'string', enum: ['terracotta', 'sage', 'slate', 'ochre', 'neutral'] },
  },
} as const;

const selectColumns = `id, to_char(event_date, 'YYYY-MM-DD') AS date,
  to_char(start_time, 'HH24:MI') AS start_time,
  to_char(end_time, 'HH24:MI') AS end_time,
  title, description, color, revision`;

function output(row: EventRow) {
  return {
    id: row.id, date: row.date, startTime: row.start_time, endTime: row.end_time,
    title: row.title, description: row.description, color: row.color, revision: row.revision,
  };
}

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() + 1 === month && date.getUTCDate() === day;
}

function validInput(input: EventInput): string | null {
  if (!validDate(input.date)) return 'Invalid date';
  if (input.startTime >= input.endTime) return 'End time must be after start time';
  if (!input.title.trim()) return 'Title is required';
  return null;
}

export async function registerEventRoutes(
  app: FastifyInstance, database: Database, authenticate: preHandlerHookHandler,
): Promise<void> {
  app.get<{ Querystring: { date: string } }>('/v1/events', {
    preHandler: authenticate,
    schema: {
      tags: ['events'], security: [{ bearerAuth: [] }],
      querystring: { type: 'object', required: ['date'], additionalProperties: false,
        properties: { date: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' } } },
      response: { 200: { type: 'object', required: ['events'], properties: { events: { type: 'array', items: eventSchema } } },
        400: errorSchema, 401: errorSchema },
    },
  }, async (request, reply) => {
    if (!validDate(request.query.date)) return reply.code(400).send({ error: 'Invalid date' });
    const result = await database.query<EventRow>(
      `SELECT ${selectColumns} FROM calendar_events
       WHERE owner_id = $1 AND event_date = $2 ORDER BY start_time, id`,
      [request.ownerId, request.query.date],
    );
    return { events: result.rows.map(output) };
  });

  app.get<{ Querystring: { month: string } }>('/v1/events/days', {
    preHandler: authenticate,
    schema: {
      tags: ['events'], security: [{ bearerAuth: [] }],
      querystring: { type: 'object', required: ['month'], additionalProperties: false,
        properties: { month: { type: 'string', pattern: '^\\d{4}-(0[1-9]|1[0-2])$' } } },
      response: { 200: { type: 'object', required: ['dates'], properties: { dates: { type: 'array', items: { type: 'string' } } } },
        400: errorSchema, 401: errorSchema },
    },
  }, async (request) => {
    const from = `${request.query.month}-01`;
    const result = await database.query<{ date: string }>(
      `SELECT DISTINCT to_char(event_date, 'YYYY-MM-DD') AS date FROM calendar_events
       WHERE owner_id = $1 AND event_date >= $2::date AND event_date < ($2::date + interval '1 month')
       ORDER BY date`,
      [request.ownerId, from],
    );
    return { dates: result.rows.map((row) => row.date) };
  });

  app.post<{ Body: EventInput }>('/v1/events', {
    preHandler: authenticate,
    schema: {
      tags: ['events'], security: [{ bearerAuth: [] }], body: bodySchema,
      response: { 201: eventSchema, 400: errorSchema, 401: errorSchema },
    },
  }, async (request, reply) => {
    const error = validInput(request.body);
    if (error) return reply.code(400).send({ error });
    const input = request.body;
    const result = await database.query<EventRow>(
      `INSERT INTO calendar_events (id, owner_id, event_date, start_time, end_time, title, description, color)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING ${selectColumns}`,
      [randomUUID(), request.ownerId, input.date, input.startTime, input.endTime,
        input.title.trim(), input.description?.trim() ?? '', input.color ?? 'neutral'],
    );
    return reply.code(201).send(output(result.rows[0]));
  });

  app.put<{ Params: { id: string }; Body: UpdateInput }>('/v1/events/:id', {
    preHandler: authenticate,
    schema: {
      tags: ['events'], security: [{ bearerAuth: [] }],
      params: { type: 'object', required: ['id'], properties: { id: { type: 'string', format: 'uuid' } } },
      body: { ...bodySchema, required: [...bodySchema.required, 'revision'],
        properties: { ...bodySchema.properties, revision: { type: 'integer', minimum: 1 } } },
      response: { 200: eventSchema, 400: errorSchema, 401: errorSchema, 404: errorSchema, 409: conflictSchema },
    },
  }, async (request, reply) => {
    const error = validInput(request.body);
    if (error) return reply.code(400).send({ error });
    const input = request.body;
    const result = await database.query<EventRow>(
      `UPDATE calendar_events SET event_date = $1, start_time = $2, end_time = $3, title = $4,
       description = $5, color = $6, revision = revision + 1, updated_at = now()
       WHERE id = $7 AND owner_id = $8 AND revision = $9 RETURNING ${selectColumns}`,
      [input.date, input.startTime, input.endTime, input.title.trim(), input.description?.trim() ?? '',
        input.color ?? 'neutral', request.params.id, request.ownerId, input.revision],
    );
    if (result.rows[0]) return output(result.rows[0]);
    const current = await database.query<EventRow>(
      `SELECT ${selectColumns} FROM calendar_events WHERE id = $1 AND owner_id = $2`,
      [request.params.id, request.ownerId],
    );
    if (!current.rows[0]) return reply.code(404).send({ error: 'Event not found' });
    return reply.code(409).send({ error: 'Event changed on another device', event: output(current.rows[0]) });
  });

  app.delete<{ Params: { id: string }; Body: { revision: number } }>('/v1/events/:id', {
    preHandler: authenticate,
    schema: {
      tags: ['events'], security: [{ bearerAuth: [] }],
      params: { type: 'object', required: ['id'], properties: { id: { type: 'string', format: 'uuid' } } },
      body: { type: 'object', required: ['revision'], additionalProperties: false,
        properties: { revision: { type: 'integer', minimum: 1 } } },
      response: { 204: { type: 'null' }, 400: errorSchema, 401: errorSchema,
        404: errorSchema, 409: conflictSchema },
    },
  }, async (request, reply) => {
    const deleted = await database.query(
      'DELETE FROM calendar_events WHERE id = $1 AND owner_id = $2 AND revision = $3',
      [request.params.id, request.ownerId, request.body.revision],
    );
    if (deleted.rowCount) return reply.code(204).send();
    const current = await database.query<EventRow>(
      `SELECT ${selectColumns} FROM calendar_events WHERE id = $1 AND owner_id = $2`,
      [request.params.id, request.ownerId],
    );
    if (!current.rows[0]) return reply.code(404).send({ error: 'Event not found' });
    return reply.code(409).send({ error: 'Event changed on another device', event: output(current.rows[0]) });
  });
}
