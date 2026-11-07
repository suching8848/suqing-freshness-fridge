# 0.1.0-rc.3 — 2026-11-08

内置 Live Wire 1.7.2 可选适配。设备分路断电时暂停返鲜，容量、存取和搬放仍可使用。恢复供电后重新计时。区块加载时先结算 Live Wire 自然老化和冻融，再开始观察返鲜时间。便携制冷包的离区掉电限制见工坊介绍。已完成 B42.21.0 单人联测。

Adds optional Live Wire 1.7.2 support. Restoration pauses during an equipment circuit outage. Capacity, item access and pickup remain available. Restoration starts a new observation when power returns. Chunk loading settles Live Wire aging and freeze/thaw before restoration timing begins. See the Workshop description for the unloaded portable-cooler limitation. Tested in a combined B42.21.0 single-player setup.

# 0.1.0-rc.2-perf.1 — 2026-11-07

中文：对成功的容量同步按容器、配置目标和setter去重，稳定Tick不再重复写入或连续刷警告。首次、目标变化、新容器、重置或setter变化重新同步；创建、放置、加载和保存仍强制同步物理容量。保留默认200、范围50–1000、返鲜规则、物品、保存schema和既有美术。首次或强制边界仍可能有一次原生超100提示，不承诺零警告或FPS涨幅。 新真实原生测试16场景／30630断言通过；10000刷新与10000对Building/Refresh均仅1次setter。旧返鲜、原生Food、容量UI及建造组件回归通过。本次单人容量修复已有用户实测及保存、正常退出日志证据。2026-11-07的06:26会话确认新版载入，稳定运行阶段容量警告为0，启动2条、保存1条；用户反馈无异常并授权发布。保存后重进和特殊自动化兼容仍未验证，不据此声称精确FPS收益。

English: Deduplicates successful capacity synchronization by container, configured target and setter, stopping repeated stable-Tick writes and log flooding. First use, target/container/reset/setter changes resynchronize; creation, placement, loading and saving retain forced physical synchronization. Default200, range50–1000, restoration rules, items, save schema and existing art remain. Initial/forced writes can still emit a native above100 warning; zero warnings or an FPS gain are not promised. The new real-native suite passes16 cases/30630 assertions:10000 refreshes and10000 Building/Refresh pairs each call the setter once. Existing freshness/native Food/capacity UI/building regressions pass. The user tested this capacity repair in single-player; logs confirm the new version loaded, saved and exited normally. The 2026-11-07 06:26 session recorded no capacity warnings during steady running, with two at startup and one at saving. The user reported no remaining problem and authorized publication. Reloading that save and special automation remain unverified; no precise FPS gain is claimed.

# 0.1.0-rc.2 — 2026-11-06

中文：修复当前单人档中腐坏食物在「变质／陈腐」之间持续闪烁。原版腐坏食物自动删除关闭时，不再临时降低食物年龄；仅对已有腐坏替换规则的食品进行可逆保护。保留外部年龄与替换规则编辑，以及旧候选中断护栏的恢复能力。容量、返鲜速度、沙盒、封面与独立icon保持不变。新增分阶段显示、跨帧回调、保存/转移及原生Food方法回归。离线通过，游戏内复测由用户完成。启用或未知的原版自动删除策略仍保留旧路径，未纳入本轮PZO显示问题已解决的声明。

English: fixes continuous rotten/stale status flicker in the current single-player save. When native rotten-food removal is disabled, no temporary age clamp is applied; only existing per-item rotten replacement rules receive reversible protection. External age/replacement edits and recovery of legacy interrupted guards remain supported. Capacity, restoration speed, sandbox settings, cover and dedicated icon are unchanged. Adds phase-by-phase display, staggered-callback, save/transfer and native Food method regressions. Offline validation passes; the user performs in-game acceptance. Enabled/unknown native removal policies retain the old path and are outside this change's PZO display-fix claim.
