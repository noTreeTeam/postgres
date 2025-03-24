-- Sanity test object existence in storage schema

select has_table('storage'::name, 'buckets'::name);
select has_table('storage'::name, 'objects'::name);
select has_table('storage'::name, 'migrations'::name);
select has_function('storage'::name, 'foldername'::name);
select has_function('storage'::name, 'filename'::name);
select has_function('storage'::name, 'extension'::name);
select has_function('storage'::name, 'search'::name);

select schema_privs_are('storage', 'anon', ARRAY['USAGE']);

-- Add tests for other roles
select schema_privs_are('storage', 'authenticated', ARRAY['USAGE']);
select schema_privs_are('storage', 'service_role', ARRAY['USAGE']);

