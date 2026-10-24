extends SceneTree
## 地形烘焙耗时自测。烘焙是开局一次性成本，超过 ~150ms 就得砍草叶数量。

func _init() -> void:
	var c: TDContent = TDContent.load_file("res://data/content.json")
	var sp: TDWaveSpawner = TDWaveSpawner.new()
	sp.configure(c)
	var t0: int = Time.get_ticks_msec()
	var tex: ImageTexture = TDArt.bake_map(sp.map)
	var dt: int = Time.get_ticks_msec() - t0
	print("bake_map: %d ms, %dx%d" % [dt, tex.get_width(), tex.get_height()])
	quit(0)
