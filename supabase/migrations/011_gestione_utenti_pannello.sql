-- Gestione degli utenti del pannello, riservata agli admin.
-- Le email stanno in auth.users, non leggibile dal sito: queste funzioni fanno da tramite.

create or replace function public.elenco_utenti_pannello()
returns table (user_id uuid, email text, ruolo text, vede_docenti boolean, ultimo_accesso timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_admin() then
    raise exception 'Solo un admin può vedere gli utenti del pannello';
  end if;
  return query
    select a.user_id, u.email::text, a.ruolo, a.vede_docenti, u.last_sign_in_at
    from public.admin_utenti a
    join auth.users u on u.id = a.user_id
    order by a.ruolo, u.email;
end $$;

create or replace function public.imposta_utente_pannello(p_email text, p_ruolo text, p_vede_docenti boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_attuale text;
begin
  if not private.e_admin() then
    raise exception 'Solo un admin può gestire gli utenti del pannello';
  end if;
  if p_ruolo not in ('admin', 'editor', 'lettura') then
    raise exception 'Ruolo non valido';
  end if;
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'Nessun account con questa email: crealo prima in Supabase (Authentication, Users)';
  end if;
  select ruolo into v_attuale from public.admin_utenti where user_id = v_id;
  if v_attuale = 'admin' and p_ruolo <> 'admin'
     and (select count(*) from public.admin_utenti where ruolo = 'admin') <= 1 then
    raise exception 'Deve restare almeno un admin';
  end if;
  insert into public.admin_utenti (user_id, ruolo, vede_docenti)
    values (v_id, p_ruolo, p_vede_docenti)
  on conflict (user_id) do update
    set ruolo = excluded.ruolo, vede_docenti = excluded.vede_docenti;
end $$;

create or replace function public.rimuovi_utente_pannello(p_user_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_attuale text;
begin
  if not private.e_admin() then
    raise exception 'Solo un admin può gestire gli utenti del pannello';
  end if;
  select ruolo into v_attuale from public.admin_utenti where user_id = p_user_id;
  if v_attuale = 'admin' and (select count(*) from public.admin_utenti where ruolo = 'admin') <= 1 then
    raise exception 'Deve restare almeno un admin';
  end if;
  delete from public.admin_utenti where user_id = p_user_id;
end $$;

revoke execute on function public.elenco_utenti_pannello() from public, anon;
revoke execute on function public.imposta_utente_pannello(text, text, boolean) from public, anon;
revoke execute on function public.rimuovi_utente_pannello(uuid) from public, anon;
grant execute on function public.elenco_utenti_pannello() to authenticated;
grant execute on function public.imposta_utente_pannello(text, text, boolean) to authenticated;
grant execute on function public.rimuovi_utente_pannello(uuid) to authenticated;
