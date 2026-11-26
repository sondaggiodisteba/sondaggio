-- Da eseguire nello SQL Editor DOPO installa.sql, sostituendo l'email in maiuscolo.

-- 1. Il dipartimento: ne serve uno solo (i corsi di laurea vi vengono associati da soli)
insert into public.dipartimenti (nome) values ('DiSTeBA');

-- 2. Il primo admin del pannello. Crea prima l'account in Authentication → Users → Add user
--    (con «Auto Confirm User»), poi scrivi qui la stessa email.
--    Il comando deve restituire una riga: se non ne restituisce nessuna, l'email non corrisponde.
insert into public.admin_utenti (user_id, ruolo, vede_docenti)
select id, 'admin', true from auth.users where lower(email) = lower('EMAIL-DEL-PRIMO-ADMIN')
returning user_id;
