import pg from "pg";

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error("DATABASE_URL is not set. Check the .env file in the server folder.");
}

export const pool = new pg.Pool({ connectionString });
