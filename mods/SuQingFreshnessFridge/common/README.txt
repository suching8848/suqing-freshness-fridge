SuQing's Freshness Fridge / 蘇清的返鲜冰箱
Runtime resources for B42.21 are in the 42 directory. Single-player candidate.
This common directory intentionally contains no overrides.

0.1.0-rc.2-perf.1 — 2026-11-07
中文：同容器、同容量目标、同setter成功同步后，稳定Tick不再重复写容量；首次、目标变化、新容器、缓存重置或setter变化时重写。加载、放置和保存边界强制物理同步，保存保留配置容量，未知外部容量编辑在这些边界恢复。超过100时，首次/边界仍可能有少量原生警告；原生限制未改，未量化FPS。默认200、范围50–1000、返鲜速度、保存schema、物品和美术不变。仅Lua修复，配套Java补丁未改；本轮不提交或发布，用户负责游戏内复测。
English: successful writes are reused for the same container, capacity target and setter during stable ticks. First use, target/container/setter changes or cache reset cause a new write. Loading, placement and save boundaries force physical synchronization, retain configured saved capacity and restore unknown external capacity edits. Targets above 100 may still cause a few initial/boundary native warnings. The native restriction is unchanged; no FPS gain is quantified. Default 200, range 50–1000, restoration speed, save schema, items and art remain unchanged. Lua-only repair; the companion Java patch is unchanged. No commit or publication for this repair; the user performs in-game acceptance.
