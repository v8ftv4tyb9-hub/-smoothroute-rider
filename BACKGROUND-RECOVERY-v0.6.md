# SmoothRoute Background Recovery v0.6

This branch documents the immediate browser-side mitigation for the iOS background suspension found in the August 15 road test.

## Root cause

The existing road-test collector persists ride chunks and marks `page_hidden`, `page_visible`, and `sample_gap`, but GPS and DeviceMotion are still browser callbacks. iOS may suspend those callbacks while Safari/PWA is hidden or the phone is locked. Browser JavaScript cannot force iOS to continue delivering those sensors during suspension.

## v0.6 browser mitigation

The revised collector should:

- lower chunk size from 80 samples to 20 samples;
- lower flush interval from 5 seconds to 1 second;
- treat a 10-second no-sample interval as a gap instead of waiting 30 seconds;
- checkpoint state immediately on GPS updates when the last persistence write is older than 750 ms;
- explicitly stop and restart geolocation and DeviceMotion listeners on foreground recovery;
- handle `visibilitychange`, `pagehide`, `pageshow`, `freeze`, and `resume` lifecycle events;
- record `watchers_restarted` markers in exported JSON;
- record a `background_strategy: checkpoint-and-auto-resume` ride metadata field;
- preserve IndexedDB chunked persistence and automatic ride recovery.

## Native requirement

This mitigation protects the ride and automatically resumes browser collection, but it cannot make Safari continue sensor delivery while iOS has suspended the page. Reliable locked-screen and other-app recording requires a native iOS recorder using Core Location and Core Motion, feeding the existing SmoothRoute JSON model.

## Validation target

Next field test:

1. Start a ride while parked.
2. Ride for 2-3 minutes with SmoothRoute visible.
3. Switch to another app for 60 seconds.
4. Return to SmoothRoute without manually stopping the ride.
5. Repeat with the phone locked for 60 seconds.
6. End the ride while parked and inspect the JSON for lifecycle markers, gap duration, watcher restart, sample counts, and recovery counts.
