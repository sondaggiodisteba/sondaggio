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
