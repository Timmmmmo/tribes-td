class_name TDTower
extends Node2D
## Hitscan tower with targeting modes; optional slow and splash. Upgradable,
## either with data-driven `levels` (see TDContent) or the default formula.

enum Targeting { FIRST, LAST, STRONGEST, CLOSEST }
const TARGETING_NAMES: Array[String] = ["First", "Last", "Strongest", "Closest"]

signal fired(target: TDEnemy)
signal upgraded(tower: TDTower)

var id: StringName = &"tower"
var display_name: String = "Tower"
@export var range_px: float = 96.0
@export var damage: float = 4.0
@export var fire_interval: float = 0.5
@export var splash_radius: float = 0.0
@export var slow_factor: float = 1.0
@export var slow_duration: float = 0.0
@export var cost: int = 50
@export var targeting: Targeting = Targeting.FIRST
@export var hits_air: bool = true
@export var hits_ground: bool = true
var level: int = 1
## Optional data levels: level N+1 stats are levels[N-1] = {cost, damage, range, interval, splash, slow}.
var levels: Array[Dictionary] = []
var cell: Vector2i = Vector2i(-1, -1)
var aim_angle: float = -PI / 2.0
var kills: int = 0
var damage_dealt: float = 0.0
var spent: int = 0
var debug_draw: bool = true
var _cooldown: float = 0.0

func _ready() -> void:
	if spent == 0:
		spent = cost

func max_level() -> int:
	return levels.size() + 1 if not levels.is_empty() else 3

func can_upgrade() -> bool:
	return level < max_level()

func upgrade_cost() -> int:
	if not levels.is_empty():
		return int(levels[level - 1].get("cost", 0)) if can_upgrade() else 0
	return int(cost * 0.75 * level)

## Stats after the next upgrade (same keys as stats()). Empty at max level.
func next_stats() -> Dictionary:
	if not can_upgrade():
		return {}
	if not levels.is_empty():
		var l: Dictionary = levels[level - 1]
		var s: Dictionary = stats()
		s["damage"] = float(l.get("damage", damage))
		s["range"] = float(l.get("range", range_px))
		s["interval"] = float(l.get("interval", fire_interval))
		s["splash"] = float(l.get("splash", splash_radius))
		s["slow"] = float(l.get("slow", slow_factor))
		s["level"] = level + 1
		return s
	var s2: Dictionary = stats()
	s2["damage"] = damage * 1.5
	s2["range"] = range_px * 1.1
	s2["level"] = level + 1
	return s2

func stats() -> Dictionary:
	return {"damage": damage, "range": range_px, "interval": fire_interval, "splash": splash_radius,
		"slow": slow_factor, "level": level, "dps": dps()}

## Damage per second against a single unarmoured target.
func dps() -> float:
	return damage / maxf(fire_interval, 0.001)

func upgrade(econ: TDEconomy) -> bool:
	if not can_upgrade():
		return false
	var c: int = upgrade_cost()
	var n: Dictionary = next_stats()
	if not econ.spend(c):
		return false
	if spent == 0:
		spent = cost
	spent += c
	level += 1
	damage = float(n["damage"])
	range_px = float(n["range"])
	fire_interval = float(n["interval"])
	splash_radius = float(n["splash"])
	slow_factor = float(n["slow"])
	upgraded.emit(self)
	if debug_draw:
		queue_redraw()
	return true

func sell_value() -> int:
	return int(maxi(spent, cost) * 0.7)

func cycle_targeting() -> Targeting:
	targeting = ((int(targeting) + 1) % TARGETING_NAMES.size()) as Targeting
	return targeting

func can_target(e: TDEnemy) -> bool:
	return (hits_air if e.flying else hits_ground)

func pick_target(enemies: Array[TDEnemy]) -> TDEnemy:
	var best: TDEnemy = null
	var best_score: float = -INF
	for e: TDEnemy in enemies:
		if e.done or not can_target(e) or global_position.distance_to(e.global_position) > range_px:
			continue
		var s: float
		match targeting:
			Targeting.FIRST: s = e.progress
			Targeting.LAST: s = -e.progress
			Targeting.STRONGEST: s = e.hp
			_: s = -global_position.distance_to(e.global_position)
		if s > best_score:
			best_score = s
			best = e
	return best

func advance(delta: float, enemies: Array[TDEnemy]) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var t: TDEnemy = pick_target(enemies)
	if t == null:
		return
	_cooldown = fire_interval
	aim_angle = (t.global_position - global_position).angle()
	fired.emit(t)
	var center: Vector2 = t.global_position
	if splash_radius > 0.0:
		for e: TDEnemy in enemies.duplicate():
			if not e.done and can_target(e) and e.global_position.distance_to(center) <= splash_radius:
				_hit(e)
	else:
		_hit(t)

func _hit(e: TDEnemy) -> void:
	if slow_duration > 0.0:
		e.apply_slow(slow_factor, slow_duration)
	damage_dealt += e.take_damage(damage)
	if e.done and e.hp <= 0.0:
		kills += 1

func _draw() -> void:
	if not debug_draw:
		return
	draw_rect(Rect2(-10, -10, 20, 20), Color(0.6, 0.6, 0.7).lightened(0.1 * level))
	draw_arc(Vector2.ZERO, range_px, 0, TAU, 48, Color(1, 1, 1, 0.15))
