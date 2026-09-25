import type { FastifyInstance } from 'fastify';
import type { Migration } from './db/migrate.js';

export type ActivityModule = {
  id: string;
  migrations: Migration[];
  register: (app: FastifyInstance) => Promise<void> | void;
};

export function validateActivityModules(modules: ActivityModule[]): void {
  const ids = new Set<string>();
  const migrations = new Set<string>();
  for (const module of modules) {
    if (!/^[a-z][a-z0-9-]*$/.test(module.id)) {
      throw new Error(`Invalid activity module ID: ${module.id}`);
    }
    if (ids.has(module.id)) throw new Error(`Duplicate activity module ID: ${module.id}`);
    ids.add(module.id);
    for (const migration of module.migrations) {
      const key = `${module.id}:${migration.id}`;
      if (migrations.has(key)) throw new Error(`Duplicate activity migration: ${key}`);
      migrations.add(key);
    }
  }
}

export function activityMigrations(modules: ActivityModule[]): Migration[] {
  return modules.flatMap((module) =>
    module.migrations.map((migration) => ({
      id: `activity:${module.id}:${migration.id}`,
      sql: migration.sql,
    })),
  );
}

export const registeredActivities: ActivityModule[] = [];
