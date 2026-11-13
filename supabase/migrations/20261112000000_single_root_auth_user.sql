-- Permit a first account to bootstrap a new project, then keep the project
-- bound to that single principal account.
create or replace function public.is_root_account_available()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select not exists (select 1 from auth.users);
$$;

revoke all on function public.is_root_account_available() from public;
grant execute on function public.is_root_account_available() to anon, authenticated;

create or replace function public.enforce_single_root_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Serialize concurrent first signups so only one can pass the empty check.
  perform pg_catalog.pg_advisory_xact_lock(81427, 1);

  if exists (select 1 from auth.users) then
    raise exception 'ROOT_ACCOUNT_ALREADY_EXISTS'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_single_root_auth_user() from public;

drop trigger if exists enforce_single_root_auth_user on auth.users;
create trigger enforce_single_root_auth_user
before insert on auth.users
for each row execute function public.enforce_single_root_auth_user();
