-- Invio delle compilazioni con verifica dello studente.
-- Lo studente accede con Google; una funzione sul server (che sola conosce la chiave segreta) controlla
-- l'identità e passa al database solo un'impronta. Qui l'impronta registra «questa persona ha già
-- compilato questa materia in questa edizione», senza collegarla in alcun modo alle risposte.

create or replace function public.invia_compilazioni_verificate(
  p_hash text,
  p_edizione uuid,
  p_fuori_corso boolean,
  p_materie jsonb,
  p_anno smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  m jsonb;
begin
  if p_hash is null or length(p_hash) < 32 then
    raise exception 'Verifica dello studente mancante';
  end if;
  if p_materie is null or jsonb_typeof(p_materie) <> 'array' or jsonb_array_length(p_materie) = 0 then
    raise exception 'Nessuna materia da inviare';
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

  -- Stesse regole di sempre (edizione aperta, risposte valide, obbligatorie). Se fallisce, anche le
  -- partecipazioni appena registrate vengono annullate: è tutto un'unica operazione.
  perform public.invia_compilazioni(p_edizione, p_fuori_corso, p_materie, p_anno);
end $$;

-- Le materie che questa persona ha già compilato in un'edizione (per non fargliele rifare)
create or replace function public.materie_compilate(p_hash text, p_edizione uuid)
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select p.materia_corso_id
  from public.partecipazioni p
  where p.studente_hash = p_hash and p.edizione_id = p_edizione;
$$;

-- Solo il server verificato può usarle: nessun accesso dal browser
revoke all on function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint) from public, anon, authenticated;
revoke all on function public.materie_compilate(text, uuid) from public, anon, authenticated;
grant execute on function public.invia_compilazioni_verificate(text, uuid, boolean, jsonb, smallint) to service_role;
grant execute on function public.materie_compilate(text, uuid) to service_role;
