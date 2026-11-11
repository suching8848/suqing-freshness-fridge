SuQing's Freshness Fridge / 蘇清的返鲜冰箱
Runtime resources for B42.21 and B42.22 are in the 42 directory.
This common directory intentionally contains no overrides.

0.2.0-rc.3 — 2026-11-11

通电后将标准可腐坏食物直接放入冰箱，右键选择「密封冰箱并开始返鲜」。密封期间无法打开或存取。冰箱累计达到设定的通电游戏时长后，原有食物恢复新鲜并自动开封。默认 12 小时，沙盒可设 0.25–24 小时。断电、离区、离线或供电不明时暂停计时。受污染、烧焦、受精或缺少有效保鲜期的食物，以及容器和其他物品，会使封箱失败。

Connect power, place standard perishable food directly inside, then right-click and select “Seal fridge and start restoration.” The sealed fridge blocks access and transfers. The original food becomes fresh and the fridge unseals after the configured powered game time. The default is 12 hours, configurable from 0.25 to 24 hours. Timing pauses during outages, unloading, offline time, and unverified power. Tainted, burnt, fertilized, or unsupported food, bags, and other objects prevent sealing.

回退或停用前完成所有密封批次。B42.22.2 单人批次模型和原生存读档已离线验证，游戏内操作及帧率待验收。

Finish all sealed batches before rolling back or disabling. The B42.22.2 single-player batch model and native save/load were verified offline. In-game behavior and FPS await acceptance.

Historical releases / 历史版本

0.1.0-rc.3 — 2026-11-08
中文：可选适配 Live Wire 1.7.2。设备分路切断时，保留冰箱的容量和存取功能并停止返鲜。复电或回区后重新观察。区块加载时，Live Wire 先结算自然老化与冻融。当前为 B42.21 单人隔离候选。
English: Optional Live Wire 1.7.2 integration. The fridge stays accessible at its configured capacity when its equipment circuit opens, and freshness restoration pauses. Power restoration and chunk reloads start a new observation. Live Wire handles ordinary aging and freeze/thaw replay first. B42.21 isolated single-player candidate.

0.1.0-rc.4-perf.1 — 2026-11-10
复用单轮容器和供电检查，减少无变化的食物记录写入。B42.22.2 单人实机性能待验证。
Reuses container and power checks within a phase and reduces unchanged food record writes. B42.22.2 single-player performance testing is pending.

0.1.0-rc.4 — 2026-11-09
B42.22.2 单人适配候选。保留 B42.21 分支的加载范围，沿用冰箱建筑、可搬运物品 ID、食物记录和返鲜规则。原版等距视角的冰箱返鲜可以独立运行。Live Wire 1.7.2 和便携冷藏配套属于可选兼容。当前 Viewpoint 与冷藏 Java 后端的新版加载和游戏内表现另行验收。
Single-player compatibility candidate for B42.22.2. The mod still accepts B42.21 and uses the existing building and movable item IDs, food records and restoration rules. Fridge restoration works independently in the standard isometric view. Live Wire 1.7.2 and portable refrigeration are optional integrations. Viewpoint and the companion refrigeration Java backend require separate B42.22.2 loading and gameplay validation.
