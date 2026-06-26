import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'features/auth/screens/login_screen.dart';
import 'core/providers/firebase_providers.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/users/data/repository/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'features/notifications/presentation/services/callkit_service.dart';
import 'features/call/presentation/screens/call_screen.dart';
import 'features/call/presentation/controllers/call_controller.dart';
import 'features/call/presentation/widgets/call_listener.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.data['type'] == 'call') {
    await CallKitService.showIncomingCall(
      callerName: message.data['callerName'] ?? 'Unknown',
      callerId: message.data['callerId'] ?? '',
      channelId: message.data['channelId'] ?? '',
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Request permissions
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return MaterialApp(
      title: 'Agora Calling',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(allUsersProvider);
    final currentUser = FirebaseAuth.instance.currentUser;

    ref.listen(authControllerProvider, (previous, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              print('UI: Log Out Tapped (main_source)');
              ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: usersAsync.when(
        data: (users) {
          // Filter out the current user from the list
          final otherUsers = users
              .where((u) => u.uid != currentUser?.uid)
              .toList();

          if (otherUsers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'No other users found',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: otherUsers.length,
            itemBuilder: (context, index) {
              final user = otherUsers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: user.isOnline ? Colors.green : Colors.grey,
                    child: Text(user.displayName[0].toUpperCase()),
                  ),
                  title: Text(
                    user.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    user.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: user.isOnline
                          ? Colors.greenAccent
                          : Colors.white54,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.videocam_rounded,
                      color: Colors.amber,
                    ),
                    onPressed: () async {
                      final currentUserData = ref
                          .read(allUsersProvider)
                          .asData
                          ?.value
                          .where((u) => u.uid == currentUser?.uid)
                          .firstOrNull;

                      final newChannelId = await ref
                          .read(callControllerProvider.notifier)
                          .makeCall(
                            senderId: currentUser?.uid ?? '',
                            senderName:
                                currentUserData?.displayName ?? 'Unknown',
                            receiverId: user.uid,
                            receiverName: user.displayName,
                            receiverToken: user.fcmToken ?? '',
                            isAudioCall:
                                false, // Explicitly set to false for video button
                          );

                      if (newChannelId != null && context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              channelId: newChannelId,
                              guestUser: user,
                              isAudioCall:
                                  false, // Explicitly set to false for video call
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
