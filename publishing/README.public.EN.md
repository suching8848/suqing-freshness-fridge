# SuQing's Freshness Fridge
Bites the Dust—bring back the freshness! An independently buildable, movable fridge that gradually restores directly stored perishable food while powered and enabled. Eligible items restore together.

## Build and use

- Select “SuQing's Freshness Fridge” in the native build menu. No extra skill threshold is imposed.
- Consumes 4 small metal sheets, 2 electric wires, and one each of an alarm clock, digital watch, pocket watch and classic analog wristwatch.
- Requires a screwdriver, welding mask and blowtorch. The first two are kept; the torch spends one native fuel use and is retained. Listed vanilla watch variants are accepted.
- Supply grid or generator power and place food directly inside. Restoration starts enabled; right-click to toggle it. Ordinary refrigeration rules apply when restoration is off.
- Empty the appliance before native furniture pickup. Its individual switch is retained; a carried fridge does not restore food.


## Separate sandbox settings
Restoration is enabled by default. Capacity defaults to 200 (50–1000). Restoring one full fresh-life interval takes 10 game hours by default (0.25–1000). Rotten-food support is on. Lower is faster; different ages do not finish at one fixed time.

Credit requires continuously observed loaded, powered and enabled time in the current session. Unloaded, offline, unverified-power intervals and abnormal clock jumps earn no catch-up. Lowering capacity does not delete contents; normal over-capacity insertion limits apply.

## Scope and compatibility

- Only directly stored Food with standard shelf-life thresholds is processed, not food in nested bags. Burnt food, fertilized eggs and unsupported shelf lives are excluded. Poison, contamination, cooking state, ingredients and remaining portions are unchanged. Deleted/replaced food is not recreated.
- Core functions need no external mod. Four-facing sprites are included; Viewpoint is optional 3D support whose visuals/collision require gameplay confirmation.
- Capacity support covers normal storage/transfers for this fridge. Automation querying capacity directly through Java may still encounter the native 100 cap. Organized/Disorganized keep native effective-capacity rules.
- This candidate includes the relevant display correction when native automatic rotten-food removal is disabled. Enabled/unknown removal policies with PZO still need display validation. World settings are never changed automatically.
- For 42.21 single-player; multiplayer is not claimed. Empty and dismantle custom fridges before disabling, then save and exit normally.

**Mod ID: SuQingFreshnessFridge**

## 0.1.0-rc.2-perf.1 (2026-11-07)

Deduplicates successful capacity synchronization by container, configured target and setter, stopping repeated stable-Tick writes and log flooding. First use, target/container/reset/setter changes resynchronize; creation, placement, loading and saving retain forced physical synchronization. Default200, range50–1000, restoration rules, items, save schema and existing art remain. Initial/forced writes can still emit a native above100 warning; zero warnings or an FPS gain are not promised.

The new real-native suite passes16 cases/30630 assertions:10000 refreshes and10000 Building/Refresh pairs each call the setter once. Existing freshness/native Food/capacity UI/building regressions pass. The capacity repair, complete save/reload and special automation still require user acceptance; feedback about the separate native refrigeration backend does not quantify this Lua repair’s FPS effect.
