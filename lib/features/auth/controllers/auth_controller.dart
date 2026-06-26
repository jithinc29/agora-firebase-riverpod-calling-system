import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/notifications/data/repositories/notification_repository.dart';

part 'auth_controller.g.dart';

@riverpod
class AuthController extends _$AuthController {
  bool _mounted = true;

  @override
  FutureOr<void> build() {
    _mounted = true;
    ref.onDispose(() {
      _mounted = false;
    });
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
    final result = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .signUp(email, password, name, fcmToken),
    );
    if (_mounted) {
      state = result;
    }
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
    final result = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signIn(email, password, fcmToken),
    );
    if (_mounted) {
      state = result;
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.signOut();
      if (_mounted) {
        state = const AsyncValue.data(null);
      }
    } catch (e, st) {
      if (_mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> deleteAccount() async {
    state = const AsyncValue.loading();
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.deleteAccount();
      if (_mounted) {
        state = const AsyncValue.data(null);
      }
    } catch (e, st) {
      if (_mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}
