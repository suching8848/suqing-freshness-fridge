# 0.1.0-rc.2-perf.1 发布验证 / Release validation

新真实原生测试16场景／30630断言通过；10000刷新与10000对Building/Refresh均仅1次setter。旧返鲜、原生Food、容量UI及建造组件回归通过。用户尚需实际复测本容量修复、完整保存重进和特殊自动化兼容；冷藏Native组合的性能反馈不是本Lua修复的FPS量化。

The new real-native suite passes16 cases/30630 assertions:10000 refreshes and10000 Building/Refresh pairs each call the setter once. Existing freshness/native Food/capacity UI/building regressions pass. The capacity repair, complete save/reload and special automation still require user acceptance; feedback about the separate native refrigeration backend does not quantify this Lua repair’s FPS effect.

本轮只同步授权源码和工坊资料；原物品、模组ID及既有启用顺序保持。不把其他场景的帧率或离线调用数当成本版本的量化FPS收益。

Only authorized source and publishing material are synchronized; item/Mod IDs and existing enabled order remain. Neither another scene’s frame rate nor offline call counts are claimed as this release’s quantified FPS gain.

离线组件：新native刷新16/30630、旧runtime64/407、native精度3600轮3605断言、显示2642、原native容量37、容量UI1949、建造/翻译通过；真实读回物理字段与effective容量，未做完整游戏序列化或UI操作。

Offline components: new native refresh16/30630, existing runtime64/407, native precision3600 passes/3605 assertions, display2642, native capacity37, capacity UI1949 and building/translation. Physical/effective values are verified; full game serialization and UI operation are excluded.
