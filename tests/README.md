# Tests

Tests are grouped into `Unit`, `Integration`, and `Fixtures`. Pure domain, asset, presentation, and
planning tests run through pinned Lune without Roblox Studio:

Run 4A coverage includes deterministic RNG/decks, battle initialization, energy, private planning,
idempotent command processing, and hidden-information projection.

```sh
lune run tests/run
```

Fixtures demonstrate schema and validation behavior only; they are not final balance data.
