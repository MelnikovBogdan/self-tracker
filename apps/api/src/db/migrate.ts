import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import type { Database } from './pool.js';
import { createPool } from './pool.js';

export type Migration = { id: string; sql: string };

export async function baseMigrations(): Promise<Migration[]> {
  const path = fileURLToPath(new URL('../../migrations/001_init.sql', import.meta.url));
  return [{ id: '001_init', sql: await readFile(path, 'utf8') }];
}

export async function runMigrations(database: Database, migrations: Migration[]): Promise<void> {
  await database.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);
  for (const migration of migrations) {
    const client = await database.connect();
    try {
      await client.query('BEGIN');
      const applied = await client.query('SELECT 1 FROM schema_migrations WHERE id = $1', [migration.id]);
      if (applied.rowCount === 0) {
        await client.query(migration.sql);
        await client.query('INSERT INTO schema_migrations (id) VALUES ($1)', [migration.id]);
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) throw new Error('DATABASE_URL is required');
  const database = createPool(databaseUrl);
  try {
    await runMigrations(database, await baseMigrations());
    process.stdout.write('Migrations applied\n');
  } finally {
    await database.end();
  }
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  await main();
}
