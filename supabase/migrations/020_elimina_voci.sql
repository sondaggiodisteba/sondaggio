-- Eliminazione definitiva di domande, corsi, materie, docenti ed edizioni, con tutto ciò che ne dipende
-- (risposte comprese). Solo gli admin. Con p_esegui = false non cancella nulla e restituisce soltanto
-- quanto verrebbe eliminato, così il pannello può chiedere una conferma informata.

create or replace function public.elimina_voce(p_tipo text, p_id uuid, p_esegui boolean default false)
returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_ids uuid[];
  v_mc uuid[];
  v_ins uuid[];
  v_comp uuid[];
  v_risposte bigint := 0;
  v_extra bigint := 0;
  v_comp_n bigint := 0;
  v_dip bigint := 0;
begin
  if not (select private.e_admin()) then
    raise exception 'Solo un admin puo eliminare';
  end if;

  if p_tipo = 'domanda' then
    if not exists (select 1 from public.domande where id = p_id) then raise exception 'Domanda non trovata'; end if;
    -- La domanda e quelle che dipendono da lei (un solo livello)
    select coalesce(array_agg(id), '{}') into v_ids from public.domande where mostra_se_domanda_id = p_id;
    v_dip := cardinality(v_ids);
    v_ids := v_ids || p_id;
    select count(*) into v_risposte from public.risposte where domanda_id = any(v_ids);
    select count(*) into v_extra from public.risposte_extra where domanda_id = any(v_ids);
    if p_esegui then
      -- Prima si disattivano (prima quelle che dipendono, poi la domanda), poi si tolgono risposte e domande
      update public.domande set attiva = false where id = any(v_ids) and id <> p_id;
      update public.domande set attiva = false where id = p_id;
      delete from public.risposte where domanda_id = any(v_ids);
      delete from public.risposte_extra where domanda_id = any(v_ids);
      delete from public.domande where id = any(v_ids) and id <> p_id;
      delete from public.domande where id = p_id;
    end if;
    return jsonb_build_object('risposte', v_risposte + v_extra, 'domande_dipendenti', v_dip);

  elsif p_tipo = 'corso' then
    if not exists (select 1 from public.corsi_di_laurea where id = p_id) then raise exception 'Corso non trovato'; end if;
    select coalesce(array_agg(id), '{}') into v_mc from public.materie_corso where corso_id = p_id;
    select coalesce(array_agg(id), '{}') into v_comp from public.compilazioni where materia_corso_id = any(v_mc);
    select count(*) into v_risposte from public.risposte where compilazione_id = any(v_comp);
    if p_esegui then
      delete from public.partecipazioni where materia_corso_id = any(v_mc);
      delete from public.compilazioni where id = any(v_comp);
      delete from public.materie_corso where id = any(v_mc);
      delete from public.corsi_di_laurea where id = p_id;
    end if;
    return jsonb_build_object('materie_collegate', cardinality(v_mc), 'compilazioni', cardinality(v_comp), 'risposte', v_risposte);

  elsif p_tipo = 'materia' then
    if not exists (select 1 from public.materie where id = p_id) then raise exception 'Materia non trovata'; end if;
    select coalesce(array_agg(id), '{}') into v_mc from public.materie_corso where materia_id = p_id;
    select coalesce(array_agg(id), '{}') into v_ins from public.insegnamenti where materia_id = p_id;
    select coalesce(array_agg(id), '{}') into v_comp from public.compilazioni where materia_corso_id = any(v_mc);
    select count(*) into v_risposte from public.risposte where compilazione_id = any(v_comp);
    if p_esegui then
      delete from public.partecipazioni where materia_corso_id = any(v_mc);
      delete from public.compilazioni where id = any(v_comp);
      delete from public.insegnamenti where id = any(v_ins);
      delete from public.materie_corso where id = any(v_mc);
      delete from public.materie where id = p_id;
    end if;
    return jsonb_build_object('corsi_collegati', cardinality(v_mc), 'docenti_collegati', cardinality(v_ins),
                              'compilazioni', cardinality(v_comp), 'risposte', v_risposte);

  elsif p_tipo = 'docente' then
    if not exists (select 1 from public.docenti where id = p_id) then raise exception 'Docente non trovato'; end if;
    select coalesce(array_agg(id), '{}') into v_ins from public.insegnamenti where docente_id = p_id;
    select count(*) into v_risposte from public.risposte where insegnamento_id = any(v_ins);
    if p_esegui then
      delete from public.risposte where insegnamento_id = any(v_ins);
      delete from public.blocchi_saltati where insegnamento_id = any(v_ins);
      delete from public.insegnamenti where id = any(v_ins);
      delete from public.docenti where id = p_id;
    end if;
    return jsonb_build_object('materie_collegate', cardinality(v_ins), 'risposte', v_risposte);

  elsif p_tipo = 'edizione' then
    if not exists (select 1 from public.edizioni where id = p_id) then raise exception 'Edizione non trovata'; end if;
    if exists (select 1 from public.edizioni where id = p_id and aperta) then
      raise exception 'Chiudi prima l''edizione: un''edizione aperta non si elimina';
    end if;
    select coalesce(array_agg(id), '{}') into v_comp from public.compilazioni where edizione_id = p_id;
    select count(*) into v_risposte from public.risposte where compilazione_id = any(v_comp);
    select count(*) into v_extra from public.risposte_extra where edizione_id = p_id;
    if p_esegui then
      delete from public.risposte_extra where edizione_id = p_id;
      delete from public.partecipazioni_extra where edizione_id = p_id;
      delete from public.partecipazioni where edizione_id = p_id;
      delete from public.compilazioni where id = any(v_comp);
      delete from public.edizioni where id = p_id;
    end if;
    return jsonb_build_object('compilazioni', cardinality(v_comp), 'risposte', v_risposte + v_extra);

  else
    raise exception 'Tipo non valido';
  end if;
end $$;
revoke all on function public.elimina_voce(text, uuid, boolean) from public, anon;
grant execute on function public.elimina_voce(text, uuid, boolean) to authenticated;
