# Development

## Setup

1. Install Git and Rokit.
2. Run `rokit install` from repository root.
3. Run `rojo build default.project.json --output Critterbound.rbxlx`.
4. On Windows or macOS, open Roblox Studio and connect its Rojo plugin to `rojo serve`.

Roblox Studio is not officially supported on Linux. Linux development can edit, format, lint,
serve, and build source, but runtime verification requires Studio on a supported operating system.

## Source conventions

- Use `--!strict` in Luau source.
- Keep server authority and trust-boundary validation explicit.
- Keep shared code deterministic where practical and free from GUI or persistence dependencies.
- Add feature code only when required; avoid global registries and speculative abstractions.
- Never place credentials, private profile data, or server-only logic in replicated modules.

## Checks

```sh
stylua src tests
stylua --check src tests
selene src tests
lune run tests/run
rojo sourcemap default.project.json --output sourcemap.json
rojo build default.project.json --output Critterbound.rbxlx
```

Studio checklist:

1. Connect Rojo and verify `ReplicatedStorage/Shared`, `ServerScriptService/Server`, and
   `StarterPlayer/StarterPlayerScripts/Client`.
2. Start a local play session.
3. Confirm output includes `[Critterbound] Server initialized` and
   `[Critterbound] Client initialized` once each.
4. Confirm profile load completes and Training Grounds uses the same three owned Critter IDs after
   leaving and rejoining.
5. Confirm no runtime errors appear during autosave, disconnect, or server shutdown.
6. Through `PlayerDataRequest`, confirm inventory/team DTOs omit profile locks and grant receipts.
7. Confirm equipment and reordered teams survive a leave/rejoin cycle without changing owned IDs.
8. Run 6C Studio checks require a published test place and Studio API Services. The explicit
   server-only Studio fixture grants one charm and material stack idempotently; it cannot run outside
   Studio.

DataStore checks require a published test universe with Studio API Services enabled. Use a separate
test universe/store. Never connect Studio testing to production player data. Disabled API access must
fail profile load without creating a guest profile.

Run 3 mounts a placeholder `BattleScreen` only in Studio. Follow
`tests/Integration/README.md` for visual and interaction checks. Lune covers pure asset,
presentation, and planning behavior but does not emulate Roblox GUI instances.
