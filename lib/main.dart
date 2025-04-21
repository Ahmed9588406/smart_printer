import 'package:flutter/material.dart';
import 'package:smart_printer/pages/home_page.dart';
import 'package:smart_printer/pages/login_page.dart';
import 'package:smart_printer/pages/profile_setup_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qsarfqkjulypynvartdg.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFzYXJmcWtqdWx5cHludmFydGRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDUxODY4NTQsImV4cCI6MjA2MDc2Mjg1NH0.vztnqt3L94DksRw-rMZGJTFnlOJDs_RpwpBpjnPUrgI',
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Printer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        fontFamily: 'Poppins',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.deepPurple.shade400, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
      home: const AuthPage(),
    );
  }
}

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkAuth(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        return const LoginPage();
      },
    );
  }

  Future<bool> _checkAuth(BuildContext context) async {
    try {
      final session = supabase.auth.currentSession;
      if (session != null) {
        final profile = await supabase
            .from('user_profiles')
            .select()
            .eq('id', session.user.id)
            .maybeSingle();

        if (profile != null) {
          if (context.mounted) {
            await Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const HomePage(title: 'Smart Printer'),
              ),
            );
          }
        } else if (context.mounted) {
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const ProfileSetupPage(),
            ),
          );
        }
        return true;
      }
    } catch (e) {
      // Handle errors silently
    }
    return false;
  }
}
