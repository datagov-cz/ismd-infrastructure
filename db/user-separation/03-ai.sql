-- ============================================================================
-- ismd-ai: dedicated role for the ismd_ai database
-- Run as ismdadmin in pgAdmin. Idempotent.
-- Replace <<AI_DB_PASSWORD>> with the value you stored in Key Vault.
-- NOTE: role is ismd_ai_app (the DATABASE is ismd_ai — different namespaces).
-- Confirm the ai app's schema: this assumes `public`. If ismd-ai uses a named
-- schema, add the same ALTER SCHEMA / GRANT lines as 01-tool.sql for it.
-- ============================================================================

-- --- Part A: connected to ANY database ---------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ismd_ai_app') THEN
    CREATE ROLE ismd_ai_app LOGIN PASSWORD '<<AI_DB_PASSWORD>>';
  END IF;
END
$$;

GRANT ismd_ai_app TO ismdadmin;

REVOKE CONNECT ON DATABASE ismd_ai FROM PUBLIC;
GRANT  CONNECT ON DATABASE ismd_ai TO ismd_ai_app;
ALTER  DATABASE ismd_ai OWNER TO ismd_ai_app;

-- --- Part B: RECONNECT the query tool to  ismd_ai  before running this --------

REASSIGN OWNED BY ismdadmin TO ismd_ai_app;

GRANT USAGE, CREATE ON SCHEMA public TO ismd_ai_app;
-- ALTER SCHEMA public OWNER TO ismd_ai_app;   -- optional
