# Sondaggio studenti

Sondaggio anonimo degli studenti del **DiSTeBA** (Università del Salento) sui corsi e sui docenti, a cura
di Udu Lecce DiSTeBA. Parte dal codice del sondaggio di Ingegneria dell'Innovazione ma è del tutto
separato, con account, database e indirizzo propri.

- **Area studenti** (`#/`): scelta del corso, delle materie e compilazione anonima.
- **Pannello admin** (`#/admin`): dati accademici, domande, edizioni, statistiche, importazioni, impostazioni e utenti.

Stack: React, TypeScript, Vite, Tailwind e Supabase (database, accessi e regole di sicurezza).

| Cartella | Contenuto |
|---|---|
| `src/`, `public/` | Il sito |
| `supabase/installa.sql` | Tutto il database, da eseguire una volta su un progetto vuoto |
| `supabase/migrations/` | Le stesse modifiche, una per file, nell'ordine in cui sono nate |
| `supabase/dati_iniziali.sql` | Nome del dipartimento e primo admin |
| `supabase/functions/verifica-studente/` | La funzione che controlla l'accesso Google e riceve le risposte |
| `.github/workflows/pubblica.yml` | Pubblicazione automatica su GitHub Pages |

> `installa.sql` è stato ricostruito dalle modifiche fatte al database originale e controllato contro il
> codice, ma **non è ancora stato eseguito su un database vuoto**. Se si ferma con un errore non lascia
> nulla a metà: si corregge e si rilancia.

## 1. Account da creare

Tutti nuovi: nessuna chiave o password del sondaggio originale va riusata.

### Supabase (database)

1. Crea un progetto in una regione dell'Unione europea (l'originale è a Parigi).
2. *SQL Editor*: incolla ed esegui `supabase/installa.sql`.
3. *Authentication → Users → Add user*: crea il primo admin, con **Auto Confirm User**.
4. *SQL Editor*: in `supabase/dati_iniziali.sql` scrivi l'email dell'admin, poi eseguilo.
5. *Authentication → Sign In / Providers*: disattiva **Allow new users to sign up**. Gli altri utenti del
   pannello si creano a mano come al punto 3 e si abilitano da *Impostazioni*.

### Google (accesso degli studenti)

In Google Cloud, *Google Auth Platform → Clients*, crea un client OAuth di tipo **Web application** e in
*Authorized JavaScript origins* metti `http://localhost:5173` e `https://NOMEUTENTE.github.io`.
Pubblica l'app (non lasciarla in prova), altrimenti entrano solo gli utenti di prova. Serve solo l'ID
client; il client secret non va scritto da nessuna parte.

### La funzione di verifica

1. In `supabase/functions/verifica-studente/index.ts` sostituisci `NOMEUTENTE` in `ORIGINI` e controlla `DOMINIO`.
2. Su Supabase, *Edge Functions → Deploy a new function → Via editor*: nome `verifica-studente`, incolla il
   codice e **disattiva «Verify JWT»** (l'identità la controlla la funzione stessa, con Google).
3. *Edge Functions → Secrets*:
   - `GOOGLE_CLIENT_ID`: l'ID client di Google;
   - `PEPPER`: una chiave casuale nuova, che si genera con
     `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`.
     Non va salvata nel codice e non va cambiata mentre un'edizione è aperta: si potrebbe rispondere due volte.

## 2. Provare in locale

1. Copia `.env.example` in `.env.local` con l'indirizzo del progetto Supabase, la chiave **publishable**
   (*Project Settings → API Keys*, mai la secret) e l'ID client di Google.
2. Installa e avvia:

```bash
npm install
npm run dev
```

Il sito è su <http://localhost:5173>. Se il sondaggio originale è avviato sulla stessa porta, chiudilo prima.

## 3. Cosa è già adattato e cosa controllare

Nome, logo (`public/udu-lecce-disteba.png`) ed email di contatto (`sondaggio.disteba@gmail.com`) sono già
quelli del DiSTeBA. Restano uguali all'originale i colori di Udu e il dominio `@studenti.unisalento.it`.

- Rileggi `public/privacy.html` prima di pubblicare: dice che il database è in Francia, a Parigi. Se scegli
  un'altra regione per il progetto Supabase, correggilo.
- Corsi, materie, docenti e domande si inseriscono dal pannello (anche con *Importazioni*): il database
  nasce vuoto.

## 4. Pubblicare

1. Crea un repository GitHub nuovo (con il piano gratuito, Pages richiede che sia pubblico).
2. *Settings → Pages → Source*: **GitHub Actions**.
3. *Settings → Secrets and variables → Actions → Variables*: crea `VITE_SUPABASE_URL`,
   `VITE_SUPABASE_PUBLISHABLE_KEY` e `VITE_GOOGLE_CLIENT_ID`.
4. Da questa cartella:

```bash
git init -b main
git add .
git commit -m "Sondaggio studenti"
git remote add origin https://github.com/NOMEUTENTE/NOME-REPO.git
git push -u origin main
```

5. Su Supabase, *Authentication → URL Configuration*: metti come **Site URL** l'indirizzo pubblicato.

Da lì in poi ogni `git push` su `main` ripubblica il sito.

La build contiene l'indirizzo di Supabase e la chiave publishable, che sono pubblici per natura: la
protezione dei dati sta nelle regole del database. `.env.local` resta fuori da git.
