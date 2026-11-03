# Persistence

Run 6A stores one versioned profile record at `player:<UserId>` in
`CritterboundPlayerProfiles_v1`. The record wraps player-owned data with a renewable server session
lock. Profile schema versions and storage-record versions are independent.

`ProfileRepository` uses only `UpdateAsync`. Loads, saves, and releases verify the lock token and
retry transport failures with bounded exponential backoff. Active foreign locks reject concurrent
loads; expired locks may be reclaimed. A successful release writes the latest profile and clears the
lock atomically.

Missing keys create profiles. Corrupt, future-version, or unavailable records fail closed and remain
untouched. No guest profile is created after a failed load. Starter creation runs inside the same
atomic transform as first load, while GUIDs are prepared outside the callback so callback replay
cannot create extra Critters.

`ProfileMigrations` accepts explicit sequential hooks. Migration and validation are pure and must not
yield. Studio testing must use a separate published test universe and store; never enable Studio API
access against production data.

Run 6B profile schema 2 migrates the empty Run 6A inventory placeholder into stack records, unique
item records, and bounded idempotent grant receipts. The DataStore name remains unchanged so existing
profiles migrate in place. Corrupt non-empty schema-1 placeholders fail migration rather than being
discarded.
