# Services

`BattleCommandProcessor` applies authenticated, versioned, idempotent planning requests.
`BattleProjector` removes private battle data before replication. `BattleService` owns active
Training Grounds sessions and accepts only authenticated player requests from the server bootstrap.

`ProfileService` owns loaded profile handles and exposes only detached DTOs through `LoadProfile`,
`GetProfile`, `GetOwnedCritters`, `GetSelectedTeam`, `SaveProfile`, and `ReleaseProfile`.
`TrainingBattleInputAdapter` resolves the authoritative selected team and copies it into a temporary
battle input. Battle state never references cached profile tables.

`InventoryService` owns stack and unique-item mutations. `EquipmentService` maintains bidirectional
item/Critter references with one slot per Critter. `TeamService` validates and persists exactly three
owned Critter IDs. Every mutation uses `ProfileService.UpdateProfile`: clone, validate, locked save,
then cache replacement. Failed saves discard the candidate profile.
