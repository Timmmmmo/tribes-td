class_name TDContent
extends RefCounted
## Data-driven content: towers, enemies, waves and the map from one JSON file
## (see examples/data/content.json). Add a tower or enemy by editing data only.

const TARGETING_IDS: Dictionary = {"first": 0, "last": 1, "strongest": 2, "closest": 3}

var towers: Dictionary = {}     ## id -> tower def (Dictionary)
var tower_order: Array[StringName] = []
var enemies: Dictionary = {}    ## id -> enemy def
var waves: Array = []           ## [{groups: [{enemy, count, interval}], bonus}]
var map_data: Dictionary = {}
var start_gold: int = 100
var lives: int = 20
var hp_scale_per_wave: float = 1.0
var errors: Array[String] = []

static func load_file(path: String) -> TDContent:
	var c: TDContent = TDContent.new()
	if not FileAccess.file_exists(path):
		c.errors.append("file not found: %s" % path)
		return c
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not v is Dictionary:
		c.errors.append("not a JSON object: %s" % path)
		return c
	c.load_dict(v)
	return c

func load_dict(d: Dictionary) -> void:
	start_gold = int(d.get("start_gold", 100))
	lives = int(d.get("lives", 20))
	hp_scale_per_wave = float(d.get("hp_scale_per_wave", 1.0))
	for t: Variant in d.get("towers", []):
		var td: Dictionary = t
		var tid: StringName = StringName(str(td.get("id", "")))
		towers[tid] = td
		tower_order.append(tid)
	for e: Variant in d.get("enemies", []):
		var ed: Dictionary = e
		enemies[StringName(str(ed.get("id", "")))] = ed
	waves = d.get("waves", [])
	map_data = d.get("map", {})

func tower_def(id: StringName) -> Dictionary:
	return towers.get(id, {})

func tower_cost(id: StringName) -> int:
	return int(tower_def(id).get("cost", 0))

## Builds a configured (not yet placed) tower.
func make_tower(id: StringName) -> TDTower:
	var d: Dictionary = tower_def(id)
	var t: TDTower = TDTower.new()
	t.id = id
	t.display_name = str(d.get("name", String(id).capitalize()))
	t.cost = int(d.get("cost", 50))
	t.damage = float(d.get("damage", 4.0))
	t.range_px = float(d.get("range", 96.0))
	t.fire_interval = float(d.get("interval", 0.5))
	t.splash_radius = float(d.get("splash", 0.0))
	t.slow_factor = float(d.get("slow", 1.0))
	t.slow_duration = float(d.get("slow_time", 0.0))
	t.hits_air = bool(d.get("hits_air", true))
	t.hits_ground = bool(d.get("hits_ground", true))
	t.targeting = int(TARGETING_IDS.get(str(d.get("targeting", "first")), 0)) as TDTower.Targeting
	var lv: Array[Dictionary] = []
	for l: Variant in d.get("levels", []):
		lv.append(l as Dictionary)
	t.levels = lv
	return t

## Wave i as spawner groups with enemy stats resolved.
func wave_groups(i: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if i < 0 or i >= waves.size():
		return out
	for g: Variant in (waves[i] as Dictionary).get("groups", []):
		var gd: Dictionary = g
		var e: Dictionary = enemies.get(StringName(str(gd.get("enemy", ""))), {})
		out.append({"enemy": str(gd.get("enemy", "")), "count": int(gd.get("count", 1)), "interval": float(gd.get("interval", 0.6)),
			"delay": float(gd.get("delay", 0.0)), "hp": float(e.get("hp", 10.0)), "speed": float(e.get("speed", 60.0)),
			"bounty": int(e.get("bounty", 5)), "armor": float(e.get("armor", 0.0)), "leak": int(e.get("leak", 1)),
			"flying": bool(e.get("flying", false))})
	return out

func wave_bonus(i: int) -> int:
	if i < 0 or i >= waves.size():
		return 0
	return int((waves[i] as Dictionary).get("bonus", 0))

func make_map() -> TDMap:
	return TDMap.from_dict(map_data)

## Problems with the content (empty = valid).
func validate() -> Array[String]:
	var errs: Array[String] = errors.duplicate()
	if towers.is_empty():
		errs.append("no towers")
	for id: StringName in towers:
		var d: Dictionary = towers[id]
		if String(id) == "":
			errs.append("tower without id")
		if int(d.get("cost", 0)) <= 0:
			errs.append("tower %s: cost must be > 0" % id)
		if float(d.get("interval", 0.5)) <= 0.0:
			errs.append("tower %s: interval must be > 0" % id)
		if not TARGETING_IDS.has(str(d.get("targeting", "first"))):
			errs.append("tower %s: unknown targeting '%s'" % [id, d.get("targeting")])
		for l: Variant in d.get("levels", []):
			if int((l as Dictionary).get("cost", 0)) <= 0:
				errs.append("tower %s: level cost must be > 0" % id)
	for id: StringName in enemies:
		if float((enemies[id] as Dictionary).get("hp", 0)) <= 0.0:
			errs.append("enemy %s: hp must be > 0" % id)
	if waves.is_empty():
		errs.append("no waves")
	for i: int in waves.size():
		for g: Variant in (waves[i] as Dictionary).get("groups", []):
			var en: String = str((g as Dictionary).get("enemy", ""))
			if not enemies.has(StringName(en)):
				errs.append("wave %d: unknown enemy '%s'" % [i + 1, en])
	errs.append_array(make_map().validate())
	return errs
