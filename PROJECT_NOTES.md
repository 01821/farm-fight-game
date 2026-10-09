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
Assets/kenney_tiny-{dungeon,farm,town}/   第三方素材（CC0，Kenney）
Assets/fonts/                             Fusion Pixel Font 12px 简体（OFL），UI 中文字体
Scenes/                                   所有场景，按类型分子目录
  base_level.tscn                         ← 真正的主场景
  game.tscn                               ⚠️ 空壳遗留，只有一行 Node2D
  character/player.tscn
  animals/base_animal.tscn                温顺的农场动物
  animals/boar.tscn                       野猪（敌人），贴图取自 kenney_tiny-dungeon
  plants/{base_plant,tree_1,tree_2,tree_3}.tscn
  buildings/{house,water_bucket,water_container}.tscn   house = 商店
Scripts/
  Global/Level.gd                         自动加载单例
  Global/DayCycle.gd                      class_name DayCycle：昼夜循环
  Global/PestSpawner.gd                   class_name PestSpawner：夜晚放野猪
  Global/SaveSystem.gd                    class_name SaveSystem：存档 / 读档
  Characters/{character,player,base_animal}.gd
  Characters/boar.gd                      class_name Boar：野猪
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

**常用分组（group）**：`farm_land`、`player`、`pest`、`pest_spawner`、`animalRegion`。
脚本之间靠这些组找彼此，避免写死跨场景路径。

---

## 3. 输入与物理层

**输入动作**（方向键用 physical keycode，所以任何键盘布局都是 WASD）

| 动作 | 键 | 用途 |
|---|---|---|
| `up` / `down` / `left` / `right` | W / S / A / D | 移动 |
| `cycle_item` | **Q** | 切换手持道具 |
| `use_item` | **F** | 使用手持道具（唯一动作键） |
| `quick_save` | **F5** | 手动存档 |
| `quick_load` | **F9** | 读档 |
| `delete_save` | **F10** | 删除存档（下次启动就是新游戏） |

**2D 物理层命名**

| 层 | 值 | 名字 | 谁在用 |
|---|---|---|---|
| 1 | 1 | Static | 地形碰撞 |
| 2 | 2 | Player | 玩家（水源 / 商店 Area2D 的 mask） |
| 3 | 4 | Animal | 动物、野猪 |
| 4 | 8 | Plant | 作物 |

> 碰撞里请用这些语义，别写裸数字。

---

## 4. 运行时场景树（`base_level.tscn`）

```
baseLevel (Node2D)
├── background / Sample (Sprite2D)
├── Grass (TileMapLayer)                图集 = kenney_tiny-town
├── Land (TileMapLayer)                 →  script = land.gd (FarmLand)
│      terrain_set 0: terrain 0 = 耕地（种植/浇水都要求 terrain 0）
│      physics_layer_0/collision_layer = 1 (Static)
│      groups: navigation_polygon_source_geometry_group, farm_land
├── HUD (CanvasLayer)                   script = hud.gd
│   ├── Backdrop / InfoLabel / HeldLabel
├── FarmController (Node)               script = farm_controller.gd ← F 键分发 + 目标判定
├── NightTint (CanvasModulate)          夜晚压暗画面（HUD 在 CanvasLayer 上，不受影响）
├── DayCycle (Node)                     script = DayCycle.gd ← 昼夜循环
├── SaveSystem (Node)                   script = SaveSystem.gd ← 存档 / 读档
├── PestSpawner (Node2D)                script = PestSpawner.gd，boar_scene 指向 boar.tscn
└── level (Node2D, y_sort)
    ├── Static (Node2D, y_sort)
    │   ├── Trees/                      100+ 个 tree_1.tscn 实例（没有碰撞）
    │   ├── Plants/                     ← 运行时种植的作物挂在这里
    │   ├── Market                      ← house.tscn 实例，带 Area2D，是商店
    │   ├── waterBucket / WaterContainer  ← 水源（Area2D）
    ├── Animals/                        base_animal.tscn 实例（1 只）
    ├── Player                          player.tscn 实例
    └── animalRegion2D (NavigationRegion2D)   group: animalRegion
```

---

## 5. 核心架构

### 角色 + 状态机

```
Character (CharacterBody2D)      Scripts/Characters/character.gd
├── Player       class_name Player      移动 + 农场状态 + 手持道具
└── base_animal.gd  extends Character   持有 move_timer

Boar 是独立的 CharacterBody2D（不继承 Character —— Character 的 @onready 需要
AnimationPlayer / StateMachine 等子节点，野猪场景没有，会直接报错）
```

- `state_machine.gd`：**子节点即状态**，`SwitchTo()` 按节点名查找。

> ⚠️ **三个名字必须一模一样**：`StateMachine` 下的节点名 == `SwitchTo()` 的字符串 == `AnimationPlayer` 里的动画名。

### 手持道具模型

玩家手上永远只有一样东西，`Q` 循环切换：

| 手持 | 说明 |
|---|---|
| `Player.Item.SEED` | 种子袋 |
| `Player.Item.WATER_CAN` | 水壶（`water_left`，容量 5） |
| `Player.Item.BASKET` | 收获篮（`player.harvested`） |
| `Player.Item.SWORD` | 剑 |

**只有一个动作键 `F`**，效果由「手持道具 + 所在位置」决定，全部逻辑在 `FarmController.use_held_item()`：

| 手持 | 位置 | F 的效果 |
|---|---|---|
| 种子袋 | 耕地格 | 播种（扣 1 种子） |
| 种子袋 | 商店范围内 | 买 1 粒种子（扣 3 金） |
| 水壶 | 有作物的格 | 浇水（扣 1 水） |
| 收获篮 | 成熟作物格 | 收获（作物进篮子） |
| 收获篮 | 商店范围内 | 卖掉篮子里全部作物（每个 +5 金） |
| 剑 | 任意位置 | 砍范围内所有野猪 |
| 其它 | 商店范围内 | 无效，给提示 |

> 注意 **商店优先**：站在商店范围内即使脚下是耕地，也走交易而不是播种。

### 农场循环规则

1. **播种**要求 terrain 0 的耕地、该格没种过、`player.seeds > 0`。
2. **种下后不会自己生长**。
3. **浇水**后该格出现蓝色湿痕（`WetMark`）。
4. `growTime`（默认 3 秒）后升 **一级** 并**自动变干**——下一级要再浇一次。
5. `growStage` 到 4 即成熟，不能再浇。
6. **收获**后作物销毁，格子空出可重种。

### 经济与目标

初始金币 20 / 种子 8；种子 3 金，作物 5 金。一个作物净赚 2 金。

**目标**：金币达到 `FarmController.GOLD_GOAL = 300` 即判定「建成谷仓」（`goal_reached` 置位，HUD 显示"目标已达成！"）。

### 昼夜循环

| 项 | 值 |
|---|---|
| 一天长度 | `DayCycle.day_length = 45` 秒 |
| 白天占比 | `day_ratio = 0.6`（前 27 秒白天，后 18 秒夜晚） |
| 画面明暗 | 夜晚用预建的 `NightTint`(CanvasModulate) 渐变到 `Color(0.42, 0.48, 0.72)`，渐变 `FADE_TIME = 2` 秒 |
| 波次规模 | `base_wave_size(2) + 天数 - 1`，上限 `max_wave_size(6)` |

- **HUD 不会被压暗**：HUD 挂在 `CanvasLayer` 上，属于另一块画布，`CanvasModulate` 管不到它。
- `DayCycle.running = false` 可冻结时间（测试用）。
- 场上没作物时野猪会自己离开（`GIVE_UP_TIME` 6 秒）——所以"不种地就没有夜间威胁"是设计使然，不是 bug。

### 存档

`SaveSystem`（挂在 `base_level` 上）把状态写成一个 JSON：`user://farm_save.json`
（Windows 实机路径 `%APPDATA%\Godot\app_userdata\farmAndFightGame\farm_save.json`，约 300 字节）。

| 键 | 作用 |
|---|---|
| **F5** | 手动存档 |
| **F9** | 读档 |
| **F10** | 删除存档（下次启动就是新游戏） |

- **天亮自动存档**（接的是 `DayCycle.day_started` 信号）；**启动自动读档**。
- 自动读档刻意**延后到第一帧的 `_process`**，而不是 `_ready`。这样测试可以在 `add_child`
  之后、第一帧之前把 `save_path` 换成临时文件——既测到真实读档路径，又不会碰玩家存档。
- 存的内容：天数与当天进度、玩家（金币/血量/水量/种子/篮子/手持物/坐标）、
  地块上每一株作物（类型、生长阶段、是否浇过水）、目标进度。
- **只存 `elapsed`，不存 `is_night`**：时段在读取时由 `elapsed` 重新推导，免得存档里出现
  自相矛盾的组合。
- 存档带 `version` 字段；**版本不符或 JSON 损坏时拒绝读取并给提示，不会崩**。
- 各系统通过 `to_save_data()` / `apply_save_data()` 参与存档；以后新增系统照这个模式接一行即可。

### 战斗

**野猪（Boar）** `Scripts/Characters/boar.gd`

| 项 | 值 |
|---|---|
| 血量 | 2 |
| 速度 | 38 px/s（直线冲向最近的作物，不寻路） |
| 吃作物范围 | 10px，啃掉后自己离场 |
| 顶玩家 | 12px 内扣 1 血，冷却 1.5s |
| 受击硬直 | 0.25s（**重要**：否则玩家砍中后它还继续跑，追击手感极差） |
| 放弃条件 | 场上没作物 6 秒后离开；被卡住 3 秒后离开 |

**玩家攻击**

| 项 | 值 |
|---|---|
| 攻击范围 | 26px 圆形（范围内**所有**野猪一起掉血，不做扇形） |
| 伤害 | 1 |
| 冷却 | 0.35s |
| 刀光 | 复用 `player.tscn` 里预建的 `Slash`(Polygon2D)，命中时显示 0.12s，按朝向翻转 `scale.x` |
| 血量 | 5 |
| 晕倒惩罚 | 损失一半金币，被抬回出生点，血量补满 |

**刷新器（PestSpawner）**：**只在夜晚出动**，天亮全部撤退。

- 每夜按「波」刷新：入夜**立刻**来第一波，之后每 8 秒一波
- 每波只数 = `DayCycle.wave_size()` = `base_wave_size + 天数 - 1`（上限 6）
- 场上上限 6 只
- 找不到 DayCycle 时退回 `always_active` 行为（给单元测试用）

---

## 6. 素材图集坐标

**kenney_tiny-farm/Tilemap/tilemap_packed.png**（192×176，12 列 × 11 行，每格 16px）

| 对象 | region_rect |
|---|---|
| 玩家 | `Rect2(16, 144, 16, 16)` |
| 温顺动物 | `Rect2(0, 160, 16, 16)` |
| 作物（按 growStage / plantType） | `Rect2(64 + 16*stage, 16*type, 16, 16)`，stage 0→4 即 x 从 64 到 128 |
| tree_1 | `Rect2(48, 0, 16, 32)` |
| 水桶 / 激活 | `Rect2(0, 96, 16, 16)` / `Rect2(16, 96, 16, 16)` |
| 水缸 / 激活 | `Rect2(32, 128, 32, 16)` / `Rect2(32, 144, 32, 16)` |

**kenney_tiny-dungeon/Tilemap/tilemap_packed.png**（同样 192×176 / 12×11）——已用 4 倍放大逐格确认过：

| 行 | 内容 |
|---|---|
| 行 9 (y144) | 绿史莱姆(0)、褐软泥(1)、红恶魔(2)、棕怪(3)、绿衣人(4)；后面是药水、武器 |
| 行 10 (y160) | 橙小怪(0)、幽灵(1)、暗红蜘蛛(2)、**獠牙野猪(3)**、绿菇怪(4)；后面是法杖 |

野猪用 **`Rect2(48, 160, 16, 16)`**。

全部素材为 **CC0（Kenney）**，各目录下有 `License.txt`。

---

## 7. 已知的坑与手工改文件规则

- **不要手改 `.godot/`**：生成目录，已 gitignore。
- ⚠️ **在编辑器之外新建 `class_name` 后，必须重新导入一次**，否则其他脚本会报
  `Parse Error: Could not find type "XXX" in the current scope`。
  命令：`godot --headless --path . --import`
- ⚠️ **`Node` 没有 `global_position`**（那是 `Node2D` 的属性）。需要坐标的节点必须 `extends Node2D`，
  否则是**解析期报错**（已踩过：`PestSpawner`）。
- **不要手写 UID**：`ext_resource` 不带 `uid` 也能正常加载（已实测），手工建场景可以只写 `path`。
- ⚠️ 每个脚本旁边的同名 `.uid` 文件**属于版本控制**；移动/重命名脚本时必须连 `.uid` 一起处理。
- 节点上的 `unique_id=` 是较新引擎字段，**手工新增节点时可以省略**（已实测）。
- 所有文本文件是 **LF**（`.gitattributes` 有 `* text=auto eol=lf`）。
- ⚠️ **Godot 内置字体不含中文字形**，Label 直接写中文会渲染成方块。本项目已引入中文字体解决：
  `Assets/fonts/fusion-pixel-12px-zh_hans.woff2` —— **Fusion Pixel Font 12px 简体**，像素风、**OFL 协议**
  （许可全文见同目录 `OFL-fusion-pixel-font.txt`），通过项目设置 `gui/theme/custom_font` 挂为全局默认字体。
  - **字号必须用 12**（该字体的设计尺寸），配合窗口的整数倍缩放才是像素对齐的；用别的字号会发糊。
  - 导入参数已刻意设成 `antialiasing=0 / hinting=0 / subpixel_positioning=0`（关抗锯齿、关微调、关次像素定位）。
    换成别的字体、或重新导入后，要确认这三项还在（实测运行时读回来就是 0/0/0）。
  - 正确验证方式：`label.get_theme_font("font").has_char("金".unicode_at(0))` ——
    查 **Label 实际取到的那个字体**，而不是 `ThemeDB.fallback_font`。
- ⚠️ 写死的节点路径（动 `base_level` 层级就会崩）：
  `land.gd` 的 `$"../level/Player"`、`$"../level/Static/Plants"`；
  `farm_controller.gd` 的 `$"../level/Static/Market"`。
- ⚠️ **`_ready` 是按兄弟节点顺序触发的**。若 A 在 `_ready` 里用**分组**查找 B，而 B 排在 A 后面，
  A 查到的必然是 null（B 还没执行 `add_to_group`）。已踩过：`PestSpawner` 找 `DayCycle`。
  稳的做法是**两件都做**：场景里把 B 排在前面，**同时**让 A 支持之后补查一次，不依赖顺序。
- `character.gd` 里的 `go()` / `dieOnCompany()` 和恒为 `false` 的 `workToAdd` 是**占位玩笑代码**。
- ⚠️ **测试必须掐掉存档**：`base_level` 上挂着 `SaveSystem`（默认启动自动读档 + 天亮自动存档）。
  其它测试实例化 `base_level` 时会读到玩家**真正的**存档，而 `test_daynight` 还会**覆盖**它。
  所有不测存档的测试，都要在第一帧之前设 `auto_load = false` 和 `auto_save_on_dawn = false`。
- ⚠️ 跑主场景冒烟测试前建议先删掉 `user://farm_save.json`，否则会从存档的天数继续，
  冒烟测试就不确定了。
- `game.tscn` 是空壳；`tree_2.tscn` / `tree_3.tscn` 没被任何场景引用。
- 动物状态里 `speed` 在 `Update()` 每帧重新随机——速度一直在抖，疑似写错位置（野猪没这问题）。
- ⚠️ **测试里必须手动补 `Level.animalRegion`**：测试场景不是主场景，自动加载 `Level` 的 `_ready`
  在 `base_level` 实例化之前就跑完了，拿不到导航区域；不补的话动物切到 Move 状态会报
  `Invalid access to property 'navigation_polygon' on null instance`。

---

## 8. 当前进度

**已能玩**
- 玩家 WASD 移动 + Idle/Move 状态切换 + 动画
- 农场动物随机漫游
- **手持道具系统**：Q 切换 种子袋 / 水壶 / 收获篮 / 剑，HUD 实时显示
- **完整农场循环**：播种 → 浇水 → 逐级生长 → 成熟 → 收获
- **经济循环**：在商店（房子）里卖作物、买种子
- **战斗循环**：**夜晚**野猪成群来袭啃作物，用剑砍跑它；被顶会掉血；晕倒损失一半金币；天亮野猪撤退
- **昼夜循环**：45 秒一天，夜晚画面变暗，难度随天数爬坡
- **目标**：攒够 300 金建成谷仓
- **存档**：天亮自动存、启动自动读，F5/F9/F10 手动控制
- 水壶容量与水源自动补水
- HUD：**中文界面**，显示 金币 / 血量 / 种子 / 作物 / 水量 / 手持物

**没做（打磨项）**
- 只有一种作物（`current_crop_type` 恒为 0）
- `Land` 的 terrain 1 在图集里定义好了但没代码使用
- 音效、动画（攻击只有一刀白光）
- 存档
- 野猪只是"啃掉作物"，没有更复杂的行为

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
& $godot --headless --path . --fixed-fps 60 res://Tests/test_plant.tscn --quit-after 3000 2>&1 | Out-String

# 2) 农场 + 经济端到端（45 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_farm.tscn --quit-after 3000 2>&1 | Out-String

# 3) 战斗端到端（30 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_combat.tscn --quit-after 3000 2>&1 | Out-String

# 4) 昼夜 + 夜晚来袭 + 目标（26 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_daynight.tscn --quit-after 4000 2>&1 | Out-String

# 5) 存档（34 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_save.tscn --quit-after 4000 2>&1 | Out-String

# 6) 跑主场景 100 秒（约 2.2 个昼夜），抓运行时错误
& $godot --headless --path . --fixed-fps 60 --quit-after 6000 2>&1 | Out-String
```

合计 149 项断言。

要点：
- `--fixed-fps 60` 让时间步长确定，定时器/生长/移动行为可复现。
- `--quit-after N` 是**帧数**，不是秒；配合 `--fixed-fps 60` 时 1800 帧 = 30 秒。
- 测试脚本用 `_check(说明, 条件)` 打印 `PASS`/`FAIL`，结尾打印 `RESULT fail=N`。
- 端到端测试**尽量走 `FarmController.use_held_item()`**（玩家真实路径），而不是直接调底层方法。
- 需要 Area2D 检测（商店/水源）时，把玩家 `global_position` 挪过去后要 `await physics_frame` 若干帧。
- 注入故障后引擎会打出带 `文件:行号` 和 GDScript 调用栈的 `ERROR`，**验证链路可信**（已实测）。

### 查文档，别凭记忆

- 首选编辑器内置帮助（F1）。
- 在线：<https://docs.godotengine.org/en/4.7/>
- 破坏性变更：<https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html>

---

## 10. 路线图

| # | 目标 | 状态 |
|---|---|---|
| 1 | 浇水 → 成熟 → 收获 闭环 | ✅ |
| 2 | 手持道具概念（Q 切换 + 单动作键分发） | ✅ |
| 3 | 经济：卖作物、买种子、商店交互 | ✅ |
| 4 | 战斗：野猪啃作物 + 剑 + 血量 + 刷新器 | ✅ |
| 5 | 中文 UI（Fusion Pixel Font 12px，OFL） | ✅ |
| 6 | 昼夜循环 + 夜晚成群来袭 + 目标 | ✅ |
| 7 | **存档系统**（天亮自动存 / 启动自动读 / F5 F9 F10） | ✅ |
| 8 | 打磨：多种作物、音效、攻击动画 | ⬜ 下一步 |
