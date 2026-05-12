import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/notifications/data/repositories/notification_repository.dart';

part 'auth_controller.g.dart';

@riverpod
class AuthController extends _$AuthController {
  @override
  FutureOr<void> build() {
    // Initial state
  }

  Future<void> signUp(String email, String password, String name) async {
    state = const AsyncValue.loading();
    String? fcmToken;
    try {
      fcmToken = await ref
          .read(notificationRepositoryProvider)
          .getToken()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      print('FCM Token retrieval failed: $e');
    }
    
    // Check if still active after async gap
    bool isStillMounted = true;
    try {
      if (!ref.mounted) isStillMounted = false;
    } catch (_) {
      isStillMounted = false;
    }
    if (!isStillMounted) return;
    
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUp(email, password, name, fcmToken),
    );
  }

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    String? fcmToken;
    try {
      fcmToken = await ref
          .read(notificationRepositoryProvider)
          .getToken()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      print('FCM Token retrieval failed during sign in: $e');
    }
    
    bool isStillMounted = true;
    try {
      if (!ref.mounted) isStillMounted = false;
    } catch (_) {
      isStillMounted = false;
    }
    if (!isStillMounted) return;

    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signIn(email, password, fcmToken),
    );
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.signOut();
      try {
        if (ref.mounted) {
          state = const AsyncValue.data(null);
        }
      } catch (_) {}
    } catch (e, st) {
      try {
        if (ref.mounted) {
          state = AsyncValue.error(e, st);
        }
      } catch (_) {}
    }
  }

  Future<void> deleteAccount() async {
    state = const AsyncValue.loading();
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.deleteAccount();
      try {
        if (ref.mounted) {
          state = const AsyncValue.data(null);
        }
      } catch (_) {}
    } catch (e, st) {
      try {
        if (ref.mounted) {
          state = AsyncValue.error(e, st);
        }
      } catch (_) {}
    }
  }
}
