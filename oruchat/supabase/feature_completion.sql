-- OruChat feature completion migration
-- Run AFTER supabase_setup.sql in Supabase SQL Editor.

-- 1) Message attachment, view-once and disappearing-message metadata.
alter table public.messages
  add column if not exists view_once boolean not null default false,
  add column if not exists viewed_at timestamptz,
  add column if not exists expires_at timestamptz;
create index if not exists messages_expiry_idx on public.messages(expires_at) where expires_at is not null;

drop policy if exists "messages read own" on public.messages;
create policy "messages read own and available" on public.messages
for select to authenticated
using (
  (expires_at is null or expires_at > now())
  and (
    auth.uid() = sender_id
    or (auth.uid() = receiver_id and (view_once = false or viewed_at is null))
  )
);

-- Atomically consume a view-once message. The receiver gets the payload once;
-- the row is deleted in the same transaction so another fetch cannot reopen it.
create or replace function public.consume_view_once_message(message_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.messages%rowtype;
begin
  select * into v_row
  from public.messages
  where id = message_id
    and receiver_id = auth.uid()
    and view_once = true
    and viewed_at is null
    and (expires_at is null or expires_at > now())
  for update;

  if not found then
    raise exception 'This view-once message is no longer available';
  end if;

  delete from public.messages where id = message_id;
  return to_jsonb(v_row);
end;
$$;
revoke all on function public.consume_view_once_message(bigint) from public;
grant execute on function public.consume_view_once_message(bigint) to authenticated;

-- Opportunistic cleanup: every new message also purges already-expired rows.
create or replace function public.purge_expired_messages()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.messages where expires_at is not null and expires_at <= now();
  return new;
end;
$$;
drop trigger if exists messages_purge_expired on public.messages;
create trigger messages_purge_expired before insert on public.messages
for each row execute function public.purge_expired_messages();

-- Per-user disappearing-message preference for each one-to-one conversation.
create table if not exists public.chat_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  chat_id text not null,
  disappearing_seconds integer not null default 0 check (disappearing_seconds in (0,60,3600,86400,2592000)),
  updated_at timestamptz not null default now(),
  primary key(user_id,chat_id)
);
alter table public.chat_preferences enable row level security;
drop policy if exists "users manage own chat preferences" on public.chat_preferences;
create policy "users manage own chat preferences" on public.chat_preferences
for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

-- 2) Group conversations.
create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.chat_group_members (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin','member')),
  joined_at timestamptz not null default now(),
  unique(group_id,user_id)
);
create table if not exists public.chat_group_messages (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text,
  media_url text,
  kind text not null default 'text',
  created_at timestamptz not null default now()
);
create index if not exists group_messages_idx on public.chat_group_messages(group_id,created_at);

alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.chat_group_messages enable row level security;

-- SECURITY DEFINER membership helpers avoid recursive RLS policy evaluation.
create or replace function public.is_chat_group_member(p_group_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.chat_group_members m where m.group_id=p_group_id and m.user_id=auth.uid());
$$;
create or replace function public.is_chat_group_admin(p_group_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.chat_group_members m where m.group_id=p_group_id and m.user_id=auth.uid() and m.role='admin');
$$;
grant execute on function public.is_chat_group_member(uuid) to authenticated;
grant execute on function public.is_chat_group_admin(uuid) to authenticated;

drop policy if exists "group members read groups" on public.chat_groups;
create policy "group members read groups" on public.chat_groups for select to authenticated
using (created_by=auth.uid() or public.is_chat_group_member(id));
drop policy if exists "users create groups" on public.chat_groups;
create policy "users create groups" on public.chat_groups for insert to authenticated with check (created_by=auth.uid());
drop policy if exists "group admins update groups" on public.chat_groups;
create policy "group admins update groups" on public.chat_groups for update to authenticated
using (public.is_chat_group_admin(id)) with check (public.is_chat_group_admin(id));

drop policy if exists "members read memberships" on public.chat_group_members;
create policy "members read memberships" on public.chat_group_members for select to authenticated
using (public.is_chat_group_member(group_id));
drop policy if exists "creator or admin add members" on public.chat_group_members;
create policy "creator or admin add members" on public.chat_group_members for insert to authenticated
with check (
  (user_id=auth.uid() and exists(select 1 from public.chat_groups g where g.id=group_id and g.created_by=auth.uid()))
  or public.is_chat_group_admin(group_id)
);
drop policy if exists "admins remove members" on public.chat_group_members;
create policy "admins remove members" on public.chat_group_members for delete to authenticated
using (user_id=auth.uid() or public.is_chat_group_admin(group_id));

drop policy if exists "members read group messages" on public.chat_group_messages;
create policy "members read group messages" on public.chat_group_messages for select to authenticated
using (public.is_chat_group_member(group_id));
drop policy if exists "members send group messages" on public.chat_group_messages;
create policy "members send group messages" on public.chat_group_messages for insert to authenticated
with check (sender_id=auth.uid() and public.is_chat_group_member(group_id));

-- Enable realtime for group messages/membership updates.
do $$ begin
  begin alter publication supabase_realtime add table public.chat_group_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.chat_group_members; exception when duplicate_object then null; end;
end $$;

-- Optional daily cleanup. Requires pg_cron to be enabled in the Supabase project.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('oru-delete-expired-messages','*/5 * * * *',
      'delete from public.messages where expires_at is not null and expires_at <= now()');
  end if;
exception when others then
  raise notice 'pg_cron unavailable; expired messages are hidden by RLS and purged on new message inserts.';
end $$;
