-- Full device sync: mirrors every remaining local entity so a collector's
-- tablet and backup phone hold the same data. Safe to run more than once.

-- ------------------------------------------------------------------ clients
-- Storage object key of the client's photo: '<user_id>/<file name>'.
-- '' means the photo was removed on purpose; null means unknown (rows written
-- by app versions without photo sync) and keeps each device's local photo.
alter table public.clients add column if not exists photo_object text;

-- ----------------------------------------------------------------- payments
-- Composite key so per-account tables below can reference payments the same
-- way cards reference clients.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass
      and conname = 'payments_user_id_id_key'
  ) then
    alter table public.payments
      add constraint payments_user_id_id_key unique (user_id, id);
  end if;
end
$$;

-- --------------------------------------------------------------------- mora
-- One row per card and calendar day. sync_id is '<card_id>:<YYYY-MM-DD>',
-- so both devices accruing the same day write the same row.
create table if not exists public.mora (
  sync_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null,
  day date not null,
  pagado boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (user_id, sync_id),
  unique (user_id, card_id, day),
  foreign key (user_id, card_id) references public.cards(user_id, id)
);

-- Last day mora was evaluated for each card.
create table if not exists public.mora_tracking (
  card_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_checked_at timestamptz not null,
  updated_at timestamptz not null,
  unique (user_id, card_id),
  foreign key (user_id, card_id) references public.cards(user_id, id)
);

-- Which payment settled which mora day; reversals are kept, never deleted.
create table if not exists public.mora_applications (
  sync_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payment_id text not null,
  mora_sync_id text not null,
  cents integer not null check (cents > 0),
  reversed boolean not null default false,
  created_at timestamptz not null,
  reversed_at timestamptz,
  unique (user_id, sync_id),
  foreign key (user_id, payment_id) references public.payments(user_id, id),
  foreign key (user_id, mora_sync_id) references public.mora(user_id, sync_id)
);

-- ---------------------------------------------------------- payment audit
-- Append-only history of every correction to a payment.
create table if not exists public.payment_changes (
  sync_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payment_id text not null,
  old_amount double precision not null,
  new_amount double precision not null,
  old_mora_cents integer not null,
  new_mora_cents integer not null,
  old_scheduled_date timestamptz,
  new_scheduled_date timestamptz,
  old_type text not null,
  new_type text not null,
  old_receipt text,
  new_receipt text,
  created_at timestamptz not null,
  unique (user_id, sync_id),
  foreign key (user_id, payment_id) references public.payments(user_id, id)
);

-- ----------------------------------------------------------- notifications
-- event_key is deterministic (e.g. 'debtor:<card>:<day>'), so the same event
-- raised on both devices is one row. card_id has no foreign key on purpose:
-- a notification may outlive its card.
create table if not exists public.operational_notifications (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_key text not null,
  type text not null,
  card_id text,
  capital_group_id text,
  title text not null,
  message text not null,
  created_at timestamptz not null,
  is_read boolean not null default false,
  updated_at timestamptz not null,
  primary key (user_id, event_key)
);

-- ------------------------------------------------------------ credit plans
-- Catalog of loan plans. Deleted plans remain as tombstones (deleted_at).
-- Factory plans use sync_id 'plan-<amount>-<installments>-<installment>'.
create table if not exists public.credit_plans (
  sync_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  installments integer not null check (installments > 0),
  installment_cents integer not null check (installment_cents > 0),
  is_active boolean not null default true,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  unique (user_id, sync_id)
);

-- ----------------------------------------------------------------- indexes
create index if not exists mora_user_card_idx
  on public.mora(user_id, card_id);
create index if not exists mora_applications_user_payment_idx
  on public.mora_applications(user_id, payment_id);
create index if not exists payment_changes_user_payment_idx
  on public.payment_changes(user_id, payment_id);
create index if not exists operational_notifications_user_created_idx
  on public.operational_notifications(user_id, created_at);

-- --------------------------------------------------------------------- RLS
alter table public.mora enable row level security;
alter table public.mora_tracking enable row level security;
alter table public.mora_applications enable row level security;
alter table public.payment_changes enable row level security;
alter table public.operational_notifications enable row level security;
alter table public.credit_plans enable row level security;

drop policy if exists "mora own rows" on public.mora;
create policy "mora own rows" on public.mora
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "mora tracking own rows" on public.mora_tracking;
create policy "mora tracking own rows" on public.mora_tracking
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "mora applications own rows" on public.mora_applications;
create policy "mora applications own rows" on public.mora_applications
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "payment changes own rows" on public.payment_changes;
create policy "payment changes own rows" on public.payment_changes
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "notifications own rows" on public.operational_notifications;
create policy "notifications own rows" on public.operational_notifications
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "credit plans own rows" on public.credit_plans;
create policy "credit plans own rows" on public.credit_plans
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on
  public.mora,
  public.mora_tracking,
  public.mora_applications,
  public.payment_changes,
  public.operational_notifications,
  public.credit_plans
  to authenticated;

revoke all on
  public.mora,
  public.mora_tracking,
  public.mora_applications,
  public.payment_changes,
  public.operational_notifications,
  public.credit_plans
  from anon;

-- ----------------------------------------------------- client photo storage
-- Private bucket; each account reads and writes only its own folder.
insert into storage.buckets (id, name, public)
values ('client-photos', 'client-photos', false)
on conflict (id) do nothing;

drop policy if exists "client photos own folder" on storage.objects;
create policy "client photos own folder" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'client-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'client-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
