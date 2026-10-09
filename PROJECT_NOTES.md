# farmAndFightGame — 开工须知

> 给协作者（尤其是 AI 助手）的上下文备忘。**动代码前先读这份，改完顺手更新。**

---

## 1. 项目身份

| 项 | 值 |
|---|---|
| 项目名 | `farmAndFightGame` |
| 引擎 | **Godot 4.7.1-stable**（Windows 版，`E:/godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe`） |
| 主场景 | `res://Scenes/base_level.tscn`（`uid://btccb47s76sxj`） |
| 自动加载 | `Level` → `res://Scripts/Global/Level.gd`（缓存 `level/animalRegion2D` 供动物导航使用） |
| 渲染 | Forward Plus；Windows 驱动 `d3d12` |
| 物理 | 3D 引擎设成了 Jolt —— **当前项目是纯 2D，这项无意义** |
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
  buildings/{house,water_bucket,water_container}.tscn
Scripts/
  Global/Level.gd                         自动加载单例
  Characters/{character,player,base_animal}.gd
  State/{State,state_machine}.gd          状态机基础设施
  State/{Player,animal}/{idle,move}.gd    具体状态
  plants/base_plant.gd                    作物：浇水驱动生长
  TileMap/land.gd                         耕地层：播种 / 浇水 / 收获
  buildings/water_source.gd               水源：靠近自动补水
  UI/hud.gd                               左上角状态栏
Tests/                                    一次性自测场景（开发用，见第 9 节）
```

---

## 3. 输入与物理层

**输入动作**（方向键用 physical keycode，所以任何键盘布局都是 WASD）

| 动作 | 键 | 用途 |
|---|---|---|
| `up` / `down` / `left` / `right` | W / S / A / D | 移动 |
| `plant` | P | 在当前格播种 |
| `water` | F | 给当前格的作物浇水 |
| `harvest` | E | 收获当前格成熟作物 |

**2D 物理层命名**

| 层 | 名字 | 谁在用 |
|---|---|---|
| 1 | Static | 地形碰撞、树的 TileSet 多边形 |
| 2 | Player | 玩家（水源 Area2D 的 mask 就是这层） |
| 3 | Animal | 动物 |
| 4 | Plant | 作物 |

> 碰撞里请用这些语义，别写裸数字。

---

## 4. 运行时场景树（`base_level.tscn`）

```
baseLevel (Node2D)
├── background (Sprite2D)          img_white.png 拉伸成底色
├── Sample (Sprite2D)              kenney_tiny-farm 的 sample.png，视觉参考
├── Grass (TileMapLayer)           图集 = kenney_tiny-town/tilemap_packed.png
├── Land (TileMapLayer)            图集 = kenney_tiny-farm/tilemap_packed.png
│      script = land.gd
│      terrain_set 0: terrain 0 = 耕地（浇水/种植都要求 terrain 0）
│      physics_layer_0/collision_layer = 1 (Static)
│      group: navigation_polygon_source_geometry_group
├── HUD (CanvasLayer)              script = hud.gd
│   ├── Backdrop (ColorRect)       半透明黑底
│   ├── InfoLabel (Label)          水/种子/收成/金币
│   └── HintLabel (Label)          按键提示
└── level (Node2D, y_sort)
    ├── Static (Node2D, y_sort)
    │   ├── Trees/                100+ 个 tree_1.tscn 实例
    │   ├── Plants/               ← 运行时种植的作物挂在这里（初始为空）
    │   ├── house, waterBucket, WaterContainer   后两者是水源
    ├── Animals/                  base_animal.tscn 实例（1 只）
    ├── Player                    player.tscn 实例
    └── animalRegion2D (NavigationRegion2D)   group: animalRegion
```

---

## 5. 核心架构

### 角色 + 状态机

```
Character (CharacterBody2D)      Scripts/Characters/character.gd
├── Player       class_name Player      移动输入 + 农场状态
└── base_animal.gd  extends Character   持有 move_timer

子节点结构（player.tscn / base_animal.tscn 都一样）：
  Sprite2D, StateMachine(Node), AnimationPlayer, debugLabel, CollisionShape2D
  动物额外有 NavigationAgent2D + MoveTimer
```

- `state_machine.gd`：**子节点即状态**。`_ready` 注入 `stateMachine`/`character`，默认进 `get_child(0)`。
- 切换用 `stateMachine.SwitchTo("Move")` —— **按节点名查找**。

> ⚠️ **三个名字必须一模一样**：`StateMachine` 下的节点名 == `SwitchTo()` 的字符串 == `AnimationPlayer` 里的动画名。
> 因为 `Character.UpdateAnimation()` 直接 `play(state_machine.currentState.name)`。新增状态时三处一起加。

### 农场循环（当前的核心玩法）

规则（全部在 `land.gd` 的 `try_*_at()` 里，可被测试直接调用）：

1. **播种**：站在耕地格按 `P`。要求 terrain 0、该格没种过、`player.seeds > 0`。扣 1 粒种子，实例化 `base_plant.tscn` 挂到 `level/Static/Plants`。
2. **种下后不会自己生长**。
3. **浇水**：按 `F`。要求该格有作物、未成熟、水壶有水。`plant.water()` 成功则扣 1 点水，该格出现蓝色湿痕。
4. **生长**：浇水后 `growTime`（默认 3 秒）升 **一级**，然后**自动变干**——下一级要再浇一次。
5. **成熟**：`growStage` 到 4 即为成熟（`is_mature()`），不能再浇。
6. **收获**：按 `E`，作物销毁，`player.harvested += 1`，格子空出可重种。
7. **补水**：站进水源（waterBucket / WaterContainer）的 `InteractionArea`，水壶自动补满（容量 `Player.WATER_CAPACITY = 5`），此时水源的 `ActiveSprite` 显示出来作为提示。

玩家初始状态：`money = 20`、`seeds = 8`、`harvested = 0`、`water_left = 0`。

### 数据流

- 作物状态（阶段/是否浇过水）**归作物自己管**，`land.gd` 只持有 `plants: Dictionary[Vector2i -> BasePlant]`。
- 玩家状态（水/种子/收成/钱）归 `Player`。
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
- 节点上的 `unique_id=` 是较新引擎的字段，**手工新增节点时可以省略**（已实测可加载）。
- 所有文本文件是 **LF**，`.gitattributes` 有 `* text=auto eol=lf`，别改成 CRLF。
- ⚠️ **Godot 内置字体不含中文字形**（已用 `ThemeDB.fallback_font.has_char("水")` 实测 = false）。
  所以 HUD/`debugLabel` 等 Label **不能用中文**，会渲染成方块。要中文必须往项目里放一个 CJK 字体（如思源黑体/Noto Sans SC）。
- ⚠️ `land.gd` 里节点路径是写死的 `$"../level/Player"`、`$"../level/Static/Plants"` —— **动 `base_level` 层级就会崩**。
- `character.gd` 里的 `go()` / `dieOnCompany()` 和恒为 `false` 的 `workToAdd` 是**占位玩笑代码，不是真逻辑**。
- `game.tscn` 是空壳；`tree_2.tscn` / `tree_3.tscn` 没被任何场景引用。
- 动物状态里 `speed` 在 `Update()` 每帧重新随机（`randi_range`）—— 速度一直在抖，疑似写错位置。

---

## 8. 当前进度

**已能玩**
- 玩家 WASD 移动 + Idle/Move 状态切换 + 动画
- 动物 Idle/Move + `NavigationAgent2D` 随机漫游
- **完整农场循环：播种 → 浇水 → 逐级生长 → 成熟 → 收获 → 计数**
- 水壶容量与水源自动补水
- 左上角 HUD 实时显示水 / 种子 / 收成 / 金币

**半成品**
- `plantType` 有字段但 `current_crop_type` 恒为 0，只有一种作物
- 金币有数值但**没有任何用途**（还不能买卖）
- `Land` 的 terrain 1 在图集里定义好了，但没代码使用

**没做**
- 经济（买种子 / 卖作物 / 商店）
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

# 2) 农场端到端自测（25 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_farm.tscn --quit-after 2400 2>&1 | Out-String

# 3) 跑主场景 15 秒，抓运行时错误
& $godot --headless --path . --fixed-fps 60 --quit-after 900 2>&1 | Out-String
```

要点：
- `--fixed-fps 60` 让时间步长确定，定时器/生长行为可复现。
- `--quit-after N` 是**帧数**，不是秒；配合 `--fixed-fps 60` 时 900 帧 = 15 秒。
- 测试脚本用 `_check(说明, 条件)` 打印 `PASS`/`FAIL`，结尾打印 `RESULT fail=N`。
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
| 1 | 浇水 → 成熟 → 收获 闭环 | ✅ 已完成 |
| 2 | 经济：卖作物赚钱、买种子、商店交互 | ⬜ 下一步 |
| 3 | 战斗：会来破坏农场的敌人 + 玩家攻击 | ⬜ |
| 4 | 打磨：多种作物、音效、中文 UI（需先放 CJK 字体）、存档 | ⬜ |
