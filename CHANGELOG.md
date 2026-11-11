# 0.2.0-rc.3 — 2026-11-11

与 Loot Tracker 1.8.5 共用库存选择接口时，保留搜刮记录及密封限制。

Preserves Loot Tracker 1.8.5 search tracking and sealed-container restrictions when they share inventory selection.

# 0.2.0-rc.2 — 2026-11-11

首次尝试封箱前核对库存锁定接口，接入启动阶段延迟安装的库存包装。

Finalizes inventory locks before the first seal, including wrappers installed late during startup.

# 0.2.0-rc.1 — 2026-11-10

新增手动密封批次。直接存放符合条件的食品后，右键开始返鲜。密封期间无法打开、放入或取出。默认累计通电 12 游戏小时，沙盒范围 0.25–24 小时。只累计已加载且持续观察到的通电时间，断电、离区、离线或供电不明时暂停。等待期间按冰箱检查供电和进度，食物在封箱、开封或恢复时处理。到期后保留原食物对象，将年龄归零并恢复原生属性。停用或回退前先完成所有密封批次。

Adds manually sealed restoration batches. Load eligible food directly, then start restoration from the fridge's context menu. Sealing blocks opening, insertion, and removal. The default is 12 powered game hours, configurable from 0.25 to 24. Only continuously observed powered time while the fridge is loaded earns credit. Progress pauses during outages, unloading, offline time, and unverified power. Waiting checks power and progress per fridge. Food processing occurs at sealing, unsealing, or recovery. Completion sets the original foods' age to zero and restores their native properties. Finish all sealed batches before disabling or rolling back.

B42.22.2 离线验证覆盖批次模型、原生 Food 存读档及餐盒组合。游戏内存取、停复电、离区、保存重进和帧率待验收。

B42.22.2 offline validation covers the batch model, native Food save/load, and the combined Freshness Lunchbox setup. In-game access, power transitions, streaming, saving and reloading, and FPS await acceptance.

# 0.1.0-rc.4-perf.1 — 2026-11-10

复用每台冰箱本轮的容器、配置和供电检查，跳过同一游戏时刻确认无变化的食物记录写入。原生回调中发生转移时，以当前归属为准。保留更新前后的腐坏保护、Live Wire 电力边界及原存档格式。B42.22.2 单人性能候选。

Reuses each fridge's container, settings and power checks within an update phase. Skips writes when food state is verified unchanged at the same game time. Uses live ownership when native callbacks move food. Preserves the pre/post spoilage guards, Live Wire power boundaries and the existing save format. B42.22.2 single-player performance candidate.

# 0.1.0-rc.4 — 2026-11-09

B42.22.2 单人适配候选。保留 B42.21 分支的加载范围，沿用冰箱建筑、可搬运物品 ID、食物记录和返鲜规则。原版等距视角的冰箱返鲜可以独立运行。Live Wire 1.7.2 和便携冷藏配套属于可选兼容。当前 Viewpoint 与冷藏 Java 后端的新版加载和游戏内表现另行验收。

Single-player compatibility candidate for B42.22.2. The mod still accepts B42.21 and uses the existing building and movable item IDs, food records and restoration rules. Fridge restoration works independently in the standard isometric view. Live Wire 1.7.2 and portable refrigeration are optional integrations. Viewpoint and the companion refrigeration Java backend require separate B42.22.2 loading and gameplay validation.

# 0.1.0-rc.3 — 2026-11-08

内置 Live Wire 1.7.2 可选适配。设备分路断电时暂停返鲜，容量、存取和搬放仍可使用。恢复供电后重新计时。区块加载时先结算 Live Wire 自然老化和冻融，再开始观察返鲜时间。便携制冷包的离区掉电限制见工坊介绍。已完成 B42.21.0 单人联测。

Adds optional Live Wire 1.7.2 support. Restoration pauses during an equipment circuit outage. Capacity, item access and pickup remain available. Restoration starts a new observation when power returns. Chunk loading settles Live Wire aging and freeze/thaw before restoration timing begins. See the Workshop description for the unloaded portable-cooler limitation. Tested in a combined B42.21.0 single-player setup.

# 0.1.0-rc.2-perf.1 — 2026-11-07

中文：对成功的容量同步按容器、配置目标和setter去重，稳定Tick不再重复写入或连续刷警告。首次、目标变化、新容器、重置或setter变化重新同步；创建、放置、加载和保存仍强制同步物理容量。保留默认200、范围50–1000、返鲜规则、物品、保存schema和既有美术。首次或强制边界仍可能有一次原生超100提示，不承诺零警告或FPS涨幅。 新真实原生测试16场景／30630断言通过；10000刷新与10000对Building/Refresh均仅1次setter。旧返鲜、原生Food、容量UI及建造组件回归通过。本次单人容量修复已有用户实测及保存、正常退出日志证据。2026-11-07的06:26会话确认新版载入，稳定运行阶段容量警告为0，启动2条、保存1条；用户反馈无异常并授权发布。保存后重进和特殊自动化兼容仍未验证，不据此声称精确FPS收益。

English: Deduplicates successful capacity synchronization by container, configured target and setter, stopping repeated stable-Tick writes and log flooding. First use, target/container/reset/setter changes resynchronize; creation, placement, loading and saving retain forced physical synchronization. Default200, range50–1000, restoration rules, items, save schema and existing art remain. Initial/forced writes can still emit a native above100 warning; zero warnings or an FPS gain are not promised. The new real-native suite passes16 cases/30630 assertions:10000 refreshes and10000 Building/Refresh pairs each call the setter once. Existing freshness/native Food/capacity UI/building regressions pass. The user tested this capacity repair in single-player; logs confirm the new version loaded, saved and exited normally. The 2026-11-07 06:26 session recorded no capacity warnings during steady running, with two at startup and one at saving. The user reported no remaining problem and authorized publication. Reloading that save and special automation remain unverified; no precise FPS gain is claimed.

# 0.1.0-rc.2 — 2026-11-06

中文：修复当前单人档中腐坏食物在「变质／陈腐」之间持续闪烁。原版腐坏食物自动删除关闭时，不再临时降低食物年龄；仅对已有腐坏替换规则的食品进行可逆保护。保留外部年龄与替换规则编辑，以及旧候选中断护栏的恢复能力。容量、返鲜速度、沙盒、封面与独立icon保持不变。新增分阶段显示、跨帧回调、保存/转移及原生Food方法回归。离线通过，游戏内复测由用户完成。启用或未知的原版自动删除策略仍保留旧路径，未纳入本轮PZO显示问题已解决的声明。

English: fixes continuous rotten/stale status flicker in the current single-player save. When native rotten-food removal is disabled, no temporary age clamp is applied; only existing per-item rotten replacement rules receive reversible protection. External age/replacement edits and recovery of legacy interrupted guards remain supported. Capacity, restoration speed, sandbox settings, cover and dedicated icon are unchanged. Adds phase-by-phase display, staggered-callback, save/transfer and native Food method regressions. Offline validation passes; the user performs in-game acceptance. Enabled/unknown native removal policies retain the old path and are outside this change's PZO display-fix claim.
