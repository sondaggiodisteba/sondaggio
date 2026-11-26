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
