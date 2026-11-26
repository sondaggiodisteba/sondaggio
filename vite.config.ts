import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Tutti i percorsi sono relativi: il sito funziona in qualsiasi cartella (per esempio nomeutente.github.io/nome-repo/).
export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss()],
})
