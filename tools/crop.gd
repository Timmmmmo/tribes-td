extends SceneTree
## 临时工具：裁一块 + 最近邻放大，用来贴到眼前看细节。
## godot --headless -s res://tools/crop.gd -- <src> <dst> <x> <y> <w> <h> <scale>

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 7:
		print("usage: <src> <dst> <x> <y> <w> <h> <scale>")
		quit(1)
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(a[0]))
	if img == null:
		img = Image.new()
		img.load(a[0])
	var r := Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
	var crop := img.get_region(r)
	var k: int = int(a[6])
	crop.resize(r.size.x * k, r.size.y * k, Image.INTERPOLATE_NEAREST)
	crop.save_png(a[1])
	print("saved ", a[1], " ", crop.get_width(), "x", crop.get_height())
	quit(0)
