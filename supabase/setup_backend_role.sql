-- Optional hardening step for launch.
-- Run this in the Supabase SQL editor, replacing the password first.
-- Then run supabase/schema.sql again so the grants and RLS policy attach to this role.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'better_notes_api') then
    create role better_notes_api login password 'REPLACE_WITH_A_LONG_RANDOM_PASSWORD';
  end if;
end $$;

alter role better_notes_api password 'REPLACE_WITH_A_LONG_RANDOM_PASSWORD';

grant usage on schema public to better_notes_api;
grant select, insert, update on public.better_notes_users to better_notes_api;
grant select, insert, update on public.waitlist_signups to better_notes_api;
grant select, insert on public.ai_usage_events to better_notes_api;

revoke delete on public.better_notes_users from better_notes_api;
revoke delete on public.waitlist_signups from better_notes_api;
revoke update, delete on public.ai_usage_events from better_notes_api;
