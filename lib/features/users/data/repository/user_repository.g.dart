// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(userRepository)
final userRepositoryProvider = UserRepositoryProvider._();

final class UserRepositoryProvider
    extends $FunctionalProvider<UserRepository, UserRepository, UserRepository>
    with $Provider<UserRepository> {
  UserRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userRepositoryHash();

  @$internal
  @override
  $ProviderElement<UserRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UserRepository create(Ref ref) {
    return userRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserRepository>(value),
    );
  }
}

String _$userRepositoryHash() => r'47d5184b12d4fe2a7cb896a833c7a4e42f3163ec';

@ProviderFor(allUsers)
final allUsersProvider = AllUsersProvider._();

final class AllUsersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<UserModel>>,
          List<UserModel>,
          Stream<List<UserModel>>
        >
    with $FutureModifier<List<UserModel>>, $StreamProvider<List<UserModel>> {
  AllUsersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allUsersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allUsersHash();

  @$internal
  @override
  $StreamProviderElement<List<UserModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<UserModel>> create(Ref ref) {
    return allUsers(ref);
  }
}

String _$allUsersHash() => r'ad13bdb8d27f1d3e05112f8b90ff69afb5e99d07';

@ProviderFor(userDetails)
final userDetailsProvider = UserDetailsFamily._();

final class UserDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<UserModel?>,
          UserModel?,
          Stream<UserModel?>
        >
    with $FutureModifier<UserModel?>, $StreamProvider<UserModel?> {
  UserDetailsProvider._({
    required UserDetailsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'userDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$userDetailsHash();

  @override
  String toString() {
    return r'userDetailsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<UserModel?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<UserModel?> create(Ref ref) {
    final argument = this.argument as String;
    return userDetails(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UserDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$userDetailsHash() => r'97f2a8c703a4f20a0f121e9d5af672fc16c50d5c';

final class UserDetailsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<UserModel?>, String> {
  UserDetailsFamily._()
    : super(
        retry: null,
        name: r'userDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UserDetailsProvider call(String uid) =>
      UserDetailsProvider._(argument: uid, from: this);

  @override
  String toString() => r'userDetailsProvider';
}
