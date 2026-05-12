// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(notificationRepository)
final notificationRepositoryProvider = NotificationRepositoryProvider._();

final class NotificationRepositoryProvider
    extends
        $FunctionalProvider<
          NotificationRepository,
          NotificationRepository,
          NotificationRepository
        >
    with $Provider<NotificationRepository> {
  NotificationRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationRepositoryHash();

  @$internal
  @override
  $ProviderElement<NotificationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationRepository create(Ref ref) {
    return notificationRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationRepository>(value),
    );
  }
}

String _$notificationRepositoryHash() =>
    r'3b7c067706bfc3e28b78b4ab15ccf93df09002d9';

@ProviderFor(notifications)
final notificationsProvider = NotificationsFamily._();

final class NotificationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<NotificationModel>>,
          List<NotificationModel>,
          Stream<List<NotificationModel>>
        >
    with
        $FutureModifier<List<NotificationModel>>,
        $StreamProvider<List<NotificationModel>> {
  NotificationsProvider._({
    required NotificationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'notificationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$notificationsHash();

  @override
  String toString() {
    return r'notificationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<NotificationModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<NotificationModel>> create(Ref ref) {
    final argument = this.argument as String;
    return notifications(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$notificationsHash() => r'7fe1d1a7430dc58a01150da221173ef126f6a083';

final class NotificationsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<NotificationModel>>, String> {
  NotificationsFamily._()
    : super(
        retry: null,
        name: r'notificationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NotificationsProvider call(String uid) =>
      NotificationsProvider._(argument: uid, from: this);

  @override
  String toString() => r'notificationsProvider';
}

@ProviderFor(unreadNotificationsCount)
final unreadNotificationsCountProvider = UnreadNotificationsCountFamily._();

final class UnreadNotificationsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  UnreadNotificationsCountProvider._({
    required UnreadNotificationsCountFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'unreadNotificationsCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$unreadNotificationsCountHash();

  @override
  String toString() {
    return r'unreadNotificationsCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    final argument = this.argument as String;
    return unreadNotificationsCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UnreadNotificationsCountProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$unreadNotificationsCountHash() =>
    r'ed25bb1de5c5c19d0cf62c0b8a6a251309f6b393';

final class UnreadNotificationsCountFamily extends $Family
    with $FunctionalFamilyOverride<Stream<int>, String> {
  UnreadNotificationsCountFamily._()
    : super(
        retry: null,
        name: r'unreadNotificationsCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UnreadNotificationsCountProvider call(String uid) =>
      UnreadNotificationsCountProvider._(argument: uid, from: this);

  @override
  String toString() => r'unreadNotificationsCountProvider';
}
