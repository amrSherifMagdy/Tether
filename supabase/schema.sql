-- Tether on Supabase. Run once in the SQL Editor (Run). Safe to re-run.
-- 1) Open sign-up (optional invite gate in closed_signup.sql)  2) per-user isolation (row level security)  3) frozen fields and status rules
-- 4) realtime on the tables the app listens to.

-- ---------- sign-up is open ----------
-- Anyone can create an account (email confirmation stays on). Removes the old invite gate if it exists.
-- For an invite-only project, run supabase/closed_signup.sql after this file.
drop trigger if exists gate_signup on auth.users;

-- ---------- sessions ----------
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','stopped','expired','ended')),
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  expires_at timestamptz,            -- null = no time limit
  duration_minutes int
);
create index if not exists sessions_user_status on public.sessions (user_id, status);

-- ---------- actions (session mode) ----------
create table if not exists public.actions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type text not null check (type in ('screenshot','move','click','scroll','type','key','open_url','open_app','wait')),
  params jsonb not null default '{}'::jsonb check (jsonb_typeof(params) = 'object' and pg_column_size(params) < 20000),
  status text not null default 'pending' check (status in ('pending','running','done','failed','rejected')),
  result text check (char_length(result) <= 2000),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists actions_session_status on public.actions (session_id, status, created_at);

-- ---------- latest screenshot per session ----------
create table if not exists public.frames (
  session_id uuid primary key references public.sessions(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  image_b64 text not null check (char_length(image_b64) <= 900000),
  width int not null,
  height int not null,
  captured_at timestamptz not null default now(),
  action_id text
);

-- ---------- allowlisted commands (approve on the laptop) ----------
create table if not exists public.commands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  command_key text not null check (char_length(command_key) <= 64),
  args jsonb not null default '[]'::jsonb check (jsonb_typeof(args) = 'array' and jsonb_array_length(args) <= 3),
  status text not null default 'pending' check (status in ('pending','running','done','failed','rejected','denied')),
  result text check (char_length(result) <= 2000),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists commands_user_created on public.commands (user_id, created_at desc);

-- ---------- triggers: transitions and timestamps ----------
create or replace function public.lk_action_guard() returns trigger language plpgsql as $$
begin
  if not ((old.status = 'pending' and new.status in ('running','rejected'))
       or (old.status = 'running' and new.status in ('done','failed'))) then
    raise exception 'bad status transition % -> %', old.status, new.status;
  end if;
  if new.status = 'running' and new.result is not null then
    raise exception 'a claim cannot carry a result';
  end if;
  if new.status <> 'running' then new.finished_at = now(); end if;
  return new;
end $$;

drop trigger if exists lk_actions_guard on public.actions;
create trigger lk_actions_guard before update on public.actions for each row execute function public.lk_action_guard();

create or replace function public.lk_command_guard() returns trigger language plpgsql as $$
begin
  if not ((old.status = 'pending' and new.status in ('running','rejected','denied'))
       or (old.status = 'running' and new.status in ('done','failed'))) then
    raise exception 'bad status transition % -> %', old.status, new.status;
  end if;
  if new.status = 'running' and new.result is not null then
    raise exception 'a claim cannot carry a result';
  end if;
  if new.status <> 'running' then new.finished_at = now(); end if;
  return new;
end $$;

drop trigger if exists lk_commands_guard on public.commands;
create trigger lk_commands_guard before update on public.commands for each row execute function public.lk_command_guard();

create or replace function public.lk_session_end() returns trigger language plpgsql as $$
begin
  if new.status <> 'active' then new.ended_at = now(); end if;
  return new;
end $$;
drop trigger if exists lk_sessions_end on public.sessions;
create trigger lk_sessions_end before update on public.sessions for each row execute function public.lk_session_end();

create or replace function public.lk_frame_touch() returns trigger language plpgsql as $$
begin new.captured_at = now(); return new; end $$;
drop trigger if exists lk_frames_touch on public.frames;
create trigger lk_frames_touch before update on public.frames for each row execute function public.lk_frame_touch();

-- ---------- privileges: only these columns can be written ----------
revoke all on public.sessions, public.actions, public.frames, public.commands from anon, authenticated;
grant select on public.sessions, public.actions, public.frames, public.commands to authenticated;
grant insert (status, expires_at, duration_minutes) on public.sessions to authenticated;
grant update (status) on public.sessions to authenticated;
grant insert (session_id, type, params) on public.actions to authenticated;
grant update (status, result) on public.actions to authenticated;
grant insert (session_id, image_b64, width, height, action_id) on public.frames to authenticated;
grant update (image_b64, width, height, action_id) on public.frames to authenticated;
grant insert (command_key, args) on public.commands to authenticated;
grant update (status, result) on public.commands to authenticated;

-- ---------- row level security: every row belongs to exactly one user ----------
alter table public.sessions enable row level security;
alter table public.actions enable row level security;
alter table public.frames enable row level security;
alter table public.commands enable row level security;

drop policy if exists sessions_select on public.sessions;
create policy sessions_select on public.sessions for select to authenticated using (user_id = auth.uid());
drop policy if exists sessions_insert on public.sessions;
create policy sessions_insert on public.sessions for insert to authenticated with check (
  user_id = auth.uid() and status = 'active'
  and (expires_at is null or (duration_minutes is not null and duration_minutes <= 240 and expires_at <= now() + interval '245 minutes')));
drop policy if exists sessions_update on public.sessions;
create policy sessions_update on public.sessions for update to authenticated
  using (user_id = auth.uid() and status = 'active')
  with check (user_id = auth.uid() and status in ('stopped','expired','ended'));

drop policy if exists actions_select on public.actions;
create policy actions_select on public.actions for select to authenticated using (user_id = auth.uid());
drop policy if exists actions_insert on public.actions;
create policy actions_insert on public.actions for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.sessions s where s.id = session_id and s.user_id = auth.uid()
              and s.status = 'active' and (s.expires_at is null or now() < s.expires_at)));
drop policy if exists actions_update on public.actions;
create policy actions_update on public.actions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists frames_select on public.frames;
create policy frames_select on public.frames for select to authenticated using (user_id = auth.uid());
drop policy if exists frames_insert on public.frames;
create policy frames_insert on public.frames for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.sessions s where s.id = session_id and s.user_id = auth.uid() and s.status = 'active'));
drop policy if exists frames_update on public.frames;
create policy frames_update on public.frames for update to authenticated
  using (user_id = auth.uid()
         and exists (select 1 from public.sessions s where s.id = session_id and s.user_id = auth.uid() and s.status = 'active'))
  with check (user_id = auth.uid());

drop policy if exists commands_select on public.commands;
create policy commands_select on public.commands for select to authenticated using (user_id = auth.uid());
drop policy if exists commands_insert on public.commands;
create policy commands_insert on public.commands for insert to authenticated with check (user_id = auth.uid());
drop policy if exists commands_update on public.commands;
create policy commands_update on public.commands for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- realtime ----------
do $$ begin
  begin alter publication supabase_realtime add table public.actions; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.commands; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.frames; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.sessions; exception when duplicate_object then null; end;
end $$;

-- ---------- privacy: the cloud is only a short-lived relay ----------
-- Screenshots are deleted by the assistant right after it fetches them, by the app 60s after the last upload and when the
-- session ends, and by the cleanup below as a backstop. Finished actions/commands are deleted right after the result is read
-- and by the cleanup after 10 minutes. The full history lives only in the local log on the laptop.
grant delete on public.frames, public.actions, public.commands to authenticated;
drop policy if exists frames_delete on public.frames;
create policy frames_delete on public.frames for delete to authenticated using (user_id = auth.uid());
drop policy if exists actions_delete on public.actions;
create policy actions_delete on public.actions for delete to authenticated using (user_id = auth.uid());
drop policy if exists commands_delete on public.commands;
create policy commands_delete on public.commands for delete to authenticated using (user_id = auth.uid());

create or replace function public.lk_cleanup() returns void language sql security definer set search_path = public as $$
  delete from public.frames where captured_at < now() - interval '60 seconds';
  delete from public.actions where created_at < now() - interval '10 minutes';
  delete from public.commands where created_at < now() - interval '10 minutes' and status not in ('pending','running');
  delete from public.commands where created_at < now() - interval '1 day';
  delete from public.sessions where created_at < now() - interval '1 day' and status <> 'active';
$$;
revoke all on function public.lk_cleanup() from public, anon, authenticated;

-- run the cleanup every minute (pg_cron); if the extension is unavailable the app-side deletes still apply
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule('lk_cleanup') where exists (select 1 from cron.job where jobname = 'lk_cleanup');
  perform cron.schedule('lk_cleanup', '* * * * *', 'select public.lk_cleanup()');
exception when others then raise notice 'pg_cron not enabled: enable it in Database > Extensions, then re-run this file';
end $$;

-- ---------- controller pairing: only controllers approved ON the laptop can drive it ----------
-- A controller (the assistant's script, a browser) has an Ed25519 key. It registers its public key here (a request only).
-- The laptop app keeps the real approved list in a local file and ignores any action whose signature
-- does not verify against an approved key. So a stolen email+password alone cannot move the laptop.
create table if not exists public.controllers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  public_key text not null check (char_length(public_key) = 44),
  created_at timestamptz not null default now(),
  unique (user_id, public_key)
);
alter table public.controllers enable row level security;
revoke all on public.controllers from anon, authenticated;
grant select, delete on public.controllers to authenticated;
grant insert (name, public_key) on public.controllers to authenticated;
drop policy if exists controllers_select on public.controllers;
create policy controllers_select on public.controllers for select to authenticated using (user_id = auth.uid());
drop policy if exists controllers_insert on public.controllers;
create policy controllers_insert on public.controllers for insert to authenticated with check (
  user_id = auth.uid() and (select count(*) from public.controllers c where c.user_id = auth.uid()) < 20);
drop policy if exists controllers_delete on public.controllers;
create policy controllers_delete on public.controllers for delete to authenticated using (user_id = auth.uid());

alter table public.actions add column if not exists controller_id uuid;
alter table public.actions add column if not exists payload text check (char_length(payload) <= 20000);
alter table public.actions add column if not exists sig text check (char_length(sig) <= 120);
alter table public.actions add column if not exists sig_ts bigint;
grant insert (id, controller_id, payload, sig, sig_ts) on public.actions to authenticated;
