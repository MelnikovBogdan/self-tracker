import 'dotenv/config';
import { buildApp } from './app.js';
import { activityMigrations, registeredActivities } from './activity-modules.js';
import { baseMigrations, runMigrations } from './db/migrate.js';
import { createPool } from './db/pool.js';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const database = createPool(databaseUrl);
await runMigrations(database, [...await baseMigrations(), ...activityMigrations(registeredActivities)]);
const app = await buildApp(database, registeredActivities);
app.addHook('onClose', async () => database.end());

const port = Number(process.env.API_PORT ?? 3000);
const host = process.env.API_HOST ?? '127.0.0.1';
await app.listen({ port, host });
process.stdout.write(`API listening on http://${host}:${port}\n`);
