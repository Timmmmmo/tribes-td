class_name TDMap
extends RefCounted
## Grid map: size in cells, a path given as waypoint cells (straight runs between
## them), blocked cells (decor) and buildable test. World units = pixels.

var cols: int = 20
var rows: int = 12
var cell_px: float = 64.0
var waypoints: Array[Vector2i] = []
var blocked: Dictionary[Vector2i, bool] = {}
var _path_cells: Dictionary[Vector2i, bool] = {}
var _ordered: Array[Vector2i] = []

static func from_dict(d: Dictionary) -> TDMap:
	var m: TDMap = TDMap.new()
	m.cols = int(d.get("cols", 20))
	m.rows = int(d.get("rows", 12))
	m.cell_px = float(d.get("cell", 64))
	var wps: Array[Vector2i] = []
	for p: Variant in d.get("path", []):
		wps.append(Vector2i(int(p[0]), int(p[1])))
	for b: Variant in d.get("blocked", []):
		m.blocked[Vector2i(int(b[0]), int(b[1]))] = true
	m.set_waypoints(wps)
	return m

func set_waypoints(wps: Array[Vector2i]) -> void:
	waypoints = wps
	_path_cells.clear()
	_ordered.clear()
	for i: int in range(1, wps.size()):
		var a: Vector2i = wps[i - 1]
		var b: Vector2i = wps[i]
		var step: Vector2i = (b - a).sign()
		var c: Vector2i = a
		while c != b:
			_add(c)
			c += step
		_add(b)
	if wps.size() == 1:
		_add(wps[0])

func _add(c: Vector2i) -> void:
	if not _path_cells.has(c):
		_path_cells[c] = true
		_ordered.append(c)

## Path cells in walking order (no duplicates).
func path_cells() -> Array[Vector2i]:
	return _ordered

func is_path(c: Vector2i) -> bool:
	return _path_cells.has(c)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows

func can_build(c: Vector2i) -> bool:
	return in_bounds(c) and not is_path(c) and not blocked.has(c)

func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell_px

func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_px), floori(p.y / cell_px))

func size_px() -> Vector2:
	return Vector2(cols, rows) * cell_px

## Walking path in pixels (waypoint centres). Start/end waypoints may lie
## outside the grid so enemies walk in from off-screen.
func world_path() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for w: Vector2i in waypoints:
		out.append(cell_center(w))
	return out

## Straight start -> end route for flying enemies.
func air_path() -> PackedVector2Array:
	var p: PackedVector2Array = world_path()
	if p.size() < 2:
		return p
	return PackedVector2Array([p[0], p[p.size() - 1]])

## Problems with the map data (empty = valid).
func validate() -> Array[String]:
	var errs: Array[String] = []
	if waypoints.size() < 2:
		errs.append("map needs at least 2 path waypoints")
	for i: int in range(1, waypoints.size()):
		var d: Vector2i = waypoints[i] - waypoints[i - 1]
		if d.x != 0 and d.y != 0:
			errs.append("path segment %d is diagonal (%s -> %s)" % [i, waypoints[i - 1], waypoints[i]])
	for b: Vector2i in blocked:
		if is_path(b):
			errs.append("blocked cell %s is on the path" % b)
	return errs
