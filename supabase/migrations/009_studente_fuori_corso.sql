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
