import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_livekit/meet_livekit.dart';

/// A URL that is refused immediately, so a failed connect resolves fast
/// instead of waiting out a DNS or TCP timeout.
const _deadUrl = 'ws://127.0.0.1:1';

void main() {
  group('MeetLiveKitRoomNotifier — single-flight connect', () {
    test('concurrent connect callers coalesce onto one attempt', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(meetLiveKitRoomProvider.notifier);
      notifier.configure(retryPolicy: MeetRetryPolicy.none);

      var tokenRequests = 0;
      final tokenSource = MeetCallbackTokenSource((refresh) async {
        tokenRequests++;
        return 'jwt';
      });

      // Three callers, as would happen when the initial connect, a room
      // `disconnected` event and a retry button all fire near each other.
      final futures = <Future<void>>[
        notifier.connect(serverUrl: _deadUrl, tokenSource: tokenSource),
        notifier.connect(serverUrl: _deadUrl, tokenSource: tokenSource),
        notifier.connect(serverUrl: _deadUrl, tokenSource: tokenSource),
      ];

      // Every caller must get an answer; none may hang.
      await expectLater(
        Future.wait(futures.map((f) => f.then<void>((_) {}, onError: (_) {}))),
        completes,
      );

      // The old implementation ran one attempt per call site, each with its own
      // retry budget. One token request proves there is now a single attempt.
      expect(
        tokenRequests,
        1,
        reason: 'concurrent connects must share one attempt, not fan out',
      );
    });

    test(
      'a fresh attempt is allowed once the previous one has settled',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(meetLiveKitRoomProvider.notifier);
        notifier.configure(retryPolicy: MeetRetryPolicy.none);

        var tokenRequests = 0;
        final tokenSource = MeetCallbackTokenSource((refresh) async {
          tokenRequests++;
          return 'jwt';
        });

        await notifier
            .connect(serverUrl: _deadUrl, tokenSource: tokenSource)
            .then<void>((_) {}, onError: (_) {});
        await notifier
            .connect(serverUrl: _deadUrl, tokenSource: tokenSource)
            .then<void>((_) {}, onError: (_) {});

        expect(tokenRequests, 2);
      },
    );
  });

  group('MeetLiveKitRoomNotifier — terminal failure latch', () {
    test('a failed connect reports a classified failure and latches', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(meetLiveKitRoomProvider.notifier);
      notifier.configure(retryPolicy: MeetRetryPolicy.none);

      expect(notifier.hasGaveUp, isFalse);

      Object? caught;
      try {
        await notifier.connect(
          serverUrl: _deadUrl,
          tokenSource: const MeetStaticTokenSource('jwt'),
        );
      } catch (error) {
        caught = error;
      }

      // Every caller now receives a typed failure instead of an opaque object,
      // which is what makes the problem diagnosable in the field.
      expect(caught, isA<MeetFailure>());
      expect((caught! as MeetFailure).kind, isNot(MeetFailureKind.cancelled));
      expect(notifier.hasGaveUp, isTrue);
    });

    test('resetGaveUp clears the latch so a host retry can proceed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(meetLiveKitRoomProvider.notifier);
      notifier.configure(retryPolicy: MeetRetryPolicy.none);

      await notifier
          .connect(
            serverUrl: _deadUrl,
            tokenSource: const MeetStaticTokenSource('jwt'),
          )
          .then<void>((_) {}, onError: (_) {});

      expect(notifier.hasGaveUp, isTrue);

      notifier.resetGaveUp();
      expect(notifier.hasGaveUp, isFalse);
    });
  });

  group('MeetLiveKitRoomNotifier — configuration', () {
    test('configure applies a custom retry policy', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(meetLiveKitRoomProvider.notifier);
      expect(notifier.retryPolicy.maxAttempts, 3);

      const custom = MeetRetryPolicy(maxAttempts: 7);
      notifier.configure(retryPolicy: custom);

      expect(notifier.retryPolicy.maxAttempts, 7);
    });

    test('defaults allow three attempts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container
            .read(meetLiveKitRoomProvider.notifier)
            .retryPolicy
            .maxAttempts,
        3,
      );
    });
  });

  group('call-scoped state reset', () {
    testWidgets('a second call does not inherit the previous call UI state', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Simulate a finished call that left the UI toggled.
      container.read(meetIsChatOpenProvider.notifier).state = true;
      container.read(meetIsTileViewEnabledProvider.notifier).state = false;
      container.read(meetIsCameraEnabledProvider.notifier).state = false;
      container.read(meetIsMicEnabledProvider.notifier).state = false;

      expect(container.read(meetIsChatOpenProvider), isTrue);
      expect(container.read(meetIsMicEnabledProvider), isFalse);

      // The reset runs through a real WidgetRef, the same way the screen calls it.
      // It has to be deferred: Riverpod forbids provider writes during build.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                resetCallScopedState(ref);
              });
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(container.read(meetIsChatOpenProvider), isFalse);
      expect(container.read(meetIsTileViewEnabledProvider), isTrue);
      expect(container.read(meetIsScreenShareEnabledProvider), isFalse);
      expect(container.read(meetIsCameraEnabledProvider), isTrue);
      expect(container.read(meetIsMicEnabledProvider), isTrue);
    });
  });
}
