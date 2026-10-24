extends Node2D
## 主控 —— 六部族塔防（Tribes TD）预研切片的场景根节点。
##
## 职责划分：
##   addons/td_core/   塔的放置/索敌/伤害、敌人的路径行走、波次调度（MIT，未改动）
##   game/merit.gd     功勋系统：第二资源、档位解锁、人口、主动技能（本项目核心差异）
##   game/hud.gd       竖屏 HUD：资源条、塔卡片、技能栏（自绘 + 手动命中测试）
##   game/main.gd      本文件：状态机、输入、建造校验、渲染
##
## 竖屏 720×1280，棋盘 9×15 格 × 64px = 576×960，左上角偏移 (72, 150)。

const SCREEN := Vector2(720, 1280)
const BOARD_ORIGIN := Vector2(72, 150)
const BOARD_SIZE := Vector2(576, 960)

## 波次之间的自动间隔（秒）。手机端不做「手动点开始」，改成自动流转。
const WAVE_GAP := 2.5

const BG := Color("#0B1420")
const PATH_COLOR := Color("#1E2E3E")
const PATH_EDGE := Color("#2C4257")
const GRID_COLOR := Color("#17242F")
const HOVER_OK := Color("#2ECC71")
const HOVER_BAD := Color("#E74C3C")

var content: TDContent
var spawner: TDWaveSpawner
var merit: MeritSystem
var hud: Node

var professions: Array = []
var profession_index: int = 0
var build_id: StringName = &"r1"

var hover_cell: Vector2i = Vector2i(-1, -1)
var selected_tower: TDTower = null
var status_text: String = ""
var status_time: float = 0.0
var wave_timer: float = 0.0

var _tex_grass: Texture2D
var _tex_dirt: Texture2D
var _tex_enemy: Dictionary = {}


func _ready() -> void:
	position = BOARD_ORIGIN
	_tex_grass = load("res://assets/sprites/grass.png")
	_tex_dirt = load("res://assets/sprites/dirt.png")
	# 只 load 两次，五种敌人共用两张贴图（靠 modulate 区分），避免重复加载同一资源
	var tex_green: Texture2D = load("res://assets/sprites/soldier_green.png")
	var tex_brown: Texture2D = load("res://assets/sprites/soldier_brown.png")
	for id: String in ["soldier", "brute", "boss"]:
		_tex_enemy[id] = tex_green
	for id: String in ["scout", "flyer"]:
		_tex_enemy[id] = tex_brown
	restart()


# ------------------------------------------------------------------ 生命周期

func restart() -> void:
	if spawner != null:
		spawner.queue_free()
		spawner = null
	content = TDContent.load_file("res://data/content.json")
	if not content.errors.is_empty():
		push_error("content.json 有误: %s" % str(content.errors))
		return
	professions = _load_professions()
	profession_index = 0
	build_id = _first_unlocked_tower()

	merit = MeritSystem.new()
	spawner = TDWaveSpawner.new()
	spawner.configure(content)
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	spawner.wave_cleared.connect(_on_wave_cleared)
	spawner.all_waves_cleared.connect(_on_victory)
	spawner.economy.defeated.connect(_on_defeat)
	add_child(spawner)

	selected_tower = null
	wave_timer = 0.0
	toast("选一个部族，点地图造塔。塔的击杀会攒功勋。")
	_ensure_hud()
	if _demo_requested():
		_apply_demo()


## 演示模式：命令行加 `--demo`，或网页加 `?demo=1`。
## 自动布防 + 给足资源，用来截图、录片、给评审一眼看终局，不影响正常开局。
func _demo_requested() -> bool:
	if "--demo" in OS.get_cmdline_args():
		return true
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		if q is String and (q as String).contains("demo"):
			return true
	return false


func _apply_demo() -> void:
	spawner.economy.earn(9000)
	merit.add(1000)
	for tier: int in [2, 3, 4, 5, 6, 7]:
		merit.try_unlock(tier)
	# 六部族各来一座，摆在路两侧，把「战力差别」摆在画面里
	var plan: Array = [
		[&"r4", Vector2i(1, 0)], [&"r5", Vector2i(3, 2)], [&"o4", Vector2i(5, 2)],
		[&"h5", Vector2i(5, 5)], [&"b4", Vector2i(1, 6)], [&"s4", Vector2i(3, 8)],
		[&"g4", Vector2i(5, 11)], [&"r6", Vector2i(1, 12)],
	]
	for item: Array in plan:
		var t: TDTower = content.make_tower(item[0])
		spawner.place_tower_at_cell(t, item[1])
		# td_core 的塔默认会自绘「灰方块 + 射程圈」用于调试，正式渲染由本文件接管
		t.debug_draw = false
	spawner.start_next_wave()
	toast("演示布防：8 座塔 · 功勋已解锁到第 7 档")


## content.json 的 professions 是本项目扩展字段，TDContent 不认识，手动读一次。
func _load_professions() -> Array:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	if raw is Dictionary:
		return (raw as Dictionary).get("professions", [])
	return []


func _ensure_hud() -> void:
	if hud != null:
		return
	# HUD 必须挂在 CanvasLayer 下：否则会跟随 main 的 position 变换，被推出屏幕。
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HudLayer"
	layer.layer = 10
	add_child(layer)
	hud = load("res://game/hud.gd").new()
	layer.add_child(hud)
	hud.setup(self)


func current_profession() -> Dictionary:
	if profession_index < 0 or profession_index >= professions.size():
		return {}
	return professions[profession_index]


func _first_unlocked_tower() -> StringName:
	var p: Dictionary = current_profession()
	var ids: Array = p.get("towers", [])
	return StringName(str(ids[0])) if not ids.is_empty() else &"r1"


# ------------------------------------------------------------------ 主循环

func _process(delta: float) -> void:
	if spawner == null:
		return
	# 排查用：加 --trace-enemies 会每 2 秒打印场上所有敌人的坐标，
	# 用来核对「地图画出来的路」和「敌人实际走的路」是否一致。
	if OS.get_cmdline_args().has("--trace-enemies") and Engine.get_process_frames() % 120 == 0:
		var parts: Array[String] = []
		for e1: TDEnemy in spawner.enemies:
			parts.append("%s@%s" % [str(e1.id), str(e1.position.round())])
		print("[trace] f=%d wave=%d onfield=%d %s" % [
			Engine.get_process_frames(), spawner.wave_index,
			spawner.enemies.size(), " ".join(parts).left(300)])
	merit.sync_kills(spawner.towers, content, spawner.economy)
	status_time = maxf(0.0, status_time - delta)

	# 本波清空后自动接下一波。手机端不做「手动点开始」，避免空转。
	if not spawner.is_game_over() and spawner.enemies_left_in_wave() <= 0:
		if spawner.wave_index + 1 < spawner.waves.size():
			wave_timer += delta
			if wave_timer >= WAVE_GAP:
				wave_timer = 0.0
				spawner.start_next_wave()
	queue_redraw()


func toast(msg: String) -> void:
	status_text = msg
	status_time = 3.0


# ------------------------------------------------------------------ 建造

func tower_def(id: StringName) -> Dictionary:
	return content.tower_def(id)


func tier_locked(id: StringName) -> bool:
	return not merit.is_unlocked(int(tower_def(id).get("tier", 1)))


func pop_used() -> int:
	return spawner.towers.size() if spawner != null else 0


## 是否可造：档位解锁 → 人口 → 格子合法性 → 金币。
## 顺序很重要：先给出「为什么不能造」，玩家才知道该攒功勋还是攒钱。
func build_block_reason(c: Vector2i) -> String:
	var def: Dictionary = tower_def(build_id)
	var tier: int = int(def.get("tier", 1))
	if not merit.is_unlocked(tier):
		return "第 %d 档未解锁，需累计 %d 功勋" % [tier, merit.required_merit(tier)]
	if pop_used() >= merit.pop_cap():
		return "人口已满 %d/%d" % [pop_used(), merit.pop_cap()]
	var err: String = spawner.placement_error(c, content.tower_cost(build_id))
	if err != "":
		if err.contains("gold") or err.contains("afford"):
			return "金币不足（需 %d）" % content.tower_cost(build_id)
		return err
	return ""


func try_build(c: Vector2i) -> bool:
	var why: String = build_block_reason(c)
	if why != "":
		toast(why)
		return false
	var t: TDTower = content.make_tower(build_id)
	if not spawner.place_tower_at_cell(t, c):
		toast("这个位置放不了")
		return false
	t.debug_draw = false
	selected_tower = t
	toast("%s 已就位" % t.display_name)
	return true


func try_upgrade(t: TDTower) -> void:
	if t == null:
		return
	if not t.can_upgrade():
		toast("%s 已满级" % t.display_name)
		return
	var cost: int = t.upgrade_cost()
	if not spawner.economy.can_afford(cost):
		toast("金币不足（需 %d）" % cost)
		return
	t.upgrade(spawner.economy)
	toast("%s 升到 %d 级" % [t.display_name, t.level])


func try_sell(t: TDTower) -> void:
	if t == null:
		return
	var refund: int = spawner.sell_tower(t)
	selected_tower = null
	toast("已出售，退回 %d 金币" % refund)


func try_unlock_tier() -> void:
	var tier: int = merit.next_locked_tier()
	if tier <= 0:
		toast("全部档位已解锁")
		return
	var req: int = merit.required_merit(tier)
	if merit.merit < req:
		toast("第 %d 档需 %d 功勋（现有 %d）" % [tier, req, merit.merit])
		return
	merit.try_unlock(tier)
	toast("第 %d 档解锁，人口上限 %d" % [tier, merit.pop_cap()])


func switch_profession(dir: int) -> void:
	if professions.is_empty():
		return
	profession_index = posmod(profession_index + dir, professions.size())
	build_id = _first_unlocked_tower()
	selected_tower = null
	toast("%s：%s" % [current_profession().get("name", ""), current_profession().get("desc", "")])


# ------------------------------------------------------------------ 主动技能

func use_skill(id: StringName) -> void:
	var s: Dictionary = merit.skill_by_id(id)
	if s.is_empty():
		return
	if not merit.can_use_skill(id):
		toast("功勋不足（%s 需 %d）" % [s["name"], int(s["cost"])])
		return
	match id:
		&"rally":
			if merit.pay_for_skill(id):
				spawner.economy.earn(90)
				toast("增援到位：+90 金币")
		&"freeze":
			if merit.pay_for_skill(id):
				for e: TDEnemy in spawner.enemies:
					e.apply_slow(0.45, 4.0)
				toast("冰封：全场减速 55%，4 秒")
		&"verdict":
			var target: TDEnemy = _strongest_enemy()
			if target == null:
				toast("场上没有目标")
				return
			if merit.pay_for_skill(id):
				# 注意：技能击杀不进入 tower.kills，所以不给功勋。
				# 这条规则是原版机制的直接继承，也是双资源张力的关键。
				target.take_damage(420.0)
				toast("裁决命中 %s" % target.id)


func _strongest_enemy() -> TDEnemy:
	var best: TDEnemy = null
	var best_hp: float = -1.0
	for e: TDEnemy in spawner.enemies:
		if e.hp > best_hp:
			best_hp = e.hp
			best = e
	return best


# ------------------------------------------------------------------ 信号

func _on_enemy_spawned(e: TDEnemy) -> void:
	e.debug_draw = false


func _on_wave_cleared(i: int) -> void:
	toast("第 %d 波清空" % (i + 1))


func _on_victory() -> void:
	toast("守住 15 波，通关")


func _on_defeat() -> void:
	toast("基地失守")


# ------------------------------------------------------------------ 输入

func _input(event: InputEvent) -> void:
	if spawner == null:
		return
	if hud != null and hud.handle_input(event):
		return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		hover_cell = spawner.map.cell_at(to_local(motion.position))
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		hover_cell = spawner.map.cell_at(to_local(drag.position))
		return

	var press_pos: Variant = null
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		press_pos = touch.position
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		press_pos = mb.position
	if press_pos == null:
		return

	var local: Vector2 = to_local(press_pos)
	var c: Vector2i = spawner.map.cell_at(local)
	if spawner.map.in_bounds(c):
		# 已有点击到的塔 → 选中，供升级/出售；空地 → 建造
		var exist: TDTower = spawner.tower_at_cell(c)
		if exist != null:
			selected_tower = exist
		else:
			try_build(c)


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_R:
			restart()
		KEY_TAB:
			switch_profession(1)
		KEY_U:
			try_upgrade(selected_tower)
		KEY_S:
			try_sell(selected_tower)
		KEY_K:
			try_unlock_tier()
		KEY_1:
			use_skill(&"rally")
		KEY_2:
			use_skill(&"freeze")
		KEY_3:
			use_skill(&"verdict")


# ------------------------------------------------------------------ 渲染

func _draw() -> void:
	draw_rect(Rect2(Vector2(-BOARD_ORIGIN.x, -BOARD_ORIGIN.y), SCREEN), BG)
	# 内容解析失败时 spawner 会是 null，_draw 仍会被调用，先挡住。
	if spawner == null or spawner.map == null:
		return

	# 地面：Kenney 那两张草/土其实是纯色块，贴上去反而更平，所以直接按格子
	# 铺底色 + 每格一点确定性微差，远看才有「草地不是一块油漆」的层次。
	var map: TDMap = spawner.map
	for x: int in range(9):
		for y: int in range(15):
			var v := 0.016 * float((x * 7 + y * 13) % 5)
			draw_rect(Rect2(Vector2(x, y) * 64.0, Vector2(64, 64)),
				Color(0.150 + v, 0.272 + v, 0.212 + v))

	# 路径：冷灰石板，比草地亮一档，靠明度差把路「抬」出来
	for c: Vector2i in map.path_cells():
		if not map.in_bounds(c):
			continue
		var r := Rect2(Vector2(c) * 64.0, Vector2(64, 64))
		var pv := 0.014 * float((c.x * 11 + c.y * 5) % 4)
		draw_rect(r, Color(0.208 + pv, 0.262 + pv, 0.325 + pv))
		draw_rect(r, Color(0.34, 0.42, 0.52, 0.30), false, 1.0)

	# 网格：只做很淡的参考线，别抢地面的戏
	for x: int in range(10):
		draw_line(Vector2(x * 64, 0), Vector2(x * 64, BOARD_SIZE.y),
			Color(GRID_COLOR, 0.35), 1.0)
	for y: int in range(16):
		draw_line(Vector2(0, y * 64), Vector2(BOARD_SIZE.x, y * 64),
			Color(GRID_COLOR, 0.35), 1.0)

	_draw_hover()
	_draw_towers()
	_draw_enemies()
	_draw_selection()


func _draw_hover() -> void:
	if hover_cell.x < 0:
		return
	var c: Vector2i = hover_cell
	if not spawner.map.in_bounds(c):
		return
	var r := Rect2(Vector2(c) * 64.0, Vector2(64, 64))
	var ok: bool = build_block_reason(c) == "" and spawner.tower_at_cell(c) == null
	draw_rect(r, Color(HOVER_OK, 0.16) if ok else Color(HOVER_BAD, 0.16))
	draw_rect(r, HOVER_OK if ok else HOVER_BAD, false, 2.0)
	# 范围预览：放下之前就告诉玩家能打到哪
	if ok:
		var rng: float = float(tower_def(build_id).get("range", 96))
		draw_arc(Vector2(c) * 64.0 + Vector2(32, 32), rng, 0, TAU, 64,
			Color(HOVER_OK, 0.35), 2.0)
		draw_arc(Vector2(c) * 64.0 + Vector2(32, 32), rng, 0, TAU, 64,
			Color(HOVER_OK, 0.10), 6.0)


func _draw_towers() -> void:
	for t: TDTower in spawner.towers:
		var def: Dictionary = content.tower_def(t.id)
		var col := Color(str(def.get("color", "#8899AA")))
		var shape := str(def.get("shape", "square"))
		var p: Vector2 = t.position
		var s: float = 19.0 + 3.0 * float(t.level)
		# 射程：只在选中时显示，避免屏幕被圆环淹没
		if t == selected_tower:
			draw_arc(p, t.range_px, 0, TAU, 64, Color(col, 0.45), 2.0)
		# 石台 + 投影：让塔有厚度，不是贴在地上的一块色
		draw_circle(p + Vector2(0, 4), s * 1.06, Color(0, 0, 0, 0.35))
		draw_circle(p, s * 1.06, Color(0.16, 0.20, 0.25))
		draw_arc(p, s * 1.06, 0, TAU, 32, Color(col, 0.45), 1.5)
		match shape:
			"circle":
				draw_circle(p, s, col)
			"diamond":
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -s), p + Vector2(s, 0),
					p + Vector2(0, s), p + Vector2(-s, 0)]), col)
			"hex":
				draw_colored_polygon(_poly(p, s, 6), col)
			"star":
				draw_colored_polygon(_poly(p, s * 1.15, 10), col)
			_:
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
		# 等级角标（只有升过级才显示，避免满屏小圆点）
		if t.level > 1:
			draw_circle(p + Vector2(s * 0.75, -s * 0.75), 8.0, Color("#0B1420"))
			draw_circle(p + Vector2(s * 0.75, -s * 0.75), 6.0, col.lightened(0.35))


func _draw_enemies() -> void:
	for e: TDEnemy in spawner.enemies:
		var p: Vector2 = e.position
		var tex: Texture2D = _tex_enemy.get(str(e.id), null)
		# 贴图是 Kenney 的两张基色图，靠 modulate 拉开辨识度。
		# 之前用的都是暗色，叠在暗绿草地上糊成一团，这里统一提亮。
		var col := Color("#EEF6FF")          # soldier
		if e.id == &"brute":
			col = Color("#F0A878")
		elif e.id == &"flyer":
			col = Color("#A8E0FF")
		elif e.id == &"boss":
			col = Color("#FF8FA8")
		elif e.id == &"scout":
			col = Color("#FFE98A")
		if tex != null:
			# 影子先把单位从地面「抬」起来，否则 40px 的贴图会糊在 64px 的格子里
			draw_circle(p + Vector2(0, 7), 15.0, Color(0, 0, 0, 0.30))
			draw_texture_rect(tex, Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, col)
		else:
			draw_circle(p, 16.0, col)
		if e.flying:
			draw_arc(p, 24.0, 0, TAU, 24, Color(col, 0.5), 1.5)
		# 血条
		var ratio: float = clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
		var bar := Rect2(p + Vector2(-22, -33), Vector2(44, 5))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 5)),
			Color("#E74C3C").lerp(Color("#2ECC71"), ratio))


func _draw_selection() -> void:
	var t: TDTower = selected_tower
	if t == null or not is_instance_valid(t):
		return
	var p: Vector2 = t.position
	draw_arc(p, 30.0, 0, TAU, 40, Color("#E0C05B"), 2.0)


func _poly(center: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(n):
		var a: float = -PI / 2.0 + TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
