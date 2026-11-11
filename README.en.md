# SuQing's Freshness Fridge

**0.2.0-rc.3** is a **B42.22.2 single-player sealed-batch candidate** for Project Zomboid. The mod metadata covers B42.21 and B42.22. This release adds batch records and retains the fridge's Mod ID, building and movable item IDs, four-facing sprites, and capacity settings.

Preserves Loot Tracker 1.8.5 search tracking and sealed-container restrictions when they share inventory selection.

Workshop updates use the existing item. See the publication record for the current public version, visibility, and upload status. Frozen manifests under `release/` preserve their preparation-time state. [Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3834692923) · [Publication status](publishing/workshop-item.json)

## Construction

Select **SuQing's Freshness Fridge** in the native build menu. There is no additional skill requirement.

| Input | Amount and handling |
| --- | --- |
| Small metal sheets | 4 objects, consumed |
| Electric wire | 2 objects, consumed |
| Alarm clock, digital watch, pocket watch, classic analog wristwatch | One of each, four separate objects consumed |
| Screwdriver and welding mask | Retained tools |
| Blowtorch | One native fuel use, tool retained |

The recipe accepts six digital-watch variants and eight classic analog-watch variants. Payment, cancellation, and completion use native BuildLogic.

## Sealed restoration

1. Connect the fridge to utility power, a generator, or a supported Live Wire grid. Put the food directly inside.
2. Right-click the fridge and select **Seal fridge and start restoration**. The fridge records the batch contents when it seals. The ordinary inventory interface cannot open the sealed fridge or transfer food into or out of it. The context menu shows the remaining time.
3. Once the loaded fridge has accumulated the configured powered game time, the batch sets the original foods' age to zero, restores their native properties, and unseals automatically.

A batch accepts directly stored standard perishable `Food`. Bags containing food, other objects, tainted food, burnt food, fertilized eggs, and food without valid shelf-life thresholds prevent sealing. With `AllowRotten` enabled, a batch can restore rotten food that still exists.

Progress pauses during outages, unverified power, area unloading, offline time, and gameplay pauses. Restoring power or reloading the area starts a new observation without losing already confirmed progress. A single clock jump of more than 15 game minutes earns no credit. Waiting checks the fridge's power and batch progress. Food processing takes place when the batch starts, completes, or needs recovery.

During sealing, the batch temporarily applies the native nonperishable threshold and disables cookability to protect the food from native rotten-food replacement or removal. Unsealing restores the original values and ordinary aging resumes. The batch keeps the original items and their portions, nutrition, ingredients, and poison. If the manifest changes, a recoverable batch aborts without restoration and unseals. Missing items are never recreated.

## Sandbox settings

| Setting | Default and range | Effect |
| --- | --- | --- |
| `Enabled` | On | Allows new batches. Already sealed batches can still finish with power. |
| `Capacity` | 200, integer range 50–1000 | Base capacity for new and loaded fridges. Reducing capacity retains existing contents and applies normal limits to further insertion. |
| `BatchHours` | 12, range 0.25–24 game hours | Observed powered time required per batch. 0.25 hours is 15 game minutes. The batch records the duration when it starts. |
| `AllowRotten` | On | Allows rotten food that still exists to enter a new batch. |

The scoped Lua capacity bridge covers ordinary single-player storage in this mod's fridge. Native storage rules and the Organized and Disorganized traits still apply. External mods that query Java capacity directly may encounter the ordinary furniture limit of 100. Targets above 100 can still produce native warnings at first or forced synchronization.

## Compatibility, maintenance, and rollback

- Standard isometric use is independent. The mod registers its included 3D model when it detects Viewpoint.
- Live Wire 1.7.2 is an optional integration. An open equipment circuit pauses timing. On chunk load, the fridge waits for Live Wire to replay ordinary aging and freeze/thaw before observing power again. Third-party automation that bypasses the Lua transfer paths needs separate verification.
- SuQing's Refrigeration Performance Patch `SuQingRefrigerationNative_4221` is an optional ordinary refrigeration backend. Version `0.1.0-rc.2` in the B42.22.2 environment requires SuQing's Refrigeration Upgrades `1.0.0-rc.2-perf.8` and ZombieBuddy. This mod's Lua handles sealed batches. Fully quit and restart after changing the refrigeration backend.
- **Finish every sealed batch before rolling back or disabling the mod.** The temporary protection is saved with the native food. Unsealing restores the original values. If the interface reports that a batch needs recovery, retain the save and check the log.
- Unseal and empty the fridge before native pickup or dismantling. Re-placement applies the current sandbox capacity. Dismantling uses the native furniture refund rules. To remove the mod entirely, finish batches, empty and dismantle the custom fridges, then save and exit normally.

## Validation

B42.22.2 offline validation covers the independent batch model, native Food save and load, and the combined Lua setup with the Freshness Lunchbox. The model checks powered timing, outages, unloading, saving and reloading, and waiting without per-food processing. The native probe checks that the protection survives save and load and that the original values can be restored. Inventory UI, transfer actions, power transitions, streaming, saving and reloading, and FPS still await in-game acceptance. B42.21 gameplay records below apply to earlier versions.

The source retains the runtime, native method, building, and capacity bridge tools. Release packages contain runtime resources and instructions. If installed locally, use the corresponding deployment records for verification. The pre-release checks in `tools/release.py` are for an uninstalled candidate.

- `tools/runtime_run_tests.py` runs runtime and native Food method checks.
- `tools/building_validate.ps1` and `tools/capacity_validate.py` check construction, moving, native Lua transfer, and capacity boundaries.
- `tools/assets_validate.py` reads back the texture pack, model, and four-facing bindings.
- `tools/release.py validate` and `tools/release.py package` check and freeze a candidate package.

## Historical releases and validation

- **2026-11-10 · 0.1.0-rc.4-perf.1** Shared container, settings, and power checks within an update phase and reduced same-clock writes in the old continuous restoration mode.
- **2026-11-09 · 0.1.0-rc.4** Prepared B42.22.2 single-player compatibility and retained B42.21 loading and the existing item and building IDs.
- **2026-11-08 · 0.1.0-rc.3** The Live Wire 1.7.2 integration passed the then-current combined B42.21.0 single-player test. A separate offline reproduction found that Live Wire could apply the outer appliance's power history to food in an active portable cooler when the chunk was unloaded. Overlapping ISA and Live Wire replay for the same appliance still needed gameplay testing. [Historical validation](docs/release-validation-20261108.md)
- **2026-11-07 · 0.1.0-rc.2-perf.1** Deduplicated capacity writes by container, target, and setter. The native suite passed 16 cases and 30,630 assertions. The user tested that capacity repair in single-player and saved and exited normally. That session had no repeated capacity warnings during steady operation. [Historical validation](docs/release-validation-20261107.md)
- **2026-11-06 · 0.1.0-rc.2** Fixed the freshness-state flicker in the then-current single-player save with native rotten-food removal disabled. The repair records are at `D:\steam\steamapps\common\ProjectZomboid\CodexAssets\FreshnessFlickerFix_20261106_001748`.
- **2026-11-05 · Personal installation** The historical installation appended this Mod ID to the user's single-player save. Deployment receipts and the original enabled-list backup are under `D:\steam\steamapps\common\ProjectZomboid\CodexAssets\SuQingFreshnessFridge_20261105\PersonalInstall_20261105_214941`. The backup from that operation covers the enabled-list configuration.

## Art and localization

The original four-facing sprites `suqing_freshness_fridge_01_0..3` use south, east, north, and west order. The PZPK pack and tile definition use tiledef ID 7825. The 562-triangle Viewpoint model includes UVs, a PNG material atlas, and four-facing bindings. The OBJ export uses Z-up. Standard isometric rendering uses the independent 2D sprites.

The selected B “Night Workshop” cover master and prompt are in `art/cover-candidates_20261105`. The dedicated icon master, prompt, and 64/128/256px exports are in `art/icon-source.png`, `art/icon-generation.json`, and `art/icon-exports`. The original covers and character references are preserved. `tools/assets_build.py` builds the appliance assets, and `tools/export_selected_cover.py` exports the cover and independent icon.

Simplified Chinese and English share the logic, IDs, and save format. Existing CH resources remain available. The mod selector uses native `Translate/<language>/Mod.json` metadata.
