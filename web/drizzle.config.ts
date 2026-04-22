import { defineConfig } from "drizzle-kit";

// Drizzle is used ONLY for schema-as-code (TypeScript types) and ad-hoc
// introspection via drizzle-kit studio. Supabase CLI migrations are the
// single source of truth for schema changes. Do not run `drizzle-kit push`.
export default defineConfig({
  schema: "./lib/db/schema.ts",
  dialect: "postgresql",
  dbCredentials: {
    url:
      process.env.DATABASE_URL ??
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  },
  verbose: true,
  strict: true,
});
