import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

      // Remove this user from other users' followers, following, blocked, and pending lists
      final usersWithFollower = await _firestore
          .collection('users')
          .where('followers', arrayContains: uid)
          .get();
      for (var doc in usersWithFollower.docs) {
        batch.update(doc.reference, {
          'followers': FieldValue.arrayRemove([uid]),
        });
      }

      final usersWithFollowing = await _firestore
          .collection('users')
          .where('following', arrayContains: uid)
          .get();
      for (var doc in usersWithFollowing.docs) {
        batch.update(doc.reference, {
          'following': FieldValue.arrayRemove([uid]),
        });
      }

      final usersWithBlocked = await _firestore
          .collection('users')
          .where('blockedUsers', arrayContains: uid)
          .get();
      for (var doc in usersWithBlocked.docs) {
        batch.update(doc.reference, {
          'blockedUsers': FieldValue.arrayRemove([uid]),
        });
      }

      final usersWithPending = await _firestore
          .collection('users')
          .where('pendingFollowRequests', arrayContains: uid)
          .get();
      for (var doc in usersWithPending.docs) {
        batch.update(doc.reference, {
          'pendingFollowRequests': FieldValue.arrayRemove([uid]),
        });
      }

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

      // 4. Delete posts and their media
      final userPosts = await _firestore
          .collection('posts')
          .where('uid', isEqualTo: uid)
          .get();
      for (var doc in userPosts.docs) {
        final data = doc.data();
        final urls = [
          data['mediaUrl'] as String?,
          data['videoUrl'] as String?,
          data['thumbnailUrl'] as String?,
          data['thumbnail'] as String?,
        ].where((u) => u != null && u.isNotEmpty).toList();

        for (final url in urls) {
          try {
            await FirebaseStorage.instance.refFromURL(url!).delete();
          } catch (_) {} // Ignore if file already deleted or invalid url
        }
        batch.delete(doc.reference);
      }

      // 5. Delete reels and their media
      final userReels = await _firestore
          .collection('reels')
          .where('uid', isEqualTo: uid)
          .get();
      for (var doc in userReels.docs) {
        final data = doc.data();
        final urls = [
          data['videoUrl'] as String?,
          data['thumbnail'] as String?,
        ].where((u) => u != null && u.isNotEmpty).toList();

        for (final url in urls) {
          try {
            await FirebaseStorage.instance.refFromURL(url!).delete();
          } catch (_) {}
        }
        batch.delete(doc.reference);
      }

      // 6. Delete stories and their media
      final userStories = await _firestore
          .collection('stories')
          .where('uid', isEqualTo: uid)
          .get();
      for (var doc in userStories.docs) {
        final data = doc.data();
        final imageUrl = data['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(imageUrl).delete();
          } catch (_) {}
        }
        batch.delete(doc.reference);
      }

      // 7. Delete chats and their messages
      final userChats = await _firestore
          .collection('chats')
          .where('users', arrayContains: uid)
          .get();
      for (var doc in userChats.docs) {
        final messages = await doc.reference.collection('messages').get();
        for (var msg in messages.docs) {
          batch.delete(msg.reference);
        }
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
