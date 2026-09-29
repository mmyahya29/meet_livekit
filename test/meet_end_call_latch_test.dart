import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_livekit/meet_livekit.dart';

void main() {
  group('meetEndCallRequestedProvider', () {
    test('starts unset and reflects request/clear', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(meetEndCallRequestedProvider), isFalse);

      container.read(meetEndCallRequestedProvider.notifier).request();
      expect(container.read(meetEndCallRequestedProvider), isTrue);

      container.read(meetEndCallRequestedProvider.notifier).clear();
      expect(container.read(meetEndCallRequestedProvider), isFalse);
    });

    test('is idempotent under repeated requests', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(meetEndCallRequestedProvider.notifier)
        ..request()
        ..request();
      expect(container.read(meetEndCallRequestedProvider), isTrue);
    });

    test('does not leak a pending request into a later call', () {
      // The latch lives on a global provider. If a call ever ended without
      // clearing it, the *next* MeetRoomScreen to mount would terminate itself
      // the instant it connected. MeetRoomScreen clears it on consumption and in
      // dispose(); this guards the provider-level default.
      final firstCall = ProviderContainer();
      firstCall.read(meetEndCallRequestedProvider.notifier).request();
      expect(firstCall.read(meetEndCallRequestedProvider), isTrue);
      firstCall.dispose();

      final secondCall = ProviderContainer();
      addTearDown(secondCall.dispose);
      expect(secondCall.read(meetEndCallRequestedProvider), isFalse);
    });
  });
}
