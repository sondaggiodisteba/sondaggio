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
