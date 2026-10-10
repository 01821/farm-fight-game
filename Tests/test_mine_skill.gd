extends Node2D

## 端到端自测：武器切换 + 四个技能（阶段 D）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_skill.tscn

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _enemy: MineEnemy
var _weapon_signals: int = 0
var _skill_signals: int = 0

func _on_weapon_changed(_id: int) -> void:
	_weapon_signals += 1

func _on_skill_used(_id: int) -> void:
	_skill_signals += 1

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _release_all() -> void:
	for a in ["left", "right", "jump", "use_item", "switch_weapon", "skill_1", "skill_2", "skill_3", "skill_4"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

## 把玩家摆到敌人左边 distance 处，面朝敌人，并把状态清干净
func _face_enemy(distance: float, settle: int = 6) -> void:
	_release_all()
	_player.global_position = Vector2(_enemy.global_position.x - distance, _enemy.global_position.y - 2)
	_player.velocity = Vector2.ZERO
	await _step(settle)
	_player.facing = 1

func _reset_skills() -> void:
	for i in range(_player.skill_cd.size()):
		_player.skill_cd[i] = 0.0
	_player.energy = float(MineCombatData.ENERGY_MAX)

func _ready() -> void:
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	_level.build()
	await _step(6)

	_player = _level.get_node("MinePlayer")
	_enemy = _level.get_node("EnemyB")     # 蓝机兵 4 血，够挨重斩
	_player.weapon_changed.connect(_on_weapon_changed)
	_player.skill_used.connect(_on_skill_used)

	print("--- 数据表 ---")
	_check("有 2 把武器", MineCombatData.weapon_count() == 2)
	_check("短剑伤害 1 / 巨剑伤害 2",
		int(MineCombatData.weapon_field(0, "damage", 0)) == 1 and int(MineCombatData.weapon_field(1, "damage", 0)) == 2)
	_check("巨剑射程更长", float(MineCombatData.weapon_field(1, "reach", 0.0)) > float(MineCombatData.weapon_field(0, "reach", 0.0)))
	_check("巨剑更慢（冷却更长）", float(MineCombatData.weapon_field(1, "cooldown", 0.0)) > float(MineCombatData.weapon_field(0, "cooldown", 0.0)))
	_check("有 4 个技能", MineCombatData.skill_count() == 4)
	_check("技能名齐了",
		MineCombatData.skill_name(0) == "重斩" and MineCombatData.skill_name(1) == "旋风斩"
		and MineCombatData.skill_name(2) == "冲刺" and MineCombatData.skill_name(3) == "治疗")
	_check("技能有说明文字", MineCombatData.skill_desc(0) != "")

	print("--- 武器切换 ---")
	_check("初始是短剑", _player.weapon_name() == "短剑")
	var box_before: Vector2 = (_player.attack_box.get_node("CollisionShape2D").shape as RectangleShape2D).size
	_check("换武器返回新 id", _player.switch_weapon() == 1)
	_check("换成巨剑了", _player.weapon_name() == "巨剑")
	_check("发了 weapon_changed 信号", _weapon_signals == 1)
	var box_after: Vector2 = (_player.attack_box.get_node("CollisionShape2D").shape as RectangleShape2D).size
	print("  INFO 判定框 ", box_before, " → ", box_after)
	_check("判定框跟着武器变大了", box_after.x > box_before.x)
	_check("再切回短剑", _player.switch_weapon() == 0 and _player.weapon_name() == "短剑")
	_check("切回后判定框也缩回去了",
		(_player.attack_box.get_node("CollisionShape2D").shape as RectangleShape2D).size.x == box_before.x)

	print("--- 巨剑伤害更高 ---")
	await _face_enemy(14.0)
	var hp0: int = _enemy.hp
	_player.attack()
	await _step(2)
	_check("短剑砍 1 点", _enemy.hp == hp0 - 1)
	await _step(40)
	_player.switch_weapon()
	await _face_enemy(14.0)
	var hp1: int = _enemy.hp
	_player.attack()
	await _step(2)
	print("  INFO 短剑后 ", hp1, " → 巨剑后 ", _enemy.hp)
	_check("巨剑砍 2 点", _enemy.hp == hp1 - 2)

	print("--- 技能：能量与冷却 ---")
	_reset_skills()
	await _step(2)
	print("  INFO 能量 = ", snappedf(_player.energy, 0.1), "/", MineCombatData.ENERGY_MAX)
	_check("初始能量是满的", is_equal_approx(_player.energy, float(MineCombatData.ENERGY_MAX)))
	_check("冷却清零后技能可用", _player.skill_ready(0))

	# 治疗：先掉点血再放
	_player.hp = 2
	var healed_ok: bool = _player.cast_skill(3)
	print("  INFO 治疗结果 ", healed_ok, "，血量 = ", _player.hp)
	_check("治疗放出来了", healed_ok)
	_check("回了 3 点血", _player.hp == 5)
	_check("扣了 8 点能量", is_equal_approx(_player.energy, float(MineCombatData.ENERGY_MAX) - 8.0))
	_check("治疗进冷却", not _player.skill_ready(3))
	_check("冷却中再放被拒", _player.cast_skill(3) == false)
	_check("发了 skill_used 信号", _skill_signals >= 1)

	# 能量不够
	_reset_skills()
	_player.energy = 1.0
	_check("能量不够时放不出重斩", _player.cast_skill(0) == false)
	_check("失败不扣能量", is_equal_approx(_player.energy, 1.0))

	# 能量会自己回
	var e0: float = _player.energy
	await _step(30)
	print("  INFO 能量回复 ", snappedf(e0, 0.1), " → ", snappedf(_player.energy, 0.1))
	_check("能量会随时间回复", _player.energy > e0)

	print("--- 技能：重斩 ---")
	_reset_skills()
	# 前面的巨剑已经把 EnemyB 打残了，换一只**满血**的来做重斩测试，
	# 并且要处理"3 血怪挨 3 点直接被秒"这条路径（不能再去读它的 hp）。
	var heavy := _level.get_node("EnemyA") as MineEnemy
	_enemy = heavy
	heavy.hp = heavy.max_hp
	await _face_enemy(18.0)
	var hp2: int = heavy.hp
	_check("重斩放出来了", _player.cast_skill(0))
	await _step(2)
	if is_instance_valid(heavy):
		print("  INFO 重斩前 ", hp2, " → 后 ", heavy.hp)
		_check("重斩打 3 点", heavy.hp == hp2 - 3)
	else:
		print("  INFO 重斩前 ", hp2, " → 一击秒杀（3 血怪挨 3 点）")
		_check("重斩打 3 点（正好秒掉 3 血的怪）", hp2 == 3)

	print("--- 技能：旋风斩（身周全员） ---")
	_reset_skills()
	# 用还活着的两只：蝙蝠 + 蓝机兵，一左一右摆到玩家身边
	var spin_l := _level.get_node("EnemyBat") as MineEnemy
	var spin_r := _level.get_node("EnemyB") as MineEnemy
	# 临时加厚血条：蝙蝠只有 2 血，被 2 点伤害秒掉后就读不到 hp 了
	spin_l.hp = 6
	spin_r.hp = 6
	_player.global_position = Vector2(300, 198)
	_player.velocity = Vector2.ZERO
	await _step(4)
	spin_l.global_position = Vector2(_player.global_position.x - 22.0, _player.global_position.y - 12.0)
	spin_r.global_position = Vector2(_player.global_position.x + 22.0, _player.global_position.y - 12.0)
	await _step(4)
	var lhp: int = spin_l.hp
	var rhp: int = spin_r.hp
	_player.cast_skill(1)
	await _step(2)
	print("  INFO 左边 ", lhp, " → ", spin_l.hp if is_instance_valid(spin_l) else -1,
		"；右边 ", rhp, " → ", spin_r.hp if is_instance_valid(spin_r) else -1)
	_check("旋风斩打到左边那只", is_instance_valid(spin_l) and spin_l.hp == lhp - 2)
	_check("旋风斩打到右边那只", is_instance_valid(spin_r) and spin_r.hp == rhp - 2)

	print("--- 技能：冲刺 ---")
	_reset_skills()
	_player.global_position = Vector2(60, 198)
	_player.velocity = Vector2.ZERO
	await _step(4)
	_player.facing = 1
	var x0: float = _player.global_position.x
	_check("冲刺前不在冲刺状态", not _player.is_dashing())
	_check("冲刺放出来了", _player.cast_skill(2))
	_check("进入冲刺状态", _player.is_dashing())
	_check("冲刺期间无敌", _player.is_invulnerable())
	await _step(12)
	print("  INFO 冲刺位移 ", snappedf(x0, 0.1), " → ", snappedf(_player.global_position.x, 0.1))
	_check("冲刺确实往前窜了一段", _player.global_position.x > x0 + 25.0)
	await _step(20)
	_check("冲刺会结束", not _player.is_dashing())

	print("--- 技能：治疗上限 ---")
	_reset_skills()
	_player.hp = MinePlayer.MAX_HP - 1
	_player.cast_skill(3)
	_check("治疗不会超过上限", _player.hp == MinePlayer.MAX_HP)

	print("--- 消耗品：三种药（和技能是分开的两套资源） ---")
	_reset_skills()
	_player.potions = [3, 2, 1]
	_player.hp = MinePlayer.MAX_HP
	_player.energy = float(MineCombatData.ENERGY_MAX)
	_check("三种药各有初始数量", _player.potion_count(0) == 3 and _player.potion_count(1) == 2 and _player.potion_count(2) == 1)
	_check("药名对得上", _player.potion_name(0) == "回血药" and _player.potion_name(1) == "能量药" and _player.potion_name(2) == "全力药")

	# 1 回血药
	_check("满血时不该喝回血药", _player.can_use_potion(0) == false)
	_check("满血时喝会被拒", _player.use_potion(0) == false)
	_check("被拒时不消耗药", _player.potion_count(0) == 3)
	_player.hp = 2
	_check("掉血后可以喝", _player.can_use_potion(0))
	_check("喝药成功", _player.use_potion(0) == true)
	print("  INFO 喝完血量 = ", _player.hp, "，剩 ", _player.potion_count(0), " 瓶")
	_check("回 2 点血", _player.hp == 4)
	_check("药少一瓶", _player.potion_count(0) == 2)
	_player.hp = MinePlayer.MAX_HP - 1
	_player.use_potion(0)
	_check("回血不会超过上限", _player.hp == MinePlayer.MAX_HP)

	# 2 能量药
	_check("满能量时不该喝能量药", _player.use_potion(1) == false)
	_player.energy = 3.0
	var e_before: float = _player.energy
	_check("能量不满时可以喝", _player.use_potion(1) == true)
	print("  INFO 能量 ", int(e_before), " → ", int(_player.energy), "，剩 ", _player.potion_count(1), " 瓶")
	_check("回 12 点能量", int(_player.energy) == int(e_before) + MinePlayer.ENERGY_AMOUNT)
	_check("能量药少一瓶", _player.potion_count(1) == 1)
	_check("能量不会超过上限", _player.energy <= float(MineCombatData.ENERGY_MAX))

	# 3 全力药
	_player.hp = 2
	_player.energy = 1.0
	_check("全力药可以用", _player.use_potion(2) == true)
	print("  INFO 全力药后：血 ", _player.hp, "，能量 ", int(_player.energy))
	_check("全力药把血补满", _player.hp == MinePlayer.MAX_HP)
	_check("全力药把能量补满", is_equal_approx(_player.energy, float(MineCombatData.ENERGY_MAX)))
	_check("全力药只剩 0 瓶（开局就 1 瓶）", _player.potion_count(2) == 0)
	_check("用完之后用不了", _player.use_potion(2) == false)

	# 用光
	_player.potions = [0, 0, 0]
	_player.hp = 1
	_player.energy = 0.0
	_check("全用光后三种都喝不了",
		_player.use_potion(0) == false and _player.use_potion(1) == false and _player.use_potion(2) == false)
	_check("越界的 id 直接返回 false", _player.use_potion(99) == false and _player.potion_count(99) == 0)

	print("--- P 技能表 ---")
	var hud2 := _level.get_node("MineHud") as MineHud
	var backdrop := _level.get_node("MineHud/SkillListBackdrop") as ColorRect
	var body := _level.get_node("MineHud/SkillListBody") as Label
	_check("技能表初始是收起的", _player.skill_list_open == false)
	await _step(3)
	_check("收起时面板隐藏", backdrop.visible == false)

	_player.skill_list_open = true
	await _step(3)
	_check("打开后面板显示", backdrop.visible == true)
	print("  INFO 技能表正文：")
	for ln in body.text.split("\n"):
		print("        ", ln)
	_check("表里列出 4 个技能的名字",
		("重斩" in body.text) and ("旋风斩" in body.text) and ("冲刺" in body.text) and ("治疗" in body.text))
	_check("表里带按键提示", "H" in body.text and "U" in body.text and "I" in body.text and "O" in body.text)
	_check("表里带说明文字", "伤害" in body.text or "回复" in body.text or "突进" in body.text)

	_player.skill_list_open = false
	await _step(3)
	_check("再按一次收起", backdrop.visible == false)

	var potion_label := _level.get_node("MineHud/PotionLabel") as Label
	_player.potions = [2, 1, 0]
	await _step(3)
	print("  INFO ", potion_label.text)
	_check("HUD 把三种药都列出来了",
		("回血药" in potion_label.text) and ("能量药" in potion_label.text) and ("全力药" in potion_label.text))
	_check("HUD 显示各自的剩余瓶数", ("x2" in potion_label.text) and ("x1" in potion_label.text) and ("x0" in potion_label.text))
	_check("HUD 显示按键 1/2/3", ("[1]" in potion_label.text) and ("[2]" in potion_label.text) and ("[3]" in potion_label.text))

	print("--- HUD 技能栏 ---")
	var hud := _level.get_node("MineHud") as MineHud
	var labels := hud.skill_labels()
	_check("技能栏有 4 格", labels.size() == 4)
	_reset_skills()
	await _step(3)
	print("  INFO ", labels[0].text, " | ", labels[1].text, " | ", labels[2].text, " | ", labels[3].text)
	_check("技能栏显示按键和名字", ("H" in labels[0].text) and ("重斩" in labels[0].text))
	_check("四个技能各占一格",
		("旋风斩" in labels[1].text) and ("冲刺" in labels[2].text) and ("治疗" in labels[3].text))
	_check("就绪时是亮色", labels[0].get_theme_color("font_color") == MineHud.COLOR_READY)

	_player.cast_skill(0)
	await _step(3)
	print("  INFO 放完重斩后：", labels[0].text)
	_check("冷却中变灰", labels[0].get_theme_color("font_color") == MineHud.COLOR_COOLDOWN)
	_check("冷却中显示剩余秒数", "3" in labels[0].text or "4" in labels[0].text)

	var status := _level.get_node("MineHud/StatusLabel") as Label
	print("  INFO ", status.text)
	_check("状态栏显示能量", "能量" in status.text)
	_check("状态栏显示当前武器", "巨剑" in status.text or "短剑" in status.text)

	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()
