/// Public Supabase settings (the URL and the "anon / publishable" key are meant to be public;
/// security comes from row level security in supabase/schema.sql). Fill these in once,
/// or pass --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://ymtahnystphyueoqgqko.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_nMT4XsdfthMBja2WMCVckA_ng6uf1pq',
);

/// Where the verification / reset links in emails send people (your hosted web console).
const siteUrl = String.fromEnvironment(
  'SITE_URL',
  defaultValue: 'https://tether-link.web.app',
);
