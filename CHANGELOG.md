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
