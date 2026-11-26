-- Le valutazioni dei docenti le vede l'admin o chi e stato autorizzato dall'admin
alter table public.admin_utenti add column vede_docenti boolean not null default false;

-- Nessun limite per dipartimento sugli editor
alter table public.admin_utenti drop column dipartimento_id;

create or replace function private.puo_vedere_docenti() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select ruolo = 'admin' or vede_docenti from public.admin_utenti where user_id = (select auth.uid())), false)
$$;
grant execute on function private.puo_vedere_docenti() to anon, authenticated;

drop policy "ruoli leggono risultati" on public.risposte;
create policy "ruoli leggono risposte" on public.risposte for select to authenticated
  using (
    (select private.puo_leggere_risultati())
    and (insegnamento_id is null or (select private.puo_vedere_docenti()))
  );

drop policy "ruoli leggono risultati" on public.blocchi_saltati;
create policy "ruoli leggono blocchi saltati" on public.blocchi_saltati for select to authenticated
  using ((select private.puo_leggere_risultati()) and (select private.puo_vedere_docenti()));
