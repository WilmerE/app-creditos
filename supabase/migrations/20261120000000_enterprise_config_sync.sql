-- One shared enterprise configuration row per authenticated account.
create table if not exists public.enterprise_configs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  phone text not null default '',
  nit text not null default '',
  email text not null default '',
  bank_account text not null default '',
  show_phone boolean not null default false,
  show_nit boolean not null default false,
  show_email boolean not null default false,
  show_bank_account boolean not null default false,
  mora integer not null default 20 check (mora > 0),
  collection_deadline_hour integer not null default 18
    check (collection_deadline_hour between 0 and 23),
  collection_deadline_minute integer not null default 0
    check (collection_deadline_minute between 0 and 59),
  collection_reminder_minutes integer not null default 60
    check (collection_reminder_minutes between 1 and 720),
  updated_at timestamptz not null
);

alter table public.enterprise_configs enable row level security;

drop policy if exists "enterprise configs own row" on public.enterprise_configs;
create policy "enterprise configs own row" on public.enterprise_configs
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.enterprise_configs to authenticated;
revoke all on public.enterprise_configs from anon;
