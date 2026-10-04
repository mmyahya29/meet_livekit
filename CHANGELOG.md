## 0.0.3

Connection resilience. The dominant failure was not "LiveKit cannot work" but
several independent connect paths racing each other and each retrying on its
own schedule, so a single network blip fanned out into a dozen concurrent
attempts that starved one another.

* Replaced four independent per-call-site `retries: 3` counters with one bounded
  `MeetRetryPolicy` (default 3 attempts, exponential backoff with jitter) owned
  by `MeetLiveKitRoomNotifier`.
* Made `connect` single-flight: concurrent callers — the initial connect, a room
  `disconnected` event and a retry button firing together — now share one
  in-flight attempt instead of each starting their own.
* Added a terminal-failure latch. A `disconnected` event can no longer restart a
  cycle that already gave up; only a user-initiated retry clears it.
* Added `MeetFailure`, which classifies failures into auth / ice / media /
  network / server / timeout / cancelled and marks each as retryable or not.
  Retrying an ICE failure with the same network was the biggest waste.
* Added `MeetTokenSource` (`MeetStaticTokenSource`, `MeetCallbackTokenSource`,
  `MeetLiveKitTokenSource`). Auth failures retry only when the token can
  actually be refreshed, instead of re-joining with the same expired token.
* Raised the connect and peer-connection timeouts from the 10-second SDK
  default to 30s, and added an explicit H.264 backup codec — the SDK otherwise
  defaults the backup to the primary codec, which is not a fallback at all.
* Split media startup out of the connect path into `enableInitialMedia`. A
  denied camera permission used to throw out of `connect()` and take the whole
  call down. Camera and microphone are now attempted independently, so
  `startWithMicrophone: false` no longer produces a silently video-less call.
* Fixed a Riverpod 3 crash: `ref.onDispose` and `dispose()` read provider
  state, which throws `Cannot use Ref or modify other providers inside
  life-cycles`. The current `Room` is now carried in a plain field.
* Fixed call-scoped state bleeding between calls. The UI singletons are not
  `autoDispose`, so a second call inherited the first call's chat-open /
  grid-view / camera state, which could show a muted microphone that was still
  publishing. Reset now runs on every call start, not only on retry.
* Added app lifecycle handling: resuming from background reconnects, backgrounding
  disconnects, and a terminal failure is not auto-retried on resume.
* Added `test/meet_room_notifier_test.dart`, which pins the single-flight and
  latch behaviour that previously had no coverage.

## 0.0.2

* Added `meetEndCallRequestedProvider` so a host app can end a call intentionally
  (e.g. when its own countdown expires) without the room silently re-connecting.
* Fixed a call restarting itself when the host disconnected the `Room` directly:
  the auto-reconnect path treated the disconnect as a network drop, re-joined
  with the same token, and left the host with no `MeetingSummary` and no
  `onLeaveCall` callback.
* Fixed a leaked room listener/engine on every reconnect attempt.
* The end-request latch is cleared on consumption and on dispose, so a stale
  request can never terminate a later call.

## 0.0.1

* TODO: Describe initial release.
