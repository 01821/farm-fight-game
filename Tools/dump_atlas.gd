extends Node

## 把地形图集放大若干倍存出来，方便**用眼睛**数格子、挑对贴图。
## 用法：Godot_v4.7.2-stable_win64.exe --headless --path . res://Tools/dump_atlas.tscn
##
## 为什么需要它：tilemap_packed.png 是 18×18 的无间距紧凑图集（20×9 = 180 格），
## 直接在原尺寸下看根本分不清哪格是什么。选错格子不会报错，
## 只会让平台渲染成一条红白警戒带（这就是我踩的）。

const SRC: String = "res://Assets/kenney_pixel-platformer/tilemap_packed.png"
const OUT: String = "user://atlas_zoom.png"
const SCALE: int = 5

func _ready() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if img == null:
		# res:// 打包之后要用 load
		var tex := load(SRC) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null:
		print("[图集] 读不到 ", SRC)
		get_tree().quit()
		return
	print("[图集] 原始尺寸 ", img.get_width(), "x", img.get_height(),
		"（", img.get_width() / 18, " 列 × ", img.get_height() / 18, " 行，每格 18px）")
	img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	var err := img.save_png(OUT)
	print("[图集] 放大 ", SCALE, " 倍 -> ", ProjectSettings.globalize_path(OUT), "（", err == OK, "）")
	get_tree().quit()
