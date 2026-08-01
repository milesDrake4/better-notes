create extension if not exists pgcrypto;

create table if not exists better_notes_users (
  id uuid primary key default gen_random_uuid(),
  install_id text unique not null,
  auth_user_id uuid unique,
  email text,
  display_name text,
  did_complete_class_setup boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table better_notes_users
  add column if not exists auth_user_id uuid;

alter table better_notes_users
  add column if not exists email text;

alter table better_notes_users
  add column if not exists did_complete_class_setup boolean not null default false;

create unique index if not exists idx_better_notes_users_auth_user_id
  on better_notes_users (auth_user_id);

do $$
begin
  if to_regclass('auth.users') is not null and not exists (
    select 1
    from pg_constraint
    where conname = 'better_notes_users_auth_user_id_fkey'
      and conrelid = 'better_notes_users'::regclass
  ) then
    alter table better_notes_users
      add constraint better_notes_users_auth_user_id_fkey
      foreign key (auth_user_id)
      references auth.users(id)
      on delete set null;
  end if;
end $$;

create table if not exists waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  name text,
  school text,
  subjects text,
  source text,
  notes text,
  wants_beta boolean not null default true,
  user_agent text,
  referrer text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_waitlist_signups_created_at
  on waitlist_signups (created_at desc);

create table if not exists ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references better_notes_users(id) on delete set null,
  install_id text not null,
  route text not null,
  status integer not null,
  success boolean not null,
  duration_ms integer not null,
  model text not null,
  mode text,
  scope text,
  note_type text,
  openai_status integer,
  error_type text,
  input_tokens integer,
  output_tokens integer,
  total_tokens integer,
  cached_input_tokens integer,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_usage_events_created_at
  on ai_usage_events (created_at desc);

create index if not exists idx_ai_usage_events_install_id_created_at
  on ai_usage_events (install_id, created_at desc);

drop index if exists idx_ai_usage_events_success;

create index if not exists idx_ai_usage_events_user_id_created_at
  on ai_usage_events (user_id, created_at desc);

create index if not exists idx_ai_usage_events_successful_feedback_by_user
  on ai_usage_events (user_id, created_at desc)
  where route = 'ai-feedback' and success = true;

create index if not exists idx_ai_usage_events_successful_feedback_by_install
  on ai_usage_events (install_id, created_at desc)
  where route = 'ai-feedback' and success = true;

alter table better_notes_users enable row level security;
alter table waitlist_signups enable row level security;
alter table ai_usage_events enable row level security;

revoke all on public.better_notes_users from anon, authenticated;
revoke all on public.waitlist_signups from anon, authenticated;
revoke all on public.ai_usage_events from anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'better_notes_api') then
    grant usage on schema public to better_notes_api;
    grant select, insert, update on public.better_notes_users to better_notes_api;
    grant select, insert, update on public.waitlist_signups to better_notes_api;
    grant select, insert on public.ai_usage_events to better_notes_api;
    revoke delete on public.better_notes_users from better_notes_api;
    revoke delete on public.waitlist_signups from better_notes_api;
    revoke update, delete on public.ai_usage_events from better_notes_api;

    drop policy if exists better_notes_api_backend_access on public.better_notes_users;
    drop policy if exists better_notes_api_backend_access on public.waitlist_signups;
    drop policy if exists better_notes_api_backend_access on public.ai_usage_events;

    drop policy if exists better_notes_api_users_select on public.better_notes_users;
    drop policy if exists better_notes_api_users_insert on public.better_notes_users;
    drop policy if exists better_notes_api_users_update on public.better_notes_users;
    drop policy if exists better_notes_api_waitlist_select on public.waitlist_signups;
    drop policy if exists better_notes_api_waitlist_insert on public.waitlist_signups;
    drop policy if exists better_notes_api_waitlist_update on public.waitlist_signups;
    drop policy if exists better_notes_api_usage_select on public.ai_usage_events;
    drop policy if exists better_notes_api_usage_insert on public.ai_usage_events;

    create policy better_notes_api_users_select
      on public.better_notes_users
      for select
      to better_notes_api
      using (true);

    create policy better_notes_api_users_insert
      on public.better_notes_users
      for insert
      to better_notes_api
      with check (true);

    create policy better_notes_api_users_update
      on public.better_notes_users
      for update
      to better_notes_api
      using (true)
      with check (true);

    create policy better_notes_api_waitlist_select
      on public.waitlist_signups
      for select
      to better_notes_api
      using (true);

    create policy better_notes_api_waitlist_insert
      on public.waitlist_signups
      for insert
      to better_notes_api
      with check (true);

    create policy better_notes_api_waitlist_update
      on public.waitlist_signups
      for update
      to better_notes_api
      using (true)
      with check (true);

    create policy better_notes_api_usage_select
      on public.ai_usage_events
      for select
      to better_notes_api
      using (true);

    create policy better_notes_api_usage_insert
      on public.ai_usage_events
      for insert
      to better_notes_api
      with check (true);
  end if;
end $$;
