extends Node

## 一次性音效生成器：用代码合成 WAV，写进 res://Assets/sounds/。
## 用法: godot --headless --path . res://Tools/gen_sfx.tscn
##
## 为什么用生成的而不是下载素材：
##   1. 零版权顾虑，可以直接放进公开仓库；
##   2. 每个音都只有几千字节；
##   3. 参数都在这里，想调音高/长短改一行重跑即可，也可以随时整体换成真素材。
##
## ⚠️ 生成的是「提示音」级别的东西（短正弦/噪声包络），不是有审美的音效设计。
##    它的作用是给操作即时反馈，好不好听要靠人耳判断。

const RATE: int = 22050
const OUT_DIR: String = "res://Assets/sounds"

func _ready() -> void:
	seed(20261009)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 播种：闷闷一声「噗」
	_save("plant", _sweep(0.09, 230.0, 160.0, 2.5, 0.50, 0.15))
	# 浇水：一小段水声（噪声为主）
	_save("water", _sweep(0.20, 900.0, 300.0, 2.0, 0.32, 0.85))
	# 收获：上行两声
	_save("harvest", _seq([
		_tone(0.07, 523.0, 523.0, 3.0, 0.40),
		_tone(0.10, 784.0, 784.0, 3.0, 0.40),
	]))
	# 卖钱：清脆「叮」
	_save("coin", _seq([
		_tone(0.05, 988.0, 988.0, 2.0, 0.42),
		_tone(0.13, 1319.0, 1319.0, 4.0, 0.36),
	]))
	# 买种子：下行「叮」
	_save("buy", _seq([
		_tone(0.05, 1319.0, 1319.0, 2.0, 0.34),
		_tone(0.12, 880.0, 880.0, 4.0, 0.34),
	]))
	# 砍中：短促噪声爆
	_save("hit", _sweep(0.10, 400.0, 90.0, 4.0, 0.50, 0.70))
	# 受伤：低沉蜂鸣
	_save("hurt", _sweep(0.26, 170.0, 90.0, 2.0, 0.45, 0.25))
	# 入夜：缓慢下沉，带一点不安
	_save("nightfall", _sweep(0.75, 320.0, 110.0, 1.2, 0.30, 0.05))
	# 天亮：缓慢上行
	_save("dawn", _sweep(0.55, 330.0, 660.0, 1.2, 0.26, 0.0))
	# 达成目标：小琶音
	_save("goal", _seq([
		_tone(0.12, 523.0, 523.0, 2.0, 0.34),
		_tone(0.12, 659.0, 659.0, 2.0, 0.34),
		_tone(0.12, 784.0, 784.0, 2.0, 0.34),
		_tone(0.30, 1047.0, 1047.0, 2.5, 0.36),
	]))

	print("[音效] 生成完毕 -> ", OUT_DIR)
	get_tree().quit()

## 一段从 f0 滑到 f1 的音，noise 是混入的噪声比例（做水声/打击声用）
func _tone(dur: float, f0: float, f1: float, decay: float, amp: float, noise: float = 0.0) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur * float(RATE)))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(f0, f1, t) / float(RATE)
		var env: float = pow(maxf(0.0, 1.0 - t), decay)
		var s: float = sin(phase)
		if noise > 0.0:
			s = lerpf(s, randf() * 2.0 - 1.0, noise)
		out[i] = s * env * amp
	return out

func _sweep(dur: float, f0: float, f1: float, decay: float, amp: float, noise: float) -> PackedFloat32Array:
	return _tone(dur, f0, f1, decay, amp, noise)

func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

func _save(name: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	for s in samples:
		var v: int = int(clampf(s, -1.0, 1.0) * 32767.0)
		data.append(v & 0xFF)
		data.append((v >> 8) & 0xFF)

	var f := FileAccess.open(OUT_DIR + "/" + name + ".wav", FileAccess.WRITE)
	if f == null:
		push_error("写不进去: " + name)
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)              # fmt chunk 大小
	f.store_16(1)               # PCM
	f.store_16(1)               # 单声道
	f.store_32(RATE)
	f.store_32(RATE * 2)        # 字节率
	f.store_16(2)               # 块对齐
	f.store_16(16)              # 位深
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	print("  ", name, ".wav  ", samples.size(), " 帧  ", (data.size() + 44) / 1024, " KB")
