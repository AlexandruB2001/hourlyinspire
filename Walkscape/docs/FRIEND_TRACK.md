# The shared friend track

The track shows today's cumulative walking distance for you and your friends
on one horizontal line. Positions are distances, never locations.

Code: `Packages/WalkscapeKit/Sources/WalkscapeDomain/FriendTrack/`.
Tests: `Tests/WalkscapeDomainTests/FriendTrackLayoutTests.swift`.

## Pipeline

```
[TrackParticipant] + TrackFocus + TrackLayoutConfiguration (+ previous range)
        │
        ▼  FriendTrackLayoutEngine.layout  (pure, deterministic)
        │
TrackViewport: visible range, scale, CharacterPosition (x, lane), left/right OverflowIndicator
```

`TrackFocusController` holds the only state: what the viewport centres on.
It lives in `AppModel` so the Journey screen can deep-link to a friend.

## Choosing the visible range

| Focus | Rule |
|---|---|
| `.currentUser` (default) | Find the largest run of participants that includes you and spans ≤ `maximumSpanMeters` (2 km). Ties go to the tighter run, then the one centred nearest you. Fit the range to it, at least `minimumSpanMeters` (500 m), with the span rounded up to 250 m and the centre to 50 m. |
| `.participant(id)` | Centre on that friend and widen symmetrically to include neighbours within ±1 km. |
| `.free(center, span)` | The range the user dragged to. Data refreshes don't move it. |

**Stability:** when the previous range still contains everyone it needs to
show, and its span is within 500 m of the new one, it is kept. Small distance
updates therefore move characters, not the camera.

Ranges never start below 0 m.

## Placing characters

x = `plotMinX + (distance − lower) × scale`. When an edge has indicators,
`indicatorWidth` is reserved on that side so badges never cover a character.

Walkers closer than `labelWidth` points are stacked into lanes (front row
first). You, then the focused friend, claim the front row. If every lane is
full, the walker shifts sideways by the smallest amount that avoids overlap
(`isNudged`), and `exactX` keeps the true position.

## Edge indicators

Everyone outside the range becomes an indicator on the left (behind) or right
(ahead):

- **You** always get your own badge ("You · 2.4 km"), never hidden in a group.
- **One friend**: "Taylor · +4.8 km" or "Alex · 2.1 km behind". The gap is
  their distance minus yours.
- **Two or more friends**: "3 friends ahead", "2 friends behind", or "2 more
  friends" when some are ahead of you and some behind. Tapping focuses the
  nearest member.

Every indicator has a full VoiceOver label, for example "Taylor, 4.8 km ahead
of you, off screen to the right. Double tap to focus."

## Data states

- **Stale** (today's data, not updated for 3 h): placed, drawn faded, with a clock icon.
- **Unavailable** (no data today, or sharing off): not placed and not in
  indicators. Listed in `unavailableParticipants` and shown as "No update today"
  on the leaderboard.
- **Estimated** distances are placed with "≈" but are unranked.
