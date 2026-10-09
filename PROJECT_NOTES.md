# farmAndFightGame �?开工须�?
> 给协作者（尤其�?AI 助手）的上下文备忘�?*动代码前先读这份，改完顺手更新�?*

---

## 1. 项目身份

| �?| �?|
|---|---|
| 项目�?| `farmAndFightGame` |
| 引擎 | **Godot 4.7.1-stable**（Windows 版，`E:/godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe`�?|
| 主场�?| `res://Scenes/base_level.tscn`（`uid://btccb47s76sxj`�?|
| 自动加载 | `Level` �?`res://Scripts/Global/Level.gd`（缓�?`level/animalRegion2D` 供动物导航）<br>`Sfx` �?`res://Scenes/global/sfx.tscn`（音效，全局 `Sfx.play("hit")`�?br>`Progression` �?`res://Scripts/Global/Progression.gd`（成长与专精，全局 `Progression.add_xp(...)`�?|
| 渲染 | Forward Plus；Windows 驱动 `d3d12` |
| 像素�?| 视口 400×300，窗�?1600×1200；`canvas_items` + `expand` + `integer` 缩放；纹理过�?= nearest |
| 版本控制 | git，`main` 分支；远�?`origin` = https://github.com/01821/farm-fight-game.git�?*公开仓库**）；`.godot/`、`/android/` 已忽�?|

---

## 2. 目录约定

```
Assets/kenney_tiny-{dungeon,farm,town}/   第三方素材（CC0，Kenney�?Assets/fonts/                             Fusion Pixel Font 12px 简体（OFL），UI 中文字体
Assets/sounds/                            音效 WAV，由 Tools/gen_sfx.gd 合成（可重跑�?Scenes/                                   所有场景，按类型分子目�?  base_level.tscn                         �?真正的主场景
  game.tscn                               ⚠️ 空壳遗留，只有一�?Node2D
  global/sfx.tscn                         音效单例场景（内�?10 个预建的 AudioStreamPlayer�?  character/player.tscn
  animals/base_animal.tscn                温顺的农场动�?  animals/pest.tscn                       害兽（敌人），贴图取�?kenney_tiny-dungeon
  plants/{base_plant,tree_1,tree_2,tree_3}.tscn
  buildings/{house,water_bucket,water_container}.tscn   house = 商店
Scripts/
  Global/Level.gd                         自动加载单例
  Global/DayCycle.gd                      class_name DayCycle：昼夜循�?  Global/PestSpawner.gd                   class_name PestSpawner：夜晚放野猪
  Global/SaveSystem.gd                    class_name SaveSystem：存�?/ 读档
  Global/Weather.gd                       class_name Weather：天气（雨天自动浇灌�?  Global/Achievements.gd                  class_name Achievements：成�?  Global/sfx.gd                           自动加载单例 Sfx：播放音�?  Global/Progression.gd                   自动加载单例 Progression：三系成长与专精
  ../Tools/gen_sfx.gd                     一次性音效合成器（不�?Scripts 下）
  ../Tools/analyze_crops.gd               一次性像素分析：判定作物阶段列映�?  Characters/{character,player,base_animal}.gd
  Characters/pest.gd                      class_name Pest：害兽，种类�?PestData 配置
  Characters/pest_data.gd                 class_name PestData：害兽数据表
  State/{State,state_machine}.gd          状态机基础设施
  State/{Player,animal}/{idle,move}.gd    具体状�?  plants/base_plant.gd                    作物：浇水驱动生�?  plants/crop_data.gd                     class_name CropData：作物数据表（价�?/ 生长 / 图集列）
  TileMap/land.gd                         class_name FarmLand：播�?浇水/收获规则
  buildings/water_source.gd               水源：靠近自动补�?  buildings/market.gd                     class_name Market：商店买�?  Interaction/farm_controller.gd          class_name FarmController：动作键分发中心
  UI/hud.gd                               左上角状态栏
Tests/                                    一次性自测场景（开发用，见�?9 节）
```

**常用分组（group�?*：`farm_land`、`player`、`pest`、`pest_spawner`、`animalRegion`�?脚本之间靠这些组找彼此，避免写死跨场景路径�?
---

## 3. 输入与物理层

**输入动作**（方向键�?physical keycode，所以任何键盘布局都是 WASD�?
| 动作 | �?| 用�?|
|---|---|---|
| `up` / `down` / `left` / `right` | W / S / A / D | 移动 |
| `cycle_item` | **Q** | 切换手持道具 |
| `use_item` | **F** | 使用手持道具（唯一动作键） |
| `quick_save` | **F5** | 手动存档 |
| `quick_load` | **F9** | 读档 |
| `delete_save` | **F10** | 删除存档（下次启动就是新游戏�?|
| `seed_1` �?`seed_5` | **1** �?**5** | 选择作物种类（播种和买种子都用它�?|

**2D 物理层命�?*

| �?| �?| 名字 | 谁在�?|
|---|---|---|---|
| 1 | 1 | Static | 地形碰撞 |
| 2 | 2 | Player | 玩家（水�?/ 商店 Area2D �?mask�?|
| 3 | 4 | Animal | 动物、野�?|
| 4 | 8 | Plant | 作物 |

> 碰撞里请用这些语义，别写裸数字�?
---

## 4. 运行时场景树（`base_level.tscn`�?
```
baseLevel (Node2D)
├── background / Sample (Sprite2D)
├── Grass (TileMapLayer)                图集 = kenney_tiny-town
├── Land (TileMapLayer)                 �? script = land.gd (FarmLand)
�?     terrain_set 0: terrain 0 = 耕地（种�?浇水都要�?terrain 0�?�?     physics_layer_0/collision_layer = 1 (Static)
�?     groups: navigation_polygon_source_geometry_group, farm_land
├── HUD (CanvasLayer)                   script = hud.gd
�?  ├── Backdrop / InfoLabel / FarmLabel / HeldLabel / KeyLabel（四行状态）
�?  └── BannerBackdrop + Banner（达成目标时亮出的横幅，平时 visible = false�?�?  └── ToastBackdrop + Toast（成就提示条，底部居中，默认隐藏�?�?  └── PerkBackdrop + PerkTitle + PerkOption1/2（升级二选一面板，默认隐藏）
├── FarmController (Node)               script = farm_controller.gd �?F 键分�?+ 目标判定
├── NightTint (CanvasModulate)          夜晚压暗画面（HUD �?CanvasLayer 上，不受影响�?├── DayCycle (Node)                     script = DayCycle.gd �?昼夜循环
├── SaveSystem (Node)                   script = SaveSystem.gd �?存档 / 读档
├── Weather (Node)                      script = Weather.gd �?天气
├── Achievements (Node)                 script = Achievements.gd �?成就
├── PestSpawner (Node2D)                script = PestSpawner.gd，boar_scene 指向 boar.tscn
└── level (Node2D, y_sort)
    ├── Static (Node2D, y_sort)
    �?  ├── Trees/                      100+ �?tree_1.tscn 实例（没有碰撞）
    �?  ├── Plants/                     �?运行时种植的作物挂在这里
    �?  ├── Market                      �?house.tscn 实例，带 Area2D，是商店
    �?  ├── waterBucket / WaterContainer  �?水源（Area2D�?    ├── Animals/                        base_animal.tscn 实例�? 只）
    ├── Player                          player.tscn 实例
    └── animalRegion2D (NavigationRegion2D)   group: animalRegion
```

---

## 5. 核心架构

### 角色 + 状态机

```
Character (CharacterBody2D)      Scripts/Characters/character.gd
├── Player       class_name Player      移动 + 农场状�?+ 手持道具
└── base_animal.gd  extends Character   持有 move_timer

Boar 是独立的 CharacterBody2D（不继承 Character —�?Character �?@onready 需�?AnimationPlayer / StateMachine 等子节点，野猪场景没有，会直接报错）
```

- `state_machine.gd`�?*子节点即状�?*，`SwitchTo()` 按节点名查找�?
> ⚠️ **三个名字必须一模一�?*：`StateMachine` 下的节点�?== `SwitchTo()` 的字符串 == `AnimationPlayer` 里的动画名�?
### 手持道具模型

玩家手上永远只有一样东西，`Q` 循环切换�?
| 手持 | 说明 |
|---|---|
| `Player.Item.SEED` | 种子�?|
| `Player.Item.WATER_CAN` | 水壶（`water_left`，容�?5�?|
| `Player.Item.BASKET` | 收获篮（`player.harvested`�?|
| `Player.Item.SWORD` | �?|

**只有一个动作键 `F`**，效果由「手持道�?+ 所在位置」决定，全部逻辑�?`FarmController.use_held_item()`�?
| 手持 | 位置 | F 的效�?|
|---|---|---|
| 种子�?| 耕地�?| 播种（扣 1 种子�?|
| 种子�?| 商店范围�?| �?1 粒种子（�?3 金） |
| 水壶 | 有作物的�?| 浇水（扣 1 水） |
| 收获�?| 成熟作物�?| 收获（作物进篮子�?|
| 收获�?| 商店范围�?| 卖掉篮子里全部作物（每个 +5 金） |
| �?| 任意位置 | 砍范围内所有野�?|
| 其它 | 商店范围�?| 无效，给提示 |

> 注意 **商店优先**：站在商店范围内即使脚下是耕地，也走交易而不是播种�?
### 农场循环规则

1. **播种**要求：terrain 0 的耕地、该格没种过、手上有**当前选中种类**的种子�?2. 种下�?*种类**�?`player.seed_type` 决定（按 **1-5** 切换）�?3. **种下后不会自己生�?*�?4. **浇水**后该格出现蓝色湿痕（`WetMark`）�?5. `CropData.grow_time(种类)` 秒后�?**一�?* �?*自动变干**——下一级要再浇一次�?6. `growStage` �?`CropData.MAX_STAGE`�?）即成熟，不能再浇�?7. **收获**后按种类计入篮子，格子空出可重种�?
### 作物表（`Scripts/plants/crop_data.gd`�?
种类 id **就是图集行号**�?
| id | 名称 | 图集�?| 种子�?| 收购�?| 每级秒数 | 满级总时�?| 单株利润 | 利润/�?| **解锁** |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 胡萝�?| 0 | 3 | 6 | 2.0 | 8.0s | 3 | 0.38 | �?1 �?|
| 1 | 紫甘�?| 1 | 5 | 11 | 2.8 | 11.2s | 6 | 0.54 | �?2 �?|
| 2 | 玉米 | 2 | 8 | 19 | 3.6 | 14.4s | 11 | 0.76 | �?3 �?|
| 3 | 番茄 | 3 | 12 | 30 | 4.6 | 18.4s | 18 | 0.98 | �?5 �?|
| 4 | 卷心�?| 4 | 18 | 48 | 5.6 | 22.4s | 30 | 1.34 | �?7 �?|

越贵的作�?*单位时间收益越高**，但前期投入大、占田时间长（夜里更容易被野猪啃）。这就是种植选择的意义�?
**作物按天数解�?*（`min_day`）：开局只有胡萝卜，之后每天天亮多一种�?每次解锁都是一次小奖励，也把复杂度摊开 —�?而不是一上来就丢给玩�?5 个选择�?- 商店只卖已解锁的（`Market.buy_seed` 会挡�?- �?`1-5` 选未解锁的会被拒绝并提示"要第 N 天才开�?
- 天亮时自动打一�?`[解锁] 新作物：...`
- 相关函数：`CropData.is_unlocked(id, day)` / `unlocked_kinds(day)` / `next_locked(day)`

### 成长与专精（`Progression` 自动加载单例�?
三个系各自攒经验、升级，升级�?*二选一**拿专精，**不可更改**�?
| �?| 经验来源 |
|---|---|
| 农�?| 每收�?1 个作�?+1 |
| 战斗 | 每赶�?1 只害�?+1 |
| 经营 | 每卖出一�?+1，之后每 10 金再 +1 |

升级阈�?`LEVEL_STEPS = [3, 8]`（两级，每级对应一层专精）�?
| �?| 第一次选择 | 第二次选择 |
|---|---|---|
| 农�?| **农夫** 售价 +20% / **园丁** 浇水覆盖周围 3x3 | **育种�?* 生长时间 -25% / **囤积�?* 25% 概率多收一�?|
| 战斗 | **剑客** 攻击范围 +40% / **铁壁** 最大生�?+3 | **处决�?* 对满血敌人伤害翻�?/ **猎手** 赏金翻�?|
| 经营 | **商人** 种子便宜 30% / **储户** 每天天亮 +5 �?| **批发** 卖光额外 +15% / **保险** 晕倒不掉钱 |

设计要点�?- **每个选项改变的是"你每天怎么�?，不�?数字 +5%"**。园丁（范围浇水）和农夫（卖价高）是两套节奏�?- **不可�?*才有取舍，才�?下一局走另一条路"的重玩价值�?- 专精效果**不写成一堆散落的 `if has_perk`**，而是集中成一组查询函�?  （`sell_multiplier()` / `water_radius()` / `grow_time_multiplier()` / `max_hp_bonus()` …）�?  各系统问一句就行�?*加新专精 = PERKS 加一�?+ 查询函数加一行�?*
- 升级�?HUD 中央弹出二选一面板�?*这时 1/2 �?选专�?而不�?选作�?**�?  路由�?`FarmController._unhandled_input` 最前面�?- `Progression.force_perk(id)` 可以绕过等级直接给专精（测试/调试用）；`enabled = false` 可以静音弹窗�?
### 经济与目�?
初始金币 20�? 粒胡萝卜种子。种子和收获物都�?*按种类分开计数**的数组（`player.seeds` / `player.harvested`，下标就是种�?id）�?
**目标**：金币达�?`FarmController.GOLD_GOAL = 300` 即判定「建成谷仓」（`goal_reached` 置位，HUD 显示"目标已达成！"）�?
### 昼夜循环

| �?| �?|
|---|---|
| 一天长�?| `DayCycle.day_length = 45` �?|
| 白天占比 | `day_ratio = 0.6`（前 27 秒白天，�?18 秒夜晚） |
| 画面明暗 | 夜晚用预建的 `NightTint`(CanvasModulate) 渐变�?`Color(0.42, 0.48, 0.72)`，渐�?`FADE_TIME = 2` �?|
| 波次规模 | `base_wave_size(2) + 天数 - 1`，上�?`max_wave_size(6)` |

- **HUD 不会被压�?*：HUD 挂在 `CanvasLayer` 上，属于另一块画布，`CanvasModulate` 管不到它�?- `DayCycle.running = false` 可冻结时间（测试用）�?- 场上没作物时野猪会自己离开（`GIVE_UP_TIME` 6 秒）——所�?不种地就没有夜间威胁"是设计使然，不是 bug�?
### 存档

`SaveSystem`（挂�?`base_level` 上）把状态写成一�?JSON：`user://farm_save.json`
（Windows 实机路径 `%APPDATA%\Godot\app_userdata\farmAndFightGame\farm_save.json`，约 300 字节）�?
| �?| 作用 |
|---|---|
| **F5** | 手动存档 |
| **F9** | 读档 |
| **F10** | 删除存档（下次启动就是新游戏�?|

- **天亮自动存档**（接的是 `DayCycle.day_started` 信号）；**启动自动读档**�?- 自动读档刻意**延后到第一帧的 `_process`**，而不�?`_ready`。这样测试可以在 `add_child`
  之后、第一帧之前把 `save_path` 换成临时文件——既测到真实读档路径，又不会碰玩家存档�?- 存的内容：天数与当天进度、玩家（金币/血�?水量/种子/篮子/手持�?坐标）�?  地块上每一株作物（类型、生长阶段、是否浇过水）、目标进度�?- **只存 `elapsed`，不�?`is_night`**：时段在读取时由 `elapsed` 重新推导，免得存档里出现
  自相矛盾的组合�?- 存档�?`version` 字段�?*版本不符�?JSON 损坏时拒绝读取并给提示，不会�?*�?- 各系统通过 `to_save_data()` / `apply_save_data()` 参与存档；以后新增系统照这个模式接一行即可�?
### 天气（借鉴同类农场游戏的「雨天」）

`Weather`（挂�?`base_level` 上）。每�?*天亮时掷一�?*骰子决定今天晴还是雨（默�?30% 下雨）�?
- **下雨�?*：每�?`RAIN_TICK`�? 秒）给所�?*还没浇过�?*的作物免费浇一�?  —�?等于当天可以省下浇水的功夫去备战夜晚。刚种下的作物也会被浇到�?- **画面偏冷**：雨天色�?*不自己开 CanvasModulate**，而是交给 `DayCycle` 一起算
  （同一块画布只能有一�?`CanvasModulate` 生效，两个会互相覆盖）�?  实测：晴�?`(1.0, 1.0, 1.0)` �?雨天 `(0.7975, 0.829, 0.919)`�?- HUD 第一行显�?`晴天` / `雨天`�?- `Weather.set_rainy(bool)` 可以强制天气（测�?调试用）�?
### 成就

`Achievements`（挂�?`base_level` 上）。每帧检查一次条件，满足就解锁：打日�?+ 放音 +
HUD 底部弹一�?2.5 秒的提示条。解锁记录进存档�?
| id | 名称 | 条件 |
|---|---|---|
| `first_harvest` | 初次丰收 | 收获第一个作�?|
| `first_kill` | 初次交锋 | 赶跑第一只害�?|
| `harvest_10` | 绿手�?| 累计收获 10 个作�?|
| `kill_25` | 农场卫士 | 累计赶跑 25 只害�?|
| `day_3` | 熬过三夜 | 活到�?4 �?|
| `barn` | 谷仓建成 | 攒够 300 �?|

- 条件全部�?*已有状�?*推导（`player.total_harvested` / `player.total_kills` / `cycle.day` /
  `controller.goal_reached`），**不额外维护一套统�?*�?- ⚠️ 因为是从状态推导的�?*清空解锁记录但状态仍满足时会被立刻重新解�?* —�?这是设计使然�?  测试要验证「载入」而不是「重新推导」，就得先构造一个条件并不支持的集合�?
### 音效

自动加载单例 `Sfx`（`Scenes/global/sfx.tscn`），任何脚本直接 `Sfx.play("hit")`�?
| 音效�?| 触发�?| 时长 |
|---|---|---|
| `plant` | 播种成功 | 0.09s |
| `water` | 浇水成功 | 0.20s |
| `harvest` | 收获成功 | 0.17s |
| `coin` | 卖出作物 | 0.18s |
| `buy` | 买下种子 | 0.17s |
| `hit` | 砍中野猪 | 0.10s |
| `hurt` | 玩家掉血 | 0.26s |
| `nightfall` | 入夜 | 0.75s |
| `dawn` | 天亮 | 0.55s |
| `goal` | 达成目标 | 0.66s |

- **10 �?`AudioStreamPlayer` 全部预建�?`sfx.tscn` �?*，运行时只调 `play()`，不创建节点�?- 音效�?`Tools/gen_sfx.gd` **用代码合成的**（短正弦/噪声包络），不是下载素材�?  零版权顾虑、总共�?140KB、参数改一行重跑即可�?  **换成真素材时只要文件名不变，代码一行都不用改�?*
- ⚠️ 这些是「提示音」级别的东西，不是有审美的音效设计。好不好听要人耳判断�?
### 战斗

**害兽（Pest�?* `Scripts/Characters/pest.gd` + `Scripts/Characters/pest_data.gd`

同一个场�?`pest.tscn` �?`kind` 就换一种敌人�?*`kind` 必须�?`add_child` 之前设好**—�?`_ready` 会拿它配置血�?速度/贴图/赏金�?
| 种类 | 贴图�?| 血�?| 速度 | 啃几株才�?| 赏金 | 出场 |
|---|---|---|---|---|---|---|
| 野猪 | (3,10) | 2 | 38 | 1 | 2 �?| �?1 �?|
| 蝙蝠 | (0,10) | 1 | 66 | 1 | 2 �?| �?2 �?|
| 蜘蛛 | (2,10) | 3 | 30 | **3** | 5 �?| �?3 �?|

共同行为�?
| �?| �?|
|---|---|
| 移动 | 直线冲向最近的作物，不寻路 |
| 吃作物范�?| 10px |
| 顶玩�?| 12px 内扣 1 血，冷�?1.5s |
| 受击硬直 | 0.25s�?*重要**：否则玩家砍中后它还继续跑，追击手感极差�?|
| 击退 | 砍中时沿「远离玩家」方向推开，初�?140 px/s，按 9/s 衰减 |
| 放弃条件 | 场上没作�?6 秒后离开；被卡住 3 秒后离开 |
| 多啃间隔 | 啃完一株后�?0.5s 再找下一株（`DIGEST_TIME`�?|

**刷新器（PestSpawner�?*�?*只在夜晚出动**，天亮全部撤退（撤退**不给赏金**）�?
- 每夜按「波」刷新：入夜**立刻**来第一波，之后�?8 秒一�?- 每波只数 = `DayCycle.wave_size()` = `base_wave_size + 天数 - 1`（上�?6�?- 每只的种类由 `PestData.pick_kind(天数)` 按权重抽—�?*天数越大，池子里越容易出现蝙蝠和蜘蛛**
- 场上上限 6 �?- 找不�?DayCycle 时退�?`always_active` 行为（给单元测试用）

**玩家攻击**

| �?| �?|
|---|---|
| 攻击范围 | 26px 圆形（范围内**所�?*野猪一起掉血，不做扇形） |
| 伤害 | 1 |
| 冷却 | 0.35s |
| 刀�?| 复用 `player.tscn` 里预建的 `Slash`(Polygon2D)，命中时显示 0.12s，按朝向翻转 `scale.x` |
| 血�?| 5 |
| 晕倒惩�?| 损失一半金币，被抬回出生点，血量补�?|

---

## 6. 素材图集坐标

**kenney_tiny-farm/Tilemap/tilemap_packed.png**�?92×176�?2 �?× 11 行，每格 16px�?
| 对象 | region_rect |
|---|---|
| 玩家 | `Rect2(16, 144, 16, 16)` |
| 温顺动物 | `Rect2(0, 160, 16, 16)` |
| 作物（按阶段 / 种类�?| `Rect2(16 * CropData.column_for_stage(stage), 16 * type, 16, 16)` —�?�?4�?，行 0�? |
| tree_1 | `Rect2(48, 0, 16, 32)` |
| 水桶 / 激�?| `Rect2(0, 96, 16, 16)` / `Rect2(16, 96, 16, 16)` |
| 水缸 / 激�?| `Rect2(32, 128, 32, 16)` / `Rect2(32, 144, 32, 16)` |

**kenney_tiny-dungeon/Tilemap/tilemap_packed.png**（同�?192×176 / 12×11）——已�?4 倍放大逐格确认过：

| �?| 内容 |
|---|---|
| �?9 (y144) | 绿史莱姆(0)、褐色小�?1)�?*红色螃蟹**(2)、棕灰软�?3)、绿头巾矮人(4)；后面是药水、武�?|
| �?10 (y160) | **蝙蝠**(0)�?*灰色幽灵**(1)�?*蜘蛛**(2)�?*獠牙野猪**(3)、灰色骷�?4)；后面是法杖 |

> ⚠️ 订正：早先把「行 9 �?2」记成了红恶魔，8 倍放大后看清�?*红色螃蟹**（两只大螯）。已不再使用该格�?
### Kenney「Pixel Platformer」（横版矿洞用）

`Assets/kenney_pixel-platformer/`�?*CC0**（授权文�?`License.txt` 一起收在目录里）�?来源 `https://kenney.nl/assets/pixel-platformer`，命令行的下载地址见提交记录�?
> 🚨 **规格陷阱：Tiles �?Characters 的格子尺寸不一样！**
>
> | 图集 | 格子 | 布局 | `_packed` 尺寸 | �?packed 尺寸 |
> |---|---|---|---|---|
> | `tilemap_packed.png` | **18×18** | 20 �?× 9 �?| 360×162�?*无间�?*�?| 379×170�?px 间距�?|
> | `tilemap-characters_packed.png` | **24×24** | 9 �?× 3 �?| 216×72�?*无间�?*�?| 224×74�?px 间距�?|
> | `tilemap-backgrounds_packed.png` | **24×24** | 8 �?× 3 �?| 192×72�?*无间�?*�?| 199×74�?px 间距�?|
>
> **按错的格子尺寸切图不会报错，只会切出错位碎片�?* �?`region_rect = Rect2(col*W, row*H, W, H)`（packed 版步长就是格子尺寸本身）�?> 每次要依赖新格子之前，先把网格线画上去放大看一眼（照着 `Tools/analyze_crops.gd` 和这次的做法）�?
**角色图集 9×3 布局**（行 = y/24，列 = x/24，已画网格确认）�?
| �?| 内容 |
|---|---|
| 0 | 绿机器人(0,1) 蓝机器人(2,3) 粉机器人(4,5) 黄机器人(6,7) **灰色尖刺�?8)** |
| 1 | **褐色人形角色(0,1)** 黄箱**宝箱�?*(2,3) 褐色小兽(4,5) **红色炸弹�?6,7,8)** |
| 2 | 蓝色矿车/履带�?0,1,2) 大型蓝色机械(3,4,5) **褐色蝙蝠(6,7,8)** |

**地形图集里跟矿洞对口�?*：镐子、宝石、矿车、铁轨、梯子、木箱、石�?土层、水、一段数字字体�?**UI 直接能用�?*：满/�?空三�?*心形**（当血条）�?*数字 0-9 字形**（伤害数字）、宝箱�?
野猪�?**`Rect2(48, 160, 16, 16)`**，蝙�?`Rect2(0, 160, 16, 16)`，蜘�?`Rect2(32, 160, 16, 16)`�?
全部素材�?**CC0（Kenney�?*，各目录下有 `License.txt`�?
**农场图集的行 = 作物种类**（已 8 倍放大逐格确认）：�?0 胡萝卜、行 1 紫甘蓝、行 2 玉米、行 3 番茄、行 4 卷心菜。每行的�?4..8 是同一种作物的生长序列�?
### �?已用像素分析判定：STAGE_COLUMNS 保持 `[4, 5, 6, 7, 8]`

曾经怀疑「列 7 是各种作物共用的空地/土堆」，那样的话 `growStage=3` 会显示成作物消失�?`Tools/analyze_crops.gd` �?*像素级比�?*把这个悬案结掉了�?
判据：如果某一列是各种作物**共用**的一张图（空�?土堆），它在�?5 种作物之间的像素�?应该接近 0；如果是各自的生长阶段，差异必然很大�?
实测（平均每像素 RGBA 绝对�?×100）：

| 图集�?| 跨作物平均差 | 与土块的平均�?|
|---|---|---|
| 4（幼苗） | 35.88 | 172.29 |
| 5 | 37.62 | 154.19 |
| 6 | 52.52 | 132.22 |
| 7 | **49.51** | 133.72 |
| 8 | 50.09 | 123.77 |

**没有任何一列接�?0**。列 7 �?49.51 与列 6�? 同量�?—�?说明**�?7 是随作物变化�?*�?不是共用空地�?*当前映射是对的，不用改�?*

（真要改的话仍然只改一行：`CropData.STAGE_COLUMNS`，同时调 `MAX_STAGE`。）

---

## 7. 已知的坑与手工改文件规则

- **不要手改 `.godot/`**：生成目录，�?gitignore�?- ⚠️ **在编辑器之外新建 `class_name` 后，必须重新导入一�?*，否则其他脚本会�?  `Parse Error: Could not find type "XXX" in the current scope`�?  命令：`godot --headless --path . --import`
- ⚠️ **`Node` 没有 `global_position`**（那�?`Node2D` 的属性）。需要坐标的节点必须 `extends Node2D`�?  否则�?*解析期报�?*（已踩过：`PestSpawner`）�?- **不要手写 UID**：`ext_resource` 不带 `uid` 也能正常加载（已实测），手工建场景可以只�?`path`�?- ⚠️ 每个脚本旁边的同�?`.uid` 文件**属于版本控制**；移�?重命名脚本时必须�?`.uid` 一起处理�?- 节点上的 `unique_id=` 是较新引擎字段，**手工新增节点时可以省�?*（已实测）�?- 所有文本文件是 **LF**（`.gitattributes` �?`* text=auto eol=lf`）�?- ⚠️ **Godot 内置字体不含中文字形**，Label 直接写中文会渲染成方块。本项目已引入中文字体解决：
  `Assets/fonts/fusion-pixel-12px-zh_hans.woff2` —�?**Fusion Pixel Font 12px 简�?*，像素风�?*OFL 协议**
  （许可全文见同目�?`OFL-fusion-pixel-font.txt`），通过项目设置 `gui/theme/custom_font` 挂为全局默认字体�?  - **字号必须�?12**（该字体的设计尺寸），配合窗口的整数倍缩放才是像素对齐的；用别的字号会发糊�?  - 导入参数已刻意设�?`antialiasing=0 / hinting=0 / subpixel_positioning=0`（关抗锯齿、关微调、关次像素定位）�?    换成别的字体、或重新导入后，要确认这三项还在（实测运行时读回来就�?0/0/0）�?  - 正确验证方式：`label.get_theme_font("font").has_char("�?.unicode_at(0))` —�?    �?**Label 实际取到的那个字�?*，而不�?`ThemeDB.fallback_font`�?- ⚠️ 写死的节点路径（�?`base_level` 层级就会崩）�?  `land.gd` �?`$"../level/Player"`、`$"../level/Static/Plants"`�?  `farm_controller.gd` �?`$"../level/Static/Market"`�?- ⚠️ **`_ready` 是按兄弟节点顺序触发�?*。若 A �?`_ready` 里用**分组**查找 B，�?B 排在 A 后面�?  A 查到的必然是 null（B 还没执行 `add_to_group`）。已踩过：`PestSpawner` �?`DayCycle`�?  稳的做法�?*两件都做**：场景里�?B 排在前面�?*同时**�?A 支持之后补查一次，不依赖顺序�?- `character.gd` 里的 `go()` / `dieOnCompany()` 和恒�?`false` �?`workToAdd` �?*占位玩笑代码**�?- 玩家和温顺动物头顶的 `debugLabel`（显�?`Idle` / `Move`�?*已在场景里设�?`visible = false`**�?  代码仍在往它写文本。想临时看状态机就把场景里的 `visible` 打开，别删节点（`Character` 依赖它存在）�?- ⚠️ **测试必须掐掉存档**：`base_level` 上挂着 `SaveSystem`（默认启动自动读�?+ 天亮自动存档）�?  其它测试实例�?`base_level` 时会读到玩家**真正�?*存档，�?`test_daynight` 还会**覆盖**它�?  所有不测存档的测试，都要在第一帧之前设 `auto_load = false` �?`auto_save_on_dawn = false`�?- ⚠️ 跑主场景冒烟测试前建议先删掉 `user://farm_save.json`，否则会从存档的天数继续�?  冒烟测试就不确定了�?- ⚠️ headless 退出时会打�?  `N ObjectDB instances were leaked at exit` / `M resources still in use at exit`�?  **这是无害�?*，已�?`--verbose` 查明：泄漏的�?*最后播放的那几�?* `AudioStreamPlaybackWAV`
  （引用计�?1），之前的播放都正常释放，所�?*不随游玩时长增长**。哑音频驱动下停掉的播放对象
  没人回收，真机有声卡时不会有。只在退出瞬间打印一次，GUI 程序没有控制台，玩家看不到�?  （`Sfx.stop_all()` 消不掉它，别在这上面浪费时间。）
- `game.tscn` 是空壳；`tree_2.tscn` / `tree_3.tscn` 没被任何场景引用�?- 动物状态里 `speed` �?`Update()` 每帧重新随机——速度一直在抖，疑似写错位置（野猪没这问题）�?- ⚠️ **测试里必须手动补 `Level.animalRegion`**：测试场景不是主场景，自动加�?`Level` �?`_ready`
  �?`base_level` 实例化之前就跑完了，拿不到导航区域；不补的话动物切到 Move 状态会�?  `Invalid access to property 'navigation_polygon' on null instance`�?
### ⚠️ 偶发失败的两次教训（都发生在测试里，不是游戏代码里）

**这两�?bug 单跑一遍都是绿的，只有连跑才暴露。所以现在固定连跑三遍�?*

1. **竞态：等冷却时敌人跑掉了�?*
   `test_combat` 里原本是「把玩家瞬移到蝙蝠身�?�?�?0.5 秒冷�?�?砍」�?   蝙蝠速度 66�?.5 秒已经跑�?26 的攻击范�?�?这一刀砍空 �?连带三条断言失败�?   残留的蝙蝠又让后面蜘蛛那段的场上计数�?1 变成 2�?   **正确写法：先等冷却，再瞬移，立刻砍�?*

2. **系统间的隐性耦合：下雨会压暗画面�?*
   `test_daynight` 断言「白天画面重新变亮」（`tint.r > 0.99`）�?   但加了天气之后，**雨天色调是叠在昼夜之上的**，天亮时正好赶上雨天就会失败�?   修法：那个测试只管昼夜，所以开局�?`Weather.rain_chance = 0.0` 把天气关掉�?   **教训：新系统改动了某个全局量时，要去搜一遍还有谁在断言那个量�?*

3. **另一类反复踩的坑：`Area2D` 的范围更新滞后一帧�?*
   测试里把玩家瞬移出商店范围后**立刻**�?F，`Market.is_player_inside()` 还是 true�?   于是播种被商店分支抢走�?*瞬移之后必须 `await` 若干 `physics_frame` 再操作�?*

---

## 8. 当前进度

**已能�?*
- 玩家 WASD 移动 + Idle/Move 状态切�?+ 动画
- 农场动物随机漫游
- **手持道具系统**：Q 切换 种子�?/ 水壶 / 收获�?/ 剑，HUD 实时显示
- **完整农场循环**：播�?�?浇水 �?逐级生长 �?成熟 �?收获
- **经济循环**：在商店（房子）里卖作物、买种子
- **战斗循环**�?*夜晚**害兽成群来袭啃作物，用剑砍跑它（有赏金）；被顶会掉血；晕倒损失一半金币；天亮害兽撤退
- **害兽种类**：野�?/ 蝙蝠 / 蜘蛛，血量速度行为各异，随天数解锁
- **昼夜循环**�?5 秒一天，夜晚画面变暗，难度随天数爬坡
- **目标**：攒�?300 金建成谷�?- **存档**：天亮自动存、启动自动读，F5/F9/F10 手动控制
- **多种作物**�? 种，�?1-5 切换；越贵单位时间收益越高；**按天数解�?*（开局只有胡萝卜）
- **成长与专�?*：农�?/ 战斗 / 经营三系攒经验，升级时二选一拿不可逆专�?- **音效**�?0 个由代码合成的提示音，覆盖种�?/ 浇水 / 收获 / 买卖 / 战斗 / 昼夜 / 目标
- **打击�?*：砍中野猪有刀�?+ 受击闪红 + 硬直 + 击退
- **胜利反馈**：攒�?300 金亮出「目标达成！谷仓建成了！」横�?- **攻击动画**：刀光按剩余时间驱动缩放/旋转/淡出�?.55 �?1.35 倍，伴随挥砍旋转�?- **天气**：每天天亮掷骰子，雨天画面偏冷且**作物自动浇水**
- **成就**�? 个，解锁�?HUD 底部弹提示条，进度进存档
- 水壶容量与水源自动补�?- HUD�?*中文界面**，显�?金币 / 血�?/ 种子 / 作物 / 水量 / 手持�?
**没做（打磨项�?*
- 只有一种作物（`current_crop_type` 恒为 0�?- `Land` �?terrain 1 在图集里定义好了但没代码使用
- 音效、动画（攻击只有一刀白光�?- 存档
- 野猪只是"啃掉作物"，没有更复杂的行�?
---

## 9. 协作方式（给 AI 助手�?
### 铁律

1. **复杂节点和场景不要用代码动态创�?*（不�?`new Area2D()` 之类）。预先在 `.tscn` / 场景里建好，运行时只�?`instantiate()` + 设属性�?2. **一次只改一小块**，改完立刻验证再继续�?3. **大改动前�?commit**�?
### 验证（不用打开编辑器，AI 自己就能跑）

> Godot �?Windows 版是 **GUI 子系统程�?*，PowerShell 直接调用**不会等待**它结束�?> 必须用管道强制等待，否则 `$LASTEXITCODE` 是空的�?
```powershell
$godot = 'E:\godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe'
Set-Location 'E:\godot\farmAndFightGame\farmAndFightGame'

# 0) 新增�?class_name 之后必须先刷新缓�?& $godot --headless --path . --import

# 1) 作物单元自测�?1 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_plant.tscn --quit-after 3000 2>&1 | Out-String

# 2) 农场 + 经济 + 多种作物端到端（66 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_farm.tscn --quit-after 3000 2>&1 | Out-String

# 3) 战斗 + 害兽种类�?4 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_combat.tscn --quit-after 3000 2>&1 | Out-String

# 4) 昼夜 + 夜晚来袭 + 目标�?6 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_daynight.tscn --quit-after 4000 2>&1 | Out-String

# 5) 存档�?6 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_save.tscn --quit-after 4000 2>&1 | Out-String

# 6) 音效�?3 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_sfx.tscn --quit-after 3000 2>&1 | Out-String

# 7) 天气�?9 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_weather.tscn --quit-after 4000 2>&1 | Out-String

# 8) 成就�?6 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_achievements.tscn --quit-after 4000 2>&1 | Out-String

# 9) 成长与专精（51 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_progression.tscn --quit-after 6000 2>&1 | Out-String

# 10) 跑主场景 150 秒（�?3.3 个昼夜），抓运行时错�?& $godot --headless --path . --fixed-fps 60 --quit-after 9000 2>&1 | Out-String

# 11) 横版矿洞角色控制�?2 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_mine.tscn --quit-after 4000 2>&1 | Out-String

# 12) 矿洞战斗�?9 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_mine_combat.tscn --quit-after 4000 2>&1 | Out-String

# 13) 矿洞怪的 AI + 玩家受伤 + 血条（29 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_mine_enemy.tscn --quit-after 4000 2>&1 | Out-String

# 14) 矿洞武器与技能（46 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_mine_skill.tscn --quit-after 4000 2>&1 | Out-String

# 15) 矿洞进出与结算（35 项）
& $godot --headless --path . --fixed-fps 60 res://Tests/test_mine_run.tscn --quit-after 4000 2>&1 | Out-String
```

合计 507 项断言�?
> ⚠️ **这些测试必须连跑三遍再下结论�?* 已经踩过两次"单跑绿、连跑红"的偶发失�?> （见�?7 节）。跑一遍不算验证过�?
要点�?- `--fixed-fps 60` 让时间步长确定，定时�?生长/移动行为可复现�?- `--quit-after N` �?*帧数**，不是秒；配�?`--fixed-fps 60` �?1800 �?= 30 秒�?- 测试脚本�?`_check(说明, 条件)` 打印 `PASS`/`FAIL`，结尾打�?`RESULT fail=N`�?- 端到端测�?*尽量�?`FarmController.use_held_item()`**（玩家真实路径），而不是直接调底层方法�?- 需�?Area2D 检测（商店/水源）时，把玩家 `global_position` 挪过去后�?`await physics_frame` 若干帧�?- 注入故障后引擎会打出�?`文件:行号` �?GDScript 调用栈的 `ERROR`�?*验证链路可信**（已实测）�?
### 查文档，别凭记忆

- 首选编辑器内置帮助（F1）�?- 在线�?https://docs.godotengine.org/en/4.7/>
- 破坏性变更：<https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html>

---

## 10. 横版矿洞（进行中的新方向�?
**目标**：农场是「家」和「经济」，矿洞是「打一架」的地方。两者共用同一套存档、音效、成长、测试方法�?
参考对象是 4399 �?*《勇士的信仰测试版�?*（`4399.com/flash/83335.htm`�?011-12-02�?1MB，标�?16+）�?它其实就�?*《勇者之�?�?*，属于勇者之路系�?—�?我第一轮误认成了它的前作《勇者之路》（`flash/43841.htm`�?010�?6MB）�?
> **对齐它的 UI / 战斗 / 奖励 / 技能，不对齐它的美术�?*
> 它是**动漫 Q 版手�?*（两个可玩角色：金发拳系 / 蓝发铠甲系），这个我们做不到，用 CC0 像素素材替代�?> 它比前作大得多：有剧情（艾格林村�?/ 女神 / 暗黑�?/ 天煞月食）、有存档点、支持双人同屏�?
### 参考游戏的实际操作（抄它之前先看清�?
```
玩家1（单人时就是这套�?  A / D      移动
  W          传�?  S          拾取物品
  H U I O    使用技�?       �?四个技能键
  J          攻击
  K          跳跃
  L          切换武器
  1 / 2 / 3  使用物品        �?消耗品道具�?  N          怪物技�?
开局流程：登�?�?单人/双人 �?选存档点 �?选择 2 种武器类�?�?开�?```

**从它身上值得抄的三件�?*（我原方案漏了的）：

1. **`L` 切换武器** —�?两把武器随时换，应对不同情况。这比我原来只做一套攻击有深度�?2. **`1/2/3` 消耗品道具�?* —�?和技能是分开的两套资源�?3. **开局「选择 2 种武器类型�?* —�?这就�?*流派选择的原�?*，而且和我们已有的
   `Progression` 二选一专精是同一个设计思路，可以直接接上�?
### 我们的操作方�?
农场�?`Q/F/1-5` 保持不变�?*进矿洞后切到横版操作**�?
| �?| 作用 | 对应参考游�?|
|---|---|---|
| A / D（沿�?`left` / `right`�?| 左右移动 | 一�?|
| `jump`�?*新增**，空�?/ K�?| 跳跃 | K |
| `attack`（沿�?`use_item`，F / J�?| 攻击 | J |
| `We` / `Ui` / `Io` / `Op`�?待定 �?先用 `1`~`4`（沿�?`seed_1..seed_4`�?| 放技�?| H U I O |
| `switch_weapon`�?*新增**，L�?| 切换武器 | L |
| `use_potion`�?*新增**�?/2/3 冲突…见下） | 使用物品 | 1/2/3 |
| `skill_list`�?*新增**，P / Tab�?| 开技能表 | �?|

> ⚠️ **键位冲突要处�?*：参考游戏用 `1/2/3` 当道具、`H U I O` 当技能；
> 而农场模式里 `1~5` �?*选作物种�?*。两种模式共用一�?`InputMap`�?> 所以矿洞里的技能键**不能**�?`1~4`（会误触发选作物）�?> 决定�?*技能用 `H U I O`（照抄参考游戏，且和农场不冲突）**，道具用 `1/2/3`（只在矿洞内生效）�?>
> 复用现有�?input action 名字（`left`/`right`/`use_item`）而不是另起一套，
> 这样两人都在同一�?`InputMap` 里，不会出现"矿洞�?WASD 不动"的经�?bug�?
### 设计要点

- **矿洞�?*做成农场地图上一个预建节�?+ `InteractionArea`，按 F 进入（复用现有交互模式）�?- **限时**：洞里有「火�?氧气」倒计时，时间到自动送回农场 —�?这样它是一个自成一体的动作关卡�?  而不是无限刷怪点。倒计时本身也制造紧迫感�?- **死亡惩罚**：在洞里倒下 = 丢掉这趟的收获，被送回农场门口。有惩罚才有张力�?- **奖励**：矿�?宝石（卖钱）、宝箱、金币。回来后卖给商店，接上现有经济系统�?- **技�?`H U I O` + 冷却 + 能量**：重�?/ 旋风�?/ 冲刺 / 治疗�?  沿用「数据表驱动」的既有做法（照 `CropData` / `PestData` / `Progression.PERKS` 的样子写 `SkillData`）�?- **`L` 切换武器**：两把武器随时换，攻击范�?伤害/速度各不相同�?- **`1/2/3` 消耗品**：回血药之类，和技能是分开的两套资源�?- **不做双人同屏**：参考游戏支持双人，但我们的农场是单人循环，加第二套输入和摄像机是另一个量级的工作�?  记在这里，万一以后想做�?- **飘字伤害数字**：纯代码，数字字形用素材里那�?0-9；中文字体已有�?
### 阶段划分（每阶段都要 headless 验证�?
| 阶段 | 内容 |
|---|---|
| A | 横版角色控制：重�?/ �?/ �?/ 单向平台 / 摄像机跟�?| �?|
| B | 近战攻击 + 命中判定 + 击退 + 受击硬直 + **飘字伤害数字** | �?|
| C | 矿洞里的怪（机器�?/ 蝙蝠�? 简�?AI | �?|
| D | `H U I O` 技能栏 + 冷却 + 能量 + **`L` 切换武器** | �?|
| D2 | 还没做：`1/2/3` 消耗品 + `P` 技能表面板 + 武器贴图 | �?|
| E | 矿洞口进出自�?+ 倒计�?+ 死亡惩罚 + 回农场结�?| �?|
| F | 矿石/宝箱掉落接进商店经济（现在只有金币） | �?下一�?|
| F | 矿石/宝箱/金币掉落，接进商店经�?|

### 🚨 阶段 A 踩到的两个坑（都会静默出错，务必记住�?
**�?1：`TileSet.tile_size` 必须�?`texture_region_size` 一致�?*

只设 `texture_region_size = Vector2i(18,18)` 的话�?*显示是对�?*（切图切得准），
但瓦片在**世界里按默认�?16×16 �?*，位置全�?2px 起。引�?*不报任何�?*�?
现象：角色明明站在地面上，却悬空 10px（`feet.y = 152` 而地面顶面是 162）�?
排查方法（很好用）：从角色上方朝下打一条射线，看真正的地面在哪�?再打�?`terrain.tile_set.tile_size`。两者一对就露馅了�?
**�?2：瓦片的物理多边形是相对格子中心的，不是左上角�?*

整格要用 `PackedVector2Array(-9,-9, 9,-9, 9,9, -9,9)`�?写成 `(0,0)�?18,18)` 会整块偏到右下，地面凭空�?9px�?
这两条已经在 `test_mine.gd` 里做成了**永久回归断言**（检�?`tile_size`�?多边形首尾点、平台多边形是不是薄片、单向标志），以后改场景文件被破坏会立刻红�?
**�?3（测试写法）：`Input.action_press()` �?`is_action_just_pressed()` 生效隔一帧�?*

`Input.action_press("jump")` 之后�?`await` 一帧就断言"有没有跳起来"�?*误判成失�?*�?正确写法�?*按下后在几帧内观察状�?*（例�?4 帧内 velocity.y 是否变成负数"），
不要绑定到具体某一帧�?
### 已实现（阶段 A：横版角色控制）

`Scenes/Mine/mine_level.tscn` + `Scripts/Mine/mine_level.gd`（关卡）
`Scenes/Mine/mine_player.tscn` + `Scripts/Mine/mine_player.gd`（角色）

- 关卡�?**ASCII �?*描述（`#` 实心 / `=` 单向平台 / `S` 出生点）�?  `build()` 里逐格 `set_cell()`。改关卡就是改字符串，diff 看得见，不用碰二进制 `tile_map_data`�?  **只用 `set_cell()` 写数据，没有动态创建任何节�?*，符合项目约定�?- 角色手感做了四件事，少一件都�?感觉不对"�?  **土狼时间**�?.10s）／**跳跃缓冲**�?.12s）／**可变跳跃高度**（松手砍�?0.42 倍）／加减速分离�?- 复用农场�?`left`/`right` 动作名，跳跃是新增的 `jump`（空�?/ K）�?
实测手感数据：按住跳上升 **39.3px**�? 格多），轻点只有 **10.7px**；单向平台能从下方穿过、从上方站住�?
### 已实现（阶段 B：近战战�?+ 飘字伤害�?
`Scripts/Mine/mine_enemy.gd` + `Scenes/Mine/mine_enemy.tscn`（怪）
`Scripts/Mine/damage_number.gd` + `Scenes/Mine/damage_number.tscn`（飘字）

- **�?*共用一套脚本，`kind` 换一种就是换一种怪（绿机�?蓝机�?红炸�?蝙蝠）�?  挨打�?*闪白 + 硬直 0.22s + 击退 130px/s**，血�?`queue_free()` 并发 `died` 信号�?- **攻击判定**用的是角色身�?*预建�?`AttackBox`（Area2D�?*，一直开着当查询区域，
  攻击时直�?`get_overlapping_bodies()` —�?不用等一帧、也不用在运行时创建任何节点�?  判定框每帧跟着 `facing` 摆到身前（朝左时 x 为负）�?- **飘字**是预建场景，命中�?`instantiate()` 一个、设好文字和位置。弹出→上飘→淡出，0.55s 后自回收�?
### 🚨 阶段 B 又踩到两个坑

**�?4：不要在运行时给节点改名�?*

我本来想�?`_ready()` �?`name = "绿机�?` 让日志好看，结果
**`get_node("EnemyA")` 全部返回 null** —�?场上明明�?3 只怪。改用单独的 `_title` 变量�?
**�?5：GDScript �?lambda 按值捕获局部变量�?*

```gdscript
var flag := false
enemy.died.connect(func(_e): flag = true)   # �?flag 永远�?false
```
lambda 改的�?*副本**。要接收信号就老老实实写个方�?+ 成员变量�?
**附带一�?API 设计教训**：`attack()` 原本只设冷却、不检查冷却（检查写�?`_physics_process` 里），于�?*任何直接调用都能绕过冷却**。冷却检查应该属�?`attack()` 自己 —�?这样键盘、AI、测试走的是同一条路，绕不过去�?
### 已实现（阶段 C：怪的 AI + 玩家受伤 + 心形血条）

- **怪的 AI**：`巡�?�?发现玩家就追 �?贴上去造成接触伤害`�?  侦测范围水平 96px、垂�?44px�?*分开判的**，免得隔着几层平台就追过来）�?  飞行怪（蝙蝠）不吃重力，会把自己的高度缓慢对齐玩家，再水平压过去�?  挨打时的闪白/硬直/击退在阶�?B 就做好了，这一阶段只管"怎么�?�?- **玩家受伤**：`MAX_HP = 6`，受伤后�?**0.8 秒无敌帧**（期间角色一闪一闪）�?  还会被撞飞一下（给即时反馈，也顺便拉开距离）�?  **没有无敌帧的话贴着怪会一秒掉光血，手感极差�?*
- **心形血�?*：直接用地形图集里的三档心形（满 `(4,2)` / �?`(5,2)` / �?`(6,2)`），
  **一颗心 = 2 点血**。心是预建的 `Sprite2D` 子节点，脚本只改 `region_rect`�?  用不到的槽位自己 `visible = false`�?
### 🚨 阶段 C 的教训：往共享场景加内容会打坏不相关的测试

往 `mine_level.tscn` 加了怪之后，`test_mine`（只管移动手感的那个）开始红�?—�?它用的是**自定义小地图**，怪在那个地图上脚下没地面，会到处漂，
最后蝙蝠飞过来把玩家撞飞，"落在平台�?这条断言就失败了�?
**看起来像是跳跃代码坏了，实际上是测试没隔离干净�?* 现在 `test_mine` 开场就清场�?
**通用教训：用自定义地�?状态的测试，必须把不相关的动态对象清�?*�?否则以后每加一种怪都要重新排查一遍这�?假故�?�?
### 已实现（阶段 D：武�?+ 技�?+ 技能栏�?
`Scripts/Mine/mine_combat_data.gd`（数值表）�?技能栏�?`mine_hud.gd/tscn`

沿用项目一贯的「数据表驱动」：**加一把武器或一个技�?= 表里加一�?*，逻辑不用动�?
| 武器 | 伤害 | 判定�?| 冷却 | 击退 |
|---|---|---|---|---|
| 短剑 | 1 | 24×20 | 0.34s | 130 |
| 巨剑 | 2 | 32×26 | 0.62s | 210 |

| 技�?| �?| 类型 | 消�?| 冷却 | 效果 |
|---|---|---|---|---|---|
| 重斩 | H | heavy | 4 | 4s | 前方 44×34 范围，伤�?3 |
| 旋风�?| U | spin | 6 | 6s | 身周 34 半径，伤�?2（可同时打多只） |
| 冲刺 | I | dash | 3 | 2s | 前冲 300px/s×0.18s�?*期间无敌**，撞到的敌人各吃 1 �?|
| 治疗 | O | heal | 8 | 10s | �?3 点血（不超上限） |

能量上限 20，每秒回 2.2�?
> **为什么技能不�?`Area2D` 的重叠结果？**
> `Area2D.get_overlapping_bodies()` 要等一个物理帧才刷新，而每个技能的判定框尺�?> 都不一样（重斩是长条、旋风斩是方块），改完形状当场查�?*查不到的**�?> 所以技能用 `intersect_shape()` �?*即时形状查询**�?> 这里创建�?`RectangleShape2D` / `PhysicsShapeQueryParameters2D` 都是 **Resource 不是 Node**�?> 项目约定禁止的是动态创建节点�?>
> 另外：换武器要改判定框尺寸，�?`.tscn` 里的 `sub_resource` 默认�?*多个实例共享**的，
> 所�?`_ready()` 里先 `duplicate()` 一份，免得改了一个实例影响另一个�?
**HUD 技能栏**�? 个预�?Label（就�?亮黄 / 冷却=灰并标剩余秒�?/ 能量不够=偏红），
外加一行状态显示能量和当前武器�?
### 阶段 D 还没做的

- `1/2/3` 消耗品道具�?- `P` 技能表面板（列出全部技能和说明�?- 武器用图集里的贴图（现在�?Polygon2D 刀光变色区分）

### 已实现（阶段 E：矿洞接进农场）

`Scripts/Global/MineRun.gd`（自动加载单例）· `Scripts/buildings/mine_entrance.gd` + `Scenes/buildings/mine_entrance.tscn`
`Scripts/Mine/mine_pickup.gd` + `Scenes/Mine/mine_pickup.tscn`

**核心难题：切场景会丢掉农场的一�?*（地块、每株作物、金币都�?`base_level` 里）�?解法�?*复用已有的存档系�?*：进洞前 `SaveSystem.save_game()`�?回来时它的「启动自动读档」把农场原样恢复。这样不用把农场塞进 autoload�?
- **矿洞�?*（农场，`(350,180)`）：走近�?`F` 下矿。交互方式和水源/商店一致�?- **火把 75 �?*：烧完自动回农场�?*收获保留**�?- **在洞里倒下 �?丢掉这趟收获**。因为存档是�?*进洞之前**拍的，失败时什么都不用做�?- **掉落**：怪死掉掉金币（`1 + 最大生命`），碰到自动捡走，钱记在 `MineRun.gold` 上，
  **回农场才真的进钱�?*�?- 回农场后由矿洞口 `_settle_previous_run()` 结算一次（`consume_result()` 保证只结算一次）�?
### 🚨 阶段 E 的两个坑

**�?6：`MineLevel._ready()` 自动开局 �?测试里一死就真的切了场景�?*

原本写成「不在洞里就自动 `start_run()`」，方便直接在编辑器跑这个场景�?结果 headless 测试里玩家一死就触发 `MineRun.finish()`，�?`finish()` �?`change_scene_to_file` —�?**测试场景当场被换�?*，后面所有断言失效�?报的错还完全看不出跟矿洞有关（是 `physics_frame` on null 之类）�?
修法：`_ready()` �?*不要**自动开局，只有真从矿洞口进来才有火把倒计时�?另外�?`MineRun` 加了 `scene_switch_enabled`，测试里关掉即可�?
**�?7：矿洞口压在农田�?�?玉米种不下去�?*

洞口交互半径 26px，而它离最近的农田格子只有 17.9px�?于是站在那格�?`F` 被洞口分支抢走，`test_farm` 的玉米种植全�?—�?**报的错跟矿洞毫无关系，查了半�?*�?
修法：把洞口挪到 `(350,180)`（离最近农田约 38px），
并在 `test_mine_run` 里加了一�?*永久断言**�?「洞口不能压在任何农田上（要�?> 30px）」，`land.get_used_cells()` 挨个算距离�?以后谁挪洞口挪坏了会立刻红�?
> 农田范围（实测）�?*x 248~312 / y 136~184**�?
### 已实现（阶段 D2：消耗品 + 技能表�?
- **`1` 回血�?*：开局�?3 瓶，每瓶�?2 点血�?*回血不超上限**，满血时喝会被拒（不浪费）�?  和技能是**分开的两套资�?* —�?技能吃能量，药吃瓶数�?- **`P` 技能表**：预建面板，列出 4 个技能的按键 / 消�?/ 冷却 / 说明�?- **关于"只在矿洞内生�?**：`item_1..3` 和农场的 `seed_1..5` **共用按键但动作名不同** —�?  矿洞脚本只监�?`item_*`，农场脚本只监听 `seed_*`，所以天然不会互相误触发�?  这比"运行时判断当前在哪个模式"更稳，也不需要在两套代码之间传状态�?
### 待定（需要用户拍板）

- **矿洞里的主角用哪个形象？** 农场主角�?`kenney_tiny-farm` 的俯视角人类农夫�?  而这包素材里没有对应的横版人类。候选：褐色人形角色(1-0)、某个机器人�?  用机器人反而有个说法——「开矿用机械」，但和农场主角不是同一个形象�?
---

## 11. 路线�?
| # | 目标 | 状�?|
|---|---|---|
| 1 | 浇水 �?成熟 �?收获 闭环 | �?|
| 2 | 手持道具概念（Q 切换 + 单动作键分发�?| �?|
| 3 | 经济：卖作物、买种子、商店交�?| �?|
| 4 | 战斗：野猪啃作物 + �?+ 血�?+ 刷新�?| �?|
| 5 | 中文 UI（Fusion Pixel Font 12px，OFL�?| �?|
| 6 | 昼夜循环 + 夜晚成群来袭 + 目标 | �?|
| 7 | 存档系统（天亮自动存 / 启动自动�?/ F5 F9 F10�?| �?|
| 8 | 多种作物�? 种，1-5 切换，价格与生长时间各不相同�?| �?|
| 9 | **音效**（代码合�?10 个提示音 + 预建 AudioStreamPlayer 单例�?| �?|
| 10 | 打磨：击退、胜利横幅、隐藏调试标�?| �?|
| 11 | 害兽种类 + 难度爬坡（野�?蝙蝠/蜘蛛，随天数解锁，击杀有赏金） | �?|
| 12 | 攻击动画 + 天气（雨天自动浇灌）+ 成就系统 | �?|
| 13 | 开局简化（作物按天解锁�? 三系成长与二选一专精 | �?|
| 14 | 还没做：**导出独立 exe**（要先把项目升到 4.7.2 以匹配已有的导出模板）、多地图（矿洞）、季节、NPC、动物产�?| �?|
