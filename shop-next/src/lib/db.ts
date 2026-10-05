import "server-only";
import { Pool } from "pg";

const globalForDb = globalThis as unknown as { pool?: Pool };

function createPool(): Pool {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("DATABASE_URL is not set. Check .env.local in the shop-next folder.");
  }
  return new Pool({ connectionString });
}

export const pool = globalForDb.pool ?? createPool();

if (process.env.NODE_ENV !== "production") {
  globalForDb.pool = pool;
}
