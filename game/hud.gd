extends Control
## 竖屏 HUD —— 全部自绘 + 手动命中测试，不用 Control 节点树。
## 理由：塔防的 HUD 元素数量少、布局固定，自绘能保证视觉统一，
## 也避免手机端嵌套容器带来的点击穿透与布局抖动。

const W := 720.0
const H := 1280.0
const TOP_H := 150.0
const CARD_Y := 1100.0
const CARD_H := 96.0
const SKILL_Y := 1200.0
const SKILL_H := 72.0
const CARD_W := 92.0
const CARD_GAP := 8.0
const ACTION_Y := 1012.0
const ACTION_H := 78.0

const BG := Color("#0B1420")
const PANEL := Color("#16232F")
const PANEL_HI := Color("#20323F")
const LINE := Color("#2A4052")
const AMBER := Color("#E0A83C")
const TEAL := Color("#1E9E8F")
const TEXT := Color("#E8EFF5")
const DIM := Color("#7C8FA0")
const BAD := Color("#E15555")

## 表示「这次输入不是按下」的哨兵坐标
const NO_POS := Vector2(-9999, -9999)

## 中文必须显式给字体：Godot 内置 fallback 不含 CJK，会显示方块。
## 桌面端用系统字体（雅黑/苹方），Web 端拿不到系统字体，必须用打包的中文子集，
## 否则整屏都是豆腐块。子集由 tools/subset_font.py 生成，只留游戏里用到的字。
const FONT_BUNDLED := "res://assets/fonts/game_cjk.ttf"
const FONT_NAMES := [
	"Microsoft YaHei", "微软雅黑", "PingFang SC", "Noto Sans CJK SC",
	"Source Han Sans SC", "WenQuanYi Micro Hei", "sans-serif",
]

var main: Node2D
var _font: Font
var _drag_target: String = ""


func setup(m: Node2D) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bundled: Font = null
	if ResourceLoader.exists(FONT_BUNDLED):
		bundled = load(FONT_BUNDLED) as Font

	if OS.has_feature("web") and bundled != null:
		# Web 里没有系统字体可查，直接用打包子集，最确定
		_font = bundled
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(FONT_NAMES)
		sf.font_weight = 400
		if bundled != null:
			# 桌面上万一系统缺字，也有兜底
			sf.fallbacks = [bundled]
		_font = sf


func _process(_d: float) -> void:
	if main != null:
		queue_redraw()


# ------------------------------------------------------------------ 绘制

func _draw() -> void:
	if main == null or main.merit == null:
		return
	_draw_top()
	_draw_actions()
	_draw_cards()
	_draw_skills()


func text(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(_font, p + Vector2(0, float(size) * 0.78), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func text_r(right_x: float, p_y: float, s: String, size: int, col: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(right_x - w, p_y), s, size, col)


func text_c(center_x: float, p_y: float, s: String, size: int, col: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(center_x - w * 0.5, p_y), s, size, col)


func _draw_top() -> void:
	var econ: TDEconomy = main.spawner.economy
	draw_rect(Rect2(0, 0, W, TOP_H), PANEL)
	draw_rect(Rect2(0, TOP_H - 2, W, 2), LINE)

	# 金币 —— 主资源，最大字号
	text(Vector2(24, 12), "金币", 15, DIM)
	text(Vector2(24, 32), str(econ.gold), 40, AMBER)

	# 功勋 —— 第二资源，与金币并列同高，因为它是本作的核心
	text(Vector2(190, 12), "功勋", 15, DIM)
	text(Vector2(190, 32), str(main.merit.merit), 40, TEAL)

	# 生命 / 波次 —— 右上
	text_r(W - 24, 12, "生命", 15, DIM)
	text_r(W - 24, 30, str(econ.lives), 34,
		BAD if econ.lives <= 5 else TEXT)
	text_r(W - 120, 12, "波次", 15, DIM)
	text_r(W - 120, 34, "%d/%d" % [maxi(main.spawner.wave_index + 1, 0),
		main.spawner.waves.size()], 22, TEXT)

	# 人口
	var used: int = main.pop_used()
	var cap: int = main.merit.pop_cap()
	text(Vector2(24, 84), "人口 %d/%d" % [used, cap], 17,
		BAD if used >= cap else TEXT)

	# 下一档解锁进度
	var nxt: int = main.merit.next_locked_tier()
	if nxt > 0:
		var req: int = main.merit.required_merit(nxt)
		var ratio: float = clampf(float(main.merit.merit) / float(maxi(req, 1)), 0.0, 1.0)
		var bar := Rect2(150, 88, 220, 10)
		draw_rect(bar, Color(0, 0, 0, 0.4))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), TEAL)
		text(Vector2(150, 100), "第 %d 档 %d/%d 功勋 · 点此解锁" % [nxt, main.merit.merit, req],
			13, DIM)
	else:
		text(Vector2(150, 88), "全部档位已解锁", 14, DIM)

	# 职业切换（两行文字，行距要够，否则「游侠」会压住「点击换部族」）
	var p: Dictionary = main.current_profession()
	var chip := Rect2(W - 216, 72, 192, 48)
	draw_rect(chip, PANEL_HI)
	draw_rect(chip, LINE, false, 1.0)
	draw_rect(Rect2(chip.position, Vector2(4, chip.size.y)),
		Color(str(p.get("color", "#5BD1A6"))))
	text(Vector2(chip.position.x + 14, chip.position.y + 5),
		str(p.get("name", "部族")), 18, TEXT)
	text(Vector2(chip.position.x + 14, chip.position.y + 28), "点击换部族", 11, DIM)


func _draw_actions() -> void:
	var t: TDTower = main.selected_tower
	if t == null or not is_instance_valid(t):
		return
	var def: Dictionary = main.content.tower_def(t.id)
	draw_rect(Rect2(16, ACTION_Y, W - 32, ACTION_H), PANEL)
	draw_rect(Rect2(16, ACTION_Y, W - 32, ACTION_H), LINE, false, 1.0)

	text(Vector2(34, ACTION_Y + 10), "%s  Lv.%d" % [t.display_name, t.level], 22, TEXT)
	text(Vector2(34, ACTION_Y + 40),
		"伤害 %.1f · 射程 %d · 击杀 %d" % [t.damage, int(t.range_px), t.kills],
		14, DIM)

	# 升级
	var uc: int = t.upgrade_cost()
	var up_rect := Rect2(W - 320, ACTION_Y + 12, 140, 54)
	var can_up: bool = t.can_upgrade()
	draw_rect(up_rect, PANEL_HI if can_up else Color("#1A2430"))
	draw_rect(up_rect, TEAL if can_up else LINE, false, 1.0)
	text_c(up_rect.position.x + up_rect.size.x * 0.5, up_rect.position.y + 10,
		"升级", 17, TEXT if can_up else DIM)
	text_c(up_rect.position.x + up_rect.size.x * 0.5, up_rect.position.y + 30,
		("%d 金币" % uc) if can_up else "已满级", 13, AMBER if can_up else DIM)

	# 出售
	var sell_rect := Rect2(W - 168, ACTION_Y + 12, 136, 54)
	draw_rect(sell_rect, Color("#2A1A1A"))
	draw_rect(sell_rect, Color("#6B3030"), false, 1.0)
	text_c(sell_rect.position.x + sell_rect.size.x * 0.5, sell_rect.position.y + 10,
		"出售", 17, TEXT)
	text_c(sell_rect.position.x + sell_rect.size.x * 0.5, sell_rect.position.y + 30,
		"+%d 金币" % t.sell_value(), 13, Color("#E0A0A0"))


func _draw_cards() -> void:
	var p: Dictionary = main.current_profession()
	var ids: Array = p.get("towers", [])
	if ids.is_empty():
		return
	var n: int = ids.size()
	var total: float = float(n) * CARD_W + float(n - 1) * CARD_GAP
	var x0: float = (W - total) * 0.5

	for i: int in range(n):
		var id := StringName(str(ids[i]))
		var def: Dictionary = main.content.tower_def(id)
		if def.is_empty():
			continue
		var x: float = x0 + float(i) * (CARD_W + CARD_GAP)
		var r := Rect2(x, CARD_Y, CARD_W, CARD_H)
		var locked: bool = not main.merit.is_unlocked(int(def.get("tier", 1)))
		var selected: bool = main.build_id == id
		var col := Color(str(def.get("color", "#8899AA")))

		draw_rect(r, Color("#1A2733") if locked else PANEL)
		if selected:
			draw_rect(r, AMBER, false, 2.5)
		else:
			draw_rect(r, LINE, false, 1.0)

		# 档位角标
		draw_rect(Rect2(x + 4, CARD_Y + 4, 22, 18), Color(col, 0.25 if locked else 1.0))
		text(Vector2(x + 7, CARD_Y + 5), "T%d" % int(def.get("tier", 1)), 12,
			TEXT if locked else Color("#0B1420"))

		var label: String = str(def.get("name", "?"))
		text_c(x + CARD_W * 0.5, CARD_Y + 28, label, 15,
			DIM if locked else TEXT)

		if locked:
			var req: int = main.merit.required_merit(int(def.get("tier", 1)))
			text_c(x + CARD_W * 0.5, CARD_Y + 52, "需要", 11, DIM)
			text_c(x + CARD_W * 0.5, CARD_Y + 66, "%d 功勋" % req, 12, TEAL)
		else:
			# JSON 里的数字都是 float，直接 str() 会显示成 "40.0"，先转 int
			text_c(x + CARD_W * 0.5, CARD_Y + 52,
				str(int(def.get("cost", 0))), 17, AMBER)
			text_c(x + CARD_W * 0.5, CARD_Y + 72,
				"伤害 %d" % int(def.get("damage", 0)), 11, DIM)


func _draw_skills() -> void:
	var skills: Array = main.merit.SKILLS
	var n: int = skills.size()
	var w := 150.0
	var gap := 14.0
	var total: float = float(n) * w + float(n - 1) * gap
	var x0: float = (W - total) * 0.5 + 40.0

	for i: int in range(n):
		var s: Dictionary = skills[i]
		var x: float = x0 + float(i) * (w + gap)
		var r := Rect2(x, SKILL_Y, w, SKILL_H)
		var ok: bool = main.merit.can_afford(int(s["cost"]))
		draw_rect(r, PANEL_HI if ok else Color("#1A2430"))
		draw_rect(r, TEAL if ok else LINE, false, 1.0)
		text_c(x + w * 0.5, SKILL_Y + 8, str(s["name"]), 19, TEXT if ok else DIM)
		text_c(x + w * 0.5, SKILL_Y + 32, "%d 功勋" % int(s["cost"]), 13,
			TEAL if ok else DIM)
		# 热键角标
		text(Vector2(x + 6, SKILL_Y + 4), str(s.get("hotkey", i + 1)), 11, DIM)


# ------------------------------------------------------------------ 命中测试

func _top_unlock_rect() -> Rect2:
	return Rect2(146, 80, 230, 32)


func _prof_rect() -> Rect2:
	return Rect2(W - 216, 78, 192, 40)


func _card_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var p: Dictionary = main.current_profession()
	var ids: Array = p.get("towers", [])
	var n: int = ids.size()
	if n == 0:
		return out
	var total: float = float(n) * CARD_W + float(n - 1) * CARD_GAP
	var x0: float = (W - total) * 0.5
	for i: int in range(n):
		out.append(Rect2(x0 + float(i) * (CARD_W + CARD_GAP), CARD_Y, CARD_W, CARD_H))
	return out


func _skill_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n: int = main.merit.SKILLS.size()
	var w := 150.0
	var gap := 14.0
	var total: float = float(n) * w + float(n - 1) * gap
	var x0: float = (W - total) * 0.5 + 40.0
	for i: int in range(n):
		out.append(Rect2(x0 + float(i) * (w + gap), SKILL_Y, w, SKILL_H))
	return out


## 返回 true 表示这次输入被 HUD 吃掉，地图不再处理。
func handle_input(event: InputEvent) -> bool:
	var p: Vector2 = _press_pos(event)
	if p == NO_POS:
		return false
	if _hit_top(p):
		return true
	if _hit_actions(p):
		return true
	if _hit_cards(p):
		return true
	if _hit_skills(p):
		return true
	# 底部区域兜底：点在空白处也不该穿透到地图去造塔
	return p.y > CARD_Y


func _press_pos(event: InputEvent) -> Vector2:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		return touch.position
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		return mb.position
	return NO_POS


func _hit_top(p: Vector2) -> bool:
	if p.y >= TOP_H:
		return false
	if _prof_rect().has_point(p):
		main.switch_profession(1)
	elif _top_unlock_rect().has_point(p):
		main.try_unlock_tier()
	return true


func _hit_actions(p: Vector2) -> bool:
	var t: TDTower = main.selected_tower
	if t == null or not is_instance_valid(t):
		return false
	if p.y < ACTION_Y or p.y > ACTION_Y + ACTION_H:
		return false
	if Rect2(W - 320, ACTION_Y + 12, 140, 54).has_point(p):
		main.try_upgrade(t)
	elif Rect2(W - 168, ACTION_Y + 12, 136, 54).has_point(p):
		main.try_sell(t)
	return true


func _hit_cards(p: Vector2) -> bool:
	var cards: Array[Rect2] = _card_rects()
	for i: int in range(cards.size()):
		if not cards[i].has_point(p):
			continue
		var ids: Array = main.current_profession().get("towers", [])
		if i < ids.size():
			main.build_id = StringName(str(ids[i]))
			main.selected_tower = null
			main.toast("%s（%d 金币）" % [
				main.content.tower_def(main.build_id).get("name", ""),
				main.content.tower_cost(main.build_id)])
		return true
	return false


func _hit_skills(p: Vector2) -> bool:
	var skills: Array[Rect2] = _skill_rects()
	for i: int in range(skills.size()):
		if not skills[i].has_point(p):
			continue
		main.use_skill(main.merit.SKILLS[i]["id"])
		return true
	return false
