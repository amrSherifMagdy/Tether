-- Tether alert emails to the owner (free): new pairing request + first sign-in from a new app/browser.
-- Run once in the SQL Editor AFTER schema.sql. Safe to re-run.
-- Sends through Resend's HTTP API from the database (pg_net). The API key lives in Supabase Vault, never in this file.
-- A failure here never blocks pairing or sign-in (everything is wrapped and ignored on error).

create extension if not exists pg_net;
do $$ begin create extension if not exists supabase_vault; exception when others then null; end $$;

create table if not exists public.lk_alert_settings (
  id int primary key default 1 check (id = 1),
  alert_to text not null
);
alter table public.lk_alert_settings enable row level security;
revoke all on public.lk_alert_settings from anon, authenticated;
-- Where alerts go. With Resend's free test sender this MUST be the email you signed up to Resend with.
insert into public.lk_alert_settings (id, alert_to) values (1, 'you@example.com')
  on conflict (id) do nothing;

create table if not exists public.lk_seen_agents (
  user_id uuid not null,
  user_agent text not null,
  first_seen timestamptz not null default now(),
  primary key (user_id, user_agent)
);
alter table public.lk_seen_agents enable row level security;
revoke all on public.lk_seen_agents from anon, authenticated;

create or replace function public.lk_esc(t text) returns text language sql immutable as $$
  select replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$$;

create or replace function public.lk_send_alert(subj text, body_html text) returns void
language plpgsql security definer set search_path = public as $$
declare k text; to_addr text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  select alert_to into to_addr from public.lk_alert_settings where id = 1;
  if k is null or to_addr is null then return; end if;
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object('from', 'Tether <onboarding@resend.dev>', 'to', jsonb_build_array(to_addr),
                               'subject', subj, 'html', body_html));
exception when others then null;
end $$;
revoke all on function public.lk_send_alert(text, text) from public, anon, authenticated;

-- 1) new pairing request
create or replace function public.lk_alert_controller() returns trigger
language plpgsql security definer set search_path = public as $$
declare em text;
begin
  select email into em from auth.users where id = new.user_id;
  perform public.lk_send_alert(
    'Tether: a new device asks to control a laptop',
    '<p>A controller named <b>' || public.lk_esc(new.name) || '</b> asked to pair for the account <b>' || public.lk_esc(em) || '</b>.</p>'
    || '<p>Nothing happens until someone taps <b>Allow</b> on that laptop. If this was not you or your assistant: tap <b>Deny</b> on the laptop and change the account password.</p>');
  return new;
exception when others then return new;
end $$;
revoke all on function public.lk_alert_controller() from public, anon, authenticated;
drop trigger if exists lk_alert_controller on public.controllers;
create trigger lk_alert_controller after insert on public.controllers for each row execute function public.lk_alert_controller();

-- 2) first sign-in from a new app/browser (by user agent), once per kind
create or replace function public.lk_alert_signin() returns trigger
language plpgsql security definer set search_path = public as $$
declare em text; ua text; ins int;
begin
  ua := coalesce(new.user_agent, 'unknown');
  insert into public.lk_seen_agents (user_id, user_agent) values (new.user_id, ua) on conflict do nothing;
  get diagnostics ins = row_count;
  if ins = 0 then return new; end if;
  select email into em from auth.users where id = new.user_id;
  perform public.lk_send_alert(
    'Tether: sign-in from a new app or browser',
    '<p>The account <b>' || public.lk_esc(em) || '</b> just signed in from a new app or browser.</p>'
    || '<p>Details: <code>' || public.lk_esc(left(ua, 200)) || '</code>, IP ' || public.lk_esc(new.ip::text) || '.</p>'
    || '<p>If this was not you, change the password. A sign-in alone cannot control the laptop: that also needs an approved controller.</p>');
  return new;
exception when others then return new;
end $$;
revoke all on function public.lk_alert_signin() from public, anon, authenticated;
do $$ begin
  drop trigger if exists lk_alert_signin on auth.sessions;
  create trigger lk_alert_signin after insert on auth.sessions for each row execute function public.lk_alert_signin();
exception when others then raise notice 'sign-in alerts not enabled: %', sqlerrm;
end $$;
