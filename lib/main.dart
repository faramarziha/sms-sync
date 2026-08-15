import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'transport/websocket_transport.dart';
import 'transport/nsd_service.dart';
import 'client/client_sync_service.dart';
import 'server/server_sync_service.dart';
import 'client/ui/client_home_screen.dart';
import 'server/ui/server_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Premium dark color scheme
    const seedColor = Color(0xFF00BCD4); // Cyan accent
    final darkScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: const Color(0xFF0D1117),
      onSurface: const Color(0xFFE6EDF3),
      primary: const Color(0xFF58A6FF),
      onPrimary: const Color(0xFF0D1117),
      secondary: const Color(0xFF7EE787),
      onSecondary: const Color(0xFF0D1117),
      tertiary: const Color(0xFFD2A8FF),
      error: const Color(0xFFFF7B72),
      surfaceContainerHighest: const Color(0xFF161B22),
    );

    return MaterialApp(
      title: 'SMS Sync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF161B22),
          foregroundColor: const Color(0xFFE6EDF3),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE6EDF3),
            letterSpacing: -0.5,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF161B22),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D1117),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF58A6FF), width: 2),
          ),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: const Color(0xFF58A6FF),
          labelColor: const Color(0xFF58A6FF),
          unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 13),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF238636),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE6EDF3),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF21262D),
          selectedColor: const Color(0xFF1F6FEB).withValues(alpha: 0.3),
          labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE6EDF3)),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF21262D),
          contentTextStyle: GoogleFonts.inter(color: const Color(0xFFE6EDF3)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE6EDF3),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.06),
          thickness: 1,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          linearTrackColor: Color(0xFF21262D),
          color: Color(0xFF58A6FF),
        ),
      ),
      home: const Initializer(),
    );
  }
}

class Initializer extends StatefulWidget {
  const Initializer({super.key});

  @override
  State<Initializer> createState() => _InitializerState();
}

class _InitializerState extends State<Initializer> {
  dynamic _service;
  bool _isServer = false;

  @override
  void initState() {
    super.initState();
    final transport = WebSocketTransport();
    final discovery = NsdDiscoveryService();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _isServer = true;
      _service = ServerSyncService(transport, discovery);
    } else {
      _isServer = false;
      _service = ClientSyncService(transport, discovery);
    }
  }

  @override
  void dispose() {
    if (_service != null) {
      try {
        (_service as dynamic).dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isServer && _service is ServerSyncService) {
      return ServerHomeScreen(service: _service as ServerSyncService);
    } else if (_service is ClientSyncService) {
      return ClientHomeScreen(service: _service as ClientSyncService);
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
