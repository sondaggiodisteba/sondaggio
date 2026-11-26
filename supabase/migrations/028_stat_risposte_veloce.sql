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
