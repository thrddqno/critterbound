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

Run 7A profile schema 3 migrates recognized schema-1 starter genomes into named schema-2 allele
triplets. Migration clones records and changes only profile/Critter/genome schema fields. Unknown
legacy appearance or ability combinations fail before `UpdateAsync` writes, preventing invented or
random genes on load.

Run 7E.2 schema 5 adds bounded acquisition operation receipts. Run 7E.3 schema 6 adds contract
instances, reward entitlements, and a separate durable redemption ledger. Claimed display history may
be pruned, but redemptions are retained for lifetime-safe claim retries; acceptance fails closed when
the 2048-record redemption capacity is reached. Contract completion and reward claim each commit via
one validated `ProfileService.UpdateProfile` write, so failed saves do not expose partial progress or
ownership.
