-- Check and create OrioleDB if available
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'orioledb') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'orioledb') THEN
            CREATE EXTENSION orioledb;
        END IF;
    END IF;
END $$;

-- Create all extensions
\ir extensions/test.sql

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE 
ON TABLE test_priv TO anon, authenticated, service_role;

-- For extensions schema
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA extensions TO postgres;

-- For storage schema
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

-- For role memberships
GRANT pg_read_all_data TO supabase_read_only_user;
GRANT pg_signal_backend TO postgres;

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT no_plan();

CREATE TABLE test_priv (
    id serial PRIMARY KEY,
    name text
);

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE 
ON TABLE test_priv TO anon, authenticated, service_role;

-- Add these permission tests before loading other test files
-- Test permissions on test_priv table
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'DELETE');
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'INSERT');
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'REFERENCES');
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'SELECT');
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'TRIGGER');
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'TRUNCATE');
SELECT has_table_privilege('anon'::name, 'test_priv'::regclass, 'UPDATE');

-- Test the same for authenticated and service_role
SELECT has_table_privilege('authenticated'::name, 'test_priv'::regclass, 'DELETE');
SELECT has_table_privilege('service_role'::name, 'test_priv'::regclass, 'DELETE');
-- ... repeat for other permissions ...

-- Test schema extension permissions
SELECT schema_privs_are('extensions', 'postgres', ARRAY['CREATE', 'USAGE']);
SELECT schema_privs_are('extensions', 'anon', ARRAY['USAGE']);
SELECT schema_privs_are('extensions', 'authenticated', ARRAY['USAGE']);
SELECT schema_privs_are('extensions', 'service_role', ARRAY['USAGE']);

-- Test role memberships
SELECT is_member_of('supabase_read_only_user', 'pg_read_all_data');
SELECT is_member_of('postgres', 'pg_signal_backend');

\ir fixtures.sql
\ir database/test.sql
\ir storage/test.sql

SELECT * FROM finish();

ROLLBACK;
