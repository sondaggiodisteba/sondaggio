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
