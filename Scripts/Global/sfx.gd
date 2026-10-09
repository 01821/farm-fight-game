extends Node

## 音效播放器。这是一个**自动加载单例**，全局名字就叫 `Sfx`，任何脚本直接 `Sfx.play("hit")`。
##
## 十个 AudioStreamPlayer 都是**预先建在 sfx.tscn 里**的，运行时只调 play()，不创建节点。
## 音效由 Tools/gen_sfx.gd 合成；想调音高/长短改那个脚本重跑即可，也可以整体换成真素材
## （只要文件名不变，这边一行都不用改）。

@onready var _players: Dictionary = {
	"plant": $Plant,
	"water": $Water,
	"harvest": $Harvest,
	"coin": $Coin,
	"buy": $Buy,
	"hit": $Hit,
	"hurt": $Hurt,
	"nightfall": $Nightfall,
	"dawn": $Dawn,
	"goal": $Goal,
}

func player(sound: String) -> AudioStreamPlayer:
	return _players.get(sound) as AudioStreamPlayer

func play(sound: String) -> void:
	var p := player(sound)
	if p == null:
		push_warning("Sfx: 没有叫 " + sound + " 的音效")
		return
	p.play()

## 停掉所有正在播放的音效（给测试或「静音」用）。
##
## 注意：它**不能**消掉 headless 退出时那句
## 「N ObjectDB instances were leaked at exit / M resources still in use at exit」。
## 已经用 --verbose 查过：泄漏的是最后播放的那几个 AudioStreamPlaybackWAV，
## 引用计数 1；之前的播放都正常释放了，所以它**不随游玩时长增长**。
## 哑音频驱动下播放对象停掉后没人回收，真机有声卡时不会有这个现象。
## 只在退出瞬间打印一次，GUI 程序没有控制台，玩家看不到。
func stop_all() -> void:
	for key in _players.keys():
		var p := player(key)
		if p != null:
			p.stop()
