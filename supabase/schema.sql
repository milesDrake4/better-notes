create extension if not exists pgcrypto;

create table if not exists better_notes_users (
  id uuid primary key default gen_random_uuid(),
  install_id text unique not null,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

create index if not exists idx_ai_usage_events_success
  on ai_usage_events (success);
