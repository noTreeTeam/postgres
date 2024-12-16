-- migrate:up
do $$
declare
    column_count integer;
    expected_columns text[] := array['queue_name', 'is_partitioned', 'is_unlogged', 'created_at'];
begin
    -- Check if pgmq.meta exists and is a regular table
    if exists (
        select 1
        from pg_catalog.pg_class c
        join pg_catalog.pg_namespace n on c.relnamespace = n.oid
        where n.nspname = 'pgmq'
        and c.relname = 'meta'
        and c.relkind = 'r'  -- 'r' means regular table
    ) then
        -- Check if all required columns exist and no additional columns exist
        select count(*)
        into column_count
        from pg_catalog.pg_attribute a
        join pg_catalog.pg_class c on a.attrelnum > 0 and a.attrelid = c.oid
        join pg_catalog.pg_namespace n on c.relnamespace = n.oid
        where n.nspname = 'pgmq'
        and c.relname = 'meta'
        and not a.attisdropped;  -- Exclude dropped columns

        -- Only proceed if column count matches and all required columns exist
        if column_count = array_length(expected_columns, 1)
        and exists (
            select 1
            from pg_catalog.pg_attribute a
            join pg_catalog.pg_class c on a.attrelnum > 0 and a.attrelid = c.oid
            join pg_catalog.pg_namespace n on c.relnamespace = n.oid
            where n.nspname = 'pgmq'
            and c.relname = 'meta'
            and a.attname = any(expected_columns)
            having count(*) = array_length(expected_columns, 1)
        ) then
            -- Insert data into pgmq.meta for all tables matching the naming pattern 'pgmq.q_<queue_name>'
            insert into pgmq.meta (queue_name, is_partitioned, is_unlogged, created_at)
            select
                substring(c.relname from 3) as queue_name,
                false as is_partitioned,
                case when c.relpersistence = 'u' then true else false end as is_unlogged,
                now() as created_at
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n on c.relnamespace = n.oid
            where n.nspname = 'pgmq'
            and c.relname like 'q_%'
            and c.relkind in ('r', 'p', 'u');
        end if;
    end if;
end $$;

-- migrate:down
