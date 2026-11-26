-- I codici di controllo (impronte degli studenti) servono solo mentre l'edizione è aperta, per impedire
-- le doppie compilazioni. Quando l'edizione si chiude vengono cancellati: restano soltanto le risposte,
-- che sono anonime. Riaprendo un'edizione già chiusa, chi aveva compilato potrebbe farlo di nuovo.

create or replace function private.cancella_codici_edizione_chiusa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.aperta and not new.aperta then
    delete from public.partecipazioni where edizione_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists edizioni_cancella_codici on public.edizioni;
create trigger edizioni_cancella_codici
  after update of aperta on public.edizioni
  for each row execute function private.cancella_codici_edizione_chiusa();
