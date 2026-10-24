class_name TDArt
extends RefCounted
## 程序化美术层 —— 把 Godot 版的表现力拉到 canvas 版的水平。
##
## 两条原则：
##   1. 静态的东西离线烘焙成一张贴图，运行时只贴一次。
##      （地形有 2600 根草叶，逐帧 draw_line 是纯浪费。）
##   2. 动态的东西用 CanvasItem 的 draw_* 现画，靠「顶点色」做渐变，
##      不引入任何位图资源 —— 和 canvas 版一样零图片依赖。
##
## 顶点色渐变是这里最关键的技巧：Godot 没有 createLinearGradient，
## 但 draw_polygon(points, colors) 会在顶点之间插值，给上下顶点不同颜色
## 就等于拿到了线性渐变。径向渐变则用一张烘焙好的软光斑贴图拉伸。

const CELL := 64

const GRASS_TOP := Color("#2F5039")
const GRASS_MID := Color("#203D2E")
const GRASS_BOT := Color("#142A20")

## 石板的四套配色，按格子哈希取一套，避免 43 个格子贴同一张图看出重复
const STONE_SETS := [
	["#3C4A5A", "#4E6072", "#232E38"],
	["#36434F", "#485A6A", "#1F2831"],
	["#404E5D", "#54677A", "#26313B"],
	["#394653", "#4B5D6E", "#212A34"],
]
const MORTAR := Color("#2A343D")
const SHADOW_K := 0.42
## 石板瓦片的变体数量。太少会看出重复（43 个格子贴同一张图），
## 太多又要多跑几次逐像素烘焙 —— 12 是实测下来的平衡点。
const STONE_VARIANTS := 12

static var _glow_tex: ImageTexture
static var _stone_tiles: Array[ImageTexture] = []


# ------------------------------------------------------------------ 基础工具

## 确定性伪随机 —— 不用 RandomNumberGenerator 是为了让每个格子/每根草叶
## 在多次烘焙之间完全一致，改代码不会导致整张地图重新洗牌。
static func hash01(i: int) -> float:
	var x: int = (i * 374761393 + 668265263) & 0x7FFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF
	x = (x ^ (x >> 16)) & 0x7FFFFFFF
	return float(x % 1000000) / 1000000.0


static func grass_at(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return GRASS_TOP.lerp(GRASS_MID, t / 0.5)
	return GRASS_MID.lerp(GRASS_BOT, (t - 0.5) / 0.5)


static func darken(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func shade(c: Color, k: float) -> Color:
	## k > 1 提亮（往白靠），k < 1 压暗。比单纯乘系数更像光照。
	if k >= 1.0:
		var t: float = clampf(k - 1.0, 0.0, 1.0)
		return Color(c.r + (1.0 - c.r) * t, c.g + (1.0 - c.g) * t, c.b + (1.0 - c.b) * t, c.a)
	return darken(c, k)


static func rgba(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## 软件画点：带 alpha 混合地写进 Image。
## RGBA8 是直通 alpha（非预乘），所以混合要按 out = (src*a + dst*da*(1-a)) / out_a 来算。
static func plot(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
		return
	var d: Color = img.get_pixel(x, y)
	var a: float = c.a + d.a * (1.0 - c.a)
	if a <= 0.002:
		return
	var inv: float = d.a * (1.0 - c.a)
	img.set_pixel(x, y, Color(
		(c.r * c.a + d.r * inv) / a,
		(c.g * c.a + d.g * inv) / a,
		(c.b * c.a + d.b * inv) / a,
		a))


# ------------------------------------------------------------------ 几何构造

static func ngon(center: Vector2, r: float, n: int, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(n):
		var a: float = rot + TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


static func star(center: Vector2, r_out: float, r_in: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(n * 2):
		var rr: float = r_out if i % 2 == 0 else r_in
		var a: float = -PI / 2.0 + PI * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts


static func ellipse(center: Vector2, rx: float, ry: float, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## 圆角矩形轮廓。Godot 的 draw_rect 不支持圆角，只能自己搭多边形。
static func round_rect(r: Rect2, rad: float, seg: int = 5) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.position.x + rad, r.position.y + rad), PI, PI * 1.5],
		[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5, TAU],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0, PI * 0.5],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5, PI],
	]
	for c: Array in corners:
		var pivot: Vector2 = c[0]
		var a0: float = float(c[1])
		var a1: float = float(c[2])
		for i: int in range(seg + 1):
			var a: float = lerpf(a0, a1, float(i) / float(seg))
			pts.append(pivot + Vector2(cos(a), sin(a)) * rad)
	return pts


## 上亮下暗的渐变填充 —— 这里就是「Godot 没有渐变」的解法。
static func fill_vgrad(ci: CanvasItem, pts: PackedVector2Array,
		top: Color, bottom: Color, y0: float, y1: float) -> void:
	var cols := PackedColorArray()
	cols.resize(pts.size())
	var span: float = maxf(y1 - y0, 0.001)
	for i: int in range(pts.size()):
		cols[i] = top.lerp(bottom, clampf((pts[i].y - y0) / span, 0.0, 1.0))
	ci.draw_polygon(pts, cols)


## 纯色填充。draw_polygon 要求 colors 和 points 等长，
## 只给一个 Color 会报错，所以这里统一补齐。
static func fill(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	ci.draw_polygon(pts, cols)


## 纯色多边形 + 描边。draw_polygon 单独用不会画边，这里补一圈。
static func fill_stroke(ci: CanvasItem, pts: PackedVector2Array, fill_col: Color,
		stroke: Color, width: float) -> void:
	fill(ci, pts, fill_col)
	ci.draw_polyline(closed(pts), stroke, width, true)


static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


# ------------------------------------------------------------------ 软光斑

## 128×128 的白色径向渐变。用它替代「叠几层同心圆」的假发光：
## 同心圆在暗底上一定能看出色阶，一张软贴图拉伸后完全看不出来。
static func glow_texture() -> ImageTexture:
	if _glow_tex != null:
		return _glow_tex
	var n: int = 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c: float = float(n) * 0.5
	for y: int in range(n):
		for x: int in range(n):
			var d: float = Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


static func glow(ci: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	ci.draw_texture_rect(glow_texture(),
		Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)


## 虚线圆环：Godot 没有 setLineDash，只能按段画弧。
## 用 2 段弧一组的规律做出「转动的符文环」。
static func dashed_ring(ci: CanvasItem, center: Vector2, r: float, col: Color,
		width: float, dashes: int = 16, phase: float = 0.0, duty: float = 0.55) -> void:
	var step: float = TAU / float(dashes)
	for i: int in range(dashes):
		var a0: float = phase + step * float(i)
		ci.draw_arc(center, r, a0, a0 + step * duty, 6, col, width, true)


# ------------------------------------------------------------------ 地形烘焙

## 把整块棋盘烘焙成一张贴图。
## 只会跑一次，成本约等于「2600 根草叶 × 5 个像素 + 43 个石板格」，
## 换来的是一帧只贴一次图，手机上也不会掉帧。
static func bake_map(map: TDMap) -> ImageTexture:
	var cell: int = int(map.cell_px)
	var w: int = map.cols * cell
	var h: int = map.rows * cell
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

	# ---- 草地底
	# 之前是「每格一个色块」，远看就是一张 9×15 的棋盘格，这是最扎眼的问题。
	# 改成一行一条的连续渐变（960 次 fill_rect，C++ 里跑，可以忽略），
	# 纹理层次全部交给草叶，而不是靠格子色差硬凑。
	for y: int in range(h):
		img.fill_rect(Rect2i(0, y, w, 1), grass_at(float(y) / float(h)))

	# ---- 草叶：5200 根，分冷暖两层
	# 透明度踩过一次坑：第一版给 0.07~0.26，整片草地看起来还是纯色。
	# 但也不能靠单根加浓（会变成划痕），正确做法是「根数多 + 单根淡 + 短」。
	for i: int in range(5200):
		var px: float = hash01(i * 3 + 1) * float(w)
		var py: float = hash01(i * 3 + 2) * float(h)
		var cell_c: Vector2i = map.cell_at(Vector2(px, py))
		if map.in_bounds(cell_c) and map.is_path(cell_c):
			continue  # 路面下面反正会被石板盖住，省掉
		var ln: float = 1.6 + hash01(i * 3 + 3) * 3.6
		var lean: float = (hash01(i * 7 + 11) - 0.5) * 2.6
		var a: float = 0.12 + hash01(i * 11 + 5) * 0.24
		var warm: bool = hash01(i * 13 + 7) > 0.70
		var col := Color(0.66, 0.88, 0.70, a) if warm else Color(0.24, 0.50, 0.38, a * 0.9)
		_blade(img, px, py, ln, lean, col)

	# ---- 路面阴影：让路「陷」进地面，而不是平铺在上面
	for c: Vector2i in map.path_cells():
		if not map.in_bounds(c):
			continue
		var yc: float = (float(c.y) + 0.5) * float(cell)
		var sh: Color = darken(grass_at(yc / float(h)), SHADOW_K)
		img.fill_rect(Rect2i(c.x * cell - 5, c.y * cell - 5, cell + 10, cell + 10), sh)

	# ---- 石板：每格贴一张 64px 的石板瓦片，4 套配色按格子哈希选
	var tiles: Array[ImageTexture] = _stone_tiles_for(cell)
	for c: Vector2i in map.path_cells():
		if not map.in_bounds(c):
			continue
		var pick: int = int(hash01(c.x * 131 + c.y * 977) * float(tiles.size())) % tiles.size()
		img.blit_rect(tiles[pick].get_image(), Rect2i(0, 0, cell, cell),
			Vector2i(c.x * cell, c.y * cell))

	return ImageTexture.create_from_image(img)


static func _blade(img: Image, x: float, y: float, ln: float, lean: float, col: Color) -> void:
	var steps: int = maxi(int(ln), 2)
	for i: int in range(steps):
		var t: float = float(i) / float(steps - 1)
		# 二次曲线：草尖向外倒，根部立着，比直线自然
		plot(img, int(round(x + lean * t * t)), int(round(y - ln * t)), col)


static func _stone_tiles_for(cell: int) -> Array[ImageTexture]:
	if not _stone_tiles.is_empty():
		return _stone_tiles
	for v: int in range(STONE_VARIANTS):
		var pal: Array = STONE_SETS[v % STONE_SETS.size()]
		_stone_tiles.append(ImageTexture.create_from_image(
			_stone_tile(cell, Color(str(pal[0])), Color(str(pal[1])), Color(str(pal[2])), v * 7919)))
	return _stone_tiles


## 一格 = 2×2 块石板。先铺勾缝底色，再压四块圆角石头。
## 关键是**切分线要抖**：如果每条缝都正好落在 32px 上，43 个格子拼起来
## 就是一面砖墙，而不是一条石板路 —— 第一版就是这么翻车的。
static func _stone_tile(cell: int, base: Color, hi: Color, lo: Color, seed_i: int) -> Image:
	var img := Image.create_empty(cell, cell, false, Image.FORMAT_RGBA8)
	img.fill(MORTAR)
	var c: float = float(cell)
	var mid_x: float = c * 0.5 + (hash01(seed_i) - 0.5) * 9.0
	var mid_y: float = c * 0.5 + (hash01(seed_i + 17) - 0.5) * 9.0
	var gap: float = 1.15
	var rad: float = c * 0.075
	var boxes: Array[Rect2] = [
		Rect2(gap, gap, mid_x - gap, mid_y - gap),
		Rect2(mid_x + gap * 0.5, gap, c - mid_x - gap * 1.5, mid_y - gap),
		Rect2(gap, mid_y + gap * 0.5, mid_x - gap, c - mid_y - gap * 1.5),
		Rect2(mid_x + gap * 0.5, mid_y + gap * 0.5, c - mid_x - gap * 1.5, c - mid_y - gap * 1.5),
	]
	for r: Rect2 in boxes:
		var y0: float = r.position.y
		var span: float = maxf(r.size.y, 0.001)
		for y: int in range(int(floor(r.position.y)), int(ceil(r.end.y))):
			var t: float = clampf((float(y) + 0.5 - y0) / span, 0.0, 1.0)
			var col: Color = hi.lerp(base, t / 0.42) if t < 0.42 else base.lerp(lo, (t - 0.42) / 0.58)
			for x: int in range(int(floor(r.position.x)), int(ceil(r.end.x))):
				if not _in_round(Vector2(float(x) + 0.5, float(y) + 0.5), r, rad):
					continue
				var out: Color = col
				if float(y) + 0.5 - y0 < 1.6:
					out = col.lerp(Color(0.80, 0.88, 0.96, 1.0), 0.26)
				img.set_pixel(x, y, out)
	return img


static func _in_round(p: Vector2, r: Rect2, rad: float) -> bool:
	if p.x < r.position.x or p.y < r.position.y or p.x > r.end.x or p.y > r.end.y:
		return false
	var cx: float = clampf(p.x, r.position.x + rad, r.end.x - rad)
	var cy: float = clampf(p.y, r.position.y + rad, r.end.y - rad)
	return p.distance_to(Vector2(cx, cy)) <= rad
