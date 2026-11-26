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
