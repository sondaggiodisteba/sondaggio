// Verifica dello studente con l'accesso Google e invio delle compilazioni.
//
// Il browser manda qui la prova d'identità di Google (id_token). La funzione ne controlla firma, destinatario,
// scadenza e dominio, calcola un'impronta con una chiave segreta che esiste solo qui, e passa al database
// soltanto l'impronta: l'email non viene mai salvata né inoltrata, e le risposte non portano nessuna identità.
//
// Segreti da impostare su Supabase (Edge Functions → Secrets):
//   GOOGLE_CLIENT_ID  l'ID client OAuth di Google (finisce con .apps.googleusercontent.com)
//   PEPPER            una chiave casuale lunga, scelta da chi gestisce il progetto; non va mai scritta altrove

import { createClient } from 'jsr:@supabase/supabase-js@2'
import { createRemoteJWKSet, jwtVerify } from 'npm:jose@5.9.6'

const DOMINIO = 'studenti.unisalento.it'
// L'indirizzo del sito pubblicato (solo https://dominio, senza cartelle) e quello delle prove in locale
const ORIGINI = ['https://sondaggiodisteba.github.io', 'http://localhost:5173']
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const GOOGLE = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'))

class Errore extends Error {
  constructor(public stato: number, messaggio: string) {
    super(messaggio)
  }
}

function intestazioni(req: Request): HeadersInit {
  const origine = req.headers.get('origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGINI.includes(origine) ? origine : ORIGINI[0],
    'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
    'Content-Type': 'application/json',
  }
}

function rispondi(req: Request, stato: number, corpo: unknown) {
  return new Response(JSON.stringify(corpo), { status: stato, headers: intestazioni(req) })
}

// Controlla la prova di Google e restituisce l'email dello studente
async function identifica(idToken: unknown): Promise<string> {
  const clientId = Deno.env.get('GOOGLE_CLIENT_ID')
  if (!clientId) throw new Errore(500, 'Il servizio non è ancora configurato.')
  if (typeof idToken !== 'string' || idToken.length < 100) {
    throw new Errore(401, 'Accedi con Google per continuare.')
  }
  let payload
  try {
    ;({ payload } = await jwtVerify(idToken, GOOGLE, {
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: clientId,
    }))
  } catch {
    throw new Errore(401, 'L\'accesso è scaduto o non è valido. Accedi di nuovo con Google.')
  }
  const email = String(payload.email ?? '').toLowerCase()
  if (payload.email_verified !== true || payload.hd !== DOMINIO || !email.endsWith(`@${DOMINIO}`)) {
    throw new Errore(403, `Serve un account @${DOMINIO}.`)
  }
  return email
}

// Impronta della persona per una certa edizione: edizioni diverse danno impronte diverse, quindi non
// si possono collegare fra loro. Senza la chiave segreta non si risale all'email.
async function impronta(email: string, edizione: string): Promise<string> {
  const pepper = Deno.env.get('PEPPER')
  if (!pepper || pepper.length < 32) throw new Errore(500, 'Il servizio non è ancora configurato.')
  const chiave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pepper),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const firma = await crypto.subtle.sign('HMAC', chiave, new TextEncoder().encode(`${edizione}:${email}`))
  return [...new Uint8Array(firma)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: intestazioni(req) })
  if (req.method !== 'POST') return rispondi(req, 405, { errore: 'Metodo non consentito.' })

  try {
    const corpo = await req.json().catch(() => null)
    if (!corpo || typeof corpo !== 'object') throw new Errore(400, 'Richiesta non valida.')
    const { azione, id_token, edizione } = corpo as Record<string, unknown>
    if (typeof edizione !== 'string' || !UUID.test(edizione)) throw new Errore(400, 'Richiesta non valida.')

    const email = await identifica(id_token)
    const hash = await impronta(email, edizione)
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
      auth: { persistSession: false },
    })

    if (azione === 'stato') {
      const [materie, extra, scelta] = await Promise.all([
        db.rpc('materie_compilate', { p_hash: hash, p_edizione: edizione }),
        db.rpc('extra_inviate', { p_hash: hash, p_edizione: edizione }),
        // Corso e anno registrati al primo invio: da lì in poi non si cambiano
        db.rpc('scelta_studente', { p_hash: hash, p_edizione: edizione }),
      ])
      if (materie.error || extra.error || scelta.error) {
        throw new Errore(500, 'Non riesco a controllare le tue compilazioni. Riprova.')
      }
      const s = Array.isArray(scelta.data) ? scelta.data[0] : null
      return rispondi(req, 200, {
        compilate: materie.data ?? [],
        extra_inviate: extra.data === true,
        scelta: s ? { corso_id: s.corso_id, anno: s.fuori_corso ? 'fuori_corso' : s.anno_studente } : null,
      })
    }

    if (azione === 'invia') {
      const { fuori_corso, anno, materie, extra } = corpo as Record<string, unknown>
      if (typeof fuori_corso !== 'boolean' || !Array.isArray(materie)) throw new Errore(400, 'Richiesta non valida.')
      if (extra !== undefined && !Array.isArray(extra)) throw new Errore(400, 'Richiesta non valida.')
      const { error } = await db.rpc('invia_compilazioni_verificate', {
        p_hash: hash,
        p_edizione: edizione,
        p_fuori_corso: fuori_corso,
        p_materie: materie,
        p_anno: fuori_corso ? null : anno,
        p_extra: extra ?? null,
      })
      if (error) {
        // I controlli scritti nel database hanno già messaggi in italiano
        if (error.code === 'P0001') throw new Errore(400, error.message)
        throw new Errore(500, 'Non è stato possibile inviare le risposte. Riprova.')
      }
      return rispondi(req, 200, { ok: true })
    }

    throw new Errore(400, 'Richiesta non valida.')
  } catch (e) {
    if (e instanceof Errore) return rispondi(req, e.stato, { errore: e.message })
    return rispondi(req, 500, { errore: 'Qualcosa non ha funzionato. Riprova.' })
  }
})
