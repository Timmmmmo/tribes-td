class_name TDEnemy
extends Node2D
## Walks a polyline path. Emits killed (bounty) or leaked (damage) exactly once.
## Pure logic: call advance(delta). `debug_draw` draws a fallback circle + hp bar;
## games turn it off and add their own visual child (see examples/game/enemy_visual.gd).

signal killed(enemy: TDEnemy)
signal leaked(enemy: TDEnemy)
signal damaged(enemy: TDEnemy, amount: float)

var id: StringName = &"enemy"
var path: PackedVector2Array = PackedVector2Array()
var max_hp: float = 10.0
var hp: float = 10.0
var speed: float = 60.0
var armor: float = 0.0 ## flat reduction per hit (min 1 damage)
var bounty: int = 5
var leak_damage: int = 1
var flying: bool = false ## flyers ignore ground-only towers
var slow_factor: float = 1.0
var slow_time: float = 0.0
var progress: float = 0.0 ## distance travelled along path
var heading: float = 0.0 ## movement direction in radians (for visuals)
var done: bool = false
var debug_draw: bool = true
var _seg: int = 0
var _length: float = 0.0

func setup(p_path: PackedVector2Array, p_hp: float, p_speed: float, p_bounty: int) -> void:
	path = p_path
	max_hp = p_hp
	hp = p_hp
	speed = p_speed
	bounty = p_bounty
	position = path[0]
	_length = 0.0
	for i: int in range(1, path.size()):
		_length += path[i - 1].distance_to(path[i])
	if path.size() > 1:
		heading = (path[1] - path[0]).angle()

## Path length still to walk (smaller = closer to the exit).
func remaining_distance() -> float:
	return maxf(0.0, _length - progress)

func is_slowed() -> bool:
	return slow_factor < 1.0

func advance(delta: float) -> void:
	if done:
		return
	var step: float = speed * slow_factor * delta
	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_factor = 1.0
	while step > 0.0 and _seg < path.size() - 1:
		var target: Vector2 = path[_seg + 1]
		var d: float = position.distance_to(target)
		if d > 0.001:
			heading = (target - position).angle()
		if d <= step:
			position = target
			step -= d
			progress += d
			_seg += 1
		else:
			position = position.move_toward(target, step)
			progress += step
			step = 0.0
	if _seg >= path.size() - 1:
		done = true
		leaked.emit(self)

## Applies one hit; returns the damage actually dealt.
func take_damage(amount: float) -> float:
	if done:
		return 0.0
	var dealt: float = minf(hp, maxf(1.0, amount - armor))
	hp -= maxf(1.0, amount - armor)
	damaged.emit(self, dealt)
	if debug_draw:
		queue_redraw()
	if hp <= 0.0:
		done = true
		killed.emit(self)
	return dealt

func apply_slow(factor: float, duration: float) -> void:
	slow_factor = minf(slow_factor, factor)
	slow_time = maxf(slow_time, duration)

func _draw() -> void:
	if not debug_draw:
		return
	draw_circle(Vector2.ZERO, 8.0, Color(0.85, 0.25, 0.25) if slow_factor >= 1.0 else Color(0.4, 0.5, 0.95))
	draw_rect(Rect2(-8, -13, 16.0 * clampf(hp / max_hp, 0.0, 1.0), 3), Color.GREEN)
