-- ============================================================================
-- Tool backend: dedicated role for ismd_tool_db
-- Run as ismdadmin in pgAdmin. Idempotent — safe to re-run.
-- Replace <<TOOL_DB_PASSWORD>> with the value you stored in Key Vault.
-- ============================================================================

-- --- Part A: connected to ANY database (role creation is server-global) ------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ismd_tool_app') THEN
    CREATE ROLE ismd_tool_app LOGIN PASSWORD '<<TOOL_DB_PASSWORD>>';
  END IF;
END
$$;

-- ismdadmin must be a MEMBER of the new role to transfer ownership to it.
GRANT ismd_tool_app TO ismdadmin;

-- Lock the database down to just this role.
REVOKE CONNECT ON DATABASE ismd_tool_db FROM PUBLIC;
GRANT  CONNECT ON DATABASE ismd_tool_db TO ismd_tool_app;
ALTER  DATABASE ismd_tool_db OWNER TO ismd_tool_app;

-- --- Part B: RECONNECT the query tool to  ismd_tool_db  before running this --
-- (REASSIGN OWNED and schema grants act on the CURRENT database only.)

REASSIGN OWNED BY ismdadmin TO ismd_tool_app;   -- all tool objects -> app role

ALTER SCHEMA ismd_schema OWNER TO ismd_tool_app;  -- Liquibase default-schema
GRANT ALL ON SCHEMA ismd_schema TO ismd_tool_app;
