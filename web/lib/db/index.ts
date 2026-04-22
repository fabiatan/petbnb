import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

// Connection string for Drizzle. Local dev defaults to the Supabase CLI instance.
// In production this should be the Supabase pooler URL. Not used yet in Phase 1a;
// exposed for Phase 1c+ when we start doing SELECTs via Drizzle (e.g. listing queries).
const connectionString =
  process.env.DATABASE_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const client = postgres(connectionString, {
  prepare: false, // Required when connecting via Supabase pooler; harmless locally
});

export const db = drizzle(client, { schema });
export type DB = typeof db;
