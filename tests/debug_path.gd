extends SceneTree
## 一次性排查脚本：确认「地图画出来的路」和「敌人实际走的路」是同一条。
## godot --headless --path . -s res://tests/debug_path.gd


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var c: TDContent = TDContent.load_file("res://data/content.json")
	var m: TDMap = c.make_map()
	print("waypoints = ", m.waypoints)
	var wp: PackedVector2Array = m.world_path()
	print("world_path 点数 = %d" % wp.size())
	for i: int in mini(wp.size(), 6):
		print("  p%d = %s" % [i, str(wp[i])])
	print("path_cells 前 8 个 = ", m.path_cells().slice(0, 8))

	var sp: TDWaveSpawner = TDWaveSpawner.new()
	sp.auto_tick = false
	sp.configure(c)
	root.add_child(sp)
	sp.start_next_wave()
	var guard: int = 0
	while sp.enemies.size() < 3 and guard < 600:
		sp.advance(0.05)
		guard += 1
	print("敌人位置：")
	for e: TDEnemy in sp.enemies:
		print("  id=%s pos=%s cell=%s" % [str(e.id), str(e.position), str(m.cell_at(e.position))])
	quit(0)
