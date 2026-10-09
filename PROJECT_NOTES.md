# farmAndFightGame — 开工须知

> 给协作者（尤其是 AI 助手）的上下文备忘。**动代码前先读这份，改完顺手更新。**

---

## 1. 项目身份

| 项 | 值 |
|---|---|
| 项目名 | `farmAndFightGame` |
| 引擎 | **Godot 4.7.1-stable**（Windows 版，`E:/godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe`） |
| 主场景 | `res://Scenes/base_level.tscn`（`uid://btccb47s76sxj`） |
| 自动加载 | `Level` → `res://Scripts/Global/Level.gd`（缓存 `level/animalRegion2D` 供动物导航） |
| 渲染 | Forward Plus；Windows 驱动 `d3d12` |
| 像素风 | 视口 400×300，窗口 1600×1200；`canvas_items` + `expand` + `integer` 缩放；纹理过滤 = nearest |
| 版本控制 | git，`main` 分支；远程 `origin` = https://github.com/01821/farm-fight-game.git（**公开仓库**）；`.godot/`、`/android/` 已忽略 |

---

## 2. 目录约定

```
Assets/kenney_tiny-{dungeon,farm,town}/   第三方素材（CC0，Kenney），按包名分目录
Scenes/                                   所有场景，按类型分子目录
  base_level.tscn                         ← 真正的主场景
  game.tscn                               ⚠️ 空壳遗留，只有一行 Node2D
  character/player.tscn
  animals/base_animal.tscn
  plants/{base_plant,tree_1,tree_2,tree_3}.tscn
  buildings/{house,water_bucket,water_container}.tscn   house = 商店
Scripts/
  Global/Level.gd                         自动加载单例
  Characters/{character,player,base_animal}.gd
  State/{State,state_machine}.gd          状态机基础设施
  State/{Player,animal}/{idle,move}.gd    具体状态
  plants/base_plant.gd                    作物：浇水驱动生长
  TileMap/land.gd                         class_name FarmLand：播种/浇水/收获规则
  buildings/water_source.gd               水源：靠近自动补水
  buildings/market.gd                     class_name Market：商店买卖
  Interaction/farm_controller.gd          class_name FarmController：动作键分发中心
  UI/hud.gd                               左上角状态栏
Tests/                                    一次性自测场景（开发用，见第 9 节）
```

---

## 3. 输入与物理层

**输入动作**（方向键用 physical keycode，所以任何键盘布局都是 WASD）

| 动作 | 键 | 用途 |
|---|---|---|
| `up` / `down` / `left` / `right` | W / S / A / D | 移动 |
| `cycle_item` | **Q** | 切换手持道具 |
| `use_item` | **F** | 使用手持道具（唯一动作键） |

**2D 物理层命名**

| 层 | 名字 | 谁在用 |
|---|---|---|
| 1 | Static | 地形碰撞、树的 TileSet 多边形 |
| 2 | Player | 玩家（水源 / 商店的 Area2D 的 mask 都是这层） |
| 3 | Animal | 动物 |
| 4 | Plant | 作物 |

> 碰撞里请用这些语义，别写裸数字。

---

## 4. 运行时场景树（`base_level.tscn`）

```
baseLevel (Node2D)
├── background / Sample (Sprite2D)      底色 与 素材参考图
├── Grass (TileMapLayer)                图集 = kenney_tiny-town
├── Land (TileMapLayer)                 图集 = kenney_tiny-farm  →  script = land.gd (FarmLand)
│      terrain_set 0: terrain 0 = 耕地（种植/浇水都要求 terrain 0）
│      physics_layer_0/collision_layer = 1 (Static)
│      group: navigation_polygon_source_geometry_group
├── HUD (CanvasLayer)                   script = hud.gd
│   ├── Backdrop (ColorRect)
│   ├── InfoLabel (Label)               Gold / Seeds / Crops / Water
│   └── HeldLabel (Label)               [Q] switch  [F] use  holding: XXX
├── FarmController (Node)               script = farm_controller.gd ← F 键分发中心
└── level (Node2D, y_sort)
    ├── Static (Node2D, y_sort)
    │   ├── Trees/                      100+ 个 tree_1.tscn 实例
    │   ├── Plants/                     ← 运行时种植的作物挂在这里（初始为空）
    │   ├── Market                      ← house.tscn 实例，带 Area2D，是商店
    │   ├── waterBucket                 ← 水源（Area2D）
    │   └── WaterContainer              ← 水源（Area2D）
    ├── Animals/                        base_animal.tscn 实例（1 只）
    ├── Player                          player.tscn 实例
    └── animalRegion2D (NavigationRegion2D)   group: animalRegion
```

---

## 5. 核心架构

### 角色 + 状态机

```
Character (CharacterBody2D)      Scripts/Characters/character.gd
├── Player       class_name Player      移动输入 + 农场状态 + 手持道具
└── base_animal.gd  extends Character   持有 move_timer

子节点结构（player.tscn / base_animal.tscn 都一样）：
  Sprite2D, StateMachine(Node), AnimationPlayer, debugLabel, CollisionShape2D
  动物额外有 NavigationAgent2D + MoveTimer
```

- `state_machine.gd`：**子节点即状态**。`_ready` 注入 `stateMachine`/`character`，默认进 `get_child(0)`。
- 切换用 `stateMachine.SwitchTo("Move")` —— **按节点名查找**。

> ⚠️ **三个名字必须一模一样**：`StateMachine` 下的节点名 == `SwitchTo()` 的字符串 == `AnimationPlayer` 里的动画名。
> 因为 `Character.UpdateAnimation()` 直接 `play(state_machine.currentState.name)`。新增状态时三处一起加。

### 手持道具模型（核心交互设计）

玩家手上永远只有一样东西，`Q` 循环切换：

| 手持 | 说明 |
|---|---|
| `Player.Item.SEED` | 种子袋 |
| `Player.Item.WATER_CAN` | 水壶（还有 `water_left` 水量，容量 5） |
| `Player.Item.BASKET` | 收获篮（`player.harvested` 就是篮子里的作物数） |

**只有一个动作键 `F`**，效果由「手持道具 + 所在位置」决定，全部逻辑在 `FarmController.use_held_item()`：

| 手持 | 位置 | F 的效果 |
|---|---|---|
| 种子袋 | 耕地格 | 播种（扣 1 种子） |
| 种子袋 | 商店范围内 | 买 1 粒种子（扣 3 金） |
| 水壶 | 有作物的格 | 浇水（扣 1 水） |
| 水壶 | 商店范围内 | 无效，提示 |
| 收获篮 | 成熟作物格 | 收获（作物进篮子） |
| 收获篮 | 商店范围内 | 卖掉篮子里全部作物（每个 +5 金） |

> 注意 **商店优先**：站在商店范围内即使脚下是耕地，也走交易而不是播种。

### 农场循环规则

1. **播种**要求 terrain 0 的耕地、该格没种过、`player.seeds > 0`。作物实例化后挂到 `level/Static/Plants`。
2. **种下后不会自己生长**。
3. **浇水**后该格出现蓝色湿痕（`WetMark`）。
4. `growTime`（默认 3 秒）后升 **一级** 并**自动变干**——下一级要再浇一次。
5. `growStage` 到 4 即成熟（`is_mature()`），不能再浇。
6. **收获**后作物销毁，格子空出可重种。

### 经济

| 项 | 值 |
|---|---|
| 初始金币 / 种子 | 20 / 8 |
| 种子售价 | 3 金 |
| 作物收购价 | 5 金 |

一个作物净赚 2 金。金币不够时买种子会被拒。

### 数据流

- 作物状态（阶段 / 是否浇过水）**归作物自己管**，`FarmLand` 只持有 `plants: Dictionary[Vector2i -> BasePlant]`。
- 玩家状态（手持物 / 水 / 种子 / 收成 / 钱）归 `Player`。
- HUD 每帧直接读 `Player`，不用信号同步。

---

## 6. 素材图集坐标（kenney_tiny-farm/Tilemap/tilemap_packed.png）

单格 16×16，图集 12 列。已用的 `region_rect`：

| 对象 | region_rect |
|---|---|
| 玩家 | `Rect2(16, 144, 16, 16)` |
| 动物 | `Rect2(0, 160, 16, 16)` |
| 作物（按 growStage / plantType 算） | `Rect2(64 + 16*stage, 16*type, 16, 16)`，stage 0→4 即 x 从 64 到 128 |
| tree_1 | `Rect2(48, 0, 16, 32)` |
| 水桶 / 水桶(激活) | `Rect2(0, 96, 16, 16)` / `Rect2(16, 96, 16, 16)` |
| 水缸 / 水缸(激活) | `Rect2(32, 128, 32, 16)` / `Rect2(32, 144, 32, 16)` |

全部素材为 **CC0（Kenney）**，各目录下有 `License.txt`。

---

## 7. 已知的坑与手工改文件规则

- **不要手改 `.godot/`**：生成目录，已 gitignore。
- ⚠️ **在编辑器之外新建 `class_name` 后，必须重新导入一次**，否则其他脚本会报
  `Parse Error: Could not find type "XXX" in the current scope`。
  原因：全局类名缓存在 `.godot/global_script_class_cache.cfg`，只有编辑器会更新它。
  命令：`godot --headless --path . --import`
- **不要手写 UID**：`.tscn`/`.tres` 里的 `uid://` 由编辑器生成。**但 `ext_resource` 不带 `uid` 也能正常加载**（已实测），所以手工建场景时可以只写 `path`。
- ⚠️ 每个脚本旁边有个同名 `.uid` 文件（Godot 4.4+），**它属于版本控制，别忽略**。
  移动 / 重命名 / 删除脚本时，**必须连 `.uid` 一起处理**，否则会留下孤儿文件（已踩过）。
- 节点上的 `unique_id=` 是较新引擎的字段，**手工新增节点时可以省略**（已实测可加载）。
- 所有文本文件是 **LF**，`.gitattributes` 有 `* text=auto eol=lf`，别改成 CRLF。
- ⚠️ **Godot 内置字体不含中文字形**（已用 `ThemeDB.fallback_font.has_char("水")` 实测 = false）。
  HUD/`debugLabel` 等 Label **不能用中文**，会渲染成方块。要中文必须往项目里放一个 CJK 字体。
- ⚠️ `land.gd` 里节点路径是写死的 `$"../level/Player"`、`$"../level/Static/Plants"`；
  `farm_controller.gd` 写死了 `$"../level/Static/Market"` —— **动 `base_level` 层级就会崩**。
- `character.gd` 里的 `go()` / `dieOnCompany()` 和恒为 `false` 的 `workToAdd` 是**占位玩笑代码，不是真逻辑**。
- `game.tscn` 是空壳；`tree_2.tscn` / `tree_3.tscn` 没被任何场景引用。
- 动物状态里 `speed` 在 `Update()` 每帧重新随机（`randi_range`）—— 速度一直在抖，疑似写错位置。

---

## 8. 当前进度

**已能玩**
- 玩家 WASD 移动 + Idle/Move 状态切换 + 动画
- 动物 Idle/Move + `NavigationAgent2D` 随机漫游
- **手持道具系统**：Q 切换 种子袋 / 水壶 / 收获篮，HUD 实时显示
- **完整农场循环**：播种 → 浇水 → 逐级生长 → 成熟 → 收获
- **经济循环**：在商店（房子）里拿篮卖作物、拿种子袋买种子；钱不够会被拒
- 水壶容量与水源自动补水
- 左上角 HUD 实时显示 金币 / 种子 / 作物 / 水量 / 手持物

**半成品**
- `plantType` 有字段但 `current_crop_type` 恒为 0，只有一种作物
- `Land` 的 terrain 1 在图集里定义好了，但没代码使用

**没做**
- 战斗（项目名里的 `Fight` 一行代码都没有）
- 存档、音效、中文 UI

---

## 9. 协作方式（给 AI 助手）

### 铁律

1. **复杂节点和场景不要用代码动态创建**（不要 `new Area2D()` 之类）。预先在 `.tscn` / 场景里建好，运行时只做 `instantiate()` + 设属性。
2. **一次只改一小块**，改完立刻验证再继续。
3. **大改动前先 commit**。

### 验证（不用打开编辑器，AI 自己就能跑）

> Godot 的 Windows 版是 **GUI 子系统程序**，PowerShell 直接调用**不会等待**它结束。
> 必须用管道强制等待，否则 `$LASTEXITCODE` 是空的。

```powershell
$godot = 'E:\godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe'
Set-Location 'E:\godot\farmAndFightGame\farmAndFightGame'

# 0) 新增了 class_name 之后必须先刷新缓存
& $godot --headless --path . --import

# 1) 作物单元自测（11 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_plant.tscn --quit-after 2400 2>&1 | Out-String

# 2) 端到端自测（44 项）：手持道具 + 农场循环 + 商店经济 + 水源 + HUD
& $godot --headless --path . --fixed-fps 60 res://Tests/test_farm.tscn --quit-after 2400 2>&1 | Out-String

# 3) 跑主场景 15 秒，抓运行时错误
& $godot --headless --path . --fixed-fps 60 --quit-after 900 2>&1 | Out-String
```

要点：
- `--fixed-fps 60` 让时间步长确定，定时器/生长行为可复现。
- `--quit-after N` 是**帧数**，不是秒；配合 `--fixed-fps 60` 时 900 帧 = 15 秒。
- 测试脚本用 `_check(说明, 条件)` 打印 `PASS`/`FAIL`，结尾打印 `RESULT fail=N`。
- 端到端测试**尽量走 `FarmController.use_held_item()`**（玩家真实路径），而不是直接调底层方法。
- 注入故障后引擎会打出带 `文件:行号` 和 GDScript 调用栈的 `ERROR`，**验证链路是可信的**（已实测）。

### 查文档，别凭记忆

- 首选编辑器内置帮助（F1）——版本一定对得上。
- 在线：<https://docs.godotengine.org/en/4.7/>
- 怀疑某个 API 行为变了：<https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html>
- 本项目引擎版本（4.7）比多数社区教程新，**默认不可信**。

---

## 10. 路线图

| # | 目标 | 状态 |
|---|---|---|
| 1 | 浇水 → 成熟 → 收获 闭环 | ✅ |
| 2 | 手持道具概念（Q 切换 + 单动作键分发） | ✅ |
| 3 | 经济：卖作物、买种子、商店交互 | ✅ |
| 4 | **战斗**：会来破坏农场的敌人 + 玩家攻击 | ⬜ 下一步 |
| 5 | 打磨：多种作物、音效、中文 UI（需 CJK 字体）、存档 | ⬜ |
