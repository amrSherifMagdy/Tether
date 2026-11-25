-- OPTIONAL. Tether sign-up is open by default. Run this only if you want an invite-only project.
-- It creates an allowlist and refuses sign-ups for emails that are not on it.
-- To go back to open sign-up: drop trigger if exists gate_signup on auth.users;
create table if not exists public.invites (
  email text primary key check (email = lower(email)),
  note text,
  created_at timestamptz not null default now()
);
alter table public.invites enable row level security;   -- no policies: nobody can read or write it through the API
revoke all on public.invites from anon, authenticated;

create or replace function public.gate_signup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.invites i where i.email = lower(new.email)) then
    raise exception 'This email is not invited to Tether';
  end if;
  return new;
end $$;

drop trigger if exists gate_signup on auth.users;
create trigger gate_signup before insert on auth.users
  for each row execute function public.gate_signup();

-- Edit, then run (never commit real emails to the repo):
insert into public.invites (email, note) values
  ('owner@example.com', 'owner')
on conflict (email) do nothing;
