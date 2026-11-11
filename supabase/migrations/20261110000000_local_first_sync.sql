-- Cloud mirror for the local Drift database. Every record belongs to one
-- authenticated Supabase user; the client must never use a service-role key.
create table if not exists public.clients (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null,
  address text not null,
  phones text[] not null default '{}',
  dpi text,
  dpi_folder text,
  alias text,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  unique (user_id, id)
);

create table if not exists public.capital_groups (
  sync_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  unique (user_id, sync_id)
);

create table if not exists public.cards (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  capital_group_id text,
  requested_amount double precision not null,
  delivered_amount double precision not null,
  total_installments integer not null,
  weekly_amount double precision not null,
  status text not null,
  color_hex text not null default '#800020',
  start_date timestamptz not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (user_id, id),
  foreign key (user_id, client_id) references public.clients(user_id, id),
  foreign key (user_id, capital_group_id) references public.capital_groups(user_id, sync_id)
);

create table if not exists public.payments (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null,
  scheduled_date timestamptz,
  amount_paid double precision not null default 0,
  mora_cents integer not null default 0,
  balance_after double precision not null,
  payment_type text not null default 'cash',
  receipt_number text,
  is_renewal boolean not null default false,
  created_at timestamptz,
  created_at_estimated boolean not null default false,
  is_manual boolean not null default false,
  position integer not null default 0,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  unique (user_id, receipt_number),
  foreign key (user_id, card_id) references public.cards(user_id, id)
);

create index if not exists cards_user_updated_idx
  on public.cards(user_id, updated_at);
create index if not exists payments_user_updated_idx
  on public.payments(user_id, updated_at);
create index if not exists clients_user_updated_idx
  on public.clients(user_id, updated_at);
create index if not exists capital_groups_user_updated_idx
  on public.capital_groups(user_id, updated_at);

alter table public.clients enable row level security;
alter table public.capital_groups enable row level security;
alter table public.cards enable row level security;
alter table public.payments enable row level security;

drop policy if exists "clients own rows" on public.clients;
create policy "clients own rows" on public.clients
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "capital groups own rows" on public.capital_groups;
create policy "capital groups own rows" on public.capital_groups
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "cards own rows" on public.cards;
create policy "cards own rows" on public.cards
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "payments own rows" on public.payments;
create policy "payments own rows" on public.payments
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.clients, public.capital_groups, public.cards, public.payments
  to authenticated;

revoke all
  on public.clients, public.capital_groups, public.cards, public.payments
  from anon;
