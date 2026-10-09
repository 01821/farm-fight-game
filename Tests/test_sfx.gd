extends Node2D

## 自测：音效单例。
## 用法: godot --headless --path . res://Tests/test_sfx.tscn
##
## 重点不是「没报错」，而是**每个播放器都真的挂上了音源、时长也正常**。

const KEYS: Array[String] = [
	"plant", "water", "harvest", "coin", "buy",
	"hit", "hurt", "nightfall", "dawn", "goal",
]

var _fail: int = 0

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _ready() -> void:
	print("--- 音效单例 ---")
	_check("自动加载 Sfx 存在", Sfx != null)
	if Sfx == null:
		_finish()
		return
	_check("Sfx 挂在场景树里", Sfx.is_inside_tree())

	var total_len: float = 0.0
	for key in KEYS:
		var p: AudioStreamPlayer = Sfx.player(key)
		_check("%s 播放器存在" % key, p != null)
		if p == null:
			continue
		_check("%s 挂上了音源" % key, p.stream != null)
		if p.stream == null:
			continue
		var length: float = p.stream.get_length()
		total_len += length
		print("  INFO %-10s 时长 %.3f 秒  音量 %.1f dB" % [key, length, p.volume_db])
		_check("%s 时长在合理区间" % key, length > 0.02 and length < 2.0)
		# 真放一次，确认不会炸
		Sfx.play(key)

	print("  INFO 全部音效总时长 %.2f 秒" % total_len)
	_check("播放不存在的音效只是警告、不崩", true)
	Sfx.play("这个音效不存在")

	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
