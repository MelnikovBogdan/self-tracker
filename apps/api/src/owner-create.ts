import 'dotenv/config';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import argon2 from 'argon2';
import { createPool } from './db/pool.js';
import { baseMigrations, runMigrations } from './db/migrate.js';

async function readPassword(label: string): Promise<string> {
  if (!stdin.isTTY || !stdout.isTTY) throw new Error('An interactive terminal is required');
  stdout.write(label);
  stdin.setRawMode(true);
  stdin.resume();
  return new Promise((resolve, reject) => {
    let password = '';
    const finish = (error?: Error) => {
      stdin.off('data', onData);
      stdin.setRawMode(false);
      stdin.pause();
      stdout.write('\n');
      if (error) reject(error);
      else resolve(password);
    };
    const onData = (chunk: Buffer) => {
      for (const character of chunk.toString('utf8')) {
        if (character === '\r' || character === '\n') return finish();
        if (character === '\u0003') return finish(new Error('Cancelled'));
        if (character === '\u007f') password = password.slice(0, -1);
        else if (character >= ' ') password += character;
      }
    };
    stdin.on('data', onData);
  });
}

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) throw new Error('DATABASE_URL is required');
  if (!stdin.isTTY) throw new Error('An interactive terminal is required');

  const database = createPool(databaseUrl);
  try {
    await runMigrations(database, await baseMigrations());
    const existing = await database.query('SELECT 1 FROM owner LIMIT 1');
    if (existing.rowCount) throw new Error('Owner already exists');

    const prompt = createInterface({ input: stdin, output: stdout });
    const answer = await prompt.question('Login [owner]: ');
    prompt.close();
    const username = answer.trim() || 'owner';
    if (username.length > 120) throw new Error('Login is too long');
    const password = await readPassword('Password: ');
    const confirmation = await readPassword('Repeat password: ');
    if (password !== confirmation) throw new Error('Passwords do not match');
    if (password.length < 12) throw new Error('Password must have at least 12 characters');

    const hash = await argon2.hash(password, { type: argon2.argon2id });
    const client = await database.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        'INSERT INTO owner (id, username, password_hash) VALUES (1, $1, $2)',
        [username, hash],
      );
      await client.query(
        'INSERT INTO profile (owner_id, display_name, revision) VALUES (1, $1, 1)',
        [username],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    stdout.write(`Owner "${username}" created\n`);
  } finally {
    await database.end();
  }
}

await main();
