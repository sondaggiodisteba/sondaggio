-- Eliminazione di corsi, materie e docenti insieme ai loro collegamenti, in un'unica operazione.
-- Valgono i permessi di chi chiama (SECURITY INVOKER): le regole di sicurezza delle tabelle restano in vigore.
-- Se esistono risposte raccolte i collegamenti non si possono togliere e tutto viene annullato.

create or replace function public.elimina_corso(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from materie_corso where corso_id = p_id;
  delete from corsi_di_laurea where id = p_id;
  if not found then
    raise exception 'Non posso eliminare questo corso: non esiste o il tuo ruolo non lo consente.';
  end if;
exception
  when foreign_key_violation then
    raise exception 'Il corso ha già risposte raccolte: non si può eliminare. Puoi disattivarlo.';
end;
$$;

create or replace function public.elimina_materia(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from materie_corso where materia_id = p_id;
  delete from insegnamenti where materia_id = p_id;
  delete from materie where id = p_id;
  if not found then
    raise exception 'Non posso eliminare questa materia: non esiste o il tuo ruolo non lo consente.';
  end if;
exception
  when foreign_key_violation then
    raise exception 'La materia ha già risposte raccolte: non si può eliminare. Puoi disattivarla.';
end;
$$;

create or replace function public.elimina_docente(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from insegnamenti where docente_id = p_id;
  delete from docenti where id = p_id;
  if not found then
    raise exception 'Non posso eliminare questo docente: non esiste o il tuo ruolo non lo consente.';
  end if;
exception
  when foreign_key_violation then
    raise exception 'Il docente ha già risposte raccolte: non si può eliminare. Puoi disattivarlo.';
end;
$$;

revoke all on function public.elimina_corso(uuid), public.elimina_materia(uuid), public.elimina_docente(uuid) from public, anon;
grant execute on function public.elimina_corso(uuid), public.elimina_materia(uuid), public.elimina_docente(uuid) to authenticated;
