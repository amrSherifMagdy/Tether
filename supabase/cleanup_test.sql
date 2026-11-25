-- Remove the isolation-test users.
delete from auth.users where email like '%@laptoplink.test';
