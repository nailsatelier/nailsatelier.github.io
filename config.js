// Conexión con Supabase (Project Settings → API). La "anon public key" es pública por diseño:
// la seguridad la ponen las reglas de supabase.sql. NUNCA pegues aquí la "service_role" key.
// Si se dejan vacías, la página funciona en modo de prueba (solo en el navegador).
window.NAILS_CONFIG = {
  supabaseUrl: 'https://siqhymcfshbfqgaknxqm.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNpcWh5bWNmc2hiZnFnYWtueHFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5MzcwOTksImV4cCI6MjEwOTUxMzA5OX0.bbMi4gHKkIevH3CVMaS-uyeGD9y0fSo_wpNmTdRcHqs',
};
