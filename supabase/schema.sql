-- StitchCraft database schema (Supabase project "StitchCraft").
-- This is the final state of the migrations applied to the project, kept here as documentation and so the project
-- can be recreated. The website talks to it with the project's publishable key; row level security does the
-- protecting, so every table below has RLS on and no anonymous access.

-- ============================================================================================================
-- 1. Backups written by the claude.ai artifact (through the owner's Supabase connector). Not used by the website.
--    RLS on with no policies: only the project owner can read or write them.
-- ============================================================================================================
create table public.sc_productions (
  id text primary key, name text, data jsonb not null, backed_up_at timestamptz not null default now()
);
create table public.sc_cast_members (
  id text primary key, production_id text not null, name text, data jsonb not null,
  backed_up_at timestamptz not null default now()
);
create index sc_cast_members_production_idx on public.sc_cast_members (production_id);
create table public.sc_backup_log (
  id bigint generated always as identity primary key, ran_at timestamptz not null default now(),
  productions integer not null, members integer not null, kind text not null default 'manual'
);
alter table public.sc_productions enable row level security;
alter table public.sc_cast_members enable row level security;
alter table public.sc_backup_log enable row level security;

-- ============================================================================================================
-- 2. Per-account data for the website
--    user_id is the OWNER of a record. Other people reach it only through app_shares.
--    rev goes up by one on every update; saves are checked against it (see app_save).
-- ============================================================================================================
create table public.app_productions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  data jsonb not null check (pg_column_size(data) < 2000000),           -- one record may not exceed ~2 MB
  updated_at timestamptz not null default now(),
  rev integer not null default 1,
  primary key (user_id, id)
);
create table public.app_members (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  production_id text not null,
  data jsonb not null check (pg_column_size(data) < 2000000),
  updated_at timestamptz not null default now(),
  rev integer not null default 1,
  primary key (user_id, id)
);
create index app_members_user_production_idx on public.app_members (user_id, production_id);

-- Who a production is shared with. An invite names an email address; it takes effect for whoever signs in with that
-- address once Supabase Auth has confirmed it, so an invite cannot be claimed by registering the address without
-- access to the mailbox.
create table public.app_shares (
  owner_id uuid not null,
  production_id text not null,
  email text not null check (email = lower(email) and length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role text not null check (role in ('editor', 'viewer')),
  owner_email text not null default '',
  created_at timestamptz not null default now(),
  primary key (owner_id, production_id, email),
  foreign key (owner_id, production_id) references public.app_productions (user_id, id) on delete cascade
);

alter table public.app_productions enable row level security;
alter table public.app_members enable row level security;
alter table public.app_shares enable row level security;
revoke all on public.app_productions from anon;
revoke all on public.app_members from anon;
revoke all on public.app_shares from anon;

-- ---- helpers (security definer so the policies below don't recurse)
create function public.app_my_email() returns text
language sql stable security definer set search_path = ''
as $$ select lower(u.email) from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null $$;

create function public.app_role(p_owner uuid, p_production text) returns text
language sql stable security definer set search_path = ''
as $$
  select case
    when auth.uid() is not null and p_owner = auth.uid() then 'owner'
    else (select s.role from public.app_shares s
          where s.owner_id = p_owner and s.production_id = p_production and s.email = public.app_my_email())
  end
$$;
revoke execute on function public.app_my_email() from public, anon;
revoke execute on function public.app_role(uuid, text) from public, anon;
grant execute on function public.app_my_email() to authenticated;
grant execute on function public.app_role(uuid, text) to authenticated;

-- ---- policies
--   owner  : everything on their production; creates and deletes productions; manages who it is shared with
--   editor : reads and changes the production and its cast members (adds and removes cast members)
--   viewer : reads only
create policy "productions: read if owner or invited" on public.app_productions
  for select to authenticated using (public.app_role(user_id, id) is not null);
create policy "productions: only the owner creates" on public.app_productions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "productions: owner or editor changes" on public.app_productions
  for update to authenticated
  using (public.app_role(user_id, id) in ('owner', 'editor'))
  with check (public.app_role(user_id, id) in ('owner', 'editor'));
create policy "productions: only the owner deletes" on public.app_productions
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "members: read if owner or invited" on public.app_members
  for select to authenticated using (public.app_role(user_id, production_id) is not null);
create policy "members: owner or editor adds" on public.app_members
  for insert to authenticated with check (public.app_role(user_id, production_id) in ('owner', 'editor'));
create policy "members: owner or editor changes" on public.app_members
  for update to authenticated
  using (public.app_role(user_id, production_id) in ('owner', 'editor'))
  with check (public.app_role(user_id, production_id) in ('owner', 'editor'));
create policy "members: owner or editor removes" on public.app_members
  for delete to authenticated using (public.app_role(user_id, production_id) in ('owner', 'editor'));

create policy "shares: anyone with access can see who has access" on public.app_shares
  for select to authenticated using (public.app_role(owner_id, production_id) is not null);
create policy "shares: only the owner invites" on public.app_shares
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "shares: only the owner changes a role" on public.app_shares
  for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "shares: the owner removes anyone, a person can leave" on public.app_shares
  for delete to authenticated
  using (owner_id = (select auth.uid()) or email = (select public.app_my_email()));

-- ---- triggers
-- revision counter
create function public.app_bump_rev() returns trigger
language plpgsql security invoker set search_path = ''
as $$ begin new.rev := old.rev + 1; new.updated_at := now(); return new; end $$;
create trigger app_productions_rev before update on public.app_productions for each row execute function public.app_bump_rev();
create trigger app_members_rev before update on public.app_members for each row execute function public.app_bump_rev();

-- Anyone can create an account, so cap what one owner can store: 200 productions, 5000 cast members. Only genuinely
-- new ids count, so an owner at the cap can still edit what they have.
create function public.app_limit_rows() returns trigger
language plpgsql security invoker set search_path = ''
as $$
declare
  cap integer := case tg_table_name when 'app_productions' then 200 else 5000 end;
  n integer; already boolean;
begin
  execute format('select exists (select 1 from public.%I where user_id = $1 and id = $2)', tg_table_name)
    into already using new.user_id, new.id;
  if already then return new; end if;
  execute format('select count(*) from public.%I where user_id = $1', tg_table_name) into n using new.user_id;
  if n >= cap then
    raise exception 'Storage limit reached: an account can hold at most % % records.', cap, tg_table_name using errcode = '54000';
  end if;
  return new;
end;
$$;
create trigger app_productions_limit before insert on public.app_productions for each row execute function public.app_limit_rows();
create trigger app_members_limit before insert on public.app_members for each row execute function public.app_limit_rows();

-- invites: lowercase the address, record the owner's email so invited people can see who shared with them, and cap
-- a production at 25 invited people
create function public.app_share_defaults() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  new.email := lower(btrim(new.email));
  select u.email into new.owner_email from auth.users u where u.id = new.owner_id;
  if tg_op = 'INSERT'
     and not exists (select 1 from public.app_shares s
                     where s.owner_id = new.owner_id and s.production_id = new.production_id and s.email = new.email) then
    select count(*) into n from public.app_shares s where s.owner_id = new.owner_id and s.production_id = new.production_id;
    if n >= 25 then
      raise exception 'A production can be shared with at most 25 people.' using errcode = '54000';
    end if;
  end if;
  return new;
end;
$$;
create trigger app_shares_defaults before insert or update on public.app_shares for each row execute function public.app_share_defaults();

-- ---- app_save(kind, rows): save records with a revision check.
-- Each row: {owner, id, base_rev, production_id (members), data}. base_rev is the revision the sender last saw
-- (0 for a new record). Returns one result per row:
--   ok       saved, with the new rev
--   conflict someone else saved first; carries their current rev and data so the app can ask which to keep
--   denied   the caller may only read this production
--   error    refused by a policy or limit (code and message included)
-- Runs as the caller, so the policies above still decide who may do what.
create function public.app_save(p_kind text, p_rows jsonb) returns jsonb
language plpgsql security invoker set search_path = ''
as $$
declare
  r jsonb; v_owner uuid; v_id text; v_base integer; v_prod text; v_rev integer; v_data jsonb; v_role text;
  res jsonb := '[]'::jsonb;
begin
  if p_kind not in ('p', 'm') then raise exception 'unknown kind %', p_kind; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_owner := (r->>'owner')::uuid; v_id := r->>'id'; v_base := coalesce((r->>'base_rev')::integer, 0); v_prod := r->>'production_id';
    begin
      if p_kind = 'p' then
        v_role := public.app_role(v_owner, v_id);
        if v_role is not null and v_role not in ('owner', 'editor') then
          res := res || jsonb_build_object('id', v_id, 'status', 'denied'); continue;
        end if;
        update public.app_productions set data = r->'data' where user_id = v_owner and id = v_id and rev = v_base returning rev into v_rev;
        if found then res := res || jsonb_build_object('id', v_id, 'status', 'ok', 'rev', v_rev); continue; end if;
        select p.rev, p.data into v_rev, v_data from public.app_productions p where p.user_id = v_owner and p.id = v_id;
        if found then res := res || jsonb_build_object('id', v_id, 'status', 'conflict', 'rev', v_rev, 'data', v_data); continue; end if;
        insert into public.app_productions (user_id, id, data) values (v_owner, v_id, r->'data') returning rev into v_rev;
      else
        v_role := public.app_role(v_owner, v_prod);
        if v_role is not null and v_role not in ('owner', 'editor') then
          res := res || jsonb_build_object('id', v_id, 'status', 'denied'); continue;
        end if;
        update public.app_members set data = r->'data', production_id = v_prod where user_id = v_owner and id = v_id and rev = v_base returning rev into v_rev;
        if found then res := res || jsonb_build_object('id', v_id, 'status', 'ok', 'rev', v_rev); continue; end if;
        select m.rev, m.data into v_rev, v_data from public.app_members m where m.user_id = v_owner and m.id = v_id;
        if found then res := res || jsonb_build_object('id', v_id, 'status', 'conflict', 'rev', v_rev, 'data', v_data); continue; end if;
        insert into public.app_members (user_id, id, production_id, data) values (v_owner, v_id, v_prod, r->'data') returning rev into v_rev;
      end if;
      res := res || jsonb_build_object('id', v_id, 'status', 'ok', 'rev', v_rev);
    exception when others then
      res := res || jsonb_build_object('id', v_id, 'status', 'error', 'code', sqlstate, 'message', sqlerrm);
    end;
  end loop;
  return res;
end;
$$;
revoke execute on function public.app_save(text, jsonb) from public, anon;
grant execute on function public.app_save(text, jsonb) to authenticated;
