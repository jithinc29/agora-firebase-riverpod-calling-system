import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'call_state_controller.g.dart';

@Riverpod(keepAlive: true)
class CallStateController extends _$CallStateController {
  @override
  String? build() {
    return null;
  }

  void setActiveCall(String? channelId) {
    state = channelId;
  }

  void clearActiveCall() {
    state = null;
  }
}
