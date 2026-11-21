-- =====================================================================
--  OruChat v2 - Supabase setup
--  Supabase Dashboard -> SQL Editor -> New query -> ith full paste -> RUN
--  (Munpu v1 run cheythittundenkilum, ith veendum run cheyyaam. Safe aanu.)
-- =====================================================================

-- 1) PROFILES --------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  display_name text not null,
  about        text default 'Hey there! I am using OruChat',
  avatar_url   text,
  created_at   timestamptz not null default now()
);
alter table public.profiles add column if not exists last_seen         timestamptz default now();
alter table public.profiles add column if not exists privacy_photo     text not null default 'public';
alter table public.profiles add column if not exists privacy_about     text not null default 'public';
alter table public.profiles add column if not exists privacy_last_seen text not null default 'public';
alter table public.profiles add column if not exists privacy_online    text not null default 'public';
alter table public.profiles add column if not exists privacy_status    text not null default 'public';
alter table public.profiles add column if not exists privacy_messages  text not null default 'public';

-- 2) FRIENDS, BLOCKS ---------------------------------------------------
create table if not exists public.friendships (
  id           bigint generated always as identity primary key,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending',
  created_at   timestamptz not null default now(),
  check (requester_id <> addressee_id)
);
create unique index if not exists friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- 3) GROUPS ----------------------------------------------------------------
create table if not exists public.groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  avatar_url text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.group_members (
  group_id  uuid not null references public.groups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- 4) MESSAGES -----------------------------------------------------------------
create table if not exists public.messages (
  id          bigint generated always as identity primary key,
  chat_id     text not null,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid references public.profiles(id) on delete cascade,
  body        text,
  media_url   text,
  kind        text not null default 'text',
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
alter table public.messages alter column receiver_id drop not null;
alter table public.messages add column if not exists group_id   uuid references public.groups(id) on delete cascade;
alter table public.messages add column if not exists once       boolean not null default false;
alter table public.messages add column if not exists viewed_at  timestamptz;
alter table public.messages add column if not exists expires_at timestamptz;
alter table public.messages add column if not exists meta       jsonb not null default '{}'::jsonb;
create index if not exists messages_chat_idx     on public.messages (chat_id, created_at desc);
create index if not exists messages_receiver_idx on public.messages (receiver_id);

create table if not exists public.chat_settings (
  chat_id           text primary key,
  disappear_seconds integer not null default 0,
  updated_by        uuid,
  updated_at        timestamptz not null default now()
);
create table if not exists public.chat_clears (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  chat_id    text not null,
  cleared_at timestamptz not null default now(),
  primary key (user_id, chat_id)
);

-- 5) STORIES, CALLS ----------------------------------------------------------
create table if not exists public.stories (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null default 'image',
  media_url  text,
  caption    text,
  created_at timestamptz not null default now()
);
create index if not exists stories_created_idx on public.stories (created_at desc);

create table if not exists public.call_signals (
  id         bigint generated always as identity primary key,
  call_id    text not null,
  from_id    uuid not null references public.profiles(id) on delete cascade,
  to_id      uuid not null references public.profiles(id) on delete cascade,
  type       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists call_signals_call_idx on public.call_signals (call_id);

create table if not exists public.call_logs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  peer_id    uuid not null references public.profiles(id) on delete cascade,
  direction  text not null,
  video      boolean not null default false,
  status     text not null,
  duration_s integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists call_logs_user_idx on public.call_logs (user_id, created_at desc);

-- 6) HELPER FUNCTIONS ----------------------------------------------------------
create or replace function public.chat_key(a uuid, b uuid) returns text
language sql immutable as $$
  select case when a::text collate "C" < b::text collate "C"
              then a::text || '_' || b::text
              else b::text || '_' || a::text end;
$$;

create or replace function public.is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships f
                 where f.status = 'accepted'
                   and ((f.requester_id = a and f.addressee_id = b) or (f.requester_id = b and f.addressee_id = a)));
$$;

create or replace function public.is_group_member(gid uuid, uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = gid and user_id = uid);
$$;

create or replace function public.is_group_admin(gid uuid, uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = gid and user_id = uid and role = 'admin');
$$;

create or replace function public.is_chat_member(cid text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when cid like 'g\_%' then exists (select 1 from public.group_members gm
                                      where gm.group_id::text = substr(cid, 3) and gm.user_id = auth.uid())
    else position(auth.uid()::text in cid) > 0
  end;
$$;

create or replace function public.can_message(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select not public.is_blocked_between(a, b)
     and ( public.are_friends(a, b)
        or coalesce((select privacy_messages from public.profiles where id = b), 'public') = 'public' );
$$;

-- profile field kaanaan permission undo? (privacy: public / contacts / chats / nobody)
create or replace function public.visible_to_me(owner uuid, field text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare s text; me uuid := auth.uid();
begin
  if me is null then return false; end if;
  if me = owner then return true; end if;
  if public.is_blocked_between(owner, me) then return false; end if;
  select case field
           when 'photo'     then privacy_photo
           when 'about'     then privacy_about
           when 'last_seen' then privacy_last_seen
           when 'online'    then privacy_online
           when 'status'    then privacy_status
           else 'nobody' end
    into s from public.profiles where id = owner;
  if s = 'public'   then return true; end if;
  if s = 'contacts' then return public.are_friends(owner, me); end if;
  if s = 'chats'    then return exists (select 1 from public.messages m where m.chat_id = public.chat_key(owner, me)); end if;
  return false;
end;
$$;

-- 7) RPC FUNCTIONS (app ithu vilikkum) -------------------------------------------
create or replace function public.get_profiles(ids uuid[])
returns table (
  id uuid, username text, display_name text, avatar_url text, about text,
  last_seen timestamptz, online boolean, friend_status text,
  blocked_by_me boolean, blocked_me boolean
)
language sql stable security definer set search_path = public as $$
  select
    p.id,
    p.username,
    p.display_name,
    case when public.visible_to_me(p.id, 'photo')     then p.avatar_url end,
    case when public.visible_to_me(p.id, 'about')     then p.about end,
    case when public.visible_to_me(p.id, 'last_seen') then p.last_seen end,
    case when public.visible_to_me(p.id, 'online')    then (p.last_seen > now() - interval '90 seconds') end,
    case
      when p.id = auth.uid() then 'self'
      when public.are_friends(p.id, auth.uid()) then 'friends'
      when exists (select 1 from public.friendships f where f.status = 'pending' and f.requester_id = auth.uid() and f.addressee_id = p.id) then 'pending_out'
      when exists (select 1 from public.friendships f where f.status = 'pending' and f.requester_id = p.id and f.addressee_id = auth.uid()) then 'pending_in'
      else 'none'
    end,
    exists (select 1 from public.blocks b where b.blocker_id = auth.uid() and b.blocked_id = p.id),
    exists (select 1 from public.blocks b where b.blocker_id = p.id and b.blocked_id = auth.uid())
  from public.profiles p
  where p.id = any(ids);
$$;

create or replace function public.search_profile_ids(q text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(s.id), '{}'::uuid[]) from (
    select p.id from public.profiles p
    where p.id <> auth.uid()
      and not public.is_blocked_between(p.id, auth.uid())
      and (length(trim(q)) = 0
           or p.username ilike '%' || trim(q) || '%'
           or p.display_name ilike '%' || trim(q) || '%')
    order by p.created_at desc
    limit 30
  ) s;
$$;

create or replace function public.username_available(u text) returns boolean
language sql security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where username = lower(u));
$$;
grant execute on function public.username_available(text) to anon, authenticated;

create or replace function public.change_username(new_username text) returns void
language plpgsql security definer set search_path = public as $$
declare u text := lower(trim(new_username));
begin
  if auth.uid() is null then raise exception 'Please log in again.'; end if;
  if u !~ '^[a-z0-9_]{3,20}$' then raise exception 'Username: 3-20 letters, numbers or underscore.'; end if;
  if exists (select 1 from public.profiles where username = u and id <> auth.uid()) then
    raise exception 'That username is already taken.';
  end if;
  update public.profiles set username = u where id = auth.uid();
end;
$$;

-- one-time message: oru thavana mathram thurakkaan, pinne content delete aakum
create or replace function public.open_once(mid bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare payload_body text; payload_url text; payload_kind text;
begin
  with claimed as (
    select id, body, media_url, kind
      from public.messages
     where id = mid
       and receiver_id = auth.uid()
       and once = true
       and viewed_at is null
     for update
  )
  update public.messages msg
     set viewed_at = now(), body = null, media_url = null
    from claimed
   where msg.id = claimed.id
  returning claimed.body, claimed.media_url, claimed.kind
       into payload_body, payload_url, payload_kind;
  if not found then return null; end if;
  return jsonb_build_object('body', payload_body, 'media_url', payload_url, 'kind', payload_kind);
end;
$$;

create or replace function public.create_group(gname text, members uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare gid uuid; m uuid;
begin
  if auth.uid() is null then raise exception 'Please log in again.'; end if;
  if length(trim(coalesce(gname, ''))) < 1 then raise exception 'Group name is required.'; end if;
  insert into public.groups (name, created_by) values (trim(gname), auth.uid()) returning id into gid;
  insert into public.group_members (group_id, user_id, role) values (gid, auth.uid(), 'admin');
  foreach m in array coalesce(members, '{}'::uuid[]) loop
    if m <> auth.uid() and public.are_friends(auth.uid(), m) then
      insert into public.group_members (group_id, user_id, role) values (gid, m, 'member') on conflict do nothing;
    end if;
  end loop;
  return gid;
end;
$$;

create or replace function public.add_group_members(gid uuid, members uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare m uuid;
begin
  if not public.is_group_admin(gid, auth.uid()) then raise exception 'Only group admins can add members.'; end if;
  foreach m in array coalesce(members, '{}'::uuid[]) loop
    if public.are_friends(auth.uid(), m) then
      insert into public.group_members (group_id, user_id, role) values (gid, m, 'member') on conflict do nothing;
    end if;
  end loop;
end;
$$;

create or replace function public.rename_group(gid uuid, new_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(gid, auth.uid()) then raise exception 'Only group admins can rename the group.'; end if;
  if length(trim(coalesce(new_name, ''))) < 1 then raise exception 'Group name is required.'; end if;
  update public.groups set name = trim(new_name) where id = gid;
end;
$$;

create or replace function public.leave_group(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.group_members where group_id = gid and user_id = auth.uid();
  if not exists (select 1 from public.group_members where group_id = gid) then
    delete from public.groups where id = gid;
  elsif not exists (select 1 from public.group_members where group_id = gid and role = 'admin') then
    update public.group_members set role = 'admin'
     where group_id = gid and user_id = (select user_id from public.group_members where group_id = gid order by joined_at limit 1);
  end if;
end;
$$;

create or replace function public.purge_expired_messages() returns void
language sql security definer set search_path = public as $$
  delete from public.messages where expires_at is not null and expires_at < now();
$$;

-- 8) TRIGGERS --------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1))),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.messages_set_expiry() returns trigger
language plpgsql security definer set search_path = public as $$
declare s integer;
begin
  select disappear_seconds into s from public.chat_settings where chat_id = new.chat_id;
  if s is not null and s > 0 then
    new.expires_at := now() + make_interval(secs => s);
  end if;
  return new;
end;
$$;
drop trigger if exists messages_expiry_trg on public.messages;
create trigger messages_expiry_trg
  before insert on public.messages
  for each row execute function public.messages_set_expiry();

-- 9) ROW LEVEL SECURITY ---------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.friendships   enable row level security;
alter table public.blocks        enable row level security;
alter table public.groups        enable row level security;
alter table public.group_members enable row level security;
alter table public.messages      enable row level security;
alter table public.chat_settings enable row level security;
alter table public.chat_clears   enable row level security;
alter table public.stories       enable row level security;
alter table public.call_signals  enable row level security;
alter table public.call_logs     enable row level security;

-- profiles: swantham row mathram direct; mattullavar get_profiles() vazhi (privacy anusarichu)
drop policy if exists "profiles readable by logged in users" on public.profiles;
drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles for select to authenticated using (auth.uid() = id);
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- friendships
drop policy if exists "friendships read mine" on public.friendships;
create policy "friendships read mine" on public.friendships for select to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);
drop policy if exists "friendships request" on public.friendships;
create policy "friendships request" on public.friendships for insert to authenticated
  with check (auth.uid() = requester_id and status = 'pending' and not public.is_blocked_between(requester_id, addressee_id));
drop policy if exists "friendships accept" on public.friendships;
create policy "friendships accept" on public.friendships for update to authenticated
  using (auth.uid() = addressee_id) with check (auth.uid() = addressee_id);
drop policy if exists "friendships delete mine" on public.friendships;
create policy "friendships delete mine" on public.friendships for delete to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- blocks
drop policy if exists "blocks read mine" on public.blocks;
create policy "blocks read mine" on public.blocks for select to authenticated using (auth.uid() = blocker_id);
drop policy if exists "blocks insert mine" on public.blocks;
create policy "blocks insert mine" on public.blocks for insert to authenticated with check (auth.uid() = blocker_id);
drop policy if exists "blocks delete mine" on public.blocks;
create policy "blocks delete mine" on public.blocks for delete to authenticated using (auth.uid() = blocker_id);

-- groups
drop policy if exists "groups read members" on public.groups;
create policy "groups read members" on public.groups for select to authenticated
  using (public.is_group_member(id, auth.uid()));
drop policy if exists "group members read" on public.group_members;
create policy "group members read" on public.group_members for select to authenticated
  using (public.is_group_member(group_id, auth.uid()));

-- messages
drop policy if exists "messages read own" on public.messages;
drop policy if exists "messages read" on public.messages;
create policy "messages read" on public.messages for select to authenticated
  using (
    (auth.uid() = sender_id or auth.uid() = receiver_id
      or (group_id is not null and public.is_group_member(group_id, auth.uid())))
    and (expires_at is null or expires_at > now())
  );
drop policy if exists "messages send as me" on public.messages;
drop policy if exists "messages send" on public.messages;
create policy "messages send" on public.messages for insert to authenticated
  with check (
    auth.uid() = sender_id
    and (
      (group_id is null and receiver_id is not null and public.can_message(sender_id, receiver_id))
      or (group_id is not null and public.is_group_member(group_id, sender_id))
    )
  );
drop policy if exists "messages mark read" on public.messages;
create policy "messages mark read" on public.messages for update to authenticated
  using (auth.uid() = receiver_id) with check (auth.uid() = receiver_id);

-- chat settings (disappearing) / chat clears
drop policy if exists "chat settings read" on public.chat_settings;
create policy "chat settings read" on public.chat_settings for select to authenticated using (public.is_chat_member(chat_id));
drop policy if exists "chat settings insert" on public.chat_settings;
create policy "chat settings insert" on public.chat_settings for insert to authenticated with check (public.is_chat_member(chat_id));
drop policy if exists "chat settings update" on public.chat_settings;
create policy "chat settings update" on public.chat_settings for update to authenticated
  using (public.is_chat_member(chat_id)) with check (public.is_chat_member(chat_id));

drop policy if exists "chat clears all own" on public.chat_clears;
create policy "chat clears all own" on public.chat_clears for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- stories (privacy_status anusarichu)
drop policy if exists "stories read all" on public.stories;
drop policy if exists "stories read visible" on public.stories;
create policy "stories read visible" on public.stories for select to authenticated
  using (public.visible_to_me(user_id, 'status'));
drop policy if exists "stories insert own" on public.stories;
create policy "stories insert own" on public.stories for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "stories delete own" on public.stories;
create policy "stories delete own" on public.stories for delete to authenticated using (auth.uid() = user_id);

-- calls: friends thammil mathram
drop policy if exists "signals read to me" on public.call_signals;
create policy "signals read to me" on public.call_signals for select to authenticated using (auth.uid() = to_id);
drop policy if exists "signals send as me" on public.call_signals;
create policy "signals send as me" on public.call_signals for insert to authenticated
  with check (auth.uid() = from_id and public.are_friends(from_id, to_id) and not public.is_blocked_between(from_id, to_id));
drop policy if exists "signals delete mine" on public.call_signals;
create policy "signals delete mine" on public.call_signals for delete to authenticated
  using (auth.uid() = from_id or auth.uid() = to_id);

drop policy if exists "call logs read own" on public.call_logs;
create policy "call logs read own" on public.call_logs for select to authenticated using (auth.uid() = user_id);
drop policy if exists "call logs insert own" on public.call_logs;
create policy "call logs insert own" on public.call_logs for insert to authenticated with check (auth.uid() = user_id);

-- 10) REALTIME ---------------------------------------------------------------------------
do $$
begin
  begin alter publication supabase_realtime add table public.messages;      exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.stories;       exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.call_signals;  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.call_logs;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.friendships;   exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.groups;        exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.group_members; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.chat_settings; exception when duplicate_object then null; end;
end $$;

-- 11) AUTO DELETE of disappearing messages (pg_cron free aanu; kittiyillenkil app thaanae clean cheyyum)
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('oruchat-purge-expired', '* * * * *', 'select public.purge_expired_messages()');
exception when others then
  null;
end $$;

-- 12) STORAGE ---------------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do update set public = true;

drop policy if exists "media public read" on storage.objects;
create policy "media public read" on storage.objects for select using (bucket_id = 'media');

drop policy if exists "media upload own folder" on storage.objects;
create policy "media upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "media delete own" on storage.objects;
create policy "media delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);


-- 13) EXISTING ACCOUNT REPAIR + RPC PERMISSIONS -------------------------------
-- Older accounts created before the profile trigger existed may not have a
-- matching public.profiles row. Create one without changing existing profiles.
insert into public.profiles (id, username, display_name)
select
  u.id,
  left(
    coalesce(
      nullif(regexp_replace(lower(split_part(coalesce(u.email, ''), '@', 1)), '[^a-z0-9_]', '_', 'g'), ''),
      'user'
    ),
    11
  ) || '_' || left(replace(u.id::text, '-', ''), 8),
  coalesce(
    nullif(trim(u.raw_user_meta_data->>'display_name'), ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'OruChat User'
  )
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
on conflict (id) do nothing;

-- Explicitly expose the RPCs used by the Android client to signed-in users.
grant execute on function public.get_profiles(uuid[]) to authenticated;
grant execute on function public.search_profile_ids(text) to authenticated;
grant execute on function public.change_username(text) to authenticated;
grant execute on function public.open_once(bigint) to authenticated;
grant execute on function public.create_group(text, uuid[]) to authenticated;
grant execute on function public.add_group_members(uuid, uuid[]) to authenticated;
grant execute on function public.rename_group(uuid, text) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;

-- Force PostgREST to refresh its function/column schema cache.
notify pgrst, 'reload schema';
