# Critterbound Agent Notes

## Toolchain and verification

- Install pinned tools with `rokit install`; versions live in `rokit.toml`. There is no package manager, Wally manifest, CI workflow, or task runner.
- Full verification:
  ```sh
  stylua --check src tests
  selene src tests
  lune run tests/run
  rojo sourcemap default.project.json --output /tmp/opencode/critterbounds-sourcemap.json
  rojo build default.project.json --output /tmp/opencode/Critterbound.rbxlx
  ```
- Keep Rojo outputs outside the repo. `Critterbound.rbxlx` and `sourcemap.json` are generated artifacts, not source.
- `tests/run.luau` has no filter and includes `Integration/FullGameplayJourney.spec.luau`; `EggDebug.spec` is intentionally disabled there.
- For focused tests, create a temporary runner **under `tests/`** that requires `./TestHarness`, requires selected `./Unit/*.spec` modules, then calls `Harness.run()`. Remove it afterward. A runner in `/tmp` cannot use these relative Lune requires, and Lune rejects absolute require paths.
- Lune covers pure Luau only. Roblox `Instance` UI/runtime checks require Studio; use `tests/Integration/README.md` for the manual visual checklist. Repo-local `opencode.json` configures Studio MCP through Vinegar/Wine.

## Runtime wiring

- Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to `ServerScriptService.Server`, and `src/client` to `StarterPlayerScripts.Client`.
- Real composition roots are `src/server/Bootstrap/init.server.luau` and `src/client/Bootstrap/init.client.luau`; inspect these before changing service dependencies or remotes.
- Shared modules must remain pure and usable by both Roblox and Lune. Existing `requireShared`/`requireSibling` helpers intentionally switch between Roblox instance paths and relative string requires.
- Dependency direction is `client/server -> shared`; shared cannot use GUI, DataStore, or server-only APIs, and client/server must not require each other.
- Server is authoritative. `OnServerInvoke` supplies `Player.UserId`; never trust identity, outcomes, rewards, genes, ownership, or persistent records from request payloads. Return tagged results: `{ ok = true, value = ... }` or `{ ok = false, errors = ... }`.
- Characterless presentation is intentional: server sets `Players.CharacterAutoLoads = false`; client uses a scriptable camera.

## Persistence changes

- `ProfileSchema.luau`, `ProfileMigrations.luau`, and `ProfileRepository.luau` are the executable truth; version numbers in prose docs may lag.
- Every profile schema bump needs: new-profile defaults, full validation, one sequential migration hook, and migration/repository tests. Future or corrupt profiles fail closed—never replace them with writable defaults.
- Persistent service mutations go through `ProfileService.UpdateProfile`: mutate the cloned candidate, validate/save under the session lock, then replace cache. Failed writes must leave cached state unchanged and remain retryable.
- Preserve durable idempotency receipts when pruning display history. Command/battle IDs must be checked again inside the profile mutation, not only before it.
- DataStore is `CritterboundPlayerProfiles_v1`. Never enable Studio API access against production data; use a separate published test universe/store.

## Source conventions

- Luau is strict (`.luaurc`); StyLua uses tabs, 100 columns, and Luau syntax.
- Battle/genetics determinism depends on explicit Park–Miller RNG state and stable sorting. Do not introduce `math.random`, wall-clock input, hash-order traversal, or retry-dependent RNG consumption into deterministic paths.
