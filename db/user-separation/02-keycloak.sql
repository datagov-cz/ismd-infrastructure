-- ============================================================================
-- Keycloak: dedicated role for keycloak_db
-- Run as ismdadmin in pgAdmin. Idempotent. Do this in a quiet window —
-- REASSIGN OWNED briefly locks Keycloak's tables.
-- Replace <<KEYCLOAK_DB_PASSWORD>> with the value you stored in Key Vault.
-- ============================================================================

-- --- Part A: connected to ANY database ---------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ismd_keycloak_app') THEN
    CREATE ROLE ismd_keycloak_app LOGIN PASSWORD '<<KEYCLOAK_DB_PASSWORD>>';
  END IF;
END
$$;

GRANT ismd_keycloak_app TO ismdadmin;

REVOKE CONNECT ON DATABASE keycloak_db FROM PUBLIC;
GRANT  CONNECT ON DATABASE keycloak_db TO ismd_keycloak_app;
ALTER  DATABASE keycloak_db OWNER TO ismd_keycloak_app;

-- --- Part B: RECONNECT the query tool to  keycloak_db  before running this ----

REASSIGN OWNED BY ismdadmin TO ismd_keycloak_app;   -- all keycloak objects -> role

-- Keycloak uses the public schema. Reassign handled existing tables; grant the
-- role rights to create new ones (PG16: PUBLIC no longer has CREATE on public).
GRANT USAGE, CREATE ON SCHEMA public TO ismd_keycloak_app;
-- Optional (cleanest, DB is single-tenant): make the role own the schema too.
-- ALTER SCHEMA public OWNER TO ismd_keycloak_app;
