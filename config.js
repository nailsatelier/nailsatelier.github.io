// Conexión con Supabase (Project Settings → API). La "anon public key" es pública por diseño:
// la seguridad la ponen las reglas de supabase.sql. NUNCA pegues aquí la "service_role" key.
// Mientras estén vacías, la página funciona en modo de prueba (solo en tu navegador).
window.NAILS_CONFIG = {
  supabaseUrl: '',      // ejemplo: 'https://abcdefghijkl.supabase.co'
  supabaseAnonKey: '',  // ejemplo: 'eyJhbGciOi...'
};
