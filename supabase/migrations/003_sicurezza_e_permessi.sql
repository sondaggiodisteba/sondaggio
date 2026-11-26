-- Accesso alle funzioni di ruolo (necessario per valutare le regole)
revoke execute on all functions in schema private from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.ruolo_admin(), private.e_admin(), private.puo_modificare(), private.puo_leggere_risultati() to anon, authenticated;

-- Tabelle di contenuto: tutti leggono (con filtri sotto), solo admin ed editor scrivono
do $$
declare t text;
begin
  foreach t in array array['dipartimenti','corsi_di_laurea','materie','materie_corso','docenti','insegnamenti','domande','opzioni_risposta','collegamenti_domanda'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('grant insert, update, delete on public.%I to authenticated', t);
    execute format('create policy "staff inserisce" on public.%I for insert to authenticated with check ((select private.puo_modificare()))', t);
    execute format('create policy "staff modifica" on public.%I for update to authenticated using ((select private.puo_modificare())) with check ((select private.puo_modificare()))', t);
    execute format('create policy "staff elimina" on public.%I for delete to authenticated using ((select private.puo_modificare()))', t);
  end loop;
end $$;

create policy "lettura dipartimenti" on public.dipartimenti for select to anon, authenticated
  using (attivo or (select private.puo_modificare()));
create policy "lettura corsi" on public.corsi_di_laurea for select to anon, authenticated
  using (attivo or (select private.puo_modificare()));
create policy "lettura materie" on public.materie for select to anon, authenticated
  using (attiva or (select private.puo_modificare()));
create policy "lettura docenti" on public.docenti for select to anon, authenticated
  using (attivo or (select private.puo_modificare()));
create policy "lettura materie_corso" on public.materie_corso for select to anon, authenticated using (true);
create policy "lettura insegnamenti" on public.insegnamenti for select to anon, authenticated using (true);
create policy "lettura collegamenti" on public.collegamenti_domanda for select to anon, authenticated using (true);
create policy "lettura domande" on public.domande for select to anon, authenticated
  using (attiva or (select private.puo_modificare()));
create policy "lettura opzioni" on public.opzioni_risposta for select to anon, authenticated
  using (
    (select private.puo_modificare())
    or exists (select 1 from public.domande d where d.id = domanda_id and d.attiva)
  );

-- Edizioni: lettura pubblica, gestione solo admin
alter table public.edizioni enable row level security;
revoke all on public.edizioni from anon, authenticated;
grant select on public.edizioni to anon, authenticated;
grant insert, update, delete on public.edizioni to authenticated;
create policy "lettura edizioni" on public.edizioni for select to anon, authenticated using (true);
create policy "admin inserisce edizioni" on public.edizioni for insert to authenticated with check ((select private.e_admin()));
create policy "admin modifica edizioni" on public.edizioni for update to authenticated using ((select private.e_admin())) with check ((select private.e_admin()));
create policy "admin elimina edizioni" on public.edizioni for delete to authenticated using ((select private.e_admin()));

-- Impostazioni: lettura per admin ed editor, modifica solo admin
alter table public.impostazioni enable row level security;
revoke all on public.impostazioni from anon, authenticated;
grant select, insert, update, delete on public.impostazioni to authenticated;
create policy "staff legge impostazioni" on public.impostazioni for select to authenticated using ((select private.puo_modificare()));
create policy "admin inserisce impostazioni" on public.impostazioni for insert to authenticated with check ((select private.e_admin()));
create policy "admin modifica impostazioni" on public.impostazioni for update to authenticated using ((select private.e_admin())) with check ((select private.e_admin()));
create policy "admin elimina impostazioni" on public.impostazioni for delete to authenticated using ((select private.e_admin()));

-- Risultati: solo lettura per chi ha un ruolo nel pannello, nessuna scrittura diretta
do $$
declare t text;
begin
  foreach t in array array['compilazioni','risposte','blocchi_saltati'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy "ruoli leggono risultati" on public.%I for select to authenticated using ((select private.puo_leggere_risultati()))', t);
  end loop;
end $$;

-- Partecipazioni: chiusa a tutti dall'API (nessun permesso, nessuna regola)
alter table public.partecipazioni enable row level security;
revoke all on public.partecipazioni from anon, authenticated;

-- Utenti del pannello
alter table public.admin_utenti enable row level security;
revoke all on public.admin_utenti from anon, authenticated;
grant select, insert, update, delete on public.admin_utenti to authenticated;
create policy "legge il proprio ruolo" on public.admin_utenti for select to authenticated
  using (user_id = (select auth.uid()) or (select private.e_admin()));
create policy "admin inserisce utenti" on public.admin_utenti for insert to authenticated with check ((select private.e_admin()));
create policy "admin modifica utenti" on public.admin_utenti for update to authenticated using ((select private.e_admin())) with check ((select private.e_admin()));
create policy "admin elimina utenti" on public.admin_utenti for delete to authenticated using ((select private.e_admin()));
