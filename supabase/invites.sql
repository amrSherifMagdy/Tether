-- Who may sign up. Run in the Supabase SQL Editor after editing the emails below.
-- Add more people later the same way (never commit real emails to this file).
insert into public.invites (email, note) values
  ('owner@example.com', 'owner'),
  ('friend@example.com', 'friend')
on conflict (email) do nothing;
