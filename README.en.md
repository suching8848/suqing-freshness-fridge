# SuQing's Freshness Fridge

Current item identity, visibility and upload status: [workshop-item.json](publishing/workshop-item.json). Frozen manifests under release/ retain their preparation-time state; an old uploaded=false value there does not describe the current Steam item.

Workshop item: [the existing public item](https://steamcommunity.com/sharedfiles/filedetails/?id=3834692923). Live Steam SDK confirmed public visibility on2026-11-07. The authorized source update is pushed to Git, and native Steam SDK readback verified the public Workshop update. See publishing/publication-20261107.json for the verified publication scope. Old frozen snapshots retain their historical meaning.

**0.1.0-rc.2-perf.1 — Project Zomboid 42.21, single-player candidate.**

2026-11-07 capacity synchronization update (0.1.0-rc.2-perf.1): after a successful write, stable ticks no longer call `setCapacity` again for the same container, configured target and setter. A first use, changed target, new container, cache reset or changed setter triggers another write. Loading, placement and save boundaries still force physical synchronization; saved capacity remains the configured value. Unknown external edits to the physical capacity are restored at those boundaries, rather than overwritten on every stable tick.

Targets above 100 can still produce a small number of native warnings on first or boundary synchronization. This removes repetitive steady-state writes and log flooding without changing the native capacity restriction; no FPS gain is quantified. Capacity remains 200 by default, configurable from 50 to 1000. Restoration speed, save schema, items and art remain unchanged. This is a Lua repair; the companion refrigeration Java patch is unchanged. This repair is now authorized for Git synchronization and a public Workshop update. The user completed this single-player capacity-repair test and saved and exited normally. A subsequent reload and special automation remain unverified; see the current validation summary below.

2026-11-06: fixes repeated rotten/stale flicker for the current save, whose native rotten-food removal option is disabled. Active restoration no longer applies a temporary age clamp under that policy. Only existing per-item rotten replacement rules are temporarily suspended and then restored. Capacity, restoration speed, food state and PZO settings are unchanged. Current fix records: `D:\steam\steamapps\common\ProjectZomboid\CodexAssets\FreshnessFlickerFix_20261106_001748`. In-game display acceptance remains with the user.

A separately buildable, movable freshness-restoring appliance, based on the proportions of the vanilla mini fridge. It includes original four-facing sprites and an optional independent Viewpoint model. It does not replace vanilla refrigerators, Workshop originals, or SuQing's wearable refrigeration upgrades.

Offline validation has passed, and the user completed the scoped single-player capacity-repair test. Other gameplay, placement, streaming, power transitions and Viewpoint visuals retain their separate acceptance limits. On 2026-11-05, the user authorized installation into `C:\Users\15792\Zomboid\mods\SuQingFreshnessFridge` and appending this Mod ID to the existing `Sandbox\2026-10-09_18-19-22` save. The original 222 Mod IDs retain their order; the global default list and sandbox file are unchanged.

The cancelled isolated test profile and its shortcut were removed to the Windows Recycle Bin. The delivery-folder launcher 「启动单人档测试.cmd」 uses the normal game executable with `-debug`; only the user starts it. Deployment records, the exact original mod-list backup and acceptance instructions are under `D:\steam\steamapps\common\ProjectZomboid\CodexAssets\SuQingFreshnessFridge_20261105\PersonalInstall_20261105_214941`. The original non-installed archive and release folder remain historical snapshots.

## Current release and validation scope (2026-11-07)

Deduplicates successful capacity synchronization by container, configured target and setter, stopping repeated stable-Tick writes and log flooding. First use, target/container/reset/setter changes resynchronize; creation, placement, loading and saving retain forced physical synchronization. Default200, range50–1000, restoration rules, items, save schema and existing art remain. Initial/forced writes can still emit a native above100 warning; zero warnings or an FPS gain are not promised.

The new real-native suite passes16 cases/30630 assertions:10000 refreshes and10000 Building/Refresh pairs each call the setter once. Existing freshness/native Food/capacity UI/building regressions pass. The user tested this capacity repair in single-player; logs confirm the new version loaded, saved and exited normally. The 2026-11-07 06:26 session recorded no capacity warnings during steady running, with two at startup and one at saving. The user reported no remaining problem and authorized publication. Reloading that save and special automation remain unverified; no precise FPS gain is claimed.

See the [current validation summary](docs/release-validation-20261107.md). Earlier per-stage figures and “not published” notes describe historical checkpoints, not current FPS or upload-status claims.

## Construction and operation

Open the native build menu and select **SuQing's Freshness Fridge**. No additional skill requirement is imposed.

| Input | Amount and handling |
| --- | --- |
| Small metal sheets | 4 objects, consumed |
| Electric wire | 2 objects, consumed |
| Alarm clock, digital watch, pocket watch, classic analog wristwatch | One of each; four separate objects consumed |
| Screwdriver and welding mask | Retained tools |
| Blowtorch | One native fuel use; tool retained |

Six digital-watch variants and eight classic analog-watch variants are accepted. Payment, cancellation and completion remain under native BuildLogic; no separate refund loop is added.

The fridge uses native grid or generator power and starts with restoration enabled. Right-click to toggle restoration. With restoration off it behaves as an ordinary refrigerator. It restores only directly stored standard perishable Food. Food inside a bag placed in the fridge is excluded.

## Sandbox settings

- `Enabled`: restoration master switch, default **true**.
- `Capacity`: base capacity **200**, integer range **50–1000**. Applies to new and loaded appliances. Reducing capacity never deletes contents; normal insertion limits apply while over capacity.
- `RestoreHours`: game hours to restore one complete native fresh-life interval, default **10**, range **0.25–1000**. Lower is faster. Each observed game hour subtracts `native fresh-life interval / RestoreHours` from food age, to a minimum of zero.
- `AllowRotten`: default **true**, allowing gradual recovery of rotten Food that still exists.

Restoration preserves portions, recipe ingredients, nutrition fields, cooking state, poison and contamination. Burnt food, fertilized eggs and items without standard shelf-life thresholds are excluded. Deleted or replaced items are not reconstructed. With native rotten-food removal disabled, protection does not change age: it temporarily suspends only a nonempty per-item rotten replacement rule and restores that rule independently of age. Explicit age or replacement-rule edits by other mods are respected.

Enabled or unknown native removal policies retain the previous age-guard path. This change does not claim to resolve that branch's display and scheduling behavior under PZO callback staggering. The verified personal save uses `DaysForRottenFoodRemoval=-1` and does not enter that branch. No sandbox or global optimizer setting needs to change for this fix.

**Time accounting:** only continuously observed, loaded and powered intervals in the current single-player session earn restoration credit. Unloaded, offline, mod-absent and unverified power intervals do not. Single clock jumps exceeding 15 game minutes are re-anchored without restoration credit. Ordinary native aging is settled before a newly discovered item is anchored.

**Capacity compatibility:** the installed engine clamps ordinary world containers to 100 internally. This mod supplies a scoped Lua capacity bridge for its own fridge, covering normal single-player drag-and-drop, transfer-all, timed-action validation and the vanilla Lua queue helper. Native storage rules remain in place; Organized/Disorganized affect effective capacity using native float32 rules. External mods that directly call Java capacity methods can still encounter the original cap and need separate compatibility work. No JAR, global cap, DLL or injector is changed.

## Moving and disabling

Empty the appliance before native pickup. Its per-fridge identifier and restoration switch are preserved during moving and re-placement. A carried fridge does not restore food. Re-placement uses the current sandbox capacity. Native furniture dismantling applies; no additional clock refunds are issued.

Before removing this custom-building mod, empty and dismantle its appliances, then save and exit normally. Do not assume that missing sprites after disabling provide an automatic rollback. This deployment backs up only the exact save mod-list configuration, not the complete world or its progress.

## Art and localization

Four original sprites use `suqing_freshness_fridge_01_0..3` in S/E/N/W order. A real PZPK texture pack and tdef tile definition use tiledef ID 7825. The original 562-triangle model includes UVs, a PNG material atlas and explicit four-facing Viewpoint bindings, exported for the installed Viewpoint Z-up parser. Standard isometric rendering remains independent of Viewpoint.

The selected B “Night Workshop” cover was created with built-in imagegen using the user's original character sheet and approved SuQing covers. The mod icon was generated independently as a simplified fridge, rewind clock and apple composition with no title. It is not a resized cover. The icon master, exact prompt and 64/128/256px exports are retained in `art/icon-source.png`, `art/icon-generation.json` and `art/icon-exports`. Original covers and character references are preserved. `tools/export_selected_cover.py` exports the poster and dedicated icon from their separate source images.

Game text is provided in CN and EN with the existing CH files retained. The logic, Mod ID, object/item IDs, settings and save data are shared between languages. Localized selector metadata now uses the native `media/lua/shared/Translate/<language>/Mod.json` mechanism with bare `name` and `description` keys, verified through the installed native parser. The unsupported `namezh` field was removed; English is the base metadata fallback. The original frozen package is preserved, and the exact current runtime candidate is frozen separately with the deployment records.

## Offline reproduction and delivery boundaries

- `tools/runtime_run_tests.py`: Core/Runtime model scenarios, real Food precision/guard probes, native container bridge and control-flow audit.
- `tools/building_validate.ps1`: native entity/recipe/Xui/translation parsing and original Lua building/moving control-flow tests.
- `tools/capacity_validate.py`: original Lua UI transfer paths, capacity boundaries and all trait capacities from 50 to 1000.
- `tools/assets_validate.py`: geometry, UVs, textures, PZPK/tdef readback and four-facing bindings.
- `tools/release.py validate`: aggregate checks, compilation of all shipped Lua, protected-profile hashes and a stable runtime manifest.
- `tools/release.py package`: a frozen, non-installing archive with per-member readback and SHA-256.

`release.py` retains its pre-installation safety checks. After personal deployment, use the current delivery's recorded `validation` results, `deployment.json` and `icon-final-validation.json`; the pre-installation entry point is not a validator for an already installed profile.

These checks use standalone methods, parsers and mocks; they do not start the game, create a game world or measure gameplay FPS. The user performed the scoped in-game capacity-repair test. Source changes were committed and pushed with authorization on 2026-11-07; publishing/workshop-item.json and the current release receipt record the separate Workshop upload result. This publication preparation did not modify the personal runtime, enabled lists, sandbox or launch configuration.
