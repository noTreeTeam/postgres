-- migrate:up
do $$
begin
    -- First, verify that pgmq.meta is a regular table with the required structure
    if exists (
        select 1
        from pg_catalog.pg_class c
        join pg_catalog.pg_namespace n on c.relnamespace = n.oid
        where n.nspname = 'pgmq'
        and c.relname = 'meta'
        and c.relkind = 'r'  -- Verify it's a regular table
        -- Verify the table has exactly these columns and no others
        and (
            select count(*)
            from pg_catalog.pg_attribute a
            where a.attrelid = c.oid
            and a.attnum > 0
            and not a.attisdropped
        ) = 4  -- Only 4 columns should exist
        and not exists (
            select 1
            from pg_catalog.pg_attribute a
            where a.attrelid = c.oid
            and a.attnum > 0
            and not a.attisdropped
            and a.attname not in ('queue_name', 'is_partitioned', 'is_unlogged', 'created_at')
        )  -- No other columns should exist
        and exists (
            select 1
            from pg_catalog.pg_attribute a
            where a.attrelid = c.oid
            and a.attnum > 0
            and not a.attisdropped
            and a.attname in ('queue_name', 'is_partitioned', 'is_unlogged', 'created_at')
            having count(*) = 4  -- All required columns must exist
        )
    ) then
        -- Check if the pgmq.meta table exists
        if exists (
            select 1
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n on c.relnamespace = n.oid
            where n.nspname = 'pgmq' and c.relname = 'meta'
        ) then
            -- Insert data into pgmq.meta for all tables matching the naming pattern 'pgmq.q_<queue_name>'
            insert into pgmq.meta (queue_name, is_partitioned, is_unlogged, created_at)
            select
                substring(c.relname from 3) as queue_name,
                false as is_partitioned,
                case when c.relpersistence = 'u' then true else false end as is_unlogged,
                now() as created_at
            from
                pg_catalog.pg_class c
                join pg_catalog.pg_namespace n
                    on c.relnamespace = n.oid
            where
                n.nspname = 'pgmq'
                and c.relname like 'q_%'
                and c.relkind in ('r', 'p', 'u');
        end if;
    end if;
end $$;

-- migrate:down
