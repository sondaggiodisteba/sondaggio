-- L'invio delle compilazioni passa solo dalla funzione di verifica (accesso Google).
-- La vecchia funzione, che chiunque poteva chiamare dal browser, non è più raggiungibile da fuori:
-- resta usata solo da invia_compilazioni_verificate, che gira con i permessi del proprietario.
revoke all on function public.invia_compilazioni(uuid, boolean, jsonb, smallint) from public, anon, authenticated;
grant execute on function public.invia_compilazioni(uuid, boolean, jsonb, smallint) to service_role;
