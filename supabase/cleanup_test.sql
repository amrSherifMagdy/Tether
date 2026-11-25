-- Remove the isolation-test users and invites.
delete from auth.users where email like '%@laptoplink.test';
delete from public.invites where email like '%@laptoplink.test';
