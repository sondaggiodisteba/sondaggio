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
