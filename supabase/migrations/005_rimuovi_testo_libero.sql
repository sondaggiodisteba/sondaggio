-- Il sondaggio non prevede risposte a testo libero
alter table public.domande drop constraint domande_tipo_risposta_check;
alter table public.domande add constraint domande_tipo_risposta_check check (tipo_risposta in ('scala','scelta_singola'));

alter table public.risposte drop column testo;
alter table public.risposte add constraint un_solo_valore check (num_nonnulls(valore_numero, opzione_id) = 1);

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
  else
    if new.opzione_id is null or not exists (select 1 from public.opzioni_risposta o where o.id = new.opzione_id and o.domanda_id = d.id) then
      raise exception 'Opzione non valida per questa domanda';
    end if;
  end if;
  return new;
end $$;
