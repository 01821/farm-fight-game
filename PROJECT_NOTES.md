# farmAndFightGame — 开工须知

> 给协作者（尤其是 AI 助手）的上下文备忘。**动代码前先读这份，改完顺手更新。**
> 最后更新：建立仓库当天，对应基线提交 `409c19c`。

---

## 1. 项目身份

| 项 | 值 |
|---|---|
| 项目名 | `farmAndFightGame` |
| 引擎 | **Godot 4.7.1-stable**（Windows 版，`E:/godot/Godot_v4.7.1-stable_win64.exe`） |
| 主场景 | `res://Scenes/base_level.tscn`（`uid://btccb47s76sxj`） |
| 自动加载 | `Level` → `res://Scripts/Global/Level.gd`（`uid://cp5eslpyr05f4`） |
| 渲染 | Forward Plus；Windows 驱动 `d3d12` |
| 物理 | 3D 引擎设成了 Jolt —— **当前项目是纯 2D，这项暂时无意义** |
| 像素风 | 视口 400×300，窗口 1600×1200；`canvas_items` + `expand` + `integer` 缩放；纹理过滤 = nearest |
| 版本控制 | git，默认分支 `main`；`.godot/` 和 `/android/` 已忽略 |

---

## 2. 目录约定

```
Assets/kenney_tiny-{dungeon,farm,town}/   第三方素材（CC0，Kenney），按包名分目录
Scenes/                                   所有场景，按类型分子目录
  base_level.tscn                         ← 真正的主场景（地图+树木+建筑+角色）
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
  plants/base_plant.gd                    作物生长
  TileMap/land.gd                         种植交互
```

---

## 3. 输入与物理层

**输入动作**（`project.godot`，方向键用 physical keycode，所以任何键盘布局都是 WASD）

| 动作 | 键 |
|---|---|
| `up` / `down` / `left` / `right` | W / S / A / D |
| `plant` | P |

**2D 物理层命名**

| 层 | 名字 |
|---|---|
| 1 | Static |
| 2 | Player |
| 3 | Animal |
| 4 | Plant |

> 碰撞中 `collision_layer`/`collision_mask` 请用这些语义，别写裸数字。

---

## 4. 运行时场景树（`base_level.tscn`）

```
baseLevel (Node2D)
├── background (Sprite2D)          img_white.png 拉伸成底色，modulate 绿
├── Sample (Sprite2D)              kenney_tiny-farm 的 sample.png，视觉参考用
├── Grass (TileMapLayer)           图集 = kenney_tiny-town/tilemap_packed.png
├── Land (TileMapLayer)            图集 = kenney_tiny-farm/tilemap_packed.png
│      script = land.gd
│      terrain_set 0: terrain 0 = 耕地, terrain 1 = 已浇水的耕地(?)
│      physics_layer_0/collision_layer = 1 (Static)
│      group: navigation_polygon_source_geometry_group
└── level (Node2D, y_sort)
    ├── Static (Node2D, y_sort)
    │   ├── Trees/                100+ 个 tree_1.tscn 实例
    │   ├── Plants/               ← 运行时种植的作物挂在这里（初始为空）
    │   ├── house, waterBucket, WaterContainer
    ├── Animals/                  base_animal.tscn 实例（1 只）
    ├── Player                    player.tscn 实例
    └── animalRegion2D (NavigationRegion2D)   group: animalRegion，动物导航用
```

---

## 5. 核心架构

### 角色 + 状态机

```
Character (CharacterBody2D)      Scripts/Characters/character.gd
├── player.gd       extends Character   读输入
└── base_animal.gd  extends Character   持有 move_timer

Character 的子节点结构（player.tscn / base_animal.tscn 都是这套）：
  Sprite2D, StateMachine(Node), AnimationPlayer, debugLabel, CollisionShape2D
  动物额外有 NavigationAgent2D + MoveTimer
```

- `state_machine.gd`：**子节点即状态**。`_ready` 里给每个子节点注入 `stateMachine` 和 `character`，然后默认进入 `get_child(0)`。
- `State.gd`：基类，钩子 `Enter / Update / UpdatePhysics / Exit / Ready`。
- 切换用 `stateMachine.SwitchTo("Move")` —— **按节点名查找**。

> ⚠️ **三个名字必须一模一样**：`StateMachine` 下的节点名 == `SwitchTo()` 的字符串 == `AnimationPlayer` 里的动画名。
> 因为 `Character.UpdateAnimation()` 直接 `animation_player.play(state_machine.currentState.name)`。
> 再加状态时，三处一起加。

### 种植链路

- `land.gd` 监听 `plant` 动作 → `local_to_map(to_local(player.global_position))` 拿格子 → 校验：
  1. 该格有 tile 数据；
  2. `terrain_set == 0 and terrain == 0`（必须是耕地）；
  3. 不在 `planted_tiles` 里（防重复种植）。
- 通过后实例化 `base_plant.tscn`（`uid://orgflfd17epj`），`plantType = current_crop_type`，挂到 `level/Static/Plants`。
- `base_plant.gd` 用 Sprite2D 的 `region_rect` 换帧：`Rect2(64 + 16*growStage, 16*plantType, 16, 16)`，`growTime` 秒升一级，0→4 停表。

---

## 6. 素材图集坐标（kenney_tiny-farm/Tilemap/tilemap_packed.png）

单格 16×16，图集 12 列。已用的 `region_rect`：

| 对象 | region_rect |
|---|---|
| 玩家 | `Rect2(16, 144, 16, 16)` |
| 动物 | `Rect2(0, 160, 16, 16)` |
| 作物（按 growStage / plantType 算） | `Rect2(64 + 16*stage, 16*type, 16, 16)` |
| tree_1 | `Rect2(48, 0, 16, 32)` |
| 水桶 / 水桶(激活) | `Rect2(0, 96, 16, 16)` / `Rect2(16, 96, 16, 16)` |

全部素材为 **CC0（Kenney）**，各目录下有 `License.txt`。

---

## 7. 已知的坑与手工改文件规则

- **不要手改 `.godot/`**：那是生成目录，已 gitignore。
- **不要手写 UID**：`.tscn`/`.tres` 里节点带 `unique_id=`、场景头有 `format=3/4`，`uid://` 由编辑器生成。新增资源让编辑器写，别自己编。
- 资源引用优先用 `uid://`（本项目已全面使用，改名/移动文件不容易断）—— 但**人肉改路径时不要同时改 uid**，二者对不上会加载失败。
- 所有文本文件是 **LF**，`.gitattributes` 有 `* text=auto eol=lf`，别改成 CRLF。
- `land.gd` 里节点路径是写死的 `$"../level/Player"`、`$"../level/Static/Plants"` —— **动 `base_level` 的层级就会崩**。
- `character.gd` 里的 `go()` / `dieOnCompany()` 和恒为 `false` 的 `workToAdd` 是**占位玩笑代码，不是真逻辑**，别被误导。
- `base_plant.gd` 里 `growStage == 3` 会直接跳到 `4`（少一帧），是硬编码补丁。
- `game.tscn` 是空壳；`tree_2.tscn` / `tree_3.tscn` 没被任何场景引用。
- 动物状态里 `speed` 在 `Update()` 每帧重新随机（`randi_range`）—— 意味着速度一直在抖，看着像是"想做成随机步速但写错了位置"。

---

## 8. 当前进度

**能用**
- 玩家 WASD 移动 + Idle/Move 状态切换 + 动画
- 动物 Idle/Move + `NavigationAgent2D` 随机漫游
- 按 P 在耕地格种下作物，作物按计时器长到第 4 帧
- 地图：草地、耕地（带碰撞与地形标记）、100+ 树、房子

**半成品（有资源没逻辑）**
- `water_bucket.tscn` / `water_container.tscn`：有 `ActiveSprite` 双贴图，**没有脚本**，浇水逻辑完全没接
- `plantType` 有字段但 `current_crop_type` 恒为 0，只有一种作物
- `Land` 的 terrain 1（第二种地形）在图集里定义好了，但没代码使用

**没做**
- 收获、库存、金钱/经济
- 战斗（项目名里的 `Fight` 一行代码都没有）
- 存档、UI、音效

---

## 9. 协作方式（给 AI 助手）

1. **一次只改一小块**，改完让人在编辑器里按 F5 跑一遍再继续。
2. **报错请贴完整原文**（含 `文件:行号`）—— 比任何描述都准。
3. **大改动前先 commit**，脏了随时 `git checkout .` 回退。
4. **查文档，别凭记忆**：
   - 首选**编辑器内置帮助（F1）**——版本一定对得上。
   - 在线：<https://docs.godotengine.org/en/4.7/>
   - 遇到"这个 API 行为好像变了"，先看 <https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html>
   - 本项目引擎版本（4.7）比多数教程/模型训练数据都新，**社区教程大多是 3.x 或 4.0–4.3 的，默认不可信**。
5. 涉及 `.tscn`/`.tres`/`.import` 的手工编辑，先查文件格式文档，再动手。

---

## 10. 路线图

按顺序做，每一步都要能跑通、能看见结果，再进下一步。

| # | 目标 | 为什么这个顺序 |
|---|---|---|
| 1 | **浇水 → 成熟 → 收获** 闭环（先不接经济） | 把三个半成品串起来，建立"能验证"的开发节奏 |
| 2 | **手持道具**概念（水桶/种子/作物） | 浇水、播种、收获都要问"手里拿的是什么"，没这个抽象后面每加一个交互都要打补丁 |
| 3 | **经济**：收获入库、卖钱、买种子 | 循环闭合，游戏才"能玩" |
| 4 | **战斗** | 依赖数值系统和"为什么要打"的设计前提；先做会变成一堆打空气的动画 |
