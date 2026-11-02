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
4. Confirm no remotes, gameplay loops, DataStore calls, or runtime errors appear.

Run 3 mounts a placeholder `BattleScreen` only in Studio. Follow
`tests/Integration/README.md` for visual and interaction checks. Lune covers pure asset,
presentation, and planning behavior but does not emulate Roblox GUI instances.
