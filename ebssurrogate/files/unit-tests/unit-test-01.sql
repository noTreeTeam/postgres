BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

DO $$ 
DECLARE
    extension_array text[];
    orioledb_available boolean;
    pg_version integer;
BEGIN
    -- Get PostgreSQL version (as integer, e.g., 15 for PostgreSQL 15.x)
    SELECT current_setting('server_version_num')::integer / 10000 INTO pg_version;
    
    -- Check if orioledb is available
    SELECT EXISTS (
        SELECT 1 FROM pg_available_extensions WHERE name = 'orioledb'
    ) INTO orioledb_available;

    -- Base extensions list
    extension_array := ARRAY[
        'plpgsql',
        'pg_stat_statements',
        'pgsodium',
        'pgtap',
        'pg_graphql',
        'pgcrypto',
        'uuid-ossp',
        'supabase_vault'
    ];
    
    -- Add pgjwt if PostgreSQL version is 15 or higher
    IF pg_version >= 15 THEN
        extension_array := array_append(extension_array, 'pgjwt');
    END IF;
    
    -- Add orioledb if available
    IF orioledb_available THEN
        CREATE EXTENSION IF NOT EXISTS orioledb;
        extension_array := array_append(extension_array, 'orioledb');
    END IF;

    -- Set the array as a temporary variable to use in the test
    PERFORM set_config('myapp.extensions', array_to_string(extension_array, ','), false);
END $$;

SELECT plan(8);

SELECT extensions_are(
    string_to_array(current_setting('myapp.extensions'), ',')::text[]
);

SELECT has_schema('pg_toast');
SELECT has_schema('pg_catalog');
SELECT has_schema('information_schema');
SELECT has_schema('public');

SELECT function_privs_are('pgsodium', 'crypto_aead_det_decrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_encrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_keygen', array[]::text[], 'service_role', array['EXECUTE']);

SELECT * FROM finish();
ROLLBACK;
