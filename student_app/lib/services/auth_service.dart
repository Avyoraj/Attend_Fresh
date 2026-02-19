import 'package:supabase_flutter/supabase_flutter.dart';

/// 🔐 Auth Service for Student App
class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Current logged-in user
  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  /// Get student profile from DB
  Future<Map<String, dynamic>?> getStudentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _supabase
        .from('students')
        .select()
        .eq('email', user.email!)
        .maybeSingle();

    return response;
  }

  /// Sign up with email/password + create student record
  Future<({bool success, String message})> signUp({
    required String email,
    required String password,
    required String name,
    required String studentId,
    String? department,
    int? year,
    String? section,
  }) async {
    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        return (success: false, message: 'Sign up failed');
      }

      // Create student record in students table
      await _supabase.from('students').insert({
        'student_id': studentId,
        'name': name,
        'email': email,
        'year': year ?? 1,
        'section': section ?? 'A',
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
