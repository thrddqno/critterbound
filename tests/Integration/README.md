# Integration Tests

## Studio visual checklist

Lune cannot execute Roblox `Instance` UI. Verify manually in Roblox Studio, including Vinegar:

1. Start play mode and confirm six Critter placeholders plus six card panels appear.
2. Confirm every placeholder shows its logical asset identifier.
3. Queue and remove cards; verify energy preview and per-Critter order.
4. Attempt an over-budget selection and confirm rejection message.
5. Commit and confirm queue/hand lock without server traffic.
6. Reset and confirm queue, allocation, lock, selection, and message clear.
7. Confirm `PLAYER TEAM` and `ENEMY TEAM` headers, side accents, and unique combatant IDs appear.
8. Confirm initiative keeps supplied order and shows side, combatant ID, and Speed.
9. Confirm empty queue is compact; queued cards expand and group by owning combatant.
10. Test long card names/descriptions; confirm text stays inside each card.
11. Test desktop 16:9 and mobile landscape; verify hand/initiative horizontal scrolling.
12. Remount controller and confirm only one `CritterboundBattleScreen` and one callback response.
13. Confirm `Players.CharacterAutoLoads == false` and `LocalPlayer.Character == nil`.
14. Confirm `Workspace.CurrentCamera.CameraType == Scriptable` and no falling or respawning occurs.
15. Confirm no duplicate `ScreenGui`, character-related Output errors, or other runtime errors.
16. Reach Round 9 and confirm the HUD warns `BLOOD MOON NEXT` with 50 HP upcoming damage.
17. Reach Round 10 and confirm the HUD shows 50 HP, each living Critter receives distinct
    `BLOOD MOON` environmental feedback after poison, and defeated Critters receive none.
18. Continue to Round 11 and confirm upcoming Blood Moon damage changes to 80 HP.
