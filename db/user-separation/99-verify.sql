-- ============================================================================
-- Verification. Run as ismdadmin (connected to any database).
-- ============================================================================

-- 1. All three app roles exist and can log in.
SELECT rolname, rolcanlogin
FROM pg_roles
WHERE rolname LIKE 'ismd_%_app'
ORDER BY rolname;

-- 2. PUBLIC can no longer CONNECT to any of the three databases (expect all false).
SELECT datname,
       has_database_privilege('public', datname, 'CONNECT') AS public_can_connect
FROM pg_database
WHERE datname IN ('ismd_tool_db', 'keycloak_db', 'ismd_ai')
ORDER BY datname;

-- 3. Each app role reaches ONLY its own database (expect: own = true, others = false).
SELECT 'ismd_tool_app'     AS role,
       has_database_privilege('ismd_tool_app',     'ismd_tool_db', 'CONNECT') AS own_tool,
       has_database_privilege('ismd_tool_app',     'keycloak_db',  'CONNECT') AS other_kc,
       has_database_privilege('ismd_tool_app',     'ismd_ai',      'CONNECT') AS other_ai
UNION ALL
SELECT 'ismd_keycloak_app',
       has_database_privilege('ismd_keycloak_app', 'ismd_tool_db', 'CONNECT'),
       has_database_privilege('ismd_keycloak_app', 'keycloak_db',  'CONNECT'),
       has_database_privilege('ismd_keycloak_app', 'ismd_ai',      'CONNECT')
UNION ALL
SELECT 'ismd_ai_app',
       has_database_privilege('ismd_ai_app',       'ismd_tool_db', 'CONNECT'),
       has_database_privilege('ismd_ai_app',       'keycloak_db',  'CONNECT'),
       has_database_privilege('ismd_ai_app',       'ismd_ai',      'CONNECT');

-- 4. Database ownership moved off ismdadmin.
SELECT d.datname, pg_get_userbyid(d.datdba) AS owner
FROM pg_database d
WHERE d.datname IN ('ismd_tool_db', 'keycloak_db', 'ismd_ai')
ORDER BY d.datname;

-- 5. FINAL manual check the queries above can't prove: open a NEW pgAdmin
--    connection authenticating AS each new role and confirm it can query its
--    own DB and is REFUSED when connecting to the other two.
