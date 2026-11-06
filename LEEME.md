# nailsatelier.github.io: agenda de citas de Nails Atelier

Página estática gratuita en **GitHub Pages**, con la base de datos en **Supabase** (plan gratuito). No cuesta nada.

| Enlace | Para quién |
|---|---|
| `https://nailsatelier.github.io/` | Clientas: reservan sin crear cuenta |
| `https://nailsatelier.github.io/#mi-cita` | Clientas: ver, reprogramar o cancelar con su código y celular |
| `https://nailsatelier.github.io/#citas` | Salón: pide correo y contraseña |

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | La página completa: reservas y panel del salón |
| `config.js` | Dirección y clave pública de Supabase (se completa en el paso 1) |
| `supabase.sql` | Tablas, reglas de seguridad y funciones de reserva |
| `.nojekyll`, `favicon.svg` | Archivos auxiliares de GitHub Pages |

Si `config.js` está vacío, la página funciona en **modo de prueba**: los datos quedan solo en tu navegador. Sirve para revisar el diseño.

---

## 1. Crear la base de datos en Supabase (gratis)

1. Entra a https://supabase.com y crea un proyecto llamado `nails-atelier`.
   - Región: **South America (São Paulo)**.
   - Guarda la contraseña de la base en un lugar seguro.
2. Ve a **SQL Editor → New query**, pega todo `supabase.sql` y pulsa **Run**. Debe terminar con "Success". Se puede volver a ejecutar sin perder datos.
3. Crea la cuenta del salón: **Authentication → Users → Add user → Create new user**, con el correo del salón, una contraseña larga y **Auto Confirm User** marcado.
4. Dale acceso al panel. En **SQL Editor**, ejecuta lo siguiente con ese correo:
   ```sql
   insert into admins (user_id) select id from auth.users where email = 'correo-del-salon@ejemplo.com';
   ```
   Repite este paso por cada persona del salón que deba entrar al panel.
5. Cierra el registro público: **Authentication → Sign In / Providers → Allow new users to sign up → desactivado**. Las clientas no necesitan cuenta.
6. En **Project Settings → API**, copia **Project URL** y la clave **anon public**, y pégalas en `config.js`:
   ```js
   window.NAILS_CONFIG = {
     supabaseUrl: 'https://xxxxxxxx.supabase.co',
     supabaseAnonKey: 'eyJhbGciOi...',
   };
   ```
   La clave `anon` es pública por diseño: la protegen las reglas de `supabase.sql`. **Nunca** pongas la clave `service_role` en `config.js`.

Nota: en el plan gratuito, Supabase **pausa el proyecto tras 7 días sin actividad**. Con reservas diarias no pasa. Si se pausa, se reactiva desde el panel de Supabase con **Restore project**.

## 2. Crear la organización `nailsatelier` en GitHub (gratis)

1. Inicia sesión en https://github.com con tu cuenta.
2. Arriba a la derecha pulsa **+ → New organization → Create a free organization**.
3. En **Organization name** escribe `nailsatelier`. El 05/11/2026 ese nombre estaba libre.
4. Pon tu correo, elige **My personal account** y termina el asistente. Puedes saltarte la invitación de miembros.

## 3. Publicar la página

1. Dentro de la organización `nailsatelier` pulsa **Repositories → New repository**.
   - **Repository name:** exactamente `nailsatelier.github.io`.
   - **Public**: GitHub Pages gratis requiere repositorio público, y ningún archivo de aquí es secreto.
   - Pulsa **Create repository**.
2. Pulsa **uploading an existing file** y arrastra **todos** los archivos de esta carpeta. Incluye `.nojekyll`: si no lo ves en Windows, actívalo en Explorador → Vista → Mostrar → Elementos ocultos. Luego pulsa **Commit changes**.
3. Ve a **Settings → Pages**.
   1. En **Source** elige **Deploy from a branch**, rama `main`, carpeta `/ (root)`, y pulsa **Save**.
   2. Cuando aparezca, marca **Enforce HTTPS**.
4. En 1 a 5 minutos la página estará en `https://nailsatelier.github.io/`.

Para cambiar algo después, por ejemplo `config.js`, ábrelo en GitHub, pulsa el lápiz ✏️, edítalo y pulsa **Commit changes**. Se publica solo en un par de minutos.

## 4. Primer uso

1. Abre `https://nailsatelier.github.io/#citas` e ingresa con la cuenta del salón.
2. En **Ajustes** completa la dirección, el WhatsApp, el aviso mínimo para reservar y la política de cancelación.
3. En **Servicios** y **Equipo y horarios** crea los reales. También puedes usar **Cargar ejemplo** y luego **Borrar ejemplo**.
4. En **Citas → Compartir enlace de reservas** copia el enlace para Instagram, TikTok, Google y WhatsApp.

## Más adelante: dominio propio `nailsatelier.pe` (opcional, de pago)

Los dominios `.pe` no son gratuitos: cuestan unos USD 30–50 al año en un registrador acreditado por https://punto.pe. Si lo compras, las citas y los datos se conservan:

1. En el repositorio crea un archivo llamado `CNAME` que contenga solo `nailsatelier.pe`.
2. En **Settings → Pages → Custom domain** escribe `nailsatelier.pe` y pulsa **Save**.
3. En el panel DNS del registrador crea estos registros y borra los otros registros A o AAAA de `@`:

   | Tipo | Nombre | Valor |
   |---|---|---|
   | A | `@` | `185.199.108.153` |
   | A | `@` | `185.199.109.153` |
   | A | `@` | `185.199.110.153` |
   | A | `@` | `185.199.111.153` |
   | CNAME | `www` | `nailsatelier.github.io` |

4. Cuando GitHub detecte el dominio, marca **Enforce HTTPS**.

La dirección `nailsatelier.github.io` seguirá funcionando y redirigirá al dominio nuevo.

## Seguridad (qué hace `supabase.sql`)

- Sin sesión, solo se pueden leer los servicios y profesionales activos, los ajustes y los horarios ocupados, sin nombres ni celulares.
- Una reserva solo se crea con la función `book`. Esa función valida el horario, el aviso mínimo y los días máximos, elige a la profesional libre y limita a 3 citas futuras por celular.
- La base **impide dos citas cruzadas de la misma profesional** (restricción `sin_cruces`), aunque dos clientas reserven en el mismo segundo.
- Una clienta solo ve, reprograma o cancela su propia cita, con código y celular. Puede cancelar hasta 3 horas antes.
- Solo las cuentas de la tabla `admins` ven nombres y celulares y modifican servicios, equipo, ausencias y citas.

## Estado de las pruebas (05/11/2026)

- **Modo de prueba local:** reserva, cruce rechazado, reprogramación con el mismo código, "Mi cita" y enlace para compartir.
- **Contra un Supabase simulado en el navegador:**
  - ingreso al panel: rechaza una clave incorrecta y una cuenta que no es del salón;
  - reserva desde el celular;
  - el público no ve nombres;
  - segunda reserva a la misma hora rechazada;
  - "Mi cita": consulta, reprogramación y cancelación;
  - límite de 3 citas por celular;
  - panel: ver citas, marcar atendida y reprogramar;
  - cierre de sesión.
- **Pendiente:**
  - ejecutar `supabase.sql` en un proyecto real, porque no se probó contra PostgreSQL;
  - probar una reserva real de punta a punta en `https://nailsatelier.github.io`;
  - probar en un iPhone y un Android.
