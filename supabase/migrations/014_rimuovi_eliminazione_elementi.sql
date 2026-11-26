-- Si è scelto di non eliminare corsi, materie e docenti: si disattivano soltanto.
drop function if exists public.elimina_corso(uuid);
drop function if exists public.elimina_materia(uuid);
drop function if exists public.elimina_docente(uuid);
