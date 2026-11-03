# Critterbound

Critterbound is a server-authoritative, 2.5D medieval-fantasy creature card battler for
Roblox. Teams contain three Critters and eventually resolve secretly planned ability cards in
Speed order. Run 5 integrates deterministic planning and resolution into a playable 3v3 Training
Grounds battle. One authenticated server endpoint owns battle creation, legal commands, deterministic
AI planning, resolution, sanitized snapshots, and restart. The client renders authoritative state and
plays ordered battle events before accepting the final snapshot.

## Tooling

- [Git](https://git-scm.com/)
- [Rokit](https://github.com/rojo-rbx/rokit)
- [Rojo](https://rojo.space/)
- [StyLua](https://github.com/JohnnyMorganz/StyLua)
- [Selene](https://kampfkarren.github.io/selene/)
- [Lune](https://lune-org.github.io/) for pure Luau tests
- Roblox Studio on Windows or macOS for runtime testing

Rokit pins project tool versions in `rokit.toml`. Install them from repository root:

```sh
rokit install
```

If Rokit requests trust for a package, review its identity and run:

```sh
rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune
rokit install
```

## Layout

- `src/shared`: replicated definitions, immutable configuration, contracts, and pure utilities
- `src/server`: authoritative battle service, deterministic Training Grounds AI, and transport
- `src/client`: network controller, event playback, UI, and placeholder sprite rendering
- `docs`: architecture, design, art, development, and roadmap documentation
- `art`: source-art organization only; no production art exists yet
- `tests`: unit, integration, playback, and multi-round battle coverage

## Build and serve

Create a place file without Roblox Studio:

```sh
rojo build default.project.json --output Critterbound.rbxlx
```

Start live synchronization:

```sh
rojo serve default.project.json
```

On Windows or macOS, install the Rojo Studio plugin, open a place, start `rojo serve`, then
connect the plugin to the address shown by Rojo. Roblox Studio is not officially supported on
Linux, so source editing and Rojo builds work there but Studio execution needs a supported OS.

## Validation

```sh
stylua --check src
selene src tests
lune run tests/run
rojo sourcemap default.project.json --output sourcemap.json
rojo build default.project.json --output Critterbound.rbxlx
```

Generated build and sourcemap files are ignored by Git.
