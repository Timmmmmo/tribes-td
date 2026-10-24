extends SceneTree
## 一次性核对脚本：把「地图画出来的路」和「敌人实际走的路」逐点打出来。
## 用法：godot --headless -s res://tests/dump_path.gd

const DT := 1.0 / 60.0

func _init() -> void:
	var c: TDContent = TDContent.load_file("res://data/content.json")
	if not c.errors.is_empty():
		print("content errors: ", c.errors)
		quit(1)
		return
	var sp: TDWaveSpawner = TDWaveSpawner.new()
	sp.auto_tick = false
	sp.configure(c)
	root.add_child(sp)

	print("map cols=%d rows=%d cell=%.0f" % [sp.map.cols, sp.map.rows, sp.map.cell_px])
	print("waypoints = ", sp.map.waypoints)
	print("world_path = ", sp.path)
	var cells: Array[Vector2i] = sp.map.path_cells()
	print("path_cells(%d) = %s" % [cells.size(), str(cells)])

	# 只放一只怪，让它从头走到底，每 0.5 秒记一次坐标
	sp.economy.earn(0)
	sp.auto_tick = false
	sp.waves = [[{"enemy": "soldier", "count": 1, "interval": 0.0,
		"hp": 1.0e9, "speed": 120.0, "bounty": 0}]]
	sp.wave_bonuses = [0]
	sp.start_next_wave()

	var t := 0.0
	var next_print := 0.0
	var last := Vector2(9999, 9999)
	var seam_jumps: Array[String] = []
	for i: int in range(60 * 40):
		sp.advance(DT)
		t += DT
		if sp.enemies.is_empty():
			break
		var e: TDEnemy = sp.enemies[0]
		# 相邻两帧的位移若超过一帧速度的 3 倍，说明路径接缝处有跳变
		var step: float = e.position.distance_to(last)
		if last.x < 9000 and step > 120.0 * DT * 3.0:
			seam_jumps.append("frame %d jump %.1fpx %s -> %s" % [i, step, last, e.position])
		last = e.position
		if t >= next_print:
			next_print += 0.5
			var cell: Vector2i = sp.map.cell_at(e.position)
			print("t=%.2f pos=%s cell=%s seg_progress=%.1f heading=%.0fdeg" % [
				t, str(e.position), str(cell), e.progress, rad_to_deg(e.heading)])

	print("seam jumps: ", seam_jumps.size())
	for s: String in seam_jumps:
		print("  ", s)
	quit(0)
