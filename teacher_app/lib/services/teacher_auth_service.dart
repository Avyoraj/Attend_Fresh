import 'package:supabase_flutter/supabase_flutter.dart';

/// 🔐 Auth Service for Teacher App
class TeacherAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  /// Get teacher profile from DB
  Future<Map<String, dynamic>?> getTeacherProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _supabase
        .from('teachers')
        .select()
        .eq('email', user.email!)
        .maybeSingle();

    return response;
  }

  /// Sign up with email/password + create teacher record
  Future<({bool success, String message})> signUp({
    required String email,
    required String password,
    required String name,
    String? department,
  }) async {
    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        return (success: false, message: 'Sign up failed');
      }

      // Create teacher record
      await _supabase.from('teachers').insert({
        'auth_id': authResponse.user!.id,
        'name': name,
        'email': email,
        'department': department ?? 'General',
      });

      return (success: true, message: 'Account created! Please check your email to verify.');
    } on AuthException catch (e) {
      return (success: false, message: e.message);
    } catch (e) {
      return (success: false, message: e.toString());
    }
  }

  /// Sign in with email/password
  Future<({bool success, String message})> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return (success: true, message: 'Login successful');
    } on AuthException catch (e) {
      return (success: false, message: e.message);
    } catch (e) {
      return (success: false, message: e.toString());
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
