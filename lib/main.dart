import 'dart:async';
import 'package:call_project/core/navigation/navigation_service.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_options.dart';
import 'features/auth/screens/login_screen.dart';
import 'core/providers/firebase_providers.dart';
import 'features/auth/repository/auth_repository.dart';

import 'features/notifications/data/repositories/notification_repository.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'features/call/presentation/widgets/call_listener.dart';
import 'features/home/presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final List<dynamic> eventQueue = [];
  bool firebaseReady = false;
  final container = ProviderContainer();

  FlutterCallkitIncoming.onEvent.listen((event) async {
    if (event == null) return;
    if (!firebaseReady) {
      debugPrint('[GLOBAL-DEBUG] Queuing event: ${event.event}');
      eventQueue.add(event);
      return;
    }
    container
        .read(notificationServiceProvider.notifier)
        .handleGlobalCallEvent(event);
  });

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  firebaseReady = true;

  await container.read(notificationRepositoryProvider).requestPermissions();

  // systemAlertWindow permission request moved to HomeScreen to prevent startup jank

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    await container
        .read(notificationRepositoryProvider)
        .updateToken(currentUser.uid);
  }

  for (final queuedEvent in eventQueue) {
    debugPrint('[GLOBAL-DEBUG] Processing queued event: ${queuedEvent.event}');
    container
        .read(notificationServiceProvider.notifier)
        .handleGlobalCallEvent(queuedEvent);
  }

  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls is List && activeCalls.isNotEmpty) {
    final body = activeCalls.first;
    final isAccepted = body['isAccepted'] == true || body['accepted'] == true;

    if (isAccepted) {
      debugPrint('[GLOBAL-DEBUG] Found accepted call on startup: $body');
      container
          .read(notificationServiceProvider.notifier)
          .handleGlobalCallEvent(CallEvent(body, Event.actionCallAccept));
    }
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Connectify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.light().textTheme,
        ),
      ),
      home: authState.when(
        data: (user) {
          if (user != null) {
            return const CallListener(child: HomeScreen());
          }
          return const LoginScreen();
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
      ),
    );
  }
}
