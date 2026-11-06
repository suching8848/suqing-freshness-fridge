# 当前原生返鲜接口与调度审计

范围：当前安装的 B42.21.0 `projectzomboid.jar`，使用 `javap -p -c` 只读检查；不启动客户端，不加载地图或用户存档。JAR SHA-256 和可重跑检查保存在 `runtime_native_audit.json`。

## 已证实的原生行为

- `Food.isRotten()`直接比较`age >= offAgeMax`（受精蛋另有分支），修改旧`rotten`布尔字段不能保护实际腐坏状态。
- `Food.update()`直接在 Java 内调用私有`updateRotting()`。该方法可能调用`updateAge()`，并按`replaceOnRotten`替换腐坏食物；当世界的腐坏食物移除天数启用时，也可能按年龄删除。Lua 的公开方法包装不能拦住这些 Java 内部调用。
- `ItemContainer.isPowered()`是当前父对象的供电查询，没有过去的供电历史。发电机当前燃油、开关与已处理小时也不足以证明整个未知离区间均持续有电。
- 当前帧顺序为`OnTickEvenPaused → IsoWorld.update → GameTime更新辅助 → OnTick`。`OnTickEvenPaused`还早于退出保存分支；暂停时不可假定必然有后续`OnTick`。
- 单人`IsoCell`先处理原生物品，再处理玩家等移动对象。正常玩家的`OnPlayerUpdate`在其父类处理计时动作之前，可用于提前恢复本帧临时年龄保护。
- `GameWindow.save()`的`OnSave`在当前`IsoCell`序列化之前执行。

## 实现约束

返鲜只应作用于直接位于本模组冰箱冷藏空间的合格食物；不递归处理包内食物。恢复量只来自本次会话中连续加载且确认供电的区间；重新加载、离区、停用、移入另一冰箱均应重新建立计时锚点，不能用当前供电补算未知时间。

先前候选采用原生物品更新前临时降低年龄、随后恢复的路径；本次用户实测证明该中间值会被界面读取，造成变质／陈腐闪烁，且原生饥饿等状态读取也受影响。当前正式档经二进制及原生字符串/整数解析交叉核验，`DaysForRottenFoodRemoval=-1`，没有原生自动删除风险。rc.2 在该策略下不再修改临时年龄，仅在必要时暂存并暂停每个食品的 `replaceOnRotten` 字符串；恢复该字段独立于年龄检查，尊重外部显式编辑，保留旧年龄护栏收据的恢复能力。启用或未知的删除策略保留先前护栏路径，不作为本轮PZO显示/调度兼容已修复的结论。

`runtime_NativeShieldProbe.java`在独立 JVM 内调用当前真实`Food.updateRotting()`，验证非空腐坏替换规则及立即移除设置下的120次临时护栏/恢复循环，并核对份量、营养、生熟、污染、毒素和原阈值保持。它没有创建`IsoWorld`、客户端或读取用户存档。

同一原生探针还核对真实`ItemContainer`容量50、200、1000的原始字段及getter差异：普通世界容器getter存在硬编码100上限，因此仅设置字段不足以实现200以上的正常UI转移，必须配套限定本建筑的Lua容量桥接。`runtime_native_core_cases.lua`将实际`Core.lua`载入真实原生`Food`对象，验证100000天高龄食品经过3600次微小返鲜后确实减龄0.5天；双精度台账用于避免逐帧浮点舍入导致返鲜停滞。

`runtime_native_capacity_cases.lua`把实际`Capacity.lua`装入真实`ItemContainer`的Kahlua公开方法表：先用真实`AddItem`加入101个1kg物品，确认原生重量101；再检查200/1000有效容量、边界拒绝、降低到50时旧内容保留、普通冰箱和未来schema不受影响。队列桥接受真实原生incoming物品，原生`AddItem`随后完成从源容器移除并加入目标，真实目标重量106、物品102件。此项只有character/计时动作队列外壳使用模拟，未执行游戏计时动作。

## 当前收据

统一重跑：`E:\code\python\python.exe tools\runtime_run_tests.py`。

- 原生静态控制流：12项。
- 原生腐坏护栏、容量基线和存储方法：120轮护栏、260条断言。
- 实际Core与原生Food浮点精度：3600次结算、3605条断言。
- 实际Capacity与原生容器：6组、37条断言，包含真实199.99f+0.01f恰好200的重量边界，以及原生float32剩余容量差值。
- 实际Core/Runtime Kahlua生命周期模型：56个场景、195条断言。

机器可读收据为`runtime_validation_report.json`；日志位于`runtime_validation`目录。Runtime模型中容量模块安装检查被显式隔离，容量逻辑本身由上述真实原生对象集成与独立`capacity_*`测试验证。

## 证据边界

静态调度审计、真实原生方法探针、Kahlua模拟回归是离线证据。它们不能证明真实游戏的流式加载、所有第三方模组交互、计时动作和UI视角均正常；这些由用户在集中验收时验证。
