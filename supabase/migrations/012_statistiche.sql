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
