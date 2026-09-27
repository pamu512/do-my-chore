/// Backend endpoints supplied at build time via --dart-define.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  static const _urlEnv = String.fromEnvironment('SUPABASE_URL');
  static const _anonEnv = String.fromEnvironment('SUPABASE_ANON_KEY');

  static SupabaseConfig? fromEnvironment() {
    if (_urlEnv.isEmpty || _anonEnv.isEmpty) return null;
    return SupabaseConfig(url: _urlEnv, anonKey: _anonEnv);
  }

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
