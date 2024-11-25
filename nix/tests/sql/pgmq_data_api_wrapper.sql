/*
	This test is to validate the SQL for the Supabase Queues integration that
	will be triggered in the FE and documented for how to manually expose
	queues over supabase client libs by wrapping `pgmq`'s functions into a
	separate schema that we can add to PostgREST's 'exposed_schemas' setting
*/

/*
	Emulate Role Setup from migrations/db/init-scripts/00000000000000-initial-schema.sql#L5
*/

-- Supabase super admin
alter user  supabase_admin with superuser createdb createrole replication bypassrls;

-- Supabase replication user
create user supabase_replication_admin with login replication;

-- Supabase read-only user
create role supabase_read_only_user with login bypassrls;
grant pg_read_all_data to supabase_read_only_user;

-- Extension namespacing
create schema if not exists extensions;
create extension if not exists "uuid-ossp"      with schema extensions;
create extension if not exists pgcrypto         with schema extensions;
create extension if not exists pgjwt            with schema extensions;

-- Set up auth roles for the developer
create role anon                nologin noinherit;
create role authenticated       nologin noinherit; -- "logged in" user: web_user, app_user, etc
create role service_role        nologin noinherit bypassrls; -- allow developers to create JWT's that bypass their policies

create user authenticator noinherit;
grant anon              to authenticator;
grant authenticated     to authenticator;
grant service_role      to authenticator;
grant supabase_admin    to authenticator;

grant usage                     on schema public to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

-- Allow Extensions to be used in the API
grant usage                     on schema extensions to postgres, anon, authenticated, service_role;

-- Set up namespacing
alter user supabase_admin SET search_path TO public, extensions; -- don't include the "auth" schema

-- These are required so that the users receive grants whenever "supabase_admin" creates tables/function
alter default privileges for user supabase_admin in schema public grant all
    on sequences to postgres, anon, authenticated, service_role;
alter default privileges for user supabase_admin in schema public grant all
    on tables to postgres, anon, authenticated, service_role;
alter default privileges for user supabase_admin in schema public grant all
    on functions to postgres, anon, authenticated, service_role;

-- Set short statement/query timeouts for API roles
alter role anon set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';


/*
	WORKFLOW: Enable Data APIs for Queues

*/
create schema if not exists queues_public;
grant usage on schema queues_public to postgres, anon, authenticated, service_role;

create or replace function queues_public.queue_pop(
    queue_name text
)
  returns setof pgmq.message_record
  language plpgsql
  set search_path = ''
as $$
begin
    return query
    select *
    from pgmq.pop(
        queue_name := queue_name
    );
end;
$$;

comment on function queues_public.queue_pop(queue_name text) is 'Retrieves and locks the next message from the specified queue.';


create or replace function queues_public.queue_send(
    queue_name text,
    message jsonb,
    sleep_seconds integer default 0  -- renamed from 'delay'
)
  returns setof bigint
  language plpgsql
  set search_path = ''
as $$
begin
    return query
    select *
    from pgmq.send(
        queue_name := queue_name,
        msg := message,
        delay := sleep_seconds
    );
end;
$$;

comment on function queues_public.queue_send(queue_name text, message jsonb, sleep_seconds integer) is 'Sends a message to the specified queue, optionally delaying its availability by a number of seconds.';


create or replace function queues_public.queue_send_batch(
    queue_name text,
    messages jsonb[],
    sleep_seconds integer default 0  -- renamed from 'delay'
)
  returns setof bigint
  language plpgsql
  set search_path = ''
as $$
begin
    return query
    select *
    from pgmq.send_batch(
        queue_name := queue_name,
        msgs := messages,
        delay := sleep_seconds
    );
end;
$$;

comment on function queues_public.queue_send_batch(queue_name text, messages jsonb[], sleep_seconds integer) is 'Sends a batch of messages to the specified queue, optionally delaying their availability by a number of seconds.';


create or replace function queues_public.queue_archive(
    queue_name text,
    message_id bigint
)
  returns boolean
  language plpgsql
  set search_path = ''
as $$
begin
    return
    pgmq.archive(
        queue_name := queue_name,
        msg_id := message_id
    );
end;
$$;

comment on function queues_public.queue_archive(queue_name text, message_id bigint) is 'Archives a message by moving it from the queue to a permanent archive.';


create or replace function queues_public.queue_archive(
    queue_name text,
    message_id bigint
)
  returns boolean
  language plpgsql
  set search_path = ''
as $$
begin
    return
    pgmq.archive(
        queue_name := queue_name,
        msg_id := message_id
    );
end;
$$;

comment on function queues_public.queue_archive(queue_name text, message_id bigint) is 'Archives a message by moving it from the queue to a permanent archive.';


create or replace function queues_public.queue_delete(
    queue_name text,
    message_id bigint
)
  returns boolean
  language plpgsql
  set search_path = ''
as $$
begin
    return
    pgmq.delete(
        queue_name := queue_name,
        msg_id := message_id
    );
end;
$$;

comment on function queues_public.queue_delete(queue_name text, message_id bigint) is 'Permanently deletes a message from the specified queue.';

create or replace function queues_public.queue_read(
    queue_name text,
    sleep_seconds integer,
    n integer
)
  returns setof pgmq.message_record
  language plpgsql
  set search_path = ''
as $$
begin
    return query
    select *
    from pgmq.read(
        queue_name := queue_name,
        vt := sleep_seconds,
        qty := n
    );
end;
$$;

comment on function queues_public.queue_read(queue_name text, sleep_seconds integer, n integer) is 'Reads up to "n" messages from the specified queue with an optional "sleep_seconds" (visibility timeout).';

-- Grant execute permissions on wrapper functions to roles
grant execute on function queues_public.queue_pop(text) to postgres, service_role, anon, authenticated;
grant execute on function pgmq.pop(text) to postgres, service_role, anon, authenticated;


grant execute on function queues_public.queue_send(text, jsonb, integer) to postgres, service_role, anon, authenticated;
grant execute on function pgmq.send(text, jsonb, integer) to postgres, service_role, anon, authenticated;

grant execute on function queues_public.queue_send_batch(text, jsonb[], integer) to postgres, service_role, anon, authenticated;
grant execute on function pgmq.send_batch(text, jsonb[], integer) to postgres, service_role, anon, authenticated;

grant execute on function queues_public.queue_archive(text, bigint) to postgres, service_role, anon, authenticated;
grant execute on function pgmq.archive(text, bigint) to postgres, service_role, anon, authenticated;

grant execute on function queues_public.queue_delete(text, bigint) to postgres, service_role, anon, authenticated;
grant execute on function pgmq.delete(text, bigint) to postgres, service_role, anon, authenticated;

grant execute on function queues_public.queue_read(text, integer, integer) to postgres, service_role, anon, authenticated;
grant execute on function pgmq.read(text, integer, integer, jsonb) to postgres, service_role, anon, authenticated;

-- For the service role, we want full access
-- Grant permissions on existing tables
grant all privileges on all tables in schema pgmq to postgres, service_role;

-- Ensure `service_role` has permissions on future tables
alter default privileges in schema pgmq grant all privileges on tables to postgres, service_role;

grant usage on schema pgmq to postgres, anon, authenticated, service_role;

/*
	Test Default Permissions
*/

select pgmq.create('baz');
-- FE should also automatically apply RLS, but we want to test default permissions and RLS separately


-- service_role can create a message, anon and authenticated can not
begin;
	set local role service_role;

	-- Should Succeed 
	select queues_public.queue_send(
		queue_name := 'baz',
		message := '{}'
	);
rollback;

begin;
	set local role anon;

	-- Should Fail
	select queues_public.queue_send(
		queue_name := 'baz',
		message := '{}'
	);
rollback;

begin;
	set local role authenticated;

	-- Should Fail
	select queues_public.queue_send(
		queue_name := 'baz',
		message := '{}'
	);
rollback;


-- service_role can read mesages, anon and authenticated can not
begin;
	set local role service_role;

	-- Should Succeed 
	select queues_public.queue_read(
		queue_name := 'baz',
		sleep_seconds := 0,
		n := 1
	);
rollback;

begin;
	set local role anon;

	-- Should Fail
	select queues_public.queue_read(
		queue_name := 'baz',
		sleep_seconds := 0,
		n := 1
	);
rollback;

begin;
	set local role authenticated;

	-- Should Fail
	select queues_public.queue_read(
		queue_name := 'baz',
		sleep_seconds := 0,
		n := 1
	);
rollback;




/*
	WORKFLOW: Create a Queue named "baz"

    In this example:
	- authenticated users will have access
    - anon users will not have access
*/

create schema front_end;

-- THIS FUNCTION IS PURELY FOR TESTING PURPOSES. DO NOT CREATE IT
create or replace function front_end.create_queue(
    queue_name text,
	anon_has_access bool,
	authenticated_has_access bool,
	rls_policy text
)
	returns void
	language plpgsql
	set search_path = ''
as $$
begin
	-- Create the queue
	perform pgmq.create(queue_name);

	-- enable RLS (ALWAYS)
	execute format('alter table pgmq.q_%s enable row level security;', queue_name);

	-- Note: in the FE we should have separate toggles for each of select/insert/update/delete
	if anon_has_access then
		-- Queue table
		execute format('grant select, insert, update, delete on pgmq.q_%s to anon;', queue_name);
		-- Archive table
		execute format('grant select, insert, update, delete on pgmq.a_%s to anon;', queue_name);
	end if;

	if authenticated_has_access then
		-- Queue table
		execute format('grant select, insert, update, delete on pgmq.q_%s to authenticated;', queue_name);
		-- Archive table
		execute format('grant select, insert, update, delete on pgmq.a_%s to authenticated;', queue_name);
	end if;

	-- Note: basic implementation for testing. Use the usual RLS widgets for control
	execute format(
		'create policy rls_q_%s on pgmq.q_%s for all using (%s) with check (%s)',
		queue_name,
		queue_name,
		rls_policy,
		rls_policy
	);

end;
$$;

/*
	Integration Test 1
	- authenticated has full access
	- anon has no access
	- RLS allows everything
*/

select front_end.create_queue(
	queue_name := 'qux',
	anon_has_access := 'f',
	authenticated_has_access := 't',
	rls_policy := 'true'
);

begin;
	set local role anon;

	-- Should Fail
	select queues_public.queue_read(
		queue_name := 'qux',
		sleep_seconds := 0,
		n := 1
	);
rollback;

-- Should all work
begin;
	set local role authenticated;

	-- Should succeed
	select queues_public.queue_send(
		queue_name := 'qux',
		message := '{}'
	);

	select queues_public.queue_send_batch(
		queue_name := 'qux',
		messages := array['{"a": 1}', '{"b": 2}']::jsonb[]
	);

	select queues_public.queue_pop(
		queue_name := 'qux'
	);

	select queues_public.queue_delete(
		queue_name := 'qux',
		message_id := 2
	);

	select queues_public.queue_archive(
		queue_name := 'qux',
		message_id := 3
	);

rollback;

/*
	Integration Test 2
	- authenticated has full access
	- anon has no access
	- RLS allows everything
*/

select front_end.create_queue(
	queue_name := 'qux',
	anon_has_access := 'f',
	authenticated_has_access := 't',
	rls_policy := 'false' -- block all
);


begin;
	set local role authenticated;

	-- Should fail 
	select queues_public.queue_send(
		queue_name := 'waldo',
		message := '{}'
	);

rollback;



/*
	Cleanup
*/
drop schema queues_public cascade;
drop extension pgmq cascade; create extension pgmq;
