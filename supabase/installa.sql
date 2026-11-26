-- Tutto il database del sondaggio in un colpo solo, per un progetto Supabase NUOVO e vuoto.
-- Incollalo nello SQL Editor ed eseguilo una volta. Sono i file di supabase/migrations/ uno dopo l'altro.
-- Non va eseguito su un database dove il sondaggio c'è già.

begin;

-- ===== 001_tabelle_sondaggio.sql =====
create schema if not exists private;

-- Struttura accademica
create table public.dipartimenti (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  attivo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.corsi_di_laurea (
  id uuid primary key default gen_random_uuid(),
  dipartimento_id uuid not null references public.dipartimenti(id) on delete restrict,
  nome text not null,
  tipo text not null check (tipo in ('triennale','magistrale','ciclo_unico')),
  durata_anni smallint not null check (durata_anni between 1 and 6),
  attivo boolean not null default true,
  created_at timestamptz not null default now(),
  unique (dipartimento_id, nome)
);
create index corsi_dipartimento_idx on public.corsi_di_laurea (dipartimento_id);

create table public.materie (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cfu smallint check (cfu > 0),
  attiva boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.materie_corso (
  id uuid primary key default gen_random_uuid(),
  materia_id uuid not null references public.materie(id) on delete restrict,
  corso_id uuid not null references public.corsi_di_laurea(id) on delete restrict,
  anno smallint not null check (anno between 1 and 6),
  unique (materia_id, corso_id)
);
create index materie_corso_corso_idx on public.materie_corso (corso_id);

create table public.docenti (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cognome text not null,
  dipartimento_id uuid references public.dipartimenti(id) on delete set null,
  attivo boolean not null default true,
  created_at timestamptz not null default now()
);
create index docenti_dipartimento_idx on public.docenti (dipartimento_id);

create table public.insegnamenti (
  id uuid primary key default gen_random_uuid(),
  materia_id uuid not null references public.materie(id) on delete restrict,
  docente_id uuid not null references public.docenti(id) on delete restrict,
  unique (materia_id, docente_id)
);
create index insegnamenti_docente_idx on public.insegnamenti (docente_id);

-- Edizioni (cicli di compilazione, aperti e chiusi dal pannello admin)
create table public.edizioni (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  anno_accademico text not null,
  aperta boolean not null default false,
  aperta_il timestamptz,
  chiusa_il timestamptz,
  created_at timestamptz not null default now()
);
create unique index una_sola_edizione_aperta on public.edizioni ((true)) where aperta;

-- Domande
create table public.domande (
  id uuid primary key default gen_random_uuid(),
  testo text not null check (length(btrim(testo)) > 0),
  categoria text not null check (categoria in ('generica','specifica_materia','generica_docente','specifica_docente')),
  ambito_docente text check (ambito_docente in ('docente','insegnamento')),
  tipo_risposta text not null check (tipo_risposta in ('scala','scelta_singola','testo_libero')),
  scala_min smallint,
  scala_max smallint,
  etichetta_min text,
  etichetta_max text,
  obbligatoria boolean not null default true,
  attiva boolean not null default false,
  ordine integer not null default 0,
  created_at timestamptz not null default now(),
  constraint ambito_coerente check ((categoria = 'specifica_docente') = (ambito_docente is not null)),
  constraint scala_coerente check (
    (tipo_risposta = 'scala' and scala_min is not null and scala_max is not null and scala_min < scala_max)
    or (tipo_risposta <> 'scala' and scala_min is null and scala_max is null)
  )
);

create table public.opzioni_risposta (
  id uuid primary key default gen_random_uuid(),
  domanda_id uuid not null references public.domande(id) on delete cascade,
  testo text not null check (length(btrim(testo)) > 0),
  ordine smallint not null,
  unique (domanda_id, ordine)
);

create table public.collegamenti_domanda (
  id uuid primary key default gen_random_uuid(),
  domanda_id uuid not null references public.domande(id) on delete cascade,
  materia_id uuid references public.materie(id) on delete cascade,
  docente_id uuid references public.docenti(id) on delete cascade,
  insegnamento_id uuid references public.insegnamenti(id) on delete cascade,
  constraint un_solo_collegamento check (num_nonnulls(materia_id, docente_id, insegnamento_id) = 1)
);
create unique index coll_materia_uq on public.collegamenti_domanda (domanda_id, materia_id) where materia_id is not null;
create unique index coll_docente_uq on public.collegamenti_domanda (domanda_id, docente_id) where docente_id is not null;
create unique index coll_insegnamento_uq on public.collegamenti_domanda (domanda_id, insegnamento_id) where insegnamento_id is not null;
create index coll_materia_idx on public.collegamenti_domanda (materia_id);
create index coll_docente_idx on public.collegamenti_domanda (docente_id);
create index coll_insegnamento_idx on public.collegamenti_domanda (insegnamento_id);

create table public.impostazioni (
  chiave text primary key,
  valore text not null,
  descrizione text
);
insert into public.impostazioni (chiave, valore, descrizione) values
  ('opzioni_min', '3', 'Numero minimo di opzioni per le domande a scelta singola'),
  ('opzioni_max', '5', 'Numero massimo di opzioni per le domande a scelta singola');

-- Compilazioni e risposte (anonime: nessun riferimento allo studente)
create table public.compilazioni (
  id uuid primary key default gen_random_uuid(),
  edizione_id uuid not null references public.edizioni(id) on delete restrict,
  materia_corso_id uuid not null references public.materie_corso(id) on delete restrict,
  anno_studente smallint not null check (anno_studente between 1 and 6),
  data_compilazione date not null default current_date
);
create index compilazioni_edizione_idx on public.compilazioni (edizione_id);
create index compilazioni_materia_corso_idx on public.compilazioni (materia_corso_id);

create table public.risposte (
  id uuid primary key default gen_random_uuid(),
  compilazione_id uuid not null references public.compilazioni(id) on delete cascade,
  domanda_id uuid not null references public.domande(id) on delete restrict,
  insegnamento_id uuid references public.insegnamenti(id) on delete restrict,
  valore_numero smallint,
  opzione_id uuid references public.opzioni_risposta(id) on delete restrict,
  testo text check (length(testo) <= 2000),
  constraint un_solo_valore check (num_nonnulls(valore_numero, opzione_id, testo) = 1)
);
create unique index risposte_unica on public.risposte (compilazione_id, domanda_id, coalesce(insegnamento_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index risposte_domanda_idx on public.risposte (domanda_id);
create index risposte_insegnamento_idx on public.risposte (insegnamento_id);
create index risposte_opzione_idx on public.risposte (opzione_id);

create table public.blocchi_saltati (
  id uuid primary key default gen_random_uuid(),
  compilazione_id uuid not null references public.compilazioni(id) on delete cascade,
  insegnamento_id uuid not null references public.insegnamenti(id) on delete restrict,
  unique (compilazione_id, insegnamento_id)
);
create index blocchi_insegnamento_idx on public.blocchi_saltati (insegnamento_id);

-- Partecipazioni: solo per impedire i doppi invii, senza alcun legame con le compilazioni
create table public.partecipazioni (
  id uuid primary key default gen_random_uuid(),
  edizione_id uuid not null references public.edizioni(id) on delete restrict,
  materia_corso_id uuid not null references public.materie_corso(id) on delete restrict,
  studente_hash text not null,
  unique (edizione_id, materia_corso_id, studente_hash)
);
create index partecipazioni_materia_corso_idx on public.partecipazioni (materia_corso_id);

-- Utenti del pannello admin
create table public.admin_utenti (
  user_id uuid primary key references auth.users(id) on delete cascade,
  ruolo text not null check (ruolo in ('admin','editor','lettura')),
  dipartimento_id uuid references public.dipartimenti(id) on delete set null,
  created_at timestamptz not null default now()
);
create index admin_utenti_dipartimento_idx on public.admin_utenti (dipartimento_id);

-- ===== 002_funzioni_e_controlli.sql =====
-- Funzioni di ruolo usate dalle regole di accesso
create or replace function private.ruolo_admin() returns text
language sql stable security definer set search_path = '' as $$
  select ruolo from public.admin_utenti where user_id = (select auth.uid())
$$;

create or replace function private.e_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.ruolo_admin() = 'admin', false)
$$;

create or replace function private.puo_modificare() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.ruolo_admin() in ('admin','editor'), false)
$$;

create or replace function private.puo_leggere_risultati() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.ruolo_admin() in ('admin','editor','lettura'), false)
$$;

create or replace function private.get_setting_int(k text, def int) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select valore::int from public.impostazioni where chiave = k), def)
$$;

-- L'anno della materia non puo superare la durata del corso
create or replace function private.check_anno_materia_corso() returns trigger
language plpgsql set search_path = '' as $$
declare d smallint;
begin
  select durata_anni into d from public.corsi_di_laurea where id = new.corso_id;
  if new.anno > d then
    raise exception 'L''anno % supera la durata del corso (% anni)', new.anno, d;
  end if;
  return new;
end $$;
create trigger materie_corso_anno before insert or update on public.materie_corso
  for each row execute function private.check_anno_materia_corso();

-- Date di apertura e chiusura delle edizioni
create or replace function private.edizione_date() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.aperta then new.aperta_il := now(); end if;
  else
    if new.aperta and not old.aperta then
      new.aperta_il := now(); new.chiusa_il := null;
    elsif not new.aperta and old.aperta then
      new.chiusa_il := now();
    end if;
  end if;
  return new;
end $$;
create trigger edizioni_date before insert or update on public.edizioni
  for each row execute function private.edizione_date();

-- Opzioni: limiti min/max dalle impostazioni, nessuna modifica se ci sono risposte
create or replace function private.proteggi_opzioni() returns trigger
language plpgsql security definer set search_path = '' as $$
declare did uuid; n int; mx int; mn int; att boolean;
begin
  if tg_op = 'DELETE' then did := old.domanda_id; else did := new.domanda_id; end if;
  if exists (select 1 from public.risposte where domanda_id = did) then
    raise exception 'Domanda con risposte gia raccolte: le opzioni non sono modificabili';
  end if;
  select count(*) into n from public.opzioni_risposta where domanda_id = did;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and old.domanda_id <> new.domanda_id) then
    mx := private.get_setting_int('opzioni_max', 5);
    if n >= mx then raise exception 'Massimo % opzioni per domanda', mx; end if;
  end if;
  if tg_op = 'DELETE' then
    select attiva into att from public.domande where id = did;
    mn := private.get_setting_int('opzioni_min', 3);
    if found and att and (n - 1) < mn then
      raise exception 'Una domanda attiva deve avere almeno % opzioni', mn;
    end if;
    return old;
  end if;
  return new;
end $$;
create trigger opzioni_protette before insert or update or delete on public.opzioni_risposta
  for each row execute function private.proteggi_opzioni();

-- Domande: niente modifiche sostanziali con risposte raccolte; controlli all'attivazione
create or replace function private.proteggi_domande() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n int; mn int; mx int;
begin
  if tg_op = 'UPDATE' then
    if exists (select 1 from public.risposte where domanda_id = old.id)
       and (new.categoria is distinct from old.categoria
         or new.tipo_risposta is distinct from old.tipo_risposta
         or new.testo is distinct from old.testo
         or new.scala_min is distinct from old.scala_min
         or new.scala_max is distinct from old.scala_max
         or new.ambito_docente is distinct from old.ambito_docente) then
      raise exception 'Domanda con risposte gia raccolte: disattivala e creane una nuova';
    end if;
  end if;
  if new.attiva then
    if new.tipo_risposta = 'scelta_singola' then
      select count(*) into n from public.opzioni_risposta where domanda_id = new.id;
      mn := private.get_setting_int('opzioni_min', 3);
      mx := private.get_setting_int('opzioni_max', 5);
      if n < mn or n > mx then
        raise exception 'Una domanda a scelta singola attiva deve avere da % a % opzioni (ora %)', mn, mx, n;
      end if;
    end if;
    if new.categoria in ('specifica_materia','specifica_docente')
       and not exists (select 1 from public.collegamenti_domanda where domanda_id = new.id) then
      raise exception 'Una domanda specifica attiva deve avere almeno un collegamento';
    end if;
  end if;
  return new;
end $$;
create trigger domande_protette before insert or update on public.domande
  for each row execute function private.proteggi_domande();

-- Collegamenti coerenti con la categoria della domanda
create or replace function private.valida_collegamento() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c text; a text;
begin
  select categoria, ambito_docente into c, a from public.domande where id = new.domanda_id;
  if c in ('generica','generica_docente') then
    raise exception 'Le domande di categoria % non hanno collegamenti', c;
  elsif c = 'specifica_materia' and new.materia_id is null then
    raise exception 'Una domanda specifica per materia va collegata a una materia';
  elsif c = 'specifica_docente' and a = 'docente' and new.docente_id is null then
    raise exception 'Questa domanda va collegata a un docente';
  elsif c = 'specifica_docente' and a = 'insegnamento' and new.insegnamento_id is null then
    raise exception 'Questa domanda va collegata a una coppia materia + docente';
  end if;
  return new;
end $$;
create trigger collegamenti_validi before insert or update on public.collegamenti_domanda
  for each row execute function private.valida_collegamento();

-- Compilazioni: edizione aperta e anno coerente con il corso
create or replace function private.valida_compilazione() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d smallint;
begin
  if not exists (select 1 from public.edizioni where id = new.edizione_id and aperta) then
    raise exception 'L''edizione non e aperta alla compilazione';
  end if;
  select c.durata_anni into d
    from public.materie_corso mc join public.corsi_di_laurea c on c.id = mc.corso_id
    where mc.id = new.materia_corso_id;
  if new.anno_studente > d then
    raise exception 'L''anno dello studente supera la durata del corso';
  end if;
  return new;
end $$;
create trigger compilazioni_valide before insert on public.compilazioni
  for each row execute function private.valida_compilazione();

create or replace function private.richiedi_edizione_aperta() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.edizioni where id = new.edizione_id and aperta) then
    raise exception 'L''edizione non e aperta alla compilazione';
  end if;
  return new;
end $$;
create trigger partecipazioni_edizione before insert on public.partecipazioni
  for each row execute function private.richiedi_edizione_aperta();

-- Risposte: coerenza con tipo di domanda, materia, docente e collegamenti
create or replace function private.valida_risposta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d public.domande%rowtype; mat uuid; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  elsif d.tipo_risposta = 'scelta_singola' then
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  else
    if new.testo is null or length(btrim(new.testo)) = 0 then raise exception 'Risposta testuale vuota'; end if;
  end if;
  return new;
end $$;
create trigger risposte_valide before insert on public.risposte
  for each row execute function private.valida_risposta();

create or replace function private.valida_blocco_saltato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare mat uuid; ins_mat uuid;
begin
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  select materia_id into ins_mat from public.insegnamenti where id = new.insegnamento_id;
  if ins_mat is distinct from mat then
    raise exception 'Il docente non appartiene alla materia compilata';
  end if;
  return new;
end $$;
create trigger blocchi_validi before insert on public.blocchi_saltati
  for each row execute function private.valida_blocco_saltato();

-- ===== 003_sicurezza_e_permessi.sql =====
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

-- ===== 004_chiudi_rls_auto_enable.sql =====
do $$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;

-- ===== 005_rimuovi_testo_libero.sql =====
-- Il sondaggio non prevede risposte a testo libero
alter table public.domande drop constraint domande_tipo_risposta_check;
alter table public.domande add constraint domande_tipo_risposta_check check (tipo_risposta in ('scala','scelta_singola'));

alter table public.risposte drop column testo;
alter table public.risposte add constraint un_solo_valore check (num_nonnulls(valore_numero, opzione_id) = 1);

create or replace function private.valida_risposta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d public.domande%rowtype; mat uuid; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  else
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  end if;
  return new;
end $$;

-- ===== 006_permesso_dati_docenti.sql =====
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

-- ===== 007_materia_non_seguita.sql =====
-- Una materia si puo saltare con "non ho seguito questa materia": compilazione senza risposte
alter table public.compilazioni add column non_seguita boolean not null default false;

create or replace function private.valida_risposta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d public.domande%rowtype; mat uuid; skipped boolean; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id, c.non_seguita into mat, skipped
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if skipped then raise exception 'La materia e stata dichiarata non seguita: nessuna risposta ammessa'; end if;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  else
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  end if;
  return new;
end $$;

create or replace function private.valida_blocco_saltato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare mat uuid; skipped boolean; ins_mat uuid;
begin
  select mc.materia_id, c.non_seguita into mat, skipped
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if skipped then raise exception 'La materia e stata dichiarata non seguita: nessun blocco docente'; end if;
  select materia_id into ins_mat from public.insegnamenti where id = new.insegnamento_id;
  if ins_mat is distinct from mat then
    raise exception 'Il docente non appartiene alla materia compilata';
  end if;
  return new;
end $$;

-- ===== 008_rimuovi_materia_non_seguita.sql =====
-- Lo studente sceglie a quali materie rispondere: "non seguita" non serve piu
alter table public.compilazioni drop column non_seguita;

create or replace function private.valida_risposta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d public.domande%rowtype; mat uuid; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  else
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  end if;
  return new;
end $$;

create or replace function private.valida_blocco_saltato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare mat uuid; ins_mat uuid;
begin
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  select materia_id into ins_mat from public.insegnamenti where id = new.insegnamento_id;
  if ins_mat is distinct from mat then
    raise exception 'Il docente non appartiene alla materia compilata';
  end if;
  return new;
end $$;

-- ===== 009_studente_fuori_corso.sql =====
-- Studenti fuori corso: nessun anno numerico, segnati con fuori_corso
alter table public.compilazioni alter column anno_studente drop not null;
alter table public.compilazioni add column fuori_corso boolean not null default false;
alter table public.compilazioni add constraint anno_o_fuori_corso check (
  (fuori_corso and anno_studente is null) or (not fuori_corso and anno_studente is not null)
);

create or replace function private.valida_compilazione() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d smallint;
begin
  if not exists (select 1 from public.edizioni where id = new.edizione_id and aperta) then
    raise exception 'L''edizione non e aperta alla compilazione';
  end if;
  select c.durata_anni into d
    from public.materie_corso mc join public.corsi_di_laurea c on c.id = mc.corso_id
    where mc.id = new.materia_corso_id;
  if new.anno_studente is not null and new.anno_studente > d then
    raise exception 'L''anno dello studente supera la durata del corso';
  end if;
  return new;
end $$;

-- ===== 010_invia_compilazioni.sql =====
-- Invio delle risposte dello studente: tutto in un'unica operazione atomica.
-- ATTENZIONE: finche non si sceglie il metodo di verifica degli studenti, la funzione non registra
-- le partecipazioni e quindi non impedisce i doppi invii. Non aprire un'edizione agli studenti prima.
create or replace function public.invia_compilazioni(
  p_edizione uuid,
  p_fuori_corso boolean,
  p_materie jsonb,
  p_anno smallint default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  m jsonb;
  v_mc uuid;
  v_materia uuid;
  v_comp uuid;
  v_saltati uuid[];
  v_mancanti int;
begin
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;
  if not p_fuori_corso and p_anno is null then
    raise exception 'Indica il tuo anno oppure fuori corso';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    v_mc := (m->>'materia_corso_id')::uuid;
    select mc.materia_id into v_materia from public.materie_corso mc where mc.id = v_mc;
    if v_materia is null then raise exception 'Materia non valida'; end if;

    insert into public.compilazioni(edizione_id, materia_corso_id, anno_studente, fuori_corso)
      values (p_edizione, v_mc, case when p_fuori_corso then null else p_anno end, p_fuori_corso)
      returning id into v_comp;

    insert into public.blocchi_saltati(compilazione_id, insegnamento_id)
      select v_comp, t.val::uuid
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    insert into public.risposte(compilazione_id, domanda_id, insegnamento_id, valore_numero, opzione_id)
      select v_comp, r.domanda_id, r.insegnamento_id, r.valore_numero, r.opzione_id
      from jsonb_to_recordset(coalesce(m->'risposte', '[]'::jsonb))
        as r(domanda_id uuid, insegnamento_id uuid, valore_numero smallint, opzione_id uuid);

    select coalesce(array_agg(t.val::uuid), '{}')
      into v_saltati
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    -- Domande obbligatorie applicabili alla materia che non hanno risposta
    select count(*) into v_mancanti
    from (
      select d.id as domanda_id, null::uuid as insegnamento_id
      from public.domande d
      where d.attiva and d.obbligatoria
        and (d.categoria = 'generica'
          or (d.categoria = 'specifica_materia' and exists (
                select 1 from public.collegamenti_domanda c
                where c.domanda_id = d.id and c.materia_id = v_materia)))
      union all
      select d.id, i.id
      from public.domande d
      join public.insegnamenti i on i.materia_id = v_materia
      join public.docenti dc on dc.id = i.docente_id and dc.attivo
      where d.attiva and d.obbligatoria
        and not (i.id = any(v_saltati))
        and (d.categoria = 'generica_docente'
          or (d.categoria = 'specifica_docente' and (
                (d.ambito_docente = 'docente' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.docente_id = i.docente_id))
             or (d.ambito_docente = 'insegnamento' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.insegnamento_id = i.id)))))
    ) richieste
    where not exists (
      select 1 from public.risposte r
      where r.compilazione_id = v_comp
        and r.domanda_id = richieste.domanda_id
        and r.insegnamento_id is not distinct from richieste.insegnamento_id
    );
    if v_mancanti > 0 then
      raise exception 'Mancano % risposte obbligatorie', v_mancanti;
    end if;
  end loop;
end $$;

revoke execute on function public.invia_compilazioni(uuid, boolean, jsonb, smallint) from public;
grant execute on function public.invia_compilazioni(uuid, boolean, jsonb, smallint) to anon, authenticated;

-- ===== 011_gestione_utenti_pannello.sql =====
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

-- ===== 012_statistiche.sql =====
-- Funzioni per le statistiche del pannello.
-- Sono "security invoker": girano con i permessi di chi le chiama, quindi le regole di accesso
-- (ruolo nel pannello, autorizzazione ai dati dei docenti) valgono anche qui.

create or replace function public.stat_risposte(
  p_edizione uuid,
  p_gruppo text default 'domanda',
  p_corso uuid default null,
  p_anno_corso smallint default null,
  p_anno_studente smallint default null,
  p_fuori_corso boolean default null,
  p_materia uuid default null,
  p_docente uuid default null
) returns table (
  domanda_id uuid, materia_id uuid, docente_id uuid,
  n bigint, somma bigint, distribuzione jsonb
)
language sql stable security invoker set search_path = '' as $$
  with base as (
    select r.domanda_id, mc.materia_id, i.docente_id, r.valore_numero, r.opzione_id
    from public.risposte r
    join public.compilazioni c on c.id = r.compilazione_id
    join public.materie_corso mc on mc.id = c.materia_corso_id
    left join public.insegnamenti i on i.id = r.insegnamento_id
    where c.edizione_id = p_edizione
      and (p_corso is null or mc.corso_id = p_corso)
      and (p_anno_corso is null or mc.anno = p_anno_corso)
      and (p_anno_studente is null or c.anno_studente = p_anno_studente)
      and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
      and (p_materia is null or mc.materia_id = p_materia)
      and (p_docente is null or i.docente_id = p_docente)
  ),
  gruppi as (
    select b.domanda_id,
           case when p_gruppo = 'domanda_materia' then b.materia_id end as materia_id,
           case when p_gruppo = 'domanda_docente' then b.docente_id end as docente_id,
           b.valore_numero, b.opzione_id, count(*) as k
    from base b
    group by 1, 2, 3, 4, 5
  )
  select g.domanda_id, g.materia_id, g.docente_id,
         sum(g.k)::bigint,
         coalesce(sum(g.valore_numero * g.k), 0)::bigint,
         jsonb_object_agg(coalesce(g.valore_numero::text, g.opzione_id::text), g.k)
  from gruppi g
  group by 1, 2, 3
$$;

create or replace function public.stat_saltati(
  p_edizione uuid,
  p_corso uuid default null,
  p_anno_corso smallint default null,
  p_anno_studente smallint default null,
  p_fuori_corso boolean default null,
  p_materia uuid default null,
  p_docente uuid default null
) returns table (materia_id uuid, docente_id uuid, n bigint)
language sql stable security invoker set search_path = '' as $$
  select mc.materia_id, i.docente_id, count(*)::bigint
  from public.blocchi_saltati b
  join public.compilazioni c on c.id = b.compilazione_id
  join public.materie_corso mc on mc.id = c.materia_corso_id
  join public.insegnamenti i on i.id = b.insegnamento_id
  where c.edizione_id = p_edizione
    and (p_corso is null or mc.corso_id = p_corso)
    and (p_anno_corso is null or mc.anno = p_anno_corso)
    and (p_anno_studente is null or c.anno_studente = p_anno_studente)
    and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
    and (p_materia is null or mc.materia_id = p_materia)
    and (p_docente is null or i.docente_id = p_docente)
  group by 1, 2
$$;

create or replace function public.stat_compilazioni(
  p_edizione uuid,
  p_corso uuid default null,
  p_anno_corso smallint default null,
  p_anno_studente smallint default null,
  p_fuori_corso boolean default null,
  p_materia uuid default null
) returns table (materia_id uuid, corso_id uuid, anno smallint, n bigint)
language sql stable security invoker set search_path = '' as $$
  select mc.materia_id, mc.corso_id, mc.anno, count(*)::bigint
  from public.compilazioni c
  join public.materie_corso mc on mc.id = c.materia_corso_id
  where c.edizione_id = p_edizione
    and (p_corso is null or mc.corso_id = p_corso)
    and (p_anno_corso is null or mc.anno = p_anno_corso)
    and (p_anno_studente is null or c.anno_studente = p_anno_studente)
    and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
    and (p_materia is null or mc.materia_id = p_materia)
  group by 1, 2, 3
$$;

revoke execute on function public.stat_risposte(uuid, text, uuid, smallint, smallint, boolean, uuid, uuid) from public, anon;
revoke execute on function public.stat_saltati(uuid, uuid, smallint, smallint, boolean, uuid, uuid) from public, anon;
revoke execute on function public.stat_compilazioni(uuid, uuid, smallint, smallint, boolean, uuid) from public, anon;
grant execute on function public.stat_risposte(uuid, text, uuid, smallint, smallint, boolean, uuid, uuid) to authenticated;
grant execute on function public.stat_saltati(uuid, uuid, smallint, smallint, boolean, uuid, uuid) to authenticated;
grant execute on function public.stat_compilazioni(uuid, uuid, smallint, smallint, boolean, uuid) to authenticated;

-- ===== 013_eliminazione_elementi.sql =====
-- Eliminazione di corsi, materie e docenti insieme ai loro collegamenti, in un'unica operazione.
-- Valgono i permessi di chi chiama (SECURITY INVOKER): le regole di sicurezza delle tabelle restano in vigore.
-- Se esistono risposte raccolte i collegamenti non si possono togliere e tutto viene annullato.

create or replace function public.elimina_corso(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from materie_corso where corso_id = p_id;
  delete from corsi_di_laurea where id = p_id;
  if not found then
    raise exception 'Non posso eliminare questo corso: non esiste o il tuo ruolo non lo consente.';
  end if;
exception
  when foreign_key_violation then
    raise exception 'Il corso ha già risposte raccolte: non si può eliminare. Puoi disattivarlo.';
end;
$$;

create or replace function public.elimina_materia(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from materie_corso where materia_id = p_id;
  delete from insegnamenti where materia_id = p_id;
  delete from materie where id = p_id;
  if not found then
    raise exception 'Non posso eliminare questa materia: non esiste o il tuo ruolo non lo consente.';
  end if;
exception
  when foreign_key_violation then
    raise exception 'La materia ha già risposte raccolte: non si può eliminare. Puoi disattivarla.';
end;
$$;

create or replace function public.elimina_docente(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from insegnamenti where docente_id = p_id;
  delete from docenti where id = p_id;
  if not found then
    raise exception 'Non posso eliminare questo docente: non esiste o il tuo ruolo non lo consente.';
  end if;
exception
  when foreign_key_violation then
    raise exception 'Il docente ha già risposte raccolte: non si può eliminare. Puoi disattivarlo.';
end;
$$;

revoke all on function public.elimina_corso(uuid), public.elimina_materia(uuid), public.elimina_docente(uuid) from public, anon;
grant execute on function public.elimina_corso(uuid), public.elimina_materia(uuid), public.elimina_docente(uuid) to authenticated;

-- ===== 014_rimuovi_eliminazione_elementi.sql =====
-- Si è scelto di non eliminare corsi, materie e docenti: si disattivano soltanto.
drop function if exists public.elimina_corso(uuid);
drop function if exists public.elimina_materia(uuid);
drop function if exists public.elimina_docente(uuid);

-- ===== 015_invio_verificato.sql =====
-- Invio delle compilazioni con verifica dello studente.
-- Lo studente accede con Google; una funzione sul server (che sola conosce la chiave segreta) controlla
-- l'identità e passa al database solo un'impronta. Qui l'impronta registra «questa persona ha già
-- compilato questa materia in questa edizione», senza collegarla in alcun modo alle risposte.

create or replace function public.invia_compilazioni_verificate(
  p_hash text,
  p_edizione uuid,
  p_fuori_corso boolean,
  p_materie jsonb,
  p_anno smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  m jsonb;
begin
  if p_hash is null or length(p_hash) < 32 then
    raise exception 'Verifica dello studente mancante';
  end if;
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    begin
      insert into public.partecipazioni(edizione_id, materia_corso_id, studente_hash)
        values (p_edizione, (m->>'materia_corso_id')::uuid, p_hash);
    exception when unique_violation then
      raise exception 'Hai gia compilato una delle materie scelte. Torna indietro e togli quelle gia inviate.';
    end;
  end loop;

  -- Stesse regole di sempre (edizione aperta, risposte valide, obbligatorie). Se fallisce, anche le
  -- partecipazioni appena registrate vengono annullate: è tutto un'unica operazione.
  perform public.invia_compilazioni(p_edizione, p_fuori_corso, p_materie, p_anno);
end $$;

-- Le materie che questa persona ha già compilato in un'edizione (per non fargliele rifare)
create or replace function public.materie_compilate(p_hash text, p_edizione uuid)
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select p.materia_corso_id
  from public.partecipazioni p
  where p.studente_hash = p_hash and p.edizione_id = p_edizione;
$$;

-- Solo il server verificato può usarle: nessun accesso dal browser
revoke all on function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint) from public, anon, authenticated;
revoke all on function public.materie_compilate(text, uuid) from public, anon, authenticated;
grant execute on function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint) to service_role;
grant execute on function public.materie_compilate(text, uuid) to service_role;

-- ===== 016_chiudi_invio_non_verificato.sql =====
-- L'invio delle compilazioni passa solo dalla funzione di verifica (accesso Google).
-- La vecchia funzione, che chiunque poteva chiamare dal browser, non è più raggiungibile da fuori:
-- resta usata solo da invia_compilazioni_verificate, che gira con i permessi del proprietario.
revoke all on function public.invia_compilazioni(uuid, boolean, jsonb, smallint) from public, anon, authenticated;
grant execute on function public.invia_compilazioni(uuid, boolean, jsonb, smallint) to service_role;

-- ===== 017_cancella_codici_alla_chiusura.sql =====
-- I codici di controllo (impronte degli studenti) servono solo mentre l'edizione è aperta, per impedire
-- le doppie compilazioni. Quando l'edizione si chiude vengono cancellati: restano soltanto le risposte,
-- che sono anonime. Riaprendo un'edizione già chiusa, chi aveva compilato potrebbe farlo di nuovo.

create or replace function private.cancella_codici_edizione_chiusa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.aperta and not new.aperta then
    delete from public.partecipazioni where edizione_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists edizioni_cancella_codici on public.edizioni;
create trigger edizioni_cancella_codici
  after update of aperta on public.edizioni
  for each row execute function private.cancella_codici_edizione_chiusa();

-- ===== 018_gruppi_e_domande_extra.sql =====
-- Gruppi di domande (titolo mostrato allo studente), domande «Extra» (una volta per studente,
-- non legate a una materia) e risposta scritta libera, ammessa solo nelle domande Extra.

alter table public.domande add column gruppo text;
alter table public.domande add constraint domande_gruppo_check
  check (gruppo is null or length(btrim(gruppo)) between 1 and 60);

alter table public.domande drop constraint domande_categoria_check;
alter table public.domande add constraint domande_categoria_check
  check (categoria = any (array['generica','specifica_materia','generica_docente','specifica_docente','extra']));

alter table public.domande drop constraint domande_tipo_risposta_check;
alter table public.domande add constraint domande_tipo_risposta_check
  check (tipo_risposta = any (array['scala','scelta_singola','testo']));

alter table public.domande add constraint testo_solo_extra
  check (tipo_risposta <> 'testo' or categoria = 'extra');

-- Risposte alle domande Extra: legate all'edizione, mai a una materia, a un docente o a una persona
create table public.risposte_extra (
  id uuid primary key default gen_random_uuid(),
  edizione_id uuid not null references public.edizioni(id) on delete restrict,
  domanda_id uuid not null references public.domande(id) on delete restrict,
  valore_numero smallint,
  opzione_id uuid references public.opzioni_risposta(id) on delete restrict,
  testo text,
  nascosta boolean not null default false,
  constraint un_solo_valore_extra check (num_nonnulls(valore_numero, opzione_id, testo) = 1),
  constraint testo_lunghezza check (testo is null or length(btrim(testo)) between 1 and 1000)
);
create index risposte_extra_edizione_domanda on public.risposte_extra (edizione_id, domanda_id);
alter table public.risposte_extra enable row level security;
revoke all on public.risposte_extra from anon, authenticated;
grant select on public.risposte_extra to authenticated;
create policy "ruoli leggono risposte extra" on public.risposte_extra
  for select to authenticated using ((select private.puo_leggere_risultati()));

-- Chi ha già risposto alle Extra (solo impronta, come per le materie): cancellata alla chiusura dell'edizione
create table public.partecipazioni_extra (
  id uuid primary key default gen_random_uuid(),
  edizione_id uuid not null references public.edizioni(id) on delete restrict,
  studente_hash text not null,
  unique (edizione_id, studente_hash)
);
alter table public.partecipazioni_extra enable row level security;
revoke all on public.partecipazioni_extra from anon, authenticated;

create trigger partecipazioni_extra_edizione before insert on public.partecipazioni_extra
  for each row execute function private.richiedi_edizione_aperta();

create or replace function private.cancella_codici_edizione_chiusa() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if old.aperta and not new.aperta then
    delete from public.partecipazioni where edizione_id = new.id;
    delete from public.partecipazioni_extra where edizione_id = new.id;
  end if;
  return new;
end $$;

-- Controlli sulle risposte Extra, come quelli sulle altre risposte
create or replace function private.valida_risposta_extra() returns trigger
language plpgsql security definer set search_path to '' as $$
declare d public.domande%rowtype;
begin
  if not exists (select 1 from public.edizioni where id = new.edizione_id and aperta) then
    raise exception 'L''edizione non e aperta alla compilazione';
  end if;
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva or d.categoria <> 'extra' then
    raise exception 'Domanda non valida o non attiva';
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  elsif d.tipo_risposta = 'scelta_singola' then
    if new.opzione_id is null or not exists (
      select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  elsif new.testo is null then
    raise exception 'Serve una risposta scritta';
  end if;
  return new;
end $$;
create trigger risposte_extra_valide before insert on public.risposte_extra
  for each row execute function private.valida_risposta_extra();

-- Una domanda con risposte (anche Extra) non si può più cambiare nel contenuto
create or replace function private.proteggi_domande() returns trigger
language plpgsql security definer set search_path to '' as $$
declare n int; mn int; mx int;
begin
  if tg_op = 'UPDATE' then
    if (exists (select 1 from public.risposte where domanda_id = old.id)
        or exists (select 1 from public.risposte_extra where domanda_id = old.id))
       and (new.categoria is distinct from old.categoria
         or new.tipo_risposta is distinct from old.tipo_risposta
         or new.testo is distinct from old.testo
         or new.scala_min is distinct from old.scala_min
         or new.scala_max is distinct from old.scala_max
         or new.ambito_docente is distinct from old.ambito_docente) then
      raise exception 'Domanda con risposte gia raccolte: disattivala e creane una nuova';
    end if;
  end if;
  if new.attiva then
    if new.tipo_risposta = 'scelta_singola' then
      select count(*) into n from public.opzioni_risposta where domanda_id = new.id;
      mn := private.get_setting_int('opzioni_min', 3);
      mx := private.get_setting_int('opzioni_max', 5);
      if n < mn or n > mx then
        raise exception 'Una domanda a scelta singola attiva deve avere da % a % opzioni (ora %)', mn, mx, n;
      end if;
    end if;
    if new.categoria in ('specifica_materia','specifica_docente')
       and not exists (select 1 from public.collegamenti_domanda where domanda_id = new.id) then
      raise exception 'Una domanda specifica attiva deve avere almeno un collegamento';
    end if;
  end if;
  return new;
end $$;

-- Per le domande Sì/No servono due opzioni
update public.impostazioni set valore = '2' where chiave = 'opzioni_min';

-- Statistiche delle Extra: stessa forma di stat_risposte (conteggi e distribuzione), senza filtri di corso
create or replace function public.stat_extra(p_edizione uuid)
returns table(domanda_id uuid, n bigint, somma bigint, distribuzione jsonb)
language sql stable set search_path to '' as $$
  with gruppi as (
    select r.domanda_id, r.valore_numero, r.opzione_id, count(*) as k
    from public.risposte_extra r
    where r.edizione_id = p_edizione and r.testo is null
    group by 1, 2, 3
  )
  select g.domanda_id, sum(g.k)::bigint, coalesce(sum(g.valore_numero * g.k), 0)::bigint,
         jsonb_object_agg(coalesce(g.valore_numero::text, g.opzione_id::text), g.k)
  from gruppi g group by 1
$$;
revoke all on function public.stat_extra(uuid) from public, anon;
grant execute on function public.stat_extra(uuid) to authenticated;

-- Nasconde (o mostra di nuovo) una risposta scritta inadeguata: solo chi può modificare
create or replace function public.nascondi_risposta_extra(p_id uuid, p_nascosta boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not (select private.puo_modificare()) then
    raise exception 'Non hai i permessi per farlo';
  end if;
  update public.risposte_extra set nascosta = p_nascosta where id = p_id and testo is not null;
end $$;
revoke all on function public.nascondi_risposta_extra(uuid, boolean) from public, anon;
grant execute on function public.nascondi_risposta_extra(uuid, boolean) to authenticated;

-- Il database dice se uno studente ha già risposto alle Extra
create or replace function public.extra_inviate(p_hash text, p_edizione uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.partecipazioni_extra
                 where studente_hash = p_hash and edizione_id = p_edizione);
$$;
revoke all on function public.extra_inviate(text, uuid) from public, anon, authenticated;
grant execute on function public.extra_inviate(text, uuid) to service_role;

-- Invio verificato: ora porta con sé anche le risposte Extra (una sola volta per studente)
drop function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint);
create function public.invia_compilazioni_verificate(
  p_hash text, p_edizione uuid, p_fuori_corso boolean, p_materie jsonb,
  p_anno smallint default null, p_extra jsonb default null)
returns void language plpgsql security definer set search_path to '' as $$
declare
  m jsonb;
  v_extra jsonb := coalesce(p_extra, '[]'::jsonb);
  v_fatto boolean;
  v_manc int;
begin
  if p_hash is null or length(p_hash) < 32 then
    raise exception 'Verifica dello studente mancante';
  end if;
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if jsonb_typeof(v_extra) <> 'array' then
    raise exception 'Risposte extra non valide';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    begin
      insert into public.partecipazioni(edizione_id, materia_corso_id, studente_hash)
        values (p_edizione, (m->>'materia_corso_id')::uuid, p_hash);
    exception when unique_violation then
      raise exception 'Hai gia compilato una delle materie scelte. Torna indietro e togli quelle gia inviate.';
    end;
  end loop;

  -- Stesse regole di sempre (edizione aperta, risposte valide, obbligatorie). Se fallisce, anche le
  -- partecipazioni appena registrate vengono annullate: è tutto un'unica operazione.
  perform public.invia_compilazioni(p_edizione, p_fuori_corso, p_materie, p_anno);

  -- Domande Extra: una sola volta per studente. Non si registra nulla se non risponde a nessuna
  -- e nessuna è obbligatoria, così potrà farlo in un invio successivo.
  v_fatto := exists (select 1 from public.partecipazioni_extra
                     where edizione_id = p_edizione and studente_hash = p_hash);
  if v_fatto then
    if jsonb_array_length(v_extra) > 0 then
      raise exception 'Hai gia risposto alle domande extra.';
    end if;
  elsif jsonb_array_length(v_extra) > 0
     or exists (select 1 from public.domande where attiva and categoria = 'extra' and obbligatoria) then
    if (select count(distinct e->>'domanda_id') from jsonb_array_elements(v_extra) e)
       <> jsonb_array_length(v_extra) then
      raise exception 'Una domanda extra compare piu volte';
    end if;
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               where length(btrim(coalesce(r.testo, ''))) > 1000) then
      raise exception 'Una risposta scritta supera i 1000 caratteri';
    end if;

    select count(*) into v_manc
    from public.domande d
    where d.attiva and d.categoria = 'extra' and d.obbligatoria
      and not exists (
        select 1 from jsonb_to_recordset(v_extra)
          as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
        where r.domanda_id = d.id
          and (r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> ''));
    if v_manc > 0 then
      raise exception 'Mancano % risposte obbligatorie nelle domande extra', v_manc;
    end if;

    insert into public.risposte_extra(edizione_id, domanda_id, valore_numero, opzione_id, testo)
      select p_edizione, r.domanda_id, r.valore_numero, r.opzione_id, nullif(btrim(r.testo), '')
      from jsonb_to_recordset(v_extra)
        as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
      where r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> '';

    if exists (select 1 from jsonb_array_elements(v_extra)) then
      insert into public.partecipazioni_extra(edizione_id, studente_hash) values (p_edizione, p_hash)
        on conflict do nothing;
    end if;
  end if;
end $$;
revoke all on function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint, jsonb)
  from public, anon, authenticated;
grant execute on function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint, jsonb)
  to service_role;

-- ===== 019_domande_condizionate.sql =====
-- Domande che compaiono solo in base alla risposta data a un'altra domanda a scelta singola
-- (ad esempio: «C'è un tutoraggio?» -> se Sì, «È utile?»). Un solo livello: il genitore non dipende da altre.

alter table public.domande
  add column mostra_se_domanda_id uuid references public.domande(id) on delete restrict,
  add column mostra_se_opzioni uuid[] not null default '{}';
alter table public.domande add constraint mostra_se_coerente
  check ((mostra_se_domanda_id is null) = (cardinality(mostra_se_opzioni) = 0));

create or replace function private.proteggi_domande() returns trigger
language plpgsql security definer set search_path to '' as $$
declare n int; mn int; mx int; g public.domande%rowtype;
begin
  if tg_op = 'UPDATE' then
    if (exists (select 1 from public.risposte where domanda_id = old.id)
        or exists (select 1 from public.risposte_extra where domanda_id = old.id))
       and (new.categoria is distinct from old.categoria
         or new.tipo_risposta is distinct from old.tipo_risposta
         or new.testo is distinct from old.testo
         or new.scala_min is distinct from old.scala_min
         or new.scala_max is distinct from old.scala_max
         or new.ambito_docente is distinct from old.ambito_docente
         or new.mostra_se_domanda_id is distinct from old.mostra_se_domanda_id
         or new.mostra_se_opzioni is distinct from old.mostra_se_opzioni) then
      raise exception 'Domanda con risposte gia raccolte: disattivala e creane una nuova';
    end if;
    -- Una domanda da cui ne dipendono altre attive non si disattiva e non cambia natura
    if exists (select 1 from public.domande c where c.mostra_se_domanda_id = old.id and c.attiva)
       and (not new.attiva
         or new.categoria is distinct from old.categoria
         or new.tipo_risposta is distinct from old.tipo_risposta) then
      raise exception 'Altre domande attive dipendono da questa: disattivale prima';
    end if;
  end if;

  if new.mostra_se_domanda_id is not null then
    if new.categoria not in ('generica','generica_docente','extra') then
      raise exception 'La condizione e ammessa solo nelle domande generiche, generiche sui docenti ed Extra';
    end if;
    select * into g from public.domande where id = new.mostra_se_domanda_id;
    if not found or g.id = new.id then raise exception 'Domanda da cui dipende non valida'; end if;
    if g.categoria <> new.categoria then
      raise exception 'La domanda da cui dipende deve avere la stessa categoria';
    end if;
    if g.tipo_risposta <> 'scelta_singola' then
      raise exception 'La domanda da cui dipende deve essere a scelta singola';
    end if;
    if g.mostra_se_domanda_id is not null then
      raise exception 'La domanda da cui dipende non puo dipendere a sua volta da un''altra';
    end if;
    if new.attiva then
      if not g.attiva then
        raise exception 'Attiva prima la domanda da cui dipende';
      end if;
      if exists (select 1 from unnest(new.mostra_se_opzioni) o
                 where not exists (select 1 from public.opzioni_risposta r
                                   where r.id = o and r.domanda_id = g.id)) then
        raise exception 'La condizione usa opzioni che la domanda non ha piu: riscegli le opzioni';
      end if;
    end if;
  end if;

  if new.attiva then
    if new.tipo_risposta = 'scelta_singola' then
      select count(*) into n from public.opzioni_risposta where domanda_id = new.id;
      mn := private.get_setting_int('opzioni_min', 3);
      mx := private.get_setting_int('opzioni_max', 5);
      if n < mn or n > mx then
        raise exception 'Una domanda a scelta singola attiva deve avere da % a % opzioni (ora %)', mn, mx, n;
      end if;
    end if;
    if new.categoria in ('specifica_materia','specifica_docente')
       and not exists (select 1 from public.collegamenti_domanda where domanda_id = new.id) then
      raise exception 'Una domanda specifica attiva deve avere almeno un collegamento';
    end if;
  end if;
  return new;
end $$;

-- Condizione verificata sulle risposte Extra di un invio (json)
create or replace function private.condizione_extra_ok(p_dom uuid, p_op uuid[], p_extra jsonb)
returns boolean language sql stable set search_path to '' as $$
  select p_dom is null or exists (
    select 1 from jsonb_to_recordset(p_extra) as r(domanda_id uuid, opzione_id uuid)
    where r.domanda_id = p_dom and r.opzione_id = any(p_op));
$$;

-- Invio delle materie: le domande condizionate contano come obbligatorie solo se la condizione e soddisfatta,
-- e una risposta a una domanda non prevista dalle risposte precedenti viene rifiutata.
create or replace function public.invia_compilazioni(
  p_edizione uuid, p_fuori_corso boolean, p_materie jsonb, p_anno smallint default null)
returns void language plpgsql security definer set search_path to '' as $$
declare
  m jsonb;
  v_mc uuid;
  v_materia uuid;
  v_comp uuid;
  v_saltati uuid[];
  v_mancanti int;
begin
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;
  if not p_fuori_corso and p_anno is null then
    raise exception 'Indica il tuo anno oppure fuori corso';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    v_mc := (m->>'materia_corso_id')::uuid;
    select mc.materia_id into v_materia from public.materie_corso mc where mc.id = v_mc;
    if v_materia is null then raise exception 'Materia non valida'; end if;

    insert into public.compilazioni(edizione_id, materia_corso_id, anno_studente, fuori_corso)
      values (p_edizione, v_mc, case when p_fuori_corso then null else p_anno end, p_fuori_corso)
      returning id into v_comp;

    insert into public.blocchi_saltati(compilazione_id, insegnamento_id)
      select v_comp, t.val::uuid
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    insert into public.risposte(compilazione_id, domanda_id, insegnamento_id, valore_numero, opzione_id)
      select v_comp, r.domanda_id, r.insegnamento_id, r.valore_numero, r.opzione_id
      from jsonb_to_recordset(coalesce(m->'risposte', '[]'::jsonb))
        as r(domanda_id uuid, insegnamento_id uuid, valore_numero smallint, opzione_id uuid);

    -- Nessuna risposta a una domanda che, secondo le risposte precedenti, non andava mostrata
    if exists (
      select 1 from public.risposte r
      join public.domande d on d.id = r.domanda_id
      where r.compilazione_id = v_comp and d.mostra_se_domanda_id is not null
        and not exists (
          select 1 from public.risposte p
          where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
            and p.insegnamento_id is not distinct from r.insegnamento_id
            and p.opzione_id = any(d.mostra_se_opzioni))
    ) then
      raise exception 'Una risposta non e prevista in base alle risposte precedenti';
    end if;

    select coalesce(array_agg(t.val::uuid), '{}')
      into v_saltati
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    -- Domande obbligatorie applicabili alla materia che non hanno risposta
    select count(*) into v_mancanti
    from (
      select d.id as domanda_id, null::uuid as insegnamento_id
      from public.domande d
      where d.attiva and d.obbligatoria
        and (d.categoria = 'generica'
          or (d.categoria = 'specifica_materia' and exists (
                select 1 from public.collegamenti_domanda c
                where c.domanda_id = d.id and c.materia_id = v_materia)))
        and (d.mostra_se_domanda_id is null or exists (
              select 1 from public.risposte p
              where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
                and p.insegnamento_id is null and p.opzione_id = any(d.mostra_se_opzioni)))
      union all
      select d.id, i.id
      from public.domande d
      join public.insegnamenti i on i.materia_id = v_materia
      join public.docenti dc on dc.id = i.docente_id and dc.attivo
      where d.attiva and d.obbligatoria
        and not (i.id = any(v_saltati))
        and (d.categoria = 'generica_docente'
          or (d.categoria = 'specifica_docente' and (
                (d.ambito_docente = 'docente' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.docente_id = i.docente_id))
             or (d.ambito_docente = 'insegnamento' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.insegnamento_id = i.id)))))
        and (d.mostra_se_domanda_id is null or exists (
              select 1 from public.risposte p
              where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
                and p.insegnamento_id = i.id and p.opzione_id = any(d.mostra_se_opzioni)))
    ) richieste
    where not exists (
      select 1 from public.risposte r
      where r.compilazione_id = v_comp
        and r.domanda_id = richieste.domanda_id
        and r.insegnamento_id is not distinct from richieste.insegnamento_id
    );
    if v_mancanti > 0 then
      raise exception 'Mancano % risposte obbligatorie', v_mancanti;
    end if;
  end loop;
end $$;

-- Invio verificato: stessa regola per le domande Extra
create or replace function public.invia_compilazioni_verificate(
  p_hash text, p_edizione uuid, p_fuori_corso boolean, p_materie jsonb,
  p_anno smallint default null, p_extra jsonb default null)
returns void language plpgsql security definer set search_path to '' as $$
declare
  m jsonb;
  v_extra jsonb := coalesce(p_extra, '[]'::jsonb);
  v_fatto boolean;
  v_manc int;
begin
  if p_hash is null or length(p_hash) < 32 then
    raise exception 'Verifica dello studente mancante';
  end if;
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if jsonb_typeof(v_extra) <> 'array' then
    raise exception 'Risposte extra non valide';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    begin
      insert into public.partecipazioni(edizione_id, materia_corso_id, studente_hash)
        values (p_edizione, (m->>'materia_corso_id')::uuid, p_hash);
    exception when unique_violation then
      raise exception 'Hai gia compilato una delle materie scelte. Torna indietro e togli quelle gia inviate.';
    end;
  end loop;

  perform public.invia_compilazioni(p_edizione, p_fuori_corso, p_materie, p_anno);

  v_fatto := exists (select 1 from public.partecipazioni_extra
                     where edizione_id = p_edizione and studente_hash = p_hash);
  if v_fatto then
    if jsonb_array_length(v_extra) > 0 then
      raise exception 'Hai gia risposto alle domande extra.';
    end if;
  elsif jsonb_array_length(v_extra) > 0
     or exists (select 1 from public.domande where attiva and categoria = 'extra' and obbligatoria) then
    if (select count(distinct e->>'domanda_id') from jsonb_array_elements(v_extra) e)
       <> jsonb_array_length(v_extra) then
      raise exception 'Una domanda extra compare piu volte';
    end if;
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               where length(btrim(coalesce(r.testo, ''))) > 1000) then
      raise exception 'Una risposta scritta supera i 1000 caratteri';
    end if;

    -- Nessuna risposta a una domanda Extra che le risposte precedenti non prevedevano
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               join public.domande d on d.id = r.domanda_id
               where not private.condizione_extra_ok(d.mostra_se_domanda_id, d.mostra_se_opzioni, v_extra)) then
      raise exception 'Una risposta extra non e prevista in base alle risposte precedenti';
    end if;

    select count(*) into v_manc
    from public.domande d
    where d.attiva and d.categoria = 'extra' and d.obbligatoria
      and private.condizione_extra_ok(d.mostra_se_domanda_id, d.mostra_se_opzioni, v_extra)
      and not exists (
        select 1 from jsonb_to_recordset(v_extra)
          as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
        where r.domanda_id = d.id
          and (r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> ''));
    if v_manc > 0 then
      raise exception 'Mancano % risposte obbligatorie nelle domande extra', v_manc;
    end if;

    insert into public.risposte_extra(edizione_id, domanda_id, valore_numero, opzione_id, testo)
      select p_edizione, r.domanda_id, r.valore_numero, r.opzione_id, nullif(btrim(r.testo), '')
      from jsonb_to_recordset(v_extra)
        as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
      where r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> '';

    if exists (select 1 from public.risposte_extra x where x.edizione_id = p_edizione and false) then null; end if;
    if jsonb_array_length(v_extra) > 0 then
      insert into public.partecipazioni_extra(edizione_id, studente_hash) values (p_edizione, p_hash)
        on conflict do nothing;
    end if;
  end if;
end $$;

-- ===== 020_elimina_voci.sql =====
-- Eliminazione definitiva di domande, corsi, materie, docenti ed edizioni, con tutto ciò che ne dipende
-- (risposte comprese). Solo gli admin. Con p_esegui = false non cancella nulla e restituisce soltanto
-- quanto verrebbe eliminato, così il pannello può chiedere una conferma informata.

create or replace function public.elimina_voce(p_tipo text, p_id uuid, p_esegui boolean default false)
returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_ids uuid[];
  v_mc uuid[];
  v_ins uuid[];
  v_comp uuid[];
  v_risposte bigint := 0;
  v_extra bigint := 0;
  v_comp_n bigint := 0;
  v_dip bigint := 0;
begin
  if not (select private.e_admin()) then
    raise exception 'Solo un admin puo eliminare';
  end if;

  if p_tipo = 'domanda' then
    if not exists (select 1 from public.domande where id = p_id) then raise exception 'Domanda non trovata'; end if;
    -- La domanda e quelle che dipendono da lei (un solo livello)
    select coalesce(array_agg(id), '{}') into v_ids from public.domande where mostra_se_domanda_id = p_id;
    v_dip := cardinality(v_ids);
    v_ids := v_ids || p_id;
    select count(*) into v_risposte from public.risposte where domanda_id = any(v_ids);
    select count(*) into v_extra from public.risposte_extra where domanda_id = any(v_ids);
    if p_esegui then
      -- Prima si disattivano (prima quelle che dipendono, poi la domanda), poi si tolgono risposte e domande
      update public.domande set attiva = false where id = any(v_ids) and id <> p_id;
      update public.domande set attiva = false where id = p_id;
      delete from public.risposte where domanda_id = any(v_ids);
      delete from public.risposte_extra where domanda_id = any(v_ids);
      delete from public.domande where id = any(v_ids) and id <> p_id;
      delete from public.domande where id = p_id;
    end if;
    return jsonb_build_object('risposte', v_risposte + v_extra, 'domande_dipendenti', v_dip);

  elsif p_tipo = 'corso' then
    if not exists (select 1 from public.corsi_di_laurea where id = p_id) then raise exception 'Corso non trovato'; end if;
    select coalesce(array_agg(id), '{}') into v_mc from public.materie_corso where corso_id = p_id;
    select coalesce(array_agg(id), '{}') into v_comp from public.compilazioni where materia_corso_id = any(v_mc);
    select count(*) into v_risposte from public.risposte where compilazione_id = any(v_comp);
    if p_esegui then
      delete from public.partecipazioni where materia_corso_id = any(v_mc);
      delete from public.compilazioni where id = any(v_comp);
      delete from public.materie_corso where id = any(v_mc);
      delete from public.corsi_di_laurea where id = p_id;
    end if;
    return jsonb_build_object('materie_collegate', cardinality(v_mc), 'compilazioni', cardinality(v_comp), 'risposte', v_risposte);

  elsif p_tipo = 'materia' then
    if not exists (select 1 from public.materie where id = p_id) then raise exception 'Materia non trovata'; end if;
    select coalesce(array_agg(id), '{}') into v_mc from public.materie_corso where materia_id = p_id;
    select coalesce(array_agg(id), '{}') into v_ins from public.insegnamenti where materia_id = p_id;
    select coalesce(array_agg(id), '{}') into v_comp from public.compilazioni where materia_corso_id = any(v_mc);
    select count(*) into v_risposte from public.risposte where compilazione_id = any(v_comp);
    if p_esegui then
      delete from public.partecipazioni where materia_corso_id = any(v_mc);
      delete from public.compilazioni where id = any(v_comp);
      delete from public.insegnamenti where id = any(v_ins);
      delete from public.materie_corso where id = any(v_mc);
      delete from public.materie where id = p_id;
    end if;
    return jsonb_build_object('corsi_collegati', cardinality(v_mc), 'docenti_collegati', cardinality(v_ins),
                              'compilazioni', cardinality(v_comp), 'risposte', v_risposte);

  elsif p_tipo = 'docente' then
    if not exists (select 1 from public.docenti where id = p_id) then raise exception 'Docente non trovato'; end if;
    select coalesce(array_agg(id), '{}') into v_ins from public.insegnamenti where docente_id = p_id;
    select count(*) into v_risposte from public.risposte where insegnamento_id = any(v_ins);
    if p_esegui then
      delete from public.risposte where insegnamento_id = any(v_ins);
      delete from public.blocchi_saltati where insegnamento_id = any(v_ins);
      delete from public.insegnamenti where id = any(v_ins);
      delete from public.docenti where id = p_id;
    end if;
    return jsonb_build_object('materie_collegate', cardinality(v_ins), 'risposte', v_risposte);

  elsif p_tipo = 'edizione' then
    if not exists (select 1 from public.edizioni where id = p_id) then raise exception 'Edizione non trovata'; end if;
    if exists (select 1 from public.edizioni where id = p_id and aperta) then
      raise exception 'Chiudi prima l''edizione: un''edizione aperta non si elimina';
    end if;
    select coalesce(array_agg(id), '{}') into v_comp from public.compilazioni where edizione_id = p_id;
    select count(*) into v_risposte from public.risposte where compilazione_id = any(v_comp);
    select count(*) into v_extra from public.risposte_extra where edizione_id = p_id;
    if p_esegui then
      delete from public.risposte_extra where edizione_id = p_id;
      delete from public.partecipazioni_extra where edizione_id = p_id;
      delete from public.partecipazioni where edizione_id = p_id;
      delete from public.compilazioni where id = any(v_comp);
      delete from public.edizioni where id = p_id;
    end if;
    return jsonb_build_object('compilazioni', cardinality(v_comp), 'risposte', v_risposte + v_extra);

  else
    raise exception 'Tipo non valido';
  end if;
end $$;
revoke all on function public.elimina_voce(text, uuid, boolean) from public, anon;
grant execute on function public.elimina_voce(text, uuid, boolean) to authenticated;

-- ===== 021_testo_libero_in_tutte_le_domande.sql =====
-- Risposte scritte anche nelle domande sulla materia e sui docenti, non più solo nelle Extra.
-- I testi si leggono nelle statistiche e chi può modificare li può nascondere, come per le Extra.

alter table public.risposte
  add column testo text,
  add column nascosta boolean not null default false;

alter table public.risposte drop constraint un_solo_valore;
alter table public.risposte
  add constraint un_solo_valore check (num_nonnulls(valore_numero, opzione_id, testo) = 1);
alter table public.risposte
  add constraint testo_lunghezza check (testo is null or (length(btrim(testo)) between 1 and 1000));

alter table public.domande drop constraint testo_solo_extra;

-- Invio: come prima, più i testi (ripuliti, al massimo 1000 caratteri, solo per le domande scritte)
create or replace function public.invia_compilazioni(p_edizione uuid, p_fuori_corso boolean, p_materie jsonb, p_anno smallint default null::smallint)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  m jsonb;
  v_mc uuid;
  v_materia uuid;
  v_comp uuid;
  v_saltati uuid[];
  v_mancanti int;
begin
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;
  if not p_fuori_corso and p_anno is null then
    raise exception 'Indica il tuo anno oppure fuori corso';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    v_mc := (m->>'materia_corso_id')::uuid;
    select mc.materia_id into v_materia from public.materie_corso mc where mc.id = v_mc;
    if v_materia is null then raise exception 'Materia non valida'; end if;

    if exists (select 1 from jsonb_to_recordset(coalesce(m->'risposte', '[]'::jsonb)) as r(testo text)
               where length(btrim(coalesce(r.testo, ''))) > 1000) then
      raise exception 'Una risposta scritta supera i 1000 caratteri';
    end if;

    insert into public.compilazioni(edizione_id, materia_corso_id, anno_studente, fuori_corso)
      values (p_edizione, v_mc, case when p_fuori_corso then null else p_anno end, p_fuori_corso)
      returning id into v_comp;

    insert into public.blocchi_saltati(compilazione_id, insegnamento_id)
      select v_comp, t.val::uuid
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    insert into public.risposte(compilazione_id, domanda_id, insegnamento_id, valore_numero, opzione_id, testo)
      select v_comp, r.domanda_id, r.insegnamento_id, r.valore_numero, r.opzione_id, nullif(btrim(r.testo), '')
      from jsonb_to_recordset(coalesce(m->'risposte', '[]'::jsonb))
        as r(domanda_id uuid, insegnamento_id uuid, valore_numero smallint, opzione_id uuid, testo text)
      where r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> '';

    -- Un testo solo nelle domande a risposta scritta, e solo testo in quelle
    if exists (
      select 1 from public.risposte r
      join public.domande d on d.id = r.domanda_id
      where r.compilazione_id = v_comp and ((r.testo is not null) <> (d.tipo_risposta = 'testo'))
    ) then
      raise exception 'Una risposta non corrisponde al tipo della domanda';
    end if;

    -- Nessuna risposta a una domanda che, secondo le risposte precedenti, non andava mostrata
    if exists (
      select 1 from public.risposte r
      join public.domande d on d.id = r.domanda_id
      where r.compilazione_id = v_comp and d.mostra_se_domanda_id is not null
        and not exists (
          select 1 from public.risposte p
          where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
            and p.insegnamento_id is not distinct from r.insegnamento_id
            and p.opzione_id = any(d.mostra_se_opzioni))
    ) then
      raise exception 'Una risposta non e prevista in base alle risposte precedenti';
    end if;

    select coalesce(array_agg(t.val::uuid), '{}')
      into v_saltati
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    -- Domande obbligatorie applicabili alla materia che non hanno risposta
    select count(*) into v_mancanti
    from (
      select d.id as domanda_id, null::uuid as insegnamento_id
      from public.domande d
      where d.attiva and d.obbligatoria
        and (d.categoria = 'generica'
          or (d.categoria = 'specifica_materia' and exists (
                select 1 from public.collegamenti_domanda c
                where c.domanda_id = d.id and c.materia_id = v_materia)))
        and (d.mostra_se_domanda_id is null or exists (
              select 1 from public.risposte p
              where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
                and p.insegnamento_id is null and p.opzione_id = any(d.mostra_se_opzioni)))
      union all
      select d.id, i.id
      from public.domande d
      join public.insegnamenti i on i.materia_id = v_materia
      join public.docenti dc on dc.id = i.docente_id and dc.attivo
      where d.attiva and d.obbligatoria
        and not (i.id = any(v_saltati))
        and (d.categoria = 'generica_docente'
          or (d.categoria = 'specifica_docente' and (
                (d.ambito_docente = 'docente' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.docente_id = i.docente_id))
             or (d.ambito_docente = 'insegnamento' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.insegnamento_id = i.id)))))
        and (d.mostra_se_domanda_id is null or exists (
              select 1 from public.risposte p
              where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
                and p.insegnamento_id = i.id and p.opzione_id = any(d.mostra_se_opzioni)))
    ) richieste
    where not exists (
      select 1 from public.risposte r
      where r.compilazione_id = v_comp
        and r.domanda_id = richieste.domanda_id
        and r.insegnamento_id is not distinct from richieste.insegnamento_id
    );
    if v_mancanti > 0 then
      raise exception 'Mancano % risposte obbligatorie', v_mancanti;
    end if;
  end loop;
end
$function$;

-- Le medie e le distribuzioni non contano i testi
create or replace function public.stat_risposte(p_edizione uuid, p_gruppo text default 'domanda'::text, p_corso uuid default null::uuid, p_anno_corso smallint default null::smallint, p_anno_studente smallint default null::smallint, p_fuori_corso boolean default null::boolean, p_materia uuid default null::uuid, p_docente uuid default null::uuid)
returns table(domanda_id uuid, materia_id uuid, docente_id uuid, n bigint, somma bigint, distribuzione jsonb)
language sql
stable
set search_path to ''
as $function$
  with base as (
    select r.domanda_id, mc.materia_id, i.docente_id, r.valore_numero, r.opzione_id
    from public.risposte r
    join public.compilazioni c on c.id = r.compilazione_id
    join public.materie_corso mc on mc.id = c.materia_corso_id
    left join public.insegnamenti i on i.id = r.insegnamento_id
    where c.edizione_id = p_edizione
      and r.testo is null
      and (p_corso is null or mc.corso_id = p_corso)
      and (p_anno_corso is null or mc.anno = p_anno_corso)
      and (p_anno_studente is null or c.anno_studente = p_anno_studente)
      and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
      and (p_materia is null or mc.materia_id = p_materia)
      and (p_docente is null or i.docente_id = p_docente)
  ),
  gruppi as (
    select b.domanda_id,
           case when p_gruppo = 'domanda_materia' then b.materia_id end as materia_id,
           case when p_gruppo = 'domanda_docente' then b.docente_id end as docente_id,
           b.valore_numero, b.opzione_id, count(*) as k
    from base b
    group by 1, 2, 3, 4, 5
  )
  select g.domanda_id, g.materia_id, g.docente_id,
         sum(g.k)::bigint,
         coalesce(sum(g.valore_numero * g.k), 0)::bigint,
         jsonb_object_agg(coalesce(g.valore_numero::text, g.opzione_id::text), g.k)
  from gruppi g
  group by 1, 2, 3
$function$;

-- I testi scritti, con gli stessi filtri delle statistiche. Le regole di lettura valgono anche qui:
-- chi non è autorizzato a vedere i docenti non riceve i testi sui docenti.
create or replace function public.testi_risposte(p_edizione uuid, p_corso uuid default null::uuid, p_anno_corso smallint default null::smallint, p_anno_studente smallint default null::smallint, p_fuori_corso boolean default null::boolean, p_materia uuid default null::uuid, p_docente uuid default null::uuid)
returns table(id uuid, domanda_id uuid, materia_id uuid, docente_id uuid, testo text, nascosta boolean)
language sql
stable
set search_path to ''
as $function$
  select r.id, r.domanda_id, mc.materia_id, i.docente_id, r.testo, r.nascosta
  from public.risposte r
  join public.compilazioni c on c.id = r.compilazione_id
  join public.materie_corso mc on mc.id = c.materia_corso_id
  left join public.insegnamenti i on i.id = r.insegnamento_id
  where c.edizione_id = p_edizione
    and r.testo is not null
    and (p_corso is null or mc.corso_id = p_corso)
    and (p_anno_corso is null or mc.anno = p_anno_corso)
    and (p_anno_studente is null or c.anno_studente = p_anno_studente)
    and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
    and (p_materia is null or mc.materia_id = p_materia)
    and (p_docente is null or i.docente_id = p_docente)
$function$;

-- Nascondere un testo (per esempio offensivo o con nomi): resta nel database ma non si mostra
create or replace function public.nascondi_risposta(p_id uuid, p_nascosta boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not (select private.puo_modificare()) then
    raise exception 'Non hai i permessi per farlo';
  end if;
  update public.risposte set nascosta = p_nascosta where id = p_id and testo is not null;
end
$function$;

revoke all on function public.testi_risposte(uuid, uuid, smallint, smallint, boolean, uuid, uuid) from public, anon;
grant execute on function public.testi_risposte(uuid, uuid, smallint, smallint, boolean, uuid, uuid) to authenticated;
revoke all on function public.nascondi_risposta(uuid, boolean) from public, anon;
grant execute on function public.nascondi_risposta(uuid, boolean) to authenticated;

-- ===== 022_valida_risposte_scritte.sql =====
-- Le risposte per materia e docente possono ora essere scritte: il controllo le accetta come fa per le Extra
create or replace function private.valida_risposta()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare d public.domande%rowtype; mat uuid; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  elsif d.tipo_risposta = 'scelta_singola' then
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  elsif new.testo is null then
    raise exception 'Serve una risposta scritta';
  end if;
  return new;
end $function$;

-- ===== 023_anni_attivi_dei_corsi.sql =====
-- Corsi in via di soppressione: si indicano gli anni ancora attivi. Vuoto (null) = tutti gli anni.
alter table public.corsi_di_laurea add column anni_attivi smallint[];
alter table public.corsi_di_laurea add constraint anni_attivi_validi check (
  anni_attivi is null
  or (cardinality(anni_attivi) > 0 and 1 <= all(anni_attivi) and durata_anni >= all(anni_attivi))
);

-- All'invio, l'anno dello studente deve essere uno di quelli ancora attivi (i fuori corso non hanno anno)
create or replace function private.valida_compilazione()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare d smallint; attivi smallint[];
begin
  if not exists (select 1 from public.edizioni where id = new.edizione_id and aperta) then
    raise exception 'L''edizione non e aperta alla compilazione';
  end if;
  select c.durata_anni, c.anni_attivi into d, attivi
    from public.materie_corso mc join public.corsi_di_laurea c on c.id = mc.corso_id
    where mc.id = new.materia_corso_id;
  if new.anno_studente is not null and new.anno_studente > d then
    raise exception 'L''anno dello studente supera la durata del corso';
  end if;
  if new.anno_studente is not null and attivi is not null and not (new.anno_studente = any(attivi)) then
    raise exception 'Il tuo anno non e piu attivo per questo corso';
  end if;
  return new;
end $function$;

-- ===== 024_corso_e_anno_ricordati.sql =====
-- Corso e anno scelti da uno studente in un'edizione: si registrano SOLO al primo invio riuscito
-- (nella stessa transazione delle risposte) e da lì non si possono più cambiare per quell'edizione.
-- Come le partecipazioni, la tabella è legata all'impronta anonima e la legge solo il server.
create table public.scelte_studenti (
  edizione_id uuid not null references public.edizioni(id) on delete cascade,
  studente_hash text not null,
  corso_id uuid not null references public.corsi_di_laurea(id) on delete cascade,
  anno_studente smallint,
  fuori_corso boolean not null,
  primary key (edizione_id, studente_hash),
  constraint anno_o_fuori_corso check (fuori_corso = (anno_studente is null))
);
alter table public.scelte_studenti enable row level security;
revoke all on public.scelte_studenti from public, anon, authenticated;

-- Invio verificato: come prima, più il controllo e la registrazione di corso e anno
create or replace function public.invia_compilazioni_verificate(p_hash text, p_edizione uuid, p_fuori_corso boolean, p_materie jsonb, p_anno smallint default null::smallint, p_extra jsonb default null::jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  m jsonb;
  v_extra jsonb := coalesce(p_extra, '[]'::jsonb);
  v_fatto boolean;
  v_manc int;
  v_corso uuid;
  v_anno smallint := case when p_fuori_corso then null else p_anno end;
  v_scelta public.scelte_studenti%rowtype;
begin
  if p_hash is null or length(p_hash) < 32 then
    raise exception 'Verifica dello studente mancante';
  end if;
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if jsonb_typeof(v_extra) <> 'array' then
    raise exception 'Risposte extra non valide';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;

  -- Tutte le materie di un invio appartengono allo stesso corso
  select min(mc.corso_id::text)::uuid into v_corso
    from jsonb_array_elements(p_materie) e
    join public.materie_corso mc on mc.id = (e->>'materia_corso_id')::uuid;
  if v_corso is null or (select count(distinct mc.corso_id)
                         from jsonb_array_elements(p_materie) e
                         join public.materie_corso mc on mc.id = (e->>'materia_corso_id')::uuid) <> 1 then
    raise exception 'Le materie inviate devono essere di un solo corso';
  end if;

  -- Corso e anno: al primo invio si registrano, poi devono restare quelli
  select * into v_scelta from public.scelte_studenti
    where edizione_id = p_edizione and studente_hash = p_hash;
  if found then
    if v_scelta.corso_id <> v_corso or v_scelta.fuori_corso <> p_fuori_corso
       or v_scelta.anno_studente is distinct from v_anno then
      raise exception 'In questa edizione hai gia inviato risposte con un altro corso o un altro anno: non si possono cambiare.';
    end if;
  else
    insert into public.scelte_studenti(edizione_id, studente_hash, corso_id, anno_studente, fuori_corso)
      values (p_edizione, p_hash, v_corso, v_anno, p_fuori_corso);
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    begin
      insert into public.partecipazioni(edizione_id, materia_corso_id, studente_hash)
        values (p_edizione, (m->>'materia_corso_id')::uuid, p_hash);
    exception when unique_violation then
      raise exception 'Hai gia compilato una delle materie scelte. Torna indietro e togli quelle gia inviate.';
    end;
  end loop;

  perform public.invia_compilazioni(p_edizione, p_fuori_corso, p_materie, p_anno);

  v_fatto := exists (select 1 from public.partecipazioni_extra
                     where edizione_id = p_edizione and studente_hash = p_hash);
  if v_fatto then
    if jsonb_array_length(v_extra) > 0 then
      raise exception 'Hai gia risposto alle domande extra.';
    end if;
  elsif jsonb_array_length(v_extra) > 0
     or exists (select 1 from public.domande where attiva and categoria = 'extra' and obbligatoria) then
    if (select count(distinct e->>'domanda_id') from jsonb_array_elements(v_extra) e)
       <> jsonb_array_length(v_extra) then
      raise exception 'Una domanda extra compare piu volte';
    end if;
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               where length(btrim(coalesce(r.testo, ''))) > 1000) then
      raise exception 'Una risposta scritta supera i 1000 caratteri';
    end if;

    -- Nessuna risposta a una domanda Extra che le risposte precedenti non prevedevano
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               join public.domande d on d.id = r.domanda_id
               where not private.condizione_extra_ok(d.mostra_se_domanda_id, d.mostra_se_opzioni, v_extra)) then
      raise exception 'Una risposta extra non e prevista in base alle risposte precedenti';
    end if;

    select count(*) into v_manc
    from public.domande d
    where d.attiva and d.categoria = 'extra' and d.obbligatoria
      and private.condizione_extra_ok(d.mostra_se_domanda_id, d.mostra_se_opzioni, v_extra)
      and not exists (
        select 1 from jsonb_to_recordset(v_extra)
          as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
        where r.domanda_id = d.id
          and (r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> ''));
    if v_manc > 0 then
      raise exception 'Mancano % risposte obbligatorie nelle domande extra', v_manc;
    end if;

    insert into public.risposte_extra(edizione_id, domanda_id, valore_numero, opzione_id, testo)
      select p_edizione, r.domanda_id, r.valore_numero, r.opzione_id, nullif(btrim(r.testo), '')
      from jsonb_to_recordset(v_extra)
        as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
      where r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> '';

    if jsonb_array_length(v_extra) > 0 then
      insert into public.partecipazioni_extra(edizione_id, studente_hash) values (p_edizione, p_hash)
        on conflict do nothing;
    end if;
  end if;
end
$function$;

-- Per il server: corso e anno già registrati per questa persona nell'edizione (nessuna riga se non ha ancora inviato)
create or replace function public.scelta_studente(p_hash text, p_edizione uuid)
returns table(corso_id uuid, anno_studente smallint, fuori_corso boolean)
language sql
stable
security definer
set search_path to ''
as $function$
  select s.corso_id, s.anno_studente, s.fuori_corso
  from public.scelte_studenti s
  where s.studente_hash = p_hash and s.edizione_id = p_edizione;
$function$;
revoke all on function public.scelta_studente(text, uuid) from public, anon, authenticated;
grant execute on function public.scelta_studente(text, uuid) to service_role;

-- Alla chiusura dell'edizione si cancellano anche corso e anno ricordati, come i codici di partecipazione
create or replace function private.cancella_codici_edizione_chiusa()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.aperta and not new.aperta then
    delete from public.partecipazioni where edizione_id = new.id;
    delete from public.partecipazioni_extra where edizione_id = new.id;
    delete from public.scelte_studenti where edizione_id = new.id;
  end if;
  return new;
end $function$;

-- ===== 025_scelta_multipla.sql =====
-- Scelta multipla: una domanda a cui lo studente puo segnare piu risposte.
-- Modifica solo additiva: le domande e le risposte che ci sono gia continuano a funzionare come prima.
-- Da eseguire UNA volta sul database (SQL Editor di Supabase), prima di pubblicare il sito.

-- 1. Nuovo tipo di domanda: scelta multipla (non ammessa nelle Extra, dove le risposte non hanno un autore comune)
alter table public.domande drop constraint domande_tipo_risposta_check;
alter table public.domande add constraint domande_tipo_risposta_check
  check (tipo_risposta = any (array['scala'::text, 'scelta_singola'::text, 'scelta_multipla'::text, 'testo'::text]));
alter table public.domande add constraint scelta_multipla_non_extra
  check (tipo_risposta <> 'scelta_multipla' or categoria <> 'extra');

-- 2. Una risposta per domanda resta la regola, ma la scelta multipla puo avere una riga per ogni opzione scelta
drop index public.risposte_unica;
create unique index risposte_unica on public.risposte
  (compilazione_id, domanda_id, coalesce(insegnamento_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where opzione_id is null;
create unique index risposte_unica_opzione on public.risposte
  (compilazione_id, domanda_id, coalesce(insegnamento_id, '00000000-0000-0000-0000-000000000000'::uuid), opzione_id)
  where opzione_id is not null;

-- 3. Invio: stessi controlli di prima, piu uno che ammette piu opzioni solo nelle domande a scelta multipla
CREATE OR REPLACE FUNCTION public.invia_compilazioni(p_edizione uuid, p_fuori_corso boolean, p_materie jsonb, p_anno smallint DEFAULT NULL::smallint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m jsonb;
  v_mc uuid;
  v_materia uuid;
  v_comp uuid;
  v_saltati uuid[];
  v_mancanti int;
begin
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;
  if not p_fuori_corso and p_anno is null then
    raise exception 'Indica il tuo anno oppure fuori corso';
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    v_mc := (m->>'materia_corso_id')::uuid;
    select mc.materia_id into v_materia from public.materie_corso mc where mc.id = v_mc;
    if v_materia is null then raise exception 'Materia non valida'; end if;

    if exists (select 1 from jsonb_to_recordset(coalesce(m->'risposte', '[]'::jsonb)) as r(testo text)
               where length(btrim(coalesce(r.testo, ''))) > 1000) then
      raise exception 'Una risposta scritta supera i 1000 caratteri';
    end if;

    insert into public.compilazioni(edizione_id, materia_corso_id, anno_studente, fuori_corso)
      values (p_edizione, v_mc, case when p_fuori_corso then null else p_anno end, p_fuori_corso)
      returning id into v_comp;

    insert into public.blocchi_saltati(compilazione_id, insegnamento_id)
      select v_comp, t.val::uuid
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    insert into public.risposte(compilazione_id, domanda_id, insegnamento_id, valore_numero, opzione_id, testo)
      select v_comp, r.domanda_id, r.insegnamento_id, r.valore_numero, r.opzione_id, nullif(btrim(r.testo), '')
      from jsonb_to_recordset(coalesce(m->'risposte', '[]'::jsonb))
        as r(domanda_id uuid, insegnamento_id uuid, valore_numero smallint, opzione_id uuid, testo text)
      where r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> '';

    -- Un testo solo nelle domande a risposta scritta, e solo testo in quelle
    if exists (
      select 1 from public.risposte r
      join public.domande d on d.id = r.domanda_id
      where r.compilazione_id = v_comp and ((r.testo is not null) <> (d.tipo_risposta = 'testo'))
    ) then
      raise exception 'Una risposta non corrisponde al tipo della domanda';
    end if;

    -- Piu risposte alla stessa domanda solo se e a scelta multipla
    if exists (
      select 1 from public.risposte r
      join public.domande d on d.id = r.domanda_id
      where r.compilazione_id = v_comp
      group by r.domanda_id, r.insegnamento_id, d.tipo_risposta
      having count(*) > 1 and d.tipo_risposta <> 'scelta_multipla'
    ) then
      raise exception 'Una domanda ammette una sola risposta';
    end if;

    -- Nessuna risposta a una domanda che, secondo le risposte precedenti, non andava mostrata
    if exists (
      select 1 from public.risposte r
      join public.domande d on d.id = r.domanda_id
      where r.compilazione_id = v_comp and d.mostra_se_domanda_id is not null
        and not exists (
          select 1 from public.risposte p
          where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
            and p.insegnamento_id is not distinct from r.insegnamento_id
            and p.opzione_id = any(d.mostra_se_opzioni))
    ) then
      raise exception 'Una risposta non e prevista in base alle risposte precedenti';
    end if;

    select coalesce(array_agg(t.val::uuid), '{}')
      into v_saltati
      from jsonb_array_elements_text(coalesce(m->'blocchi_saltati', '[]'::jsonb)) as t(val);

    -- Domande obbligatorie applicabili alla materia che non hanno risposta
    select count(*) into v_mancanti
    from (
      select d.id as domanda_id, null::uuid as insegnamento_id
      from public.domande d
      where d.attiva and d.obbligatoria
        and (d.categoria = 'generica'
          or (d.categoria = 'specifica_materia' and exists (
                select 1 from public.collegamenti_domanda c
                where c.domanda_id = d.id and c.materia_id = v_materia)))
        and (d.mostra_se_domanda_id is null or exists (
              select 1 from public.risposte p
              where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
                and p.insegnamento_id is null and p.opzione_id = any(d.mostra_se_opzioni)))
      union all
      select d.id, i.id
      from public.domande d
      join public.insegnamenti i on i.materia_id = v_materia
      join public.docenti dc on dc.id = i.docente_id and dc.attivo
      where d.attiva and d.obbligatoria
        and not (i.id = any(v_saltati))
        and (d.categoria = 'generica_docente'
          or (d.categoria = 'specifica_docente' and (
                (d.ambito_docente = 'docente' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.docente_id = i.docente_id))
             or (d.ambito_docente = 'insegnamento' and exists (
                   select 1 from public.collegamenti_domanda c
                   where c.domanda_id = d.id and c.insegnamento_id = i.id)))))
        and (d.mostra_se_domanda_id is null or exists (
              select 1 from public.risposte p
              where p.compilazione_id = v_comp and p.domanda_id = d.mostra_se_domanda_id
                and p.insegnamento_id = i.id and p.opzione_id = any(d.mostra_se_opzioni)))
    ) richieste
    where not exists (
      select 1 from public.risposte r
      where r.compilazione_id = v_comp
        and r.domanda_id = richieste.domanda_id
        and r.insegnamento_id is not distinct from richieste.insegnamento_id
    );
    if v_mancanti > 0 then
      raise exception 'Mancano % risposte obbligatorie', v_mancanti;
    end if;
  end loop;
end
$function$;

-- 4. Statistiche: n conta le persone che hanno risposto, non le singole opzioni scelte
-- (per scale e scelte singole e identico a prima; nella scelta multipla le percentuali possono superare il 100% in somma)
CREATE OR REPLACE FUNCTION public.stat_risposte(p_edizione uuid, p_gruppo text DEFAULT 'domanda'::text, p_corso uuid DEFAULT NULL::uuid, p_anno_corso smallint DEFAULT NULL::smallint, p_anno_studente smallint DEFAULT NULL::smallint, p_fuori_corso boolean DEFAULT NULL::boolean, p_materia uuid DEFAULT NULL::uuid, p_docente uuid DEFAULT NULL::uuid)
 RETURNS TABLE(domanda_id uuid, materia_id uuid, docente_id uuid, n bigint, somma bigint, distribuzione jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with base as (
    select r.domanda_id, mc.materia_id, i.docente_id, r.valore_numero, r.opzione_id,
           r.compilazione_id::text || ':' || coalesce(r.insegnamento_id::text, '') as chi
    from public.risposte r
    join public.compilazioni c on c.id = r.compilazione_id
    join public.materie_corso mc on mc.id = c.materia_corso_id
    left join public.insegnamenti i on i.id = r.insegnamento_id
    where c.edizione_id = p_edizione
      and r.testo is null
      and (p_corso is null or mc.corso_id = p_corso)
      and (p_anno_corso is null or mc.anno = p_anno_corso)
      and (p_anno_studente is null or c.anno_studente = p_anno_studente)
      and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
      and (p_materia is null or mc.materia_id = p_materia)
      and (p_docente is null or i.docente_id = p_docente)
  ),
  gruppi as (
    select b.domanda_id,
           case when p_gruppo = 'domanda_materia' then b.materia_id end as materia_id,
           case when p_gruppo = 'domanda_docente' then b.docente_id end as docente_id,
           b.valore_numero, b.opzione_id, count(*) as k
    from base b
    group by 1, 2, 3, 4, 5
  ),
  persone as (
    select b.domanda_id,
           case when p_gruppo = 'domanda_materia' then b.materia_id end as materia_id,
           case when p_gruppo = 'domanda_docente' then b.docente_id end as docente_id,
           count(distinct b.chi) as n
    from base b
    group by 1, 2, 3
  )
  select g.domanda_id, g.materia_id, g.docente_id,
         p.n::bigint,
         coalesce(sum(g.valore_numero * g.k), 0)::bigint,
         jsonb_object_agg(coalesce(g.valore_numero::text, g.opzione_id::text), g.k)
  from gruppi g
  join persone p on p.domanda_id = g.domanda_id
    and p.materia_id is not distinct from g.materia_id
    and p.docente_id is not distinct from g.docente_id
  group by g.domanda_id, g.materia_id, g.docente_id, p.n
$function$;

-- ===== 026_scelta_multipla_controlli.sql =====
-- Scelta multipla, parte 2: i due controlli del database che ammettevano solo la scelta singola.
-- Da eseguire dopo migrazione-scelta-multipla.sql (SQL Editor di Supabase). Modifica additiva.

-- 1. Una risposta a una domanda a scelta multipla e valida se l'opzione appartiene alla domanda,
--    come per la scelta singola (prima cadeva nel ramo «serve una risposta scritta»)
CREATE OR REPLACE FUNCTION private.valida_risposta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.domande%rowtype; mat uuid; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  elsif d.tipo_risposta in ('scelta_singola', 'scelta_multipla') then
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  elsif new.testo is null then
    raise exception 'Serve una risposta scritta';
  end if;
  return new;
end $function$;

-- 2. Protezione delle domande: la scelta multipla vale come la singola per condizioni e numero di opzioni,
--    e una domanda a scelta singola con risposte gia raccolte puo diventare multipla (le risposte restano valide)
CREATE OR REPLACE FUNCTION private.proteggi_domande()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int; mn int; mx int; g public.domande%rowtype; cambia_tipo boolean;
begin
  if tg_op = 'UPDATE' then
    -- Cambiare tipo e ammesso solo da scelta singola a scelta multipla
    cambia_tipo := new.tipo_risposta is distinct from old.tipo_risposta
      and not (old.tipo_risposta = 'scelta_singola' and new.tipo_risposta = 'scelta_multipla');
    if (exists (select 1 from public.risposte where domanda_id = old.id)
        or exists (select 1 from public.risposte_extra where domanda_id = old.id))
       and (new.categoria is distinct from old.categoria
         or cambia_tipo
         or new.testo is distinct from old.testo
         or new.scala_min is distinct from old.scala_min
         or new.scala_max is distinct from old.scala_max
         or new.ambito_docente is distinct from old.ambito_docente
         or new.mostra_se_domanda_id is distinct from old.mostra_se_domanda_id
         or new.mostra_se_opzioni is distinct from old.mostra_se_opzioni) then
      raise exception 'Domanda con risposte gia raccolte: disattivala e creane una nuova';
    end if;
    -- Una domanda da cui ne dipendono altre attive non si disattiva e non cambia natura
    if exists (select 1 from public.domande c where c.mostra_se_domanda_id = old.id and c.attiva)
       and (not new.attiva
         or new.categoria is distinct from old.categoria
         or cambia_tipo) then
      raise exception 'Altre domande attive dipendono da questa: disattivale prima';
    end if;
  end if;

  if new.mostra_se_domanda_id is not null then
    if new.categoria not in ('generica','generica_docente','extra') then
      raise exception 'La condizione e ammessa solo nelle domande generiche, generiche sui docenti ed Extra';
    end if;
    select * into g from public.domande where id = new.mostra_se_domanda_id;
    if not found or g.id = new.id then raise exception 'Domanda da cui dipende non valida'; end if;
    if g.categoria <> new.categoria then
      raise exception 'La domanda da cui dipende deve avere la stessa categoria';
    end if;
    if g.tipo_risposta not in ('scelta_singola', 'scelta_multipla') then
      raise exception 'La domanda da cui dipende deve essere a scelta singola o multipla';
    end if;
    if g.mostra_se_domanda_id is not null then
      raise exception 'La domanda da cui dipende non puo dipendere a sua volta da un''altra';
    end if;
    if new.attiva then
      if not g.attiva then
        raise exception 'Attiva prima la domanda da cui dipende';
      end if;
      if exists (select 1 from unnest(new.mostra_se_opzioni) o
                 where not exists (select 1 from public.opzioni_risposta r
                                   where r.id = o and r.domanda_id = g.id)) then
        raise exception 'La condizione usa opzioni che la domanda non ha piu: riscegli le opzioni';
      end if;
    end if;
  end if;

  if new.attiva then
    if new.tipo_risposta in ('scelta_singola', 'scelta_multipla') then
      select count(*) into n from public.opzioni_risposta where domanda_id = new.id;
      mn := private.get_setting_int('opzioni_min', 3);
      mx := private.get_setting_int('opzioni_max', 5);
      if n < mn or n > mx then
        raise exception 'Una domanda a scelta attiva deve avere da % a % opzioni (ora %)', mn, mx, n;
      end if;
    end if;
    if new.categoria in ('specifica_materia','specifica_docente')
       and not exists (select 1 from public.collegamenti_domanda where domanda_id = new.id) then
      raise exception 'Una domanda specifica attiva deve avere almeno un collegamento';
    end if;
  end if;
  return new;
end $function$;

-- ===== 027_extra_corso_anno.sql =====
-- Domande Extra: a ogni risposta si associano il corso e l'anno di chi l'ha scritta (non l'identita).
-- Modifica additiva: le risposte gia raccolte restano com'e (non hanno il corso: non c'e modo di risalirvi, perche
-- le risposte Extra non sono collegate in nessun modo a chi le ha date). Da eseguire una volta nell'SQL Editor di Supabase.

-- 1. Dove si salvano corso, anno e fuori corso (stesse informazioni che hanno gia le compilazioni per materia)
alter table public.risposte_extra
  add column corso_id uuid references public.corsi_di_laurea(id) on delete set null,
  add column anno_studente smallint check (anno_studente between 1 and 6),
  add column fuori_corso boolean;

-- 2. L'invio le registra: stesso controllo di prima, in piu corso e anno dell'invio (v_corso, v_anno, p_fuori_corso)
CREATE OR REPLACE FUNCTION public.invia_compilazioni_verificate(p_hash text, p_edizione uuid, p_fuori_corso boolean, p_materie jsonb, p_anno smallint DEFAULT NULL::smallint, p_extra jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m jsonb;
  v_extra jsonb := coalesce(p_extra, '[]'::jsonb);
  v_fatto boolean;
  v_manc int;
  v_corso uuid;
  v_anno smallint := case when p_fuori_corso then null else p_anno end;
  v_scelta public.scelte_studenti%rowtype;
begin
  if p_hash is null or length(p_hash) < 32 then
    raise exception 'Verifica dello studente mancante';
  end if;
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
  end if;
  if jsonb_typeof(v_extra) <> 'array' then
    raise exception 'Risposte extra non valide';
  end if;
  if (select count(distinct e->>'materia_corso_id') from jsonb_array_elements(p_materie) e)
     <> jsonb_array_length(p_materie) then
    raise exception 'Una materia compare piu volte';
  end if;

  -- Tutte le materie di un invio appartengono allo stesso corso
  select min(mc.corso_id::text)::uuid into v_corso
    from jsonb_array_elements(p_materie) e
    join public.materie_corso mc on mc.id = (e->>'materia_corso_id')::uuid;
  if v_corso is null or (select count(distinct mc.corso_id)
                         from jsonb_array_elements(p_materie) e
                         join public.materie_corso mc on mc.id = (e->>'materia_corso_id')::uuid) <> 1 then
    raise exception 'Le materie inviate devono essere di un solo corso';
  end if;

  -- Corso e anno: al primo invio si registrano, poi devono restare quelli
  select * into v_scelta from public.scelte_studenti
    where edizione_id = p_edizione and studente_hash = p_hash;
  if found then
    if v_scelta.corso_id <> v_corso or v_scelta.fuori_corso <> p_fuori_corso
       or v_scelta.anno_studente is distinct from v_anno then
      raise exception 'In questa edizione hai gia inviato risposte con un altro corso o un altro anno: non si possono cambiare.';
    end if;
  else
    insert into public.scelte_studenti(edizione_id, studente_hash, corso_id, anno_studente, fuori_corso)
      values (p_edizione, p_hash, v_corso, v_anno, p_fuori_corso);
  end if;

  for m in select * from jsonb_array_elements(p_materie) loop
    begin
      insert into public.partecipazioni(edizione_id, materia_corso_id, studente_hash)
        values (p_edizione, (m->>'materia_corso_id')::uuid, p_hash);
    exception when unique_violation then
      raise exception 'Hai gia compilato una delle materie scelte. Torna indietro e togli quelle gia inviate.';
    end;
  end loop;

  perform public.invia_compilazioni(p_edizione, p_fuori_corso, p_materie, p_anno);

  v_fatto := exists (select 1 from public.partecipazioni_extra
                     where edizione_id = p_edizione and studente_hash = p_hash);
  if v_fatto then
    if jsonb_array_length(v_extra) > 0 then
      raise exception 'Hai gia risposto alle domande extra.';
    end if;
  elsif jsonb_array_length(v_extra) > 0
     or exists (select 1 from public.domande where attiva and categoria = 'extra' and obbligatoria) then
    if (select count(distinct e->>'domanda_id') from jsonb_array_elements(v_extra) e)
       <> jsonb_array_length(v_extra) then
      raise exception 'Una domanda extra compare piu volte';
    end if;
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               where length(btrim(coalesce(r.testo, ''))) > 1000) then
      raise exception 'Una risposta scritta supera i 1000 caratteri';
    end if;

    -- Nessuna risposta a una domanda Extra che le risposte precedenti non prevedevano
    if exists (select 1 from jsonb_to_recordset(v_extra)
                 as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
               join public.domande d on d.id = r.domanda_id
               where not private.condizione_extra_ok(d.mostra_se_domanda_id, d.mostra_se_opzioni, v_extra)) then
      raise exception 'Una risposta extra non e prevista in base alle risposte precedenti';
    end if;

    select count(*) into v_manc
    from public.domande d
    where d.attiva and d.categoria = 'extra' and d.obbligatoria
      and private.condizione_extra_ok(d.mostra_se_domanda_id, d.mostra_se_opzioni, v_extra)
      and not exists (
        select 1 from jsonb_to_recordset(v_extra)
          as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
        where r.domanda_id = d.id
          and (r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> ''));
    if v_manc > 0 then
      raise exception 'Mancano % risposte obbligatorie nelle domande extra', v_manc;
    end if;

    insert into public.risposte_extra(edizione_id, domanda_id, valore_numero, opzione_id, testo, corso_id, anno_studente, fuori_corso)
      select p_edizione, r.domanda_id, r.valore_numero, r.opzione_id, nullif(btrim(r.testo), ''), v_corso, v_anno, p_fuori_corso
      from jsonb_to_recordset(v_extra)
        as r(domanda_id uuid, valore_numero smallint, opzione_id uuid, testo text)
      where r.valore_numero is not null or r.opzione_id is not null or btrim(coalesce(r.testo, '')) <> '';

    if jsonb_array_length(v_extra) > 0 then
      insert into public.partecipazioni_extra(edizione_id, studente_hash) values (p_edizione, p_hash)
        on conflict do nothing;
    end if;
  end if;
end
$function$;

-- ===== 028_stat_risposte_veloce.sql =====
-- stat_risposte: stesso risultato di prima, senza l'autounione fra «gruppi» e «persone» (che confrontava ogni
-- riga con tutte quelle della stessa domanda) e senza count(distinct) su testi concatenati.
-- Le persone si contano marcando la prima riga di ogni persona con una funzione finestra.
create or replace function public.stat_risposte(
  p_edizione uuid, p_gruppo text default 'domanda', p_corso uuid default null, p_anno_corso smallint default null,
  p_anno_studente smallint default null, p_fuori_corso boolean default null, p_materia uuid default null,
  p_docente uuid default null)
returns table(domanda_id uuid, materia_id uuid, docente_id uuid, n bigint, somma bigint, distribuzione jsonb)
language sql stable set search_path to '' as $$
  with base as (
    select r.domanda_id,
           case when p_gruppo = 'domanda_materia' then mc.materia_id end as materia_id,
           case when p_gruppo = 'domanda_docente' then i.docente_id end as docente_id,
           r.valore_numero, r.opzione_id, r.compilazione_id, r.insegnamento_id
    from public.risposte r
    join public.compilazioni c on c.id = r.compilazione_id
    join public.materie_corso mc on mc.id = c.materia_corso_id
    left join public.insegnamenti i on i.id = r.insegnamento_id
    where c.edizione_id = p_edizione
      and r.testo is null
      and (p_corso is null or mc.corso_id = p_corso)
      and (p_anno_corso is null or mc.anno = p_anno_corso)
      and (p_anno_studente is null or c.anno_studente = p_anno_studente)
      and (p_fuori_corso is null or c.fuori_corso = p_fuori_corso)
      and (p_materia is null or mc.materia_id = p_materia)
      and (p_docente is null or i.docente_id = p_docente)
  ),
  marcate as (
    -- Una persona (compilazione + docente) conta una volta per domanda, anche con più opzioni scelte
    select b.*, row_number() over (
      partition by b.domanda_id, b.materia_id, b.docente_id, b.compilazione_id, b.insegnamento_id) = 1 as prima
    from base b
  ),
  gruppi as (
    select m.domanda_id, m.materia_id, m.docente_id, m.valore_numero, m.opzione_id,
           count(*) as k, count(*) filter (where m.prima) as persone
    from marcate m
    group by 1, 2, 3, 4, 5
  )
  select g.domanda_id, g.materia_id, g.docente_id,
         sum(g.persone)::bigint,
         coalesce(sum(g.valore_numero * g.k), 0)::bigint,
         jsonb_object_agg(coalesce(g.valore_numero::text, g.opzione_id::text), g.k)
  from gruppi g
  group by g.domanda_id, g.materia_id, g.docente_id
$$;

-- ===== 029_stat_risposte_senza_or_null.sql =====
-- Con i filtri scritti come «(parametro is null or colonna = parametro)» il database non sapeva quante righe
-- aspettarsi, sceglieva un piano che rileggeva tutta la tabella delle risposte una volta per ogni compilazione
-- (circa 7 milioni di confronti) e ogni chiamata impiegava più di un secondo e mezzo. Qui la query viene
-- composta con i soli filtri davvero scelti, così il piano si calcola sui valori reali.
create or replace function public.stat_risposte(
  p_edizione uuid, p_gruppo text default 'domanda', p_corso uuid default null, p_anno_corso smallint default null,
  p_anno_studente smallint default null, p_fuori_corso boolean default null, p_materia uuid default null,
  p_docente uuid default null)
returns table(domanda_id uuid, materia_id uuid, docente_id uuid, n bigint, somma bigint, distribuzione jsonb)
language plpgsql stable set search_path to '' as $$
declare
  v_filtri text := '';
begin
  if p_corso is not null then v_filtri := v_filtri || ' and mc.corso_id = $3'; end if;
  if p_anno_corso is not null then v_filtri := v_filtri || ' and mc.anno = $4'; end if;
  if p_anno_studente is not null then v_filtri := v_filtri || ' and c.anno_studente = $5'; end if;
  if p_fuori_corso is not null then v_filtri := v_filtri || ' and c.fuori_corso = $6'; end if;
  if p_materia is not null then v_filtri := v_filtri || ' and mc.materia_id = $7'; end if;
  if p_docente is not null then v_filtri := v_filtri || ' and i.docente_id = $8'; end if;

  return query execute format($q$
    with base as (
      select r.domanda_id,
             case when $2 = 'domanda_materia' then mc.materia_id end as materia_id,
             case when $2 = 'domanda_docente' then i.docente_id end as docente_id,
             r.valore_numero, r.opzione_id, r.compilazione_id, r.insegnamento_id
      from public.risposte r
      join public.compilazioni c on c.id = r.compilazione_id
      join public.materie_corso mc on mc.id = c.materia_corso_id
      left join public.insegnamenti i on i.id = r.insegnamento_id
      where c.edizione_id = $1 and r.testo is null %s
    ),
    marcate as (
      -- Una persona (compilazione + docente) conta una volta per domanda, anche con più opzioni scelte
      select b.*, row_number() over (
        partition by b.domanda_id, b.materia_id, b.docente_id, b.compilazione_id, b.insegnamento_id) = 1 as prima
      from base b
    ),
    gruppi as (
      select m.domanda_id, m.materia_id, m.docente_id, m.valore_numero, m.opzione_id,
             count(*) as k, count(*) filter (where m.prima) as persone
      from marcate m
      group by 1, 2, 3, 4, 5
    )
    select g.domanda_id, g.materia_id, g.docente_id,
           sum(g.persone)::bigint,
           coalesce(sum(g.valore_numero * g.k), 0)::bigint,
           jsonb_object_agg(coalesce(g.valore_numero::text, g.opzione_id::text), g.k)
    from gruppi g
    group by g.domanda_id, g.materia_id, g.docente_id
  $q$, v_filtri)
  using p_edizione, p_gruppo, p_corso, p_anno_corso, p_anno_studente, p_fuori_corso, p_materia, p_docente;
end $$;

-- ===== 030_studenti_per_edizione.sql =====
-- Quanti studenti hanno compilato: solo totali, mai i codici.
-- I codici si cancellano alla chiusura dell'edizione: un attimo prima se ne salva il numero.
alter table public.edizioni add column if not exists studenti_alla_chiusura integer;

comment on column public.edizioni.studenti_alla_chiusura is
  'Studenti che avevano compilato quando l''edizione è stata chiusa (i loro codici poi si cancellano). Se si riapre e richiude, si somma.';

create or replace function private.cancella_codici_edizione_chiusa()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_studenti integer;
begin
  if old.aperta and not new.aperta then
    select count(distinct studente_hash) into v_studenti from public.partecipazioni where edizione_id = new.id;
    update public.edizioni
      set studenti_alla_chiusura = coalesce(studenti_alla_chiusura, 0) + v_studenti
      where id = new.id;
    delete from public.partecipazioni where edizione_id = new.id;
    delete from public.partecipazioni_extra where edizione_id = new.id;
    delete from public.scelte_studenti where edizione_id = new.id;
  end if;
  return new;
end $function$;

-- Studenti distinti per edizione. Con i filtri conta solo i codici ancora presenti: se l'edizione
-- è già stata chiusa una volta quei conteggi non si possono più fare e la funzione restituisce null.
create or replace function public.stat_studenti(
  p_edizione uuid default null,
  p_tipo_corso text default null,
  p_corso uuid default null,
  p_anno_corso smallint default null,
  p_anno_studente smallint default null,
  p_fuori_corso boolean default null
)
 returns table(edizione_id uuid, n bigint)
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_filtri boolean := p_tipo_corso is not null or p_corso is not null or p_anno_corso is not null
                      or p_anno_studente is not null or p_fuori_corso is not null;
begin
  if not (select private.puo_leggere_risultati()) then
    raise exception 'Non hai i permessi per leggere i risultati';
  end if;
  return query
  select e.id,
    case
      when v_filtri and e.studenti_alla_chiusura is not null then null
      else (case when v_filtri then 0 else coalesce(e.studenti_alla_chiusura, 0) end) + (
        select count(distinct p.studente_hash)
        from public.partecipazioni p
        join public.materie_corso mc on mc.id = p.materia_corso_id
        join public.corsi_di_laurea c on c.id = mc.corso_id
        left join public.scelte_studenti s on s.edizione_id = p.edizione_id and s.studente_hash = p.studente_hash
        where p.edizione_id = e.id
          and (p_tipo_corso is null or c.tipo = p_tipo_corso)
          and (p_corso is null or mc.corso_id = p_corso)
          and (p_anno_corso is null or mc.anno = p_anno_corso)
          and (p_anno_studente is null or s.anno_studente = p_anno_studente)
          and (p_fuori_corso is null or s.fuori_corso = p_fuori_corso)
      )
    end::bigint
  from public.edizioni e
  where p_edizione is null or e.id = p_edizione;
end $function$;

revoke all on function public.stat_studenti(uuid, text, uuid, smallint, smallint, boolean) from public, anon;
grant execute on function public.stat_studenti(uuid, text, uuid, smallint, smallint, boolean) to authenticated;

commit;
