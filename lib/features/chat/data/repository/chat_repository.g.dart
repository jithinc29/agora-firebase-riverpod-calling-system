// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatRepository)
final chatRepositoryProvider = ChatRepositoryProvider._();

final class ChatRepositoryProvider
    extends $FunctionalProvider<ChatRepository, ChatRepository, ChatRepository>
    with $Provider<ChatRepository> {
  ChatRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatRepositoryHash();

  @$internal
  @override
  $ProviderElement<ChatRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatRepository create(Ref ref) {
    return chatRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatRepository>(value),
    );
  }
}

String _$chatRepositoryHash() => r'963ee12163141005fad22ccb55ebd5f7cfdc2be1';

@ProviderFor(chatMessages)
final chatMessagesProvider = ChatMessagesFamily._();

final class ChatMessagesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MessageModel>>,
          List<MessageModel>,
          Stream<List<MessageModel>>
        >
    with
        $FutureModifier<List<MessageModel>>,
        $StreamProvider<List<MessageModel>> {
  ChatMessagesProvider._({
    required ChatMessagesFamily super.from,
    required ({String currentUserId, String receiverId}) super.argument,
  }) : super(
         retry: null,
         name: r'chatMessagesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatMessagesHash();

  @override
  String toString() {
    return r'chatMessagesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<MessageModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<MessageModel>> create(Ref ref) {
    final argument =
        this.argument as ({String currentUserId, String receiverId});
    return chatMessages(
      ref,
      currentUserId: argument.currentUserId,
      receiverId: argument.receiverId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessagesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatMessagesHash() => r'4e98feca7a7cfa4572eac3deba70ac9b537e0b93';

final class ChatMessagesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<MessageModel>>,
          ({String currentUserId, String receiverId})
        > {
  ChatMessagesFamily._()
    : super(
        retry: null,
        name: r'chatMessagesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ChatMessagesProvider call({
    required String currentUserId,
    required String receiverId,
  }) => ChatMessagesProvider._(
    argument: (currentUserId: currentUserId, receiverId: receiverId),
    from: this,
  );

  @override
  String toString() => r'chatMessagesProvider';
}

@ProviderFor(unreadChatMessagesCount)
final unreadChatMessagesCountProvider = UnreadChatMessagesCountFamily._();

final class UnreadChatMessagesCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  UnreadChatMessagesCountProvider._({
    required UnreadChatMessagesCountFamily super.from,
    required ({String currentUserId, String otherUserId}) super.argument,
  }) : super(
         retry: null,
         name: r'unreadChatMessagesCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$unreadChatMessagesCountHash();

  @override
  String toString() {
    return r'unreadChatMessagesCountProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    final argument =
        this.argument as ({String currentUserId, String otherUserId});
    return unreadChatMessagesCount(
      ref,
      currentUserId: argument.currentUserId,
      otherUserId: argument.otherUserId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UnreadChatMessagesCountProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$unreadChatMessagesCountHash() =>
    r'7a585115a8dd57a66668e8c944cde7573d59ec76';

final class UnreadChatMessagesCountFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<int>,
          ({String currentUserId, String otherUserId})
        > {
  UnreadChatMessagesCountFamily._()
    : super(
        retry: null,
        name: r'unreadChatMessagesCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UnreadChatMessagesCountProvider call({
    required String currentUserId,
    required String otherUserId,
  }) => UnreadChatMessagesCountProvider._(
    argument: (currentUserId: currentUserId, otherUserId: otherUserId),
    from: this,
  );

  @override
  String toString() => r'unreadChatMessagesCountProvider';
}
