-- =====================================================================
--  OruChat - Supabase setup (oru thavana mathram run cheyyanam)
--  Supabase Dashboard -> SQL Editor -> New query -> ith full paste -> RUN
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

alter table public.profiles enable row level security;

drop policy if exists "profiles readable by logged in users" on public.profiles;
create policy "profiles readable by logged in users" on public.profiles
  for select to authenticated using (true);

drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- signup cheyyumbol profile thaanae undaakum
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

-- signup page-il username free aano ennu nokkaan
create or replace function public.username_available(u text)
returns boolean language sql security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where username = lower(u));
$$;
grant execute on function public.username_available(text) to anon, authenticated;

-- 2) MESSAGES --------------------------------------------------------
create table if not exists public.messages (
  id          bigint generated always as identity primary key,
  chat_id     text not null,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body        text,
  media_url   text,
  kind        text not null default 'text',
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index if not exists messages_chat_idx on public.messages (chat_id, created_at desc);
create index if not exists messages_receiver_idx on public.messages (receiver_id);

alter table public.messages enable row level security;

drop policy if exists "messages read own" on public.messages;
create policy "messages read own" on public.messages
  for select to authenticated using (auth.uid() = sender_id or auth.uid() = receiver_id);

drop policy if exists "messages send as me" on public.messages;
create policy "messages send as me" on public.messages
  for insert to authenticated with check (auth.uid() = sender_id);

drop policy if exists "messages mark read" on public.messages;
create policy "messages mark read" on public.messages
  for update to authenticated using (auth.uid() = receiver_id) with check (auth.uid() = receiver_id);

-- 3) STORIES ---------------------------------------------------------
create table if not exists public.stories (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null default 'image',
  media_url  text,
  caption    text,
  created_at timestamptz not null default now()
);
create index if not exists stories_created_idx on public.stories (created_at desc);

alter table public.stories enable row level security;

drop policy if exists "stories read all" on public.stories;
create policy "stories read all" on public.stories
  for select to authenticated using (true);

drop policy if exists "stories insert own" on public.stories;
create policy "stories insert own" on public.stories
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "stories delete own" on public.stories;
create policy "stories delete own" on public.stories
  for delete to authenticated using (auth.uid() = user_id);

-- 4) CALL SIGNALS (voice/video call connect cheyyaan) ------------------
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

alter table public.call_signals enable row level security;

drop policy if exists "signals read to me" on public.call_signals;
create policy "signals read to me" on public.call_signals
  for select to authenticated using (auth.uid() = to_id);

drop policy if exists "signals send as me" on public.call_signals;
create policy "signals send as me" on public.call_signals
  for insert to authenticated with check (auth.uid() = from_id);

drop policy if exists "signals delete mine" on public.call_signals;
create policy "signals delete mine" on public.call_signals
  for delete to authenticated using (auth.uid() = from_id or auth.uid() = to_id);

-- 5) CALL LOGS ---------------------------------------------------------
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

alter table public.call_logs enable row level security;

drop policy if exists "call logs read own" on public.call_logs;
create policy "call logs read own" on public.call_logs
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "call logs insert own" on public.call_logs;
create policy "call logs insert own" on public.call_logs
  for insert to authenticated with check (auth.uid() = user_id);

-- 6) REALTIME ON ---------------------------------------------------------
do $$
begin
  begin alter publication supabase_realtime add table public.messages;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.stories;      exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.call_signals; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.call_logs;    exception when duplicate_object then null; end;
end $$;

-- 7) PHOTO STORAGE (chat photos, stories, profile pictures) --------------
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do update set public = true;

drop policy if exists "media public read" on storage.objects;
create policy "media public read" on storage.objects
  for select using (bucket_id = 'media');

drop policy if exists "media upload own folder" on storage.objects;
create policy "media upload own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "media delete own" on storage.objects;
create policy "media delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
