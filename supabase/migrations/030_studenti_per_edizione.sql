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
