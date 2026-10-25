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

## 波次之间的准备时间（秒）。
## 原来这里叫 WAVE_GAP = 2.5，到点自动开下一波，玩家没有插手的余地。
## 改成 12 秒倒计时之后，「等」变成了「要不要现在开」的决策：
## 提前开波按剩余秒数折金币，倒计时归零则自动开、不拿奖励。
## 这是塔防品类最便宜的一个「把玩家拽回驾驶座」的改动（Kingdom Rush 的 Call Wave）。
const PREP_TIME := 12.0
## 提前开波，每省下 1 秒换多少金币。12 秒全换 = 24 金币 ≈ 半个 T1 塔。
const EARLY_BONUS_PER_SEC := 2

## 装备掉落概率与上限。上限是为了不让棋盘被掉落物铺满 —— 掉落物是「奖励」，
## 一旦变成地上的垃圾，玩家就不会为了它去动英雄。
const DROP_CHANCE := 0.14
const ITEM_CAP := 6
const ITEM_LIFETIME := 30.0
const ITEM_PICK_RADIUS := 26.0

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
var status: StatusSystem
var hero: HeroUnit

var professions: Array = []
var profession_index: int = 0
var build_id: StringName = &"r1"

var hover_cell: Vector2i = Vector2i(-1, -1)
var selected_tower: TDTower = null
var status_text: String = ""
var status_time: float = 0.0

## 准备阶段：_awaiting_wave 为真时 prep_left 在倒数，数到 0 自动开波。
var prep_left: float = 0.0
var _awaiting_wave: bool = false

## 掉落物：[{pos, kind, level, t}]
var _items: Array[Dictionary] = []
## 正在拖英雄
var _hero_drag: bool = false

## 渲染侧的全部状态。这些都不是玩法数据，所以不进 spawner/merit，
## 清空重开时一起丢掉 —— 视觉残留留在新局里没有意义。
var _terrain: ImageTexture
var _time: float = 0.0
var _shake: float = 0.0
var _shake_off: Vector2 = Vector2.ZERO
var _particles: Array[Dictionary] = []
var _floaters: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _flash: Dictionary = {}


func _ready() -> void:
	position = BOARD_ORIGIN
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
	spawner.tower_placed.connect(_on_tower_placed)
	spawner.wave_cleared.connect(_on_wave_cleared)
	spawner.all_waves_cleared.connect(_on_victory)
	spawner.economy.defeated.connect(_on_defeat)
	add_child(spawner)

	# 地形是一张烘焙贴图，重开时重建（地图数据可能被改），其余视觉残留直接清掉
	_terrain = TDArt.bake_map(spawner.map) if spawner.map != null else null
	_particles.clear()
	_floaters.clear()
	_rings.clear()
	_beams.clear()
	_flash.clear()
	_shake = 0.0

	# 英雄与状态机是这一轮新增的两套系统，必须跟 spawner 一起重建
	status = StatusSystem.new()
	status.setup(spawner, content)
	status.split_requested.connect(_on_split_requested)
	var hero_start: Vector2 = spawner.map.cell_center(Vector2i(1, 3))
	hero = HeroUnit.new()
	hero.reset(hero_start)
	_items.clear()
	prep_left = PREP_TIME
	_awaiting_wave = true
	_hero_drag = false

	selected_tower = null
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
	_tick_effects(delta)
	status.tick(delta)
	_tick_hero(delta)
	_tick_items(delta)
	_tick_waves(delta)
	# 验证用：加 `--autoplay` 会在每次准备阶段立刻开波，
	# 相当于一个「很急的玩家」，用来在录屏里跑到中后段看机制。正常游戏不会传这个参数。
	if OS.get_cmdline_args().has("--autoplay") and _awaiting_wave:
		start_wave_early()
	queue_redraw()


## 波次节奏：清空 → 进准备阶段倒数 → 归零自动开。
## 手动开波走 start_wave_early()，两者共用 _awaiting_wave 这一个状态位。
func _tick_waves(delta: float) -> void:
	if spawner == null or spawner.is_game_over():
		return
	if spawner.enemies_left_in_wave() > 0:
		_awaiting_wave = false
		prep_left = 0.0
		return
	if spawner.wave_index + 1 >= spawner.waves.size():
		return  # 全清，没有下一波了
	if not _awaiting_wave:
		_awaiting_wave = true
		prep_left = PREP_TIME
		return
	prep_left = maxf(0.0, prep_left - delta)
	if prep_left <= 0.0:
		_awaiting_wave = false
		spawner.start_next_wave()


## 玩家点「开波」。剩下的准备时间按秒折金币 —— 这是这一版里
## 唯一一个「主动承担风险换收益」的按钮，前期的金币节奏全靠它。
func start_wave_early() -> void:
	if spawner == null or spawner.is_game_over() or not _awaiting_wave:
		return
	if spawner.wave_index + 1 >= spawner.waves.size():
		return
	var reward: int = int(ceil(prep_left)) * EARLY_BONUS_PER_SEC
	_awaiting_wave = false
	prep_left = 0.0
	if reward > 0:
		spawner.economy.earn(reward)
		_float_text(hero.pos + Vector2(0, -30), "+%d 金币" % reward, Color("#F2C14E"), 17)
		toast("提前开波，多拿 %d 金币" % reward)
	spawner.start_next_wave()


func next_wave_hint() -> Array[Dictionary]:
	if spawner == null:
		return [] as Array[Dictionary]
	return WaveIntel.rows(content, spawner.wave_index + 1)


## 是否处于「两侧波次之间、可以提前开波」的窗口。
func is_prep_phase() -> bool:
	return _awaiting_wave and spawner != null and not spawner.is_game_over()


## 提前开波能拿多少金币（HUD 要显示这个数，玩家才会算这笔账）。
func early_wave_bonus() -> int:
	return int(ceil(prep_left)) * EARLY_BONUS_PER_SEC if _awaiting_wave else 0


## 准备阶段还剩多少比例（1 = 刚开始，0 = 马上自动开波）。
func prep_progress() -> float:
	return clampf(prep_left / PREP_TIME, 0.0, 1.0)


func _tick_hero(delta: float) -> void:
	if hero == null:
		return
	var hit: TDEnemy = hero.tick(delta, spawner.enemies)
	if hit == null:
		return
	# 英雄击杀只给金币（内核的 economy 走 killed 信号），绝不给功勋 ——
	# 功勋只认 TDTower.kills，这里一行都不碰。
	_beams.append({"from": hero.pos, "to": hit.position,
		"color": Color("#FFE9A6"), "life": 0.09, "t": 0.0})
	_spawn_burst(hit.position, Color("#FFE9A6"), 3, 80.0)


func _tick_items(delta: float) -> void:
	if _items.is_empty() or hero == null:
		return
	var board := Rect2(Vector2.ZERO, BOARD_SIZE)
	# 先结算拾取，再走存活时间 —— 顺序反了会出现「已经捡走却又被判过期」
	var picked: Dictionary = {}
	for it: Dictionary in hero.collect_near(_items, ITEM_PICK_RADIUS):
		picked[it] = true
		var msg: String = hero.pick_equipment(str(it["kind"]), int(it["level"]))
		_spawn_burst(it["pos"], HeroUnit.SLOT_COLORS.get(str(it["kind"]), Color.WHITE), 8, 110.0)
		_float_text(it["pos"], msg if msg != "" else "装备", Color("#BFE8FF"), 14)
		if msg != "":
			toast("英雄：" + msg)

	var alive: Array[Dictionary] = []
	for it: Dictionary in _items:
		if picked.has(it):
			continue
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) >= ITEM_LIFETIME:
			continue
		alive.append(it)
	_items = alive
	# 兜底：英雄被拖到棋盘外时不该把装备也拉出去
	if not board.has_point(hero.pos):
		hero.teleport(hero.pos.clamp(board.position, board.end), board)


func _maybe_drop_item(pos: Vector2) -> void:
	if _items.size() >= ITEM_CAP or randf() > DROP_CHANCE:
		return
	var kind: String = HeroUnit.SLOTS[randi() % HeroUnit.SLOTS.size()]
	# 后期直接掉二级，否则 9 件一级才合成一件三级，一局根本攒不出来
	var lvl: int = 2 if spawner.wave_index >= 8 else 1
	_items.append({"pos": pos, "kind": kind, "level": lvl, "t": 0.0})


## 分裂请求：状态机只算出「裂成什么、多少血、走哪条路」，生成放在这里，
## 因为要碰 spawner.enemies 和它的击杀/漏怪回调。
func _on_split_requested(into: StringName, hp: float, speed: float, bounty: int,
		path: PackedVector2Array, count: int) -> void:
	for i: int in range(count):
		var e: TDEnemy = TDEnemy.new()
		e.id = into
		e.setup(path, hp, speed, bounty)
		# 两只稍微错开，否则完全重叠看起来像一只没死
		e.position += Vector2(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		# 这两个是 spawner 的私有回调，但走的是它自己的赏金/移除逻辑。
		# 在这里重写一遍等于复制内核代码，反而更容易和上游跑偏。
		e.killed.connect(spawner._on_killed)
		e.leaked.connect(spawner._on_leaked)
		spawner.add_child(e)
		spawner.enemies.append(e)
		_on_enemy_spawned(e)


func _tick_effects(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta * 3.2)

	var alive: Array[Dictionary] = []
	for p: Dictionary in _particles:
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) >= float(p["life"]):
			continue
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["vel"] = (p["vel"] as Vector2) * (1.0 - 3.4 * delta)
		alive.append(p)
	_particles = alive

	alive = []
	for f: Dictionary in _floaters:
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) >= float(f["life"]):
			continue
		f["pos"] = (f["pos"] as Vector2) + Vector2(0, -34.0 * delta)
		alive.append(f)
	_floaters = alive

	alive = []
	for r: Dictionary in _rings:
		r["t"] = float(r["t"]) + delta
		if float(r["t"]) < float(r["life"]):
			alive.append(r)
	_rings = alive

	alive = []
	for b: Dictionary in _beams:
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) < float(b["life"]):
			alive.append(b)
	_beams = alive

	for k: int in _flash.keys():
		var v: float = float(_flash[k]) - delta
		if v <= 0.0:
			_flash.erase(k)
		else:
			_flash[k] = v


func _spawn_burst(pos: Vector2, col: Color, n: int, power: float) -> void:
	for i: int in range(n):
		var a: float = TAU * (float(i) / float(maxi(n, 1))) + randf() * 0.5
		var sp: float = power * (0.55 + randf() * 0.75)
		_particles.append({
			"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp,
			"life": 0.32 + randf() * 0.30, "t": 0.0,
			"r": 1.4 + randf() * 2.4, "color": col,
		})


func _float_text(pos: Vector2, text: String, col: Color, size: int = 15) -> void:
	_floaters.append({
		"pos": pos, "text": text, "color": col, "size": size,
		"life": 0.85, "t": 0.0,
	})


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
	e.damaged.connect(_on_enemy_damaged)
	e.killed.connect(_on_enemy_killed)
	e.leaked.connect(_on_enemy_leaked)


func _on_tower_placed(t: TDTower) -> void:
	# td_core 的塔默认会自绘「灰方块 + 射程圈」用于调试，正式渲染由本文件接管
	t.debug_draw = false
	t.fired.connect(_on_tower_fired.bind(t))


func _on_tower_fired(target: TDEnemy, shooter: TDTower) -> void:
	if target == null or shooter == null:
		return
	# 命中反馈只做两件事：一道衰减的光束 + 命中点的小火星。
	# 常驻范围圈会让人看不清谁在打谁，所以只在开火那一瞬给信号。
	var col: Color = Color(str(content.tower_def(shooter.id).get("color", "#8FD8FF"))).lightened(0.25)
	_flash[shooter.get_instance_id()] = 0.09
	_beams.append({
		"from": shooter.position, "to": target.position,
		"color": col, "life": 0.10, "t": 0.0,
	})
	_spawn_burst(target.position, col, 4, 90.0)
	# 部族的附加机制（毒 / 眩晕）挂在这里：这是「塔打中了」的唯一收口，
	# 放在别处就会漏掉溅射命中的目标。
	status.on_tower_fired(shooter, target)


func _on_enemy_damaged(e: TDEnemy, _amount: float) -> void:
	_spawn_burst(e.position, Color(1, 1, 1, 0.85), 3, 70.0)


func _on_enemy_killed(e: TDEnemy) -> void:
	_spawn_burst(e.position, Color("#FFD98A"), 10, 150.0)
	_rings.append({"pos": e.position, "r0": 6.0, "r1": 34.0,
		"color": Color(1.0, 0.85, 0.5, 1.0), "life": 0.34, "t": 0.0})
	# 赏金是这只怪给的，飘字挂在怪身上，玩家才能把「击杀 → 金币」连起来
	_float_text(e.position + Vector2(0, -6), "+%d" % e.bounty, Color("#F2C14E"), 15)
	_maybe_drop_item(e.position)
	status.try_split(e)


func _on_enemy_leaked(_e: TDEnemy) -> void:
	_shake = 1.0


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
	# 英雄拖动优先级最高：它的落点在棋盘里，不可能是 UI
	if _handle_hero_drag(event):
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
		KEY_SPACE:
			start_wave_early()


## 英雄拖动。用「按下时命中英雄 → 整段拖动都由这里接管」的方式，
## 而不是加一个「指挥模式」开关：模式会多一次点击，手机上这一步很贵。
func _handle_hero_drag(event: InputEvent) -> bool:
	if hero == null:
		return false
	var board := Rect2(Vector2.ZERO, BOARD_SIZE)

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if not _hero_drag:
			return false
		hero.teleport(to_local(motion.position), board)
		return true
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		if not _hero_drag:
			return false
		hero.teleport(to_local(drag.position), board)
		return true

	var local: Variant = null
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if not touch.pressed:
			var was: bool = _hero_drag
			_hero_drag = false
			return was
		local = to_local(touch.position)
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if not mb.pressed:
			var was2: bool = _hero_drag
			_hero_drag = false
			return was2
		local = to_local(mb.position)
	if local == null:
		return false

	if (local as Vector2).distance_to(hero.pos) <= 34.0:
		_hero_drag = true
		selected_tower = null
		return true
	return false


# ------------------------------------------------------------------ 渲染
#
# 分层顺序：背景 → 烘焙地形 → 棋盘框 → 路径流光 → 出生门/基地 → 网格
#           → 悬停 → 塔 → 敌人 → 波纹 → 光束 → 粒子 → 飘字 → 选中环
# 单位和塔都按 y 排序再画，靠前后遮挡骗出「俯视但立得住」的体积感。

func _draw() -> void:
	draw_rect(Rect2(Vector2(-BOARD_ORIGIN.x, -BOARD_ORIGIN.y), SCREEN), BG)
	# 内容解析失败时 spawner 会是 null，_draw 仍会被调用，先挡住。
	if spawner == null or spawner.map == null:
		return

	# 震屏只晃棋盘：HUD 挂在独立 CanvasLayer 上，天然不受影响
	_shake_off = Vector2.ZERO
	if _shake > 0.01:
		_shake_off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 9.0 * _shake
	draw_set_transform(_shake_off)

	# 地形是一张烘焙贴图，一帧一次 draw call。2600 根草叶和 43 块石板已经在里面了。
	if _terrain != null:
		draw_texture_rect(_terrain, Rect2(Vector2.ZERO, BOARD_SIZE), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, BOARD_SIZE), TDArt.GRASS_MID)

	_draw_board_frame()
	_draw_path_flow()
	_draw_gate_and_base()
	_draw_grid()
	_draw_hover()
	_draw_items()
	_draw_towers()
	_draw_enemies()
	_draw_hero()
	_draw_rings()
	_draw_beams()
	_draw_particles()
	_draw_floaters()
	_draw_selection()

	draw_set_transform(Vector2.ZERO)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	return TDArt.closed(pts)


func _font() -> Font:
	if hud != null and hud.has_method("font"):
		return hud.font()
	return null


func _draw_board_frame() -> void:
	# 两道框：外侧压暗把棋盘从背景里「切」出来，内侧一道冷光做边缘反射
	draw_polyline(_closed(TDArt.round_rect(
		Rect2(Vector2(-7, -7), BOARD_SIZE + Vector2(14, 14)), 16.0)),
		Color(0.01, 0.02, 0.04, 0.85), 3.0, true)
	draw_polyline(_closed(TDArt.round_rect(
		Rect2(Vector2(-6, -6), BOARD_SIZE + Vector2(12, 12)), 15.0)),
		Color(0.42, 0.62, 0.74, 0.20), 1.2, true)


## 沿路径流动的光点 —— 不用文字说明也知道怪往哪边走。
func _draw_path_flow() -> void:
	var poly: PackedVector2Array = spawner.path
	if poly.size() < 2:
		return
	var segs: Array[float] = []
	var total: float = 0.0
	for i: int in range(1, poly.size()):
		var d: float = poly[i - 1].distance_to(poly[i])
		segs.append(d)
		total += d
	if total <= 0.0:
		return
	for i: int in range(14):
		var dist: float = fmod(_time * 46.0 + float(i) * total / 14.0, total)
		var p: Vector2 = _sample_path(poly, segs, dist)
		var a: float = 0.10 + 0.10 * sin(_time * 2.0 + float(i))
		draw_circle(p, 2.6, Color(0.55, 0.78, 0.90, a), true, -1.0, true)


func _draw_gate_and_base() -> void:
	var poly: PackedVector2Array = spawner.path
	if poly.size() < 2:
		return
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.6)

	# 出生门：红光。第一个航点在屏幕外，标记点取格内的第一个拐角。
	var gate: Vector2 = Vector2(clampf(poly[1].x, 20.0, BOARD_SIZE.x - 20.0), poly[1].y)
	TDArt.glow(self, gate, 54.0, Color(0.88, 0.29, 0.43, 0.42))
	TDArt.glow(self, gate, 22.0 + pulse * 7.0, Color(0.95, 0.42, 0.52, 0.26))

	# 基地：旋转的菱形水晶，越靠近越亮。
	# 终点格 (3,15) 在棋盘下沿之外，要往里收 —— 否则一半挂在屏幕外，还会被 HUD 卡片压住。
	var end: Vector2 = poly[poly.size() - 1]
	var b: Vector2 = Vector2(clampf(end.x, 40.0, BOARD_SIZE.x - 40.0),
		clampf(end.y, 40.0, BOARD_SIZE.y - 58.0))
	TDArt.glow(self, b, 72.0, Color(0.35, 0.78, 1.0, 0.40))
	draw_set_transform(_shake_off + b, _time * 0.6, Vector2.ONE)
	for i: int in range(3):
		var d: float = 20.0 - float(i) * 3.0
		draw_polyline(_closed(PackedVector2Array([
			Vector2(0, -d), Vector2(d * 0.7, 0), Vector2(0, d), Vector2(-d * 0.7, 0)])),
			Color(0.47, 0.82, 1.0, 0.26 - float(i) * 0.06 + pulse * 0.12), 1.5, true)
	draw_set_transform(_shake_off)


## 网格只做极淡的参考线。之前它是「棋盘格感」的第二来源，现在降到几乎看不见。
func _draw_grid() -> void:
	var col := Color(0.47, 0.67, 0.78, 0.05)
	for x: int in range(10):
		draw_line(Vector2(x * 64, 0), Vector2(x * 64, BOARD_SIZE.y), col, 1.0)
	for y: int in range(16):
		draw_line(Vector2(0, y * 64), Vector2(BOARD_SIZE.x, y * 64), col, 1.0)


func _draw_hover() -> void:
	if hover_cell.x < 0:
		return
	var c: Vector2i = hover_cell
	if not spawner.map.in_bounds(c):
		return
	var cell_rect := Rect2(Vector2(c) * 64.0, Vector2(64, 64)).grow(-2.0)
	var ok: bool = build_block_reason(c) == "" and spawner.tower_at_cell(c) == null
	var tint: Color = HOVER_OK if ok else HOVER_BAD
	var shape: PackedVector2Array = TDArt.round_rect(cell_rect, 9.0)
	TDArt.fill(self, shape, TDArt.rgba(tint, 0.14))
	draw_polyline(_closed(shape), TDArt.rgba(tint, 0.85), 2.0, true)
	if not ok:
		return
	# 范围预览：放下之前就告诉玩家能打到哪
	var def: Dictionary = tower_def(build_id)
	var rng: float = float(def.get("range", 96))
	var col := Color(str(def.get("color", "#2ECC71")))
	var center: Vector2 = Vector2(c) * 64.0 + Vector2(32, 32)
	TDArt.glow(self, center, rng, TDArt.rgba(col, 0.09))
	TDArt.dashed_ring(self, center, rng, TDArt.rgba(col, 0.55), 2.0, 22, _time * 0.6)


func _draw_towers() -> void:
	var sorted: Array = spawner.towers.duplicate()
	sorted.sort_custom(func(a: TDTower, b: TDTower) -> bool: return a.position.y < b.position.y)
	for t: TDTower in sorted:
		_draw_tower(t)


func _draw_tower(t: TDTower) -> void:
	var def: Dictionary = content.tower_def(t.id)
	var col := Color(str(def.get("color", "#8899AA")))
	var shape := str(def.get("shape", "square"))
	var p: Vector2 = t.position
	var seed: float = float(t.get_instance_id() % 1000) * 0.017
	var s: float = (20.0 + 2.4 * float(t.level)) * (1.0 + 0.03 * sin(_time * 2.2 + seed))

	# 地面投影用椭圆：圆影子在俯视角里永远像贴着地面的一张纸
	TDArt.fill(self, TDArt.ellipse(p + Vector2(0, s * 0.74), s * 0.94, s * 0.36),
		Color(0, 0, 0, 0.42))

	if t == selected_tower:
		TDArt.glow(self, p, t.range_px, TDArt.rgba(col, 0.10))
		TDArt.dashed_ring(self, p, t.range_px, TDArt.rgba(col, 0.62), 1.8, 26, -_time * 0.7, 0.5)

	# 部族色光晕：一眼看出这座塔属于哪一支，比写文字快
	TDArt.glow(self, p, t.range_px * 0.34, TDArt.rgba(col, 0.30))

	# 八边形石台：上亮下暗的顶点色渐变 + 深色描边，压住场面
	var plinth: PackedVector2Array = TDArt.ngon(p, s, 8, PI / 8.0)
	TDArt.fill_vgrad(self, plinth, Color("#4C5F72"), Color("#12191F"), p.y - s, p.y + s)
	draw_polyline(_closed(plinth), Color(0.01, 0.02, 0.04, 0.92), 2.0, true)
	draw_polyline(_closed(TDArt.ngon(p, s * 0.90, 8, PI / 8.0)), TDArt.rgba(col, 0.44), 1.3, true)

	# 四角铆钉：四个小亮点，石台立刻有「加工过」的感觉
	for i: int in range(4):
		var a: float = PI / 4.0 + PI * 0.5 * float(i)
		draw_circle(p + Vector2(cos(a), sin(a)) * s * 0.80, 2.4,
			Color(0.72, 0.84, 0.92, 0.55), true, -1.0, true)

	# 符文环：慢速旋转的虚线，暗示这是座施法建筑而不是一块石头。
	# 半径必须明显大于塔身（0.64s），否则会被塔身整个盖住 —— 第一版就是这样白画了。
	TDArt.dashed_ring(self, p, s * 0.82, TDArt.rgba(col.lightened(0.35), 0.70), 1.6, 12,
		_time * 0.5 + seed)

	# 炮管先画，让它从塔身后面伸出来
	_draw_barrel(t, p, s, col)

	# 塔身
	var bs: float = s * 0.64
	var body: PackedVector2Array
	match shape:
		"circle":
			body = TDArt.ellipse(p, bs, bs, 26)
		"diamond":
			body = TDArt.ngon(p, bs * 1.16, 4, 0.0)
		"hex":
			body = TDArt.ngon(p, bs * 1.06, 6, 0.0)
		"star":
			body = TDArt.star(p, bs * 1.20, bs * 0.56, 5)
		_:
			body = TDArt.round_rect(Rect2(p - Vector2(bs, bs), Vector2(bs, bs) * 2.0), bs * 0.34, 4)
	# 塔身自带辉光：暗底上一块纯色完全没有体积，这层光就是「塑料感」和「发光体」的分界
	TDArt.glow(self, p, bs * 2.1, TDArt.rgba(col, 0.45))
	# 渐变区间要收窄：多边形顶点少（六边形只有 6 个），跨度一大就只剩混白和混黑，
	# 中间那一档纯色反而不见了 —— 塔会整体发灰。
	TDArt.fill_vgrad(self, body, TDArt.shade(col, 1.34), TDArt.shade(col, 0.52),
		p.y - bs * 1.1, p.y + bs * 1.1)
	draw_polyline(_closed(body), Color(0.01, 0.02, 0.04, 0.85), 2.2, true)

	# 内高光：把同一个形状缩到 74% 描一圈白。比再烘一张贴图便宜，也不会糊。
	var hl := PackedVector2Array()
	for v: Vector2 in body:
		hl.append(p + (v - p) * 0.74)
	draw_polyline(_closed(hl), Color(1, 1, 1, 0.26), 1.2, true)
	draw_circle(p, bs * 0.28, Color(1, 1, 1, 0.62), true, -1.0, true)

	# 开火闪光
	var flash: float = float(_flash.get(t.get_instance_id(), 0.0))
	if flash > 0.0:
		var k: float = flash / 0.09
		TDArt.glow(self, p, s * 2.2 * k, Color(1, 1, 1, 0.45 * k))

	# 等级徽章：只有升过级才出现，避免满屏数字
	if t.level > 1:
		var bp: Vector2 = p + Vector2(s * 0.74, s * 0.72)
		draw_circle(bp, 9.5, Color(0.03, 0.06, 0.08, 0.95), true, -1.0, true)
		draw_arc(bp, 9.5, 0, TAU, 20, TDArt.rgba(col, 0.90), 1.5, true)
		var f: Font = _font()
		if f != null:
			draw_string(f, bp + Vector2(-9.5, 4.0), str(t.level),
				HORIZONTAL_ALIGNMENT_CENTER, 19.0, 11, Color("#EAF4FF"))


func _draw_barrel(t: TDTower, p: Vector2, s: float, col: Color) -> void:
	var flash: float = float(_flash.get(t.get_instance_id(), 0.0))
	var length: float = s * 1.06 * (1.0 + (flash / 0.09) * 0.26)
	var base_x: float = s * 0.24
	# 单独给炮管设一个旋转变换，形状本身按「沿 +x 方向伸出」来描述，代码短很多
	draw_set_transform(_shake_off + p, t.aim_angle, Vector2.ONE)
	var shell: PackedVector2Array = TDArt.round_rect(
		Rect2(base_x, -s * 0.21, length, s * 0.42), s * 0.18, 4)
	TDArt.fill_stroke(self, shell, Color("#141D25"), Color(0.01, 0.02, 0.04, 0.92), 1.6)
	var inner: PackedVector2Array = TDArt.round_rect(
		Rect2(base_x + 2.0, -s * 0.10, maxf(length - 5.0, 2.0), s * 0.20), s * 0.10, 3)
	TDArt.fill(self, inner, TDArt.rgba(col, 0.85))
	draw_circle(Vector2(base_x + length - 1.5, 0), s * 0.13,
		TDArt.rgba(col.lightened(0.6), 0.95), true, -1.0, true)
	draw_set_transform(_shake_off)


func _enemy_color(id: StringName) -> Color:
	match id:
		&"brute":
			return Color("#F0A878")
		&"flyer":
			return Color("#A8E0FF")
		&"boss":
			return Color("#FF8FA8")
		&"scout":
			return Color("#FFE98A")
		_:
			# 原来给的是 #EEF6FF，接近纯白 —— 渐变上下都是白，身体读不出体积，
			# 远看就是一坨灰球。压到带蓝的浅灰，渐变才有空间。
			return Color("#CBDCEA")


func _draw_enemies() -> void:
	var sorted: Array = spawner.enemies.duplicate()
	sorted.sort_custom(func(a: TDEnemy, b: TDEnemy) -> bool: return a.position.y < b.position.y)
	for e: TDEnemy in sorted:
		_draw_enemy(e)


func _draw_enemy(e: TDEnemy) -> void:
	var col := _enemy_color(e.id)
	var boss: bool = e.id == &"boss"
	var brute: bool = e.id == &"brute"
	var base_r: float = 30.0 if boss else (21.0 if brute else 16.0)
	var phase: float = float(e.get_instance_id() % 360) * 0.017
	var bob: float = sin(_time * 4.0 + phase) * (4.0 if e.flying else 2.0)
	# 飞行单位整体抬高，影子留在原地不跟着飘 —— 这是「离地」唯一有效的廉价信号
	var p: Vector2 = e.position + Vector2(0, -10.0 + bob) if e.flying else e.position + Vector2(0, bob * 0.5)

	TDArt.fill(self, TDArt.ellipse(Vector2(p.x, e.position.y + base_r * 0.92),
		base_r * 0.82, base_r * 0.30), Color(0, 0, 0, 0.38))

	if e.is_slowed():
		TDArt.glow(self, p, base_r * 2.0, Color(0.51, 0.80, 1.0, 0.32))

	# 五种敌人靠轮廓区分，不靠贴图 modulate —— 后者在 40px 尺度上根本看不出差别
	var body: PackedVector2Array
	if e.flying:
		body = PackedVector2Array([p + Vector2(0, -base_r), p + Vector2(base_r * 0.95, 0),
			p + Vector2(0, base_r * 0.8), p + Vector2(-base_r * 0.95, 0)])
	elif brute:
		body = TDArt.round_rect(Rect2(p - Vector2(base_r, base_r * 0.92),
			Vector2(base_r * 2.0, base_r * 1.84)), base_r * 0.3, 4)
	else:
		body = TDArt.ellipse(p, base_r, base_r, 24)
	TDArt.fill_vgrad(self, body, TDArt.shade(col, 1.38), TDArt.shade(col, 0.50),
		p.y - base_r, p.y + base_r)
	draw_polyline(_closed(body), Color(0.01, 0.03, 0.05, 0.85), 2.4, true)
	# 底缘反光：一条比身体暗的弧，把「球」压成「球体」
	draw_arc(p + Vector2(0, base_r * 0.16), base_r * 0.86, deg_to_rad(38.0), deg_to_rad(142.0),
		14, TDArt.rgba(Color(0.06, 0.10, 0.16, 1.0), 0.30), 2.0, true)

	TDArt.fill(self, TDArt.ellipse(p + Vector2(-base_r * 0.28, -base_r * 0.42),
		base_r * 0.44, base_r * 0.30, 16), Color(1, 1, 1, 0.26))

	# 眼睛跟着 heading 翻面，再加一道压眉 —— 有脸才像个兵，不是一块色
	var fx: float = 1.0 if cos(e.heading) >= 0.0 else -1.0
	var brow: Color = Color(0.03, 0.05, 0.08, 0.88)
	for sgn: float in [-1.0, 1.0]:
		var eye: Vector2 = p + Vector2((sgn * 0.30 + fx * 0.10) * base_r, -base_r * 0.06)
		draw_circle(eye, base_r * 0.19, Color("#FFE9A6") if boss else Color("#F2F8FF"),
			true, -1.0, true)
		draw_circle(eye + Vector2(fx * base_r * 0.05, base_r * 0.02), base_r * 0.088,
			Color("#0A1218"), true, -1.0, true)
		draw_line(p + Vector2(sgn * base_r * 0.52, -base_r * 0.36),
			p + Vector2(sgn * base_r * 0.10, -base_r * 0.16), brow,
			maxf(1.3, base_r * 0.10), true)

	if boss:
		var pulse: float = 0.5 + 0.5 * sin(_time * 3.4)
		draw_arc(p, base_r * (1.35 + pulse * 0.15), 0, TAU, 32,
			Color(0.88, 0.29, 0.48, 0.35 + pulse * 0.30), 2.0, true)

	# 血条：圆角 + 按比例换色，比一条纯色条更能读出「还剩多少」
	var ratio: float = clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	var bw: float = 74.0 if boss else (44.0 if brute else 36.0)
	var bh: float = 7.0 if boss else 5.0
	var bar := Rect2(p + Vector2(-bw * 0.5, -base_r - 6.0), Vector2(bw, bh))
	TDArt.fill(self, TDArt.round_rect(bar.grow(1.5), (bh + 3.0) * 0.5),
		Color(0, 0, 0, 0.62))
	if ratio > 0.01:
		var hc: Color = Color("#4BE08A")
		if ratio <= 0.28:
			hc = Color("#FF6B6B")
		elif ratio <= 0.55:
			hc = Color("#FFD166")
		TDArt.fill(self, TDArt.round_rect(
			Rect2(bar.position, Vector2(maxf(bw * ratio, bh), bh)), bh * 0.5), hc)


## 掉落物：脉冲的菱形。用颜色区分槽位（剑/护符/靴），玩家不用读字就知道该捡什么。
func _draw_items() -> void:
	for it: Dictionary in _items:
		var p: Vector2 = it["pos"]
		var col: Color = HeroUnit.SLOT_COLORS.get(str(it["kind"]), Color.WHITE)
		var pulse: float = 0.5 + 0.5 * sin(_time * 4.0 + float(it["t"]) * 2.5)
		# 快过期时闪烁提醒
		var left: float = ITEM_LIFETIME - float(it["t"])
		if left < 5.0 and int(left * 6.0) % 2 == 0:
			continue
		TDArt.glow(self, p, 16.0 + pulse * 6.0, TDArt.rgba(col, 0.34))
		var s: float = 8.5 + pulse * 1.8
		var dia := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0),
			p + Vector2(0, s), p + Vector2(-s, 0)])
		TDArt.fill(self, dia, col)
		draw_polyline(_closed(dia), Color(0.06, 0.09, 0.12, 0.85), 1.4, true)
		if int(it["level"]) > 1:
			draw_circle(p, 2.2, Color(1, 1, 1, 0.85), true, -1.0, true)


## 英雄：一个会走路的圆形战士。它必须一眼就能从塔和怪里分出来 ——
## 所以给了金色描边和一圈暖光，这是棋盘上唯一「暖色 + 有剑」的单位。
func _draw_hero() -> void:
	if hero == null:
		return
	var p: Vector2 = hero.pos
	var r: float = 15.0

	TDArt.fill(self, TDArt.ellipse(Vector2(p.x, p.y + r * 0.95), r * 0.85, r * 0.32),
		Color(0, 0, 0, 0.38))
	TDArt.glow(self, p, 44.0, Color(0.90, 0.72, 0.30, 0.28))
	if _hero_drag:
		TDArt.dashed_ring(self, p, hero.attack_range(), Color(0.95, 0.85, 0.45, 0.70),
			2.0, 24, _time * 0.8)

	var body: PackedVector2Array = TDArt.ellipse(p, r, r, 24)
	TDArt.fill_vgrad(self, body, Color("#FFEDB8"), Color("#B87F34"), p.y - r, p.y + r)
	draw_polyline(_closed(body), Color(0.10, 0.07, 0.03, 0.92), 2.4, true)

	# 剑：跟着朝向，出手瞬间会亮
	var dir := Vector2(cos(hero.aim), sin(hero.aim))
	var tip: Vector2 = p + dir * r * 1.85
	draw_line(p + dir * r * 0.45, tip, Color("#F8F4E6"), 3.2, true)
	draw_circle(tip, 3.4, Color("#FFF7CC"), true, -1.0, true)
	if hero.attack_flash > 0.0:
		var k: float = hero.attack_flash / 0.12
		TDArt.glow(self, tip, 14.0 + 10.0 * k, Color(1.0, 0.95, 0.75, 0.55 * k))

	# 等级：底部一个金环，级数越高环越亮
	draw_arc(p, r + 4.0, 0, TAU, 26,
		Color(1.0, 0.86, 0.45, 0.25 + 0.05 * float(hero.level)), 1.6, true)


func _draw_rings() -> void:
	for r: Dictionary in _rings:
		var k: float = float(r["t"]) / float(r["life"])
		var rad: float = lerpf(float(r["r0"]), float(r["r1"]), k * k * 0.6 + k * 0.4)
		draw_arc(r["pos"], rad, 0, TAU, 28,
			TDArt.rgba(r["color"], (1.0 - k) * 0.85), maxf(0.6, 3.2 * (1.0 - k)), true)


func _draw_beams() -> void:
	for b: Dictionary in _beams:
		var k: float = 1.0 - float(b["t"]) / float(b["life"])
		draw_line(b["from"], b["to"], TDArt.rgba(b["color"], 0.75 * k), 3.0 * k, true)


func _draw_particles() -> void:
	for p: Dictionary in _particles:
		var k: float = 1.0 - float(p["t"]) / float(p["life"])
		var c: Color = p["color"]
		draw_circle(p["pos"], float(p["r"]) * (0.4 + k * 0.8), TDArt.rgba(c, c.a * k),
			true, -1.0, true)


func _draw_floaters() -> void:
	var f: Font = _font()
	if f == null:
		return
	for it: Dictionary in _floaters:
		var k: float = 1.0 - float(it["t"]) / float(it["life"])
		var size: int = int(it["size"])
		var txt: String = str(it["text"])
		var pos: Vector2 = it["pos"]
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var a: float = minf(1.0, k * 1.6)
		# 先垫一层深色描边字，再叠主色，浅色飘字在草地上也能读
		draw_string(f, pos + Vector2(-w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(0.02, 0.04, 0.06, a * 0.85))
		draw_string(f, pos + Vector2(-w * 0.5, -1.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			TDArt.rgba(it["color"], a))


func _draw_selection() -> void:
	var t: TDTower = selected_tower
	if t == null or not is_instance_valid(t):
		return
	var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
	draw_arc(t.position, 30.0 + pulse * 2.5, 0, TAU, 40,
		Color(0.88, 0.75, 0.36, 0.90), 2.0, true)


func _sample_path(poly: PackedVector2Array, segs: Array[float], dist: float) -> Vector2:
	var left: float = dist
	for i: int in range(segs.size()):
		if left <= segs[i]:
			return poly[i].lerp(poly[i + 1], left / maxf(segs[i], 0.001))
		left -= segs[i]
	return poly[poly.size() - 1]
