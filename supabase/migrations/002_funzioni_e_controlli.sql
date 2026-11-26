-- Funzioni di ruolo usate dalle regole di accesso
create or replace function private.ruolo_admin() returns text
language sql stable security definer set search_path = '' as $$
  select ruolo from public.admin_utenti where user_id = (select auth.uid())
$$;

create or replace function private.e_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.ruolo_admin() = 'admin', false)
$$;

create or replace function private.puo_modificare() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.ruolo_admin() in ('admin','editor'), false)
$$;

create or replace function private.puo_leggere_risultati() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.ruolo_admin() in ('admin','editor','lettura'), false)
$$;

create or replace function private.get_setting_int(k text, def int) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select valore::int from public.impostazioni where chiave = k), def)
$$;

-- L'anno della materia non puo superare la durata del corso
create or replace function private.check_anno_materia_corso() returns trigger
language plpgsql set search_path = '' as $$
declare d smallint;
begin
  select durata_anni into d from public.corsi_di_laurea where id = new.corso_id;
  if new.anno > d then
    raise exception 'L''anno % supera la durata del corso (% anni)', new.anno, d;
  end if;
  return new;
end $$;
create trigger materie_corso_anno before insert or update on public.materie_corso
  for each row execute function private.check_anno_materia_corso();

-- Date di apertura e chiusura delle edizioni
create or replace function private.edizione_date() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.aperta then new.aperta_il := now(); end if;
  else
    if new.aperta and not old.aperta then
      new.aperta_il := now(); new.chiusa_il := null;
    elsif not new.aperta and old.aperta then
      new.chiusa_il := now();
    end if;
  end if;
  return new;
end $$;
create trigger edizioni_date before insert or update on public.edizioni
  for each row execute function private.edizione_date();

-- Opzioni: limiti min/max dalle impostazioni, nessuna modifica se ci sono risposte
create or replace function private.proteggi_opzioni() returns trigger
language plpgsql security definer set search_path = '' as $$
declare did uuid; n int; mx int; mn int; att boolean;
begin
  if tg_op = 'DELETE' then did := old.domanda_id; else did := new.domanda_id; end if;
  if exists (select 1 from public.risposte where domanda_id = did) then
    raise exception 'Domanda con risposte gia raccolte: le opzioni non sono modificabili';
  end if;
  select count(*) into n from public.opzioni_risposta where domanda_id = did;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and old.domanda_id <> new.domanda_id) then
    mx := private.get_setting_int('opzioni_max', 5);
    if n >= mx then raise exception 'Massimo % opzioni per domanda', mx; end if;
  end if;
  if tg_op = 'DELETE' then
    select attiva into att from public.domande where id = did;
    mn := private.get_setting_int('opzioni_min', 3);
    if found and att and (n - 1) < mn then
      raise exception 'Una domanda attiva deve avere almeno % opzioni', mn;
    end if;
    return old;
  end if;
  return new;
end $$;
create trigger opzioni_protette before insert or update or delete on public.opzioni_risposta
  for each row execute function private.proteggi_opzioni();

-- Domande: niente modifiche sostanziali con risposte raccolte; controlli all'attivazione
create or replace function private.proteggi_domande() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n int; mn int; mx int;
begin
  if tg_op = 'UPDATE' then
    if exists (select 1 from public.risposte where domanda_id = old.id)
       and (new.categoria is distinct from old.categoria
         or new.tipo_risposta is distinct from old.tipo_risposta
         or new.testo is distinct from old.testo
         or new.scala_min is distinct from old.scala_min
         or new.scala_max is distinct from old.scala_max
         or new.ambito_docente is distinct from old.ambito_docente) then
      raise exception 'Domanda con risposte gia raccolte: disattivala e creane una nuova';
    end if;
  end if;
  if new.attiva then
    if new.tipo_risposta = 'scelta_singola' then
      select count(*) into n from public.opzioni_risposta where domanda_id = new.id;
      mn := private.get_setting_int('opzioni_min', 3);
      mx := private.get_setting_int('opzioni_max', 5);
      if n < mn or n > mx then
        raise exception 'Una domanda a scelta singola attiva deve avere da % a % opzioni (ora %)', mn, mx, n;
      end if;
    end if;
    if new.categoria in ('specifica_materia','specifica_docente')
       and not exists (select 1 from public.collegamenti_domanda where domanda_id = new.id) then
      raise exception 'Una domanda specifica attiva deve avere almeno un collegamento';
    end if;
  end if;
  return new;
end $$;
create trigger domande_protette before insert or update on public.domande
  for each row execute function private.proteggi_domande();

-- Collegamenti coerenti con la categoria della domanda
create or replace function private.valida_collegamento() returns trigger
language plpgsql security definer set search_path = '' as $$
declare c text; a text;
begin
  select categoria, ambito_docente into c, a from public.domande where id = new.domanda_id;
  if c in ('generica','generica_docente') then
    raise exception 'Le domande di categoria % non hanno collegamenti', c;
  elsif c = 'specifica_materia' and new.materia_id is null then
    raise exception 'Una domanda specifica per materia va collegata a una materia';
  elsif c = 'specifica_docente' and a = 'docente' and new.docente_id is null then
    raise exception 'Questa domanda va collegata a un docente';
  elsif c = 'specifica_docente' and a = 'insegnamento' and new.insegnamento_id is null then
    raise exception 'Questa domanda va collegata a una coppia materia + docente';
  end if;
  return new;
end $$;
create trigger collegamenti_validi before insert or update on public.collegamenti_domanda
  for each row execute function private.valida_collegamento();

-- Compilazioni: edizione aperta e anno coerente con il corso
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
  if new.anno_studente > d then
    raise exception 'L''anno dello studente supera la durata del corso';
  end if;
  return new;
end $$;
create trigger compilazioni_valide before insert on public.compilazioni
  for each row execute function private.valida_compilazione();

create or replace function private.richiedi_edizione_aperta() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.edizioni where id = new.edizione_id and aperta) then
    raise exception 'L''edizione non e aperta alla compilazione';
  end if;
  return new;
end $$;
create trigger partecipazioni_edizione before insert on public.partecipazioni
  for each row execute function private.richiedi_edizione_aperta();

-- Risposte: coerenza con tipo di domanda, materia, docente e collegamenti
create or replace function private.valida_risposta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare d public.domande%rowtype; mat uuid; ins_mat uuid; ins_doc uuid; ok boolean;
begin
  select * into d from public.domande where id = new.domanda_id;
  if not found or not d.attiva then raise exception 'Domanda non valida o non attiva'; end if;
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  if d.categoria in ('generica_docente','specifica_docente') then
    if new.insegnamento_id is null then raise exception 'Per una domanda sul docente serve l''insegnamento'; end if;
    select materia_id, docente_id into ins_mat, ins_doc from public.insegnamenti where id = new.insegnamento_id;
    if ins_mat is distinct from mat then raise exception 'Il docente non appartiene alla materia compilata'; end if;
  elsif new.insegnamento_id is not null then
    raise exception 'Insegnamento non ammesso per questa domanda';
  end if;
  if d.categoria = 'specifica_materia' then
    if not exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and materia_id = mat) then
      raise exception 'Domanda non collegata a questa materia';
    end if;
  elsif d.categoria = 'specifica_docente' then
    if d.ambito_docente = 'docente' then
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and docente_id = ins_doc);
    else
      ok := exists (select 1 from public.collegamenti_domanda where domanda_id = d.id and insegnamento_id = new.insegnamento_id);
    end if;
    if not ok then raise exception 'Domanda non collegata a questo docente'; end if;
  end if;
  if d.tipo_risposta = 'scala' then
    if new.valore_numero is null or new.valore_numero < d.scala_min or new.valore_numero > d.scala_max then
      raise exception 'Valore fuori dalla scala';
    end if;
  elsif d.tipo_risposta = 'scelta_singola' then
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  else
    if new.testo is null or length(btrim(new.testo)) = 0 then raise exception 'Risposta testuale vuota'; end if;
  end if;
  return new;
end $$;
create trigger risposte_valide before insert on public.risposte
  for each row execute function private.valida_risposta();

create or replace function private.valida_blocco_saltato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare mat uuid; ins_mat uuid;
begin
  select mc.materia_id into mat
    from public.compilazioni c join public.materie_corso mc on mc.id = c.materia_corso_id
    where c.id = new.compilazione_id;
  select materia_id into ins_mat from public.insegnamenti where id = new.insegnamento_id;
  if ins_mat is distinct from mat then
    raise exception 'Il docente non appartiene alla materia compilata';
  end if;
  return new;
end $$;
create trigger blocchi_validi before insert on public.blocchi_saltati
  for each row execute function private.valida_blocco_saltato();
