import pg from 'pg';

export type Database = pg.Pool;

export function createPool(databaseUrl: string): Database {
  return new pg.Pool({ connectionString: databaseUrl, max: 10 });
}
