extends Node2D

## 一次性自测：验证作物的「浇水才生长、一次水升一级、成熟可收」规则。
## 用法: godot --headless --path . res://Scenes/_test_plant.tscn

var _fail: int = 0

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _ready() -> void:
	var ps := load("res://Scenes/plants/base_plant.tscn") as PackedScene
	var plant := ps.instantiate() as BasePlant
	plant.growTime = 0.1
	add_child(plant)
	await get_tree().process_frame

	var wet := plant.get_node("WetMark") as Polygon2D
	var spr := plant.get_node("Sprite2D") as Sprite2D

	_check("初始 stage=0", plant.growStage == 0)
	_check("初始未成熟", not plant.is_mature())
	_check("初始湿标记隐藏", not wet.visible)
	print("  初始 region_rect=", spr.region_rect)

	_check("第一次浇水成功", plant.water() == true)
	_check("浇水后变湿", wet.visible and plant.is_watered)
	_check("水分未消耗时重复浇水被拒", plant.water() == false)

	await get_tree().create_timer(0.3).timeout
	_check("长一级后自动变干", plant.growStage == 1 and not plant.is_watered)
	_check("变干后湿标记隐藏", not wet.visible)
	print("  1级 region_rect=", spr.region_rect)

	for i in range(3):
		var ok: bool = plant.water()
		await get_tree().create_timer(0.3).timeout
		print("  浇水#", i + 2, " ok=", ok, " -> stage=", plant.growStage)

	_check("长满 4 级", plant.growStage == 4)
	_check("判为成熟", plant.is_mature())
	_check("成熟后拒绝浇水", plant.water() == false)
	print("  最终 region_rect=", spr.region_rect)

	print("RESULT fail=", _fail)
	get_tree().quit()
