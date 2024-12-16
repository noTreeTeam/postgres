-- migrate:up
do $$
begin
    -- Check if the pgmq.meta table exists
    if exists (
        select 1
        from pg_catalog.pg_class cls
        join pg_catalog.pg_namespace ns on cls.relnamespace = ns.oid
        where ns.nspname = 'pgmq' and cls.relname = 'meta'
    ) then
        -- Insert data into pgmq.meta for all tables matching the naming pattern 'pgmq.q_<queue_name>'
        insert into pgmq.meta (queue_name, is_partitioned, is_unlogged, created_at)
        select
            substring(cls.relname from 3) as queue_name,
            false as is_partitioned,
            case when cls.relpersistence = 'u' then true else false end as is_unlogged,
            now() as created_at
        from
            pg_catalog.pg_class cls
            join pg_catalog.pg_namespace ns
                on cls.relnamespace = ns.oid
        where
            ns.nspname = 'pgmq'
            and cls.relname like 'q_%'
            and cls.relkind in ('r', 'p', 'u');
    end if;
end $$;

-- migrate:down
