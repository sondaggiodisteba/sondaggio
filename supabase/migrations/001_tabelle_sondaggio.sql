create schema if not exists private;

-- Struttura accademica
create table public.dipartimenti (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  attivo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.corsi_di_laurea (
  id uuid primary key default gen_random_uuid(),
  dipartimento_id uuid not null references public.dipartimenti(id) on delete restrict,
  nome text not null,
  tipo text not null check (tipo in ('triennale','magistrale','ciclo_unico')),
  durata_anni smallint not null check (durata_anni between 1 and 6),
  attivo boolean not null default true,
  created_at timestamptz not null default now(),
  unique (dipartimento_id, nome)
);
create index corsi_dipartimento_idx on public.corsi_di_laurea (dipartimento_id);

create table public.materie (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cfu smallint check (cfu > 0),
  attiva boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.materie_corso (
  id uuid primary key default gen_random_uuid(),
  materia_id uuid not null references public.materie(id) on delete restrict,
  corso_id uuid not null references public.corsi_di_laurea(id) on delete restrict,
  anno smallint not null check (anno between 1 and 6),
  unique (materia_id, corso_id)
);
create index materie_corso_corso_idx on public.materie_corso (corso_id);

create table public.docenti (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cognome text not null,
  dipartimento_id uuid references public.dipartimenti(id) on delete set null,
  attivo boolean not null default true,
  created_at timestamptz not null default now()
);
create index docenti_dipartimento_idx on public.docenti (dipartimento_id);

create table public.insegnamenti (
  id uuid primary key default gen_random_uuid(),
  materia_id uuid not null references public.materie(id) on delete restrict,
  docente_id uuid not null references public.docenti(id) on delete restrict,
  unique (materia_id, docente_id)
);
create index insegnamenti_docente_idx on public.insegnamenti (docente_id);

-- Edizioni (cicli di compilazione, aperti e chiusi dal pannello admin)
create table public.edizioni (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  anno_accademico text not null,
  aperta boolean not null default false,
  aperta_il timestamptz,
  chiusa_il timestamptz,
  created_at timestamptz not null default now()
);
create unique index una_sola_edizione_aperta on public.edizioni ((true)) where aperta;

-- Domande
create table public.domande (
  id uuid primary key default gen_random_uuid(),
  testo text not null check (length(btrim(testo)) > 0),
  categoria text not null check (categoria in ('generica','specifica_materia','generica_docente','specifica_docente')),
  ambito_docente text check (ambito_docente in ('docente','insegnamento')),
  tipo_risposta text not null check (tipo_risposta in ('scala','scelta_singola','testo_libero')),
  scala_min smallint,
  scala_max smallint,
  etichetta_min text,
  etichetta_max text,
  obbligatoria boolean not null default true,
  attiva boolean not null default false,
  ordine integer not null default 0,
  created_at timestamptz not null default now(),
  constraint ambito_coerente check ((categoria = 'specifica_docente') = (ambito_docente is not null)),
  constraint scala_coerente check (
    (tipo_risposta = 'scala' and scala_min is not null and scala_max is not null and scala_min < scala_max)
    or (tipo_risposta <> 'scala' and scala_min is null and scala_max is null)
  )
);

create table public.opzioni_risposta (
  id uuid primary key default gen_random_uuid(),
  domanda_id uuid not null references public.domande(id) on delete cascade,
  testo text not null check (length(btrim(testo)) > 0),
  ordine smallint not null,
  unique (domanda_id, ordine)
);

create table public.collegamenti_domanda (
  id uuid primary key default gen_random_uuid(),
  domanda_id uuid not null references public.domande(id) on delete cascade,
  materia_id uuid references public.materie(id) on delete cascade,
  docente_id uuid references public.docenti(id) on delete cascade,
  insegnamento_id uuid references public.insegnamenti(id) on delete cascade,
  constraint un_solo_collegamento check (num_nonnulls(materia_id, docente_id, insegnamento_id) = 1)
);
create unique index coll_materia_uq on public.collegamenti_domanda (domanda_id, materia_id) where materia_id is not null;
create unique index coll_docente_uq on public.collegamenti_domanda (domanda_id, docente_id) where docente_id is not null;
create unique index coll_insegnamento_uq on public.collegamenti_domanda (domanda_id, insegnamento_id) where insegnamento_id is not null;
create index coll_materia_idx on public.collegamenti_domanda (materia_id);
create index coll_docente_idx on public.collegamenti_domanda (docente_id);
create index coll_insegnamento_idx on public.collegamenti_domanda (insegnamento_id);

create table public.impostazioni (
  chiave text primary key,
  valore text not null,
  descrizione text
);
insert into public.impostazioni (chiave, valore, descrizione) values
  ('opzioni_min', '3', 'Numero minimo di opzioni per le domande a scelta singola'),
  ('opzioni_max', '5', 'Numero massimo di opzioni per le domande a scelta singola');

-- Compilazioni e risposte (anonime: nessun riferimento allo studente)
create table public.compilazioni (
  id uuid primary key default gen_random_uuid(),
  edizione_id uuid not null references public.edizioni(id) on delete restrict,
  materia_corso_id uuid not null references public.materie_corso(id) on delete restrict,
  anno_studente smallint not null check (anno_studente between 1 and 6),
  data_compilazione date not null default current_date
);
create index compilazioni_edizione_idx on public.compilazioni (edizione_id);
create index compilazioni_materia_corso_idx on public.compilazioni (materia_corso_id);

create table public.risposte (
  id uuid primary key default gen_random_uuid(),
  compilazione_id uuid not null references public.compilazioni(id) on delete cascade,
  domanda_id uuid not null references public.domande(id) on delete restrict,
  insegnamento_id uuid references public.insegnamenti(id) on delete restrict,
  valore_numero smallint,
  opzione_id uuid references public.opzioni_risposta(id) on delete restrict,
  testo text check (length(testo) <= 2000),
  constraint un_solo_valore check (num_nonnulls(valore_numero, opzione_id, testo) = 1)
);
create unique index risposte_unica on public.risposte (compilazione_id, domanda_id, coalesce(insegnamento_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index risposte_domanda_idx on public.risposte (domanda_id);
create index risposte_insegnamento_idx on public.risposte (insegnamento_id);
create index risposte_opzione_idx on public.risposte (opzione_id);

create table public.blocchi_saltati (
  id uuid primary key default gen_random_uuid(),
  compilazione_id uuid not null references public.compilazioni(id) on delete cascade,
  insegnamento_id uuid not null references public.insegnamenti(id) on delete restrict,
  unique (compilazione_id, insegnamento_id)
);
create index blocchi_insegnamento_idx on public.blocchi_saltati (insegnamento_id);

-- Partecipazioni: solo per impedire i doppi invii, senza alcun legame con le compilazioni
create table public.partecipazioni (
  id uuid primary key default gen_random_uuid(),
  edizione_id uuid not null references public.edizioni(id) on delete restrict,
  materia_corso_id uuid not null references public.materie_corso(id) on delete restrict,
  studente_hash text not null,
  unique (edizione_id, materia_corso_id, studente_hash)
);
create index partecipazioni_materia_corso_idx on public.partecipazioni (materia_corso_id);

-- Utenti del pannello admin
create table public.admin_utenti (
  user_id uuid primary key references auth.users(id) on delete cascade,
  ruolo text not null check (ruolo in ('admin','editor','lettura')),
  dipartimento_id uuid references public.dipartimenti(id) on delete set null,
  created_at timestamptz not null default now()
);
create index admin_utenti_dipartimento_idx on public.admin_utenti (dipartimento_id);
