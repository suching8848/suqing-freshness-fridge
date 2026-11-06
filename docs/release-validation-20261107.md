# 0.1.0-rc.2-perf.1 发布验证 / Release validation

新真实原生测试16场景／30630断言通过；10000刷新与10000对Building/Refresh均仅1次setter。旧返鲜、原生Food、容量UI及建造组件回归通过。本次单人容量修复已有用户实测及保存、正常退出日志证据。2026-11-07的06:26会话确认新版载入，稳定运行阶段容量警告为0，启动2条、保存1条；用户反馈无异常并授权发布。保存后重进和特殊自动化兼容仍未验证，不据此声称精确FPS收益。

The new real-native suite passes16 cases/30630 assertions:10000 refreshes and10000 Building/Refresh pairs each call the setter once. Existing freshness/native Food/capacity UI/building regressions pass. The user tested this capacity repair in single-player; logs confirm the new version loaded, saved and exited normally. The 2026-11-07 06:26 session recorded no capacity warnings during steady running, with two at startup and one at saving. The user reported no remaining problem and authorized publication. Reloading that save and special automation remain unverified; no precise FPS gain is claimed.

本轮只同步授权源码和工坊资料；原物品、模组ID及既有启用顺序保持。不把其他场景的帧率或离线调用数当成本版本的量化FPS收益。

Only authorized source and publishing material are synchronized; item/Mod IDs and existing enabled order remain. Neither another scene’s frame rate nor offline call counts are claimed as this release’s quantified FPS gain.

离线组件：新native刷新16/30630、旧runtime64/407、native精度3600轮3605断言、显示2642、原native容量37、容量UI1949、建造/翻译通过；真实读回物理字段与effective容量，未做完整游戏序列化或UI操作。

Offline components: new native refresh16/30630, existing runtime64/407, native precision3600 passes/3605 assertions, display2642, native capacity37, capacity UI1949 and building/translation. Physical/effective values are verified; full game serialization and UI operation are excluded.

## 本轮用户实测证据 / User-run evidence

2026-11-07的06:26会话冻结核验：`D:\steam\steamapps\common\ProjectZomboid\CodexAssets\UnifiedCoolingRelease_20261107_0634\game-audit\native-fridge\audit.md`及同目录`audit.json`。完整DebugLog SHA-256：`3b4988430908ebec68afe42d53f2f1d1c90e09b3acfa921e47fd5e4c38eea690`。物理LF行号：22103新版载入；21999、22102启动警告；22466保存边界警告；22465、22472保存；22478正常GameThread退出。首次非零帧至保存前容量警告为0。用户随后反馈无异常并授权同步发布。

Frozen audit of the user-run 06:26 session: the paths above identify the local evidence without distributing the full user log. Physical-LF lines confirm the loaded Fridge version (22103), two startup warnings (21999/22102), one save-boundary warning (22466), saving (22465/22472) and normal GameThread exit (22478). There were no capacity warnings between the first nonzero gameplay frame and saving. This does not certify a subsequent reload, special automation, long-term behavior or a controlled FPS gain.
