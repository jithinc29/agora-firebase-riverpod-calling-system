import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/auth/models/user_model.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : _auth = auth,
       _firestore = firestore;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signUp(
    String email,
    String password,
    String name,
    String? fcmToken,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (credential.user != null) {
      // 1. Update the Auth Profile itself so currentUser.displayName is not null
      await credential.user!.updateDisplayName(name);
      await credential.user!.reload();

      final userModel = UserModel(
        uid: credential.user!.uid,
        email: email,
        displayName: name,
        isOnline: true,
        fcmToken: fcmToken,
        lastSeen: DateTime.now(),
      );

      await _firestore
          .collection('users')
          .doc(userModel.uid)
          .set(userModel.toMap());
    }
  }

  Future<void> signIn(String email, String password, String? fcmToken) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    await _updateUserToken(fcmToken);
    await _setUserOnline(true);
  }

  Future<void> _updateUserToken(String? token) async {
    final user = _auth.currentUser;
    if (user != null && token != null) {
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    }
  }

  Future<void> signOut() async {
    print('Starting signOut process...');
    try {
      await _setUserOnline(false);
      print('User status set to offline.');
    } catch (e) {
      print('Error setting user offline: $e');
    }
    await _auth.signOut();
    print('Firebase signOut completed.');
  }

  Future<void> _setUserOnline(bool online) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).set({
        'isOnline': online,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    }
  }

  Stream<UserModel?> getUserData(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromMap(doc.data()!) : null);
  }
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user != null) {
      final uid = user.uid;
      
      final batch = _firestore.batch();

      // 1. Delete user document
      batch.delete(_firestore.collection('users').doc(uid));

      // 2. Delete calls associated with this user (Sender)
      final senderCalls = await _firestore
          .collection('calls')
          .where('senderId', isEqualTo: uid)
          .get();
      for (var doc in senderCalls.docs) {
        batch.delete(doc.reference);
      }

      // 3. Delete calls associated with this user (Receiver)
      final receiverCalls = await _firestore
          .collection('calls')
          .where('receiverId', isEqualTo: uid)
          .get();
      for (var doc in receiverCalls.docs) {
        batch.delete(doc.reference);
      }

      // Commit all Firestore deletions
      await batch.commit();

      // 4. Delete from Firebase Auth
      await user.delete();
    }
  }
}

@riverpod
AuthRepository authRepository(Ref ref) {
  return AuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
  );
}

@riverpod
Stream<UserModel?> currentUserData(Ref ref) {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.asData?.value;
  if (user == null) return Stream.value(null);
  
  return ref.watch(authRepositoryProvider).getUserData(user.uid);
}
