// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_state_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CallStateController)
final callStateControllerProvider = CallStateControllerProvider._();

final class CallStateControllerProvider
    extends $NotifierProvider<CallStateController, String?> {
  CallStateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'callStateControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$callStateControllerHash();

  @$internal
  @override
  CallStateController create() => CallStateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$callStateControllerHash() =>
    r'26d1f05bf5321946984489e0549e135b0ec4ac24';

abstract class _$CallStateController extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
