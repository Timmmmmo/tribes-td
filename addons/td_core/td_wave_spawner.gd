class_name TDWaveSpawner
extends Node2D
## Data-driven waves + simulation loop owner. Each wave: Array of groups
## {count, hp, speed, bounty, interval, armor?, flying?, enemy?, leak?}.
## Call advance(delta) (auto in _process, scaled by time_scale). configure()
## sets everything up from a TDContent.

signal wave_started(index: int)
signal wave_cleared(index: int)
signal all_waves_cleared()
signal enemy_spawned(enemy: TDEnemy)
signal tower_placed(tower: TDTower)
signal tower_sold(tower: TDTower, refund: int)

@export var auto_tick: bool = true
var time_scale: float = 1.0
var paused: bool = false
var waves: Array[Array] = []
var wave_bonuses: Array[int] = []
var path: PackedVector2Array = PackedVector2Array()
var air_path: PackedVector2Array = PackedVector2Array()
var map: TDMap
var content: TDContent
var economy: TDEconomy = TDEconomy.new()
var towers: Array[TDTower] = []
var enemies: Array[TDEnemy] = []
var wave_index: int = -1
var hp_scale_per_wave: float = 1.0
var won: bool = false
var lost: bool = false
var _queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _active: bool = false

func configure(c: TDContent) -> void:
	content = c
	map = c.make_map()
	path = map.world_path()
	air_path = map.air_path()
	economy = TDEconomy.new(c.start_gold, c.lives)
	hp_scale_per_wave = c.hp_scale_per_wave
	waves.clear()
	wave_bonuses.clear()
	for i: int in c.waves.size():
		waves.append(c.wave_groups(i))
		wave_bonuses.append(c.wave_bonus(i))
	economy.defeated.connect(func() -> void: lost = true)

func is_game_over() -> bool:
	return won or lost

func start_next_wave() -> bool:
	if _active or lost or wave_index + 1 >= waves.size():
		return false
	wave_index += 1
	_queue.clear()
	for g: Dictionary in waves[wave_index]:
		for i: int in int(g["count"]):
			_queue.append(g)
	_spawn_timer = 0.0
	_active = true
	wave_started.emit(wave_index)
	return true

## {enemy id: count} for wave i (default: the next wave).
func wave_preview(i: int = -2) -> Dictionary:
	var w: int = wave_index + 1 if i == -2 else i
	var out: Dictionary = {}
	if w < 0 or w >= waves.size():
		return out
	for g: Dictionary in waves[w]:
		var k: String = str(g.get("enemy", "enemy"))
		out[k] = int(out.get(k, 0)) + int(g["count"])
	return out

func enemies_left_in_wave() -> int:
	return _queue.size() + enemies.size()

func place_tower(t: TDTower, pos: Vector2) -> bool:
	if lost:
		return false
	for o: TDTower in towers:
		if o.position.distance_to(pos) < 20.0:
			return false
	if not economy.spend(t.cost):
		return false
	t.position = pos
	t.spent = t.cost
	add_child(t)
	towers.append(t)
	tower_placed.emit(t)
	return true

func tower_at_cell(c: Vector2i) -> TDTower:
	for t: TDTower in towers:
		if t.cell == c:
			return t
	return null

## Why a cell cannot take a tower ("" = it can).
func placement_error(c: Vector2i, cost: int) -> String:
	if map == null:
		return "no map"
	if not map.in_bounds(c):
		return "outside the map"
	if map.is_path(c):
		return "on the path"
	if map.blocked.has(c):
		return "blocked"
	if tower_at_cell(c) != null:
		return "occupied"
	if not economy.can_afford(cost):
		return "not enough gold"
	return ""

func place_tower_at_cell(t: TDTower, c: Vector2i) -> bool:
	if placement_error(c, t.cost) != "":
		return false
	t.cell = c
	return place_tower(t, map.cell_center(c))

func sell_tower(t: TDTower) -> int:
	if not towers.has(t):
		return 0
	var v: int = t.sell_value()
	towers.erase(t)
	economy.earn(v)
	tower_sold.emit(t, v)
	t.queue_free()
	return v

func _process(delta: float) -> void:
	if auto_tick and not paused:
		advance(delta * time_scale)

func advance(delta: float) -> void:
	if _active and not _queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			var g: Dictionary = _queue.pop_front()
			_spawn(g)
			_spawn_timer = float(g.get("interval", 0.5))
	for e: TDEnemy in enemies.duplicate():
		e.advance(delta)
	for t: TDTower in towers:
		t.advance(delta, enemies)
	if _active and _queue.is_empty() and enemies.is_empty():
		_active = false
		if not lost:
			if wave_index < wave_bonuses.size():
				economy.earn(wave_bonuses[wave_index])
			wave_cleared.emit(wave_index)
			if wave_index == waves.size() - 1:
				won = true
				all_waves_cleared.emit()

func _spawn(g: Dictionary) -> void:
	var e: TDEnemy = TDEnemy.new()
	var hp: float = float(g.get("hp", 10.0)) * pow(hp_scale_per_wave, maxi(wave_index, 0))
	e.flying = bool(g.get("flying", false))
	e.id = StringName(str(g.get("enemy", "enemy")))
	e.setup(air_path if e.flying and air_path.size() >= 2 else path, hp, float(g.get("speed", 60.0)), int(g.get("bounty", 5)))
	e.armor = float(g.get("armor", 0.0))
	e.leak_damage = int(g.get("leak", 1))
	e.killed.connect(_on_killed)
	e.leaked.connect(_on_leaked)
	add_child(e)
	enemies.append(e)
	enemy_spawned.emit(e)

func _on_killed(e: TDEnemy) -> void:
	economy.earn(e.bounty)
	_remove(e)

func _on_leaked(e: TDEnemy) -> void:
	economy.leak(e.leak_damage)
	_remove(e)

func _remove(e: TDEnemy) -> void:
	enemies.erase(e)
	e.queue_free()

func is_wave_active() -> bool:
	return _active
