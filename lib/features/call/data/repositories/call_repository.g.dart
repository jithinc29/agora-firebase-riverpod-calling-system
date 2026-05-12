// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(callRepository)
final callRepositoryProvider = CallRepositoryProvider._();

final class CallRepositoryProvider
    extends $FunctionalProvider<CallRepository, CallRepository, CallRepository>
    with $Provider<CallRepository> {
  CallRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'callRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$callRepositoryHash();

  @$internal
  @override
  $ProviderElement<CallRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CallRepository create(Ref ref) {
    return callRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CallRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CallRepository>(value),
    );
  }
}

String _$callRepositoryHash() => r'2dbd4d7663a22576080c95a6d2b30a2950366909';

@ProviderFor(incomingCallStream)
final incomingCallStreamProvider = IncomingCallStreamFamily._();

final class IncomingCallStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<QuerySnapshot<Object?>>,
          QuerySnapshot<Object?>,
          Stream<QuerySnapshot<Object?>>
        >
    with
        $FutureModifier<QuerySnapshot<Object?>>,
        $StreamProvider<QuerySnapshot<Object?>> {
  IncomingCallStreamProvider._({
    required IncomingCallStreamFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'incomingCallStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$incomingCallStreamHash();

  @override
  String toString() {
    return r'incomingCallStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<QuerySnapshot<Object?>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<QuerySnapshot<Object?>> create(Ref ref) {
    final argument = this.argument as String;
    return incomingCallStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IncomingCallStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$incomingCallStreamHash() =>
    r'fce7688f3bc57627a376ddd56061de43cf0f5d50';

final class IncomingCallStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<QuerySnapshot<Object?>>, String> {
  IncomingCallStreamFamily._()
    : super(
        retry: null,
        name: r'incomingCallStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IncomingCallStreamProvider call(String receiverId) =>
      IncomingCallStreamProvider._(argument: receiverId, from: this);

  @override
  String toString() => r'incomingCallStreamProvider';
}

@ProviderFor(callStream)
final callStreamProvider = CallStreamFamily._();

final class CallStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<DocumentSnapshot<Object?>>,
          DocumentSnapshot<Object?>,
          Stream<DocumentSnapshot<Object?>>
        >
    with
        $FutureModifier<DocumentSnapshot<Object?>>,
        $StreamProvider<DocumentSnapshot<Object?>> {
  CallStreamProvider._({
    required CallStreamFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'callStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$callStreamHash();

  @override
  String toString() {
    return r'callStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<DocumentSnapshot<Object?>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<DocumentSnapshot<Object?>> create(Ref ref) {
    final argument = this.argument as String;
    return callStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CallStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$callStreamHash() => r'54db408632ca184522ee08dd24eaa88e28ca2991';

final class CallStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<DocumentSnapshot<Object?>>, String> {
  CallStreamFamily._()
    : super(
        retry: null,
        name: r'callStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CallStreamProvider call(String channelId) =>
      CallStreamProvider._(argument: channelId, from: this);

  @override
  String toString() => r'callStreamProvider';
}
