import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet_livekit/meet_livekit.dart';

void main() {
  group('MeetStaticTokenSource', () {
    test('cannot refresh, so auth failures are treated as terminal', () {
      const source = MeetStaticTokenSource('jwt');

      expect(source.canRefresh, isFalse);
    });

    test('returns the same token regardless of the refresh flag', () async {
      const source = MeetStaticTokenSource('jwt');

      expect(await source.obtain(refresh: false), 'jwt');
      expect(await source.obtain(refresh: true), 'jwt');
    });
  });

  group('MeetCallbackTokenSource', () {
    test('can refresh by default', () {
      const source = MeetCallbackTokenSource(_unused);

      expect(source.canRefresh, isTrue);
    });

    test('serves a cached token when no refresh is requested', () async {
      final calls = <bool>[];
      final source = MeetCallbackTokenSource((refresh) async {
        calls.add(refresh);
        return refresh ? 'fresh' : 'cached';
      });

      expect(await source.obtain(refresh: false), 'cached');
      expect(calls, [false]);
    });

    test('fetches a new token only when a refresh is requested', () async {
      final source = MeetCallbackTokenSource(
        (refresh) async => refresh ? 'fresh' : 'cached',
      );

      expect(await source.obtain(refresh: true), 'fresh');
    });

    test('a refresh is requested at most once per connect session', () async {
      // Mirrors the notifier's contract: the first obtain is unrefreshed, and
      // a single retry after an auth rejection asks for a fresh token.
      final refreshFlags = <bool>[];
      final source = MeetCallbackTokenSource((refresh) async {
        refreshFlags.add(refresh);
        return refresh ? 'token-2' : 'token-1';
      });

      expect(await source.obtain(refresh: false), 'token-1');
      expect(await source.obtain(refresh: true), 'token-2');

      expect(refreshFlags, [false, true]);
    });
  });

  group('MeetLiveKitTokenSource', () {
    test('adapts a livekit TokenSourceFixed to a MeetTokenSource', () async {
      final source = MeetLiveKitTokenSource(_FixedTokenSource('from-livekit'));

      expect(source.canRefresh, isTrue);
      expect(await source.obtain(refresh: false), 'from-livekit');
    });
  });
}

Future<String> _unused(bool refresh) async => 'unused';

class _FixedTokenSource implements TokenSourceFixed {
  final String token;

  _FixedTokenSource(this.token);

  @override
  Future<TokenSourceResponse> fetch() async {
    return TokenSourceResponse(
      serverUrl: 'wss://example.livekit.cloud',
      participantToken: token,
    );
  }
}
