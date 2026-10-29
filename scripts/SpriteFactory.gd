class_name SpriteFactory
extends RefCounted

static var _cache: Dictionary = {}

static func get_monster_texture(archetype_idx: int) -> Texture2D:
	var key: String = "monster_%d" % archetype_idx
	if _cache.has(key):
		return _cache[key]

	var filenames: Array[String] = [
		"res://assets/sprites/imp.png",
		"res://assets/sprites/wraith.png",
		"res://assets/sprites/golem.png",
		"res://assets/sprites/executioner.png"
	]
	var idx: int = clampi(archetype_idx, 0, 3)
	var tex: Texture2D = _try_load_external_png(filenames[idx])
	if tex == null:
		tex = _build_procedural_monster_texture(idx)
	_cache[key] = tex
	return tex

static func get_tower_texture() -> Texture2D:
	var key: String = "wizard_tower"
	if _cache.has(key):
		return _cache[key]

	var tex: Texture2D = _try_load_external_png("res://assets/sprites/wizard_tower.png")
	if tex == null:
		tex = _build_procedural_tower_texture()
	_cache[key] = tex
	return tex

static func get_wizard_texture(is_casting: bool = false) -> Texture2D:
	var key: String = "wizard_cast" if is_casting else "wizard_idle"
	if _cache.has(key):
		return _cache[key]

	var tex: Texture2D = _build_procedural_wizard_texture(is_casting)
	_cache[key] = tex
	return tex

static func _try_load_external_png(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var loaded = load(res_path)
		if loaded is Texture2D:
			return loaded
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.new()
		if img.load(abs_path) == OK:
			return ImageTexture.create_from_image(img)
	return null

static func _grid_to_texture(grid: Array[String], palette: Dictionary, scale: int = 4) -> ImageTexture:
	var h: int = grid.size()
	var w: int = grid[0].length()
	var img: Image = Image.create(w * scale, h * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for y in range(h):
		var row: String = grid[y]
		for x in range(w):
			var ch: String = row.substr(x, 1)
			if ch != "." and palette.has(ch):
				var col: Color = palette[ch]
				img.fill_rect(Rect2i(x * scale, y * scale, scale, scale), col)

	return ImageTexture.create_from_image(img)

static func _build_procedural_monster_texture(archetype_idx: int) -> ImageTexture:
	match archetype_idx:
		0: # Diablotin Véloce (Imp)
			var grid: Array[String] = [
				"..y..........y..",
				".yy...rrrr...yy.",
				"..yr.rrrrrr.ry..",
				"...rrrrrrrrrr...",
				"..d.rrlrrlrr.d..",
				".dd.rrrrrrrr.dd.",
				"ddd.rr.ww.rr.ddd",
				"dd.rrrrrrrrrr.dd",
				"d..rrrrrrrrrr..d",
				"....rrrrrrrr....",
				"....rrrrrrrr....",
				"....rrr..rrr....",
				"...rrr....rrr...",
				"...rr......rr...",
				"..dd........dd..",
				"................"
			]
			var pal := {
				"r": Color.html("#E04838"),
				"d": Color.html("#7A1C18"),
				"y": Color.html("#FFD84D"),
				"l": Color.html("#FFF275"),
				"w": Color.html("#FFFFFF")
			}
			return _grid_to_texture(grid, pal)
		1: # Rôdeur des Brumes (Wraith)
			var grid: Array[String] = [
				".....pppppp.....",
				"...pppppppppp...",
				"..pppddddddppp..",
				"..ppddddddddpp..",
				"..ppddcddcddpp..",
				"..ppddddddddpp..",
				".ppppddbbddpppp.",
				".pppppppppppppp.",
				"pppppppppppppppp",
				"ppp.pppppppp.ppp",
				"pp..pppppppp..pp",
				"....pppppppp....",
				"...pppppppppp...",
				"..ppp.pppp.ppp..",
				"..p...p..p...p..",
				"................"
			]
			var pal := {
				"p": Color.html("#7E48C4"),
				"d": Color.html("#23113B"),
				"c": Color.html("#5CEEFF"),
				"b": Color.html("#2998B8")
			}
			return _grid_to_texture(grid, pal)
		2: # Carapace de Roc (Golem)
			var grid: Array[String] = [
				"....gggggggg....",
				"..ggggllllgggg..",
				".ggglladddllggg.",
				".gglddodddoddlg.",
				"ggglddddddddddgg",
				"ggggllllllllgggg",
				"gggglllkooolgggg",
				"ggggllkooooolggg",
				"gggllllkooollggg",
				"gg.ggggllllgg.gg",
				"gg..gggggggg..gg",
				"....gggggggg....",
				"...gggg..gggg...",
				"...ggg....ggg...",
				"..dddd....dddd..",
				"................"
			]
			var pal := {
				"g": Color.html("#5E7A68"),
				"l": Color.html("#88A892"),
				"d": Color.html("#2C3830"),
				"a": Color.html("#2C3830"),
				"o": Color.html("#FFB838"),
				"k": Color.html("#E06A28")
			}
			return _grid_to_texture(grid, pal)
		_: # Exécuteur Abyssal (Executioner)
			var grid: Array[String] = [
				".y............y.",
				".yy..mmmmmm..yy.",
				"..yymmmmmmmmyy..",
				"...mmddddddmm...",
				"...mddrddrddm...",
				"..mmmmddddddmm..",
				".ssmmmmmmmmmmss.",
				"sssmmmmllmmmmsss",
				"ss.mmmmllmmmm.ss",
				"...mmmmmmmmmm...",
				"...mmmmmmmmmm...",
				"...mmmm..mmmm...",
				"..mmmm....mmmm..",
				"..mmm......mmm..",
				"..ddd......ddd..",
				"................"
			]
			var pal := {
				"m": Color.html("#B82868"),
				"d": Color.html("#240C1C"),
				"y": Color.html("#E8C868"),
				"l": Color.html("#FFD84D"),
				"r": Color.html("#FF3838"),
				"s": Color.html("#B8C8D8")
			}
			return _grid_to_texture(grid, pal)

static func _build_procedural_tower_texture() -> ImageTexture:
	var grid: Array[String] = [
		".......cc.......",
		"......cwwc......",
		"......bbbb......",
		".....bbbbbb.....",
		"....bbbbbbbb....",
		"...bbbbbbbbbb...",
		"..ss.ssssss.ss..",
		"..ssssssssssss..",
		"...ssddssddss...",
		"...ssssssssss...",
		"...ssssddssss...",
		"...ssssddssss...",
		"..ssssssssssss..",
		"..ssssssssssss..",
		".dddddddddddddd.",
		"................"
	]
	var pal := {
		"c": Color.html("#5CEEFF"),
		"w": Color.html("#FFFFFF"),
		"b": Color.html("#6C3CE8"),
		"s": Color.html("#8F9BB3"),
		"d": Color.html("#353C4B")
	}
	return _grid_to_texture(grid, pal)

static func _build_procedural_wizard_texture(is_casting: bool) -> ImageTexture:
	var pal := {
		"h": Color.html("#3D257A"), # Chapeau / Robe sombre
		"p": Color.html("#6E42C8"), # Robe violette
		"g": Color.html("#FFD84D"), # Galons dorés / Étoile
		"f": Color.html("#FFCC99"), # Visage
		"b": Color.html("#E6ECF5"), # Barbe blanche
		"w": Color.html("#8C5230"), # Bâton en bois
		"c": Color.html("#5CEEFF"), # Cristal magique cyan
		"e": Color.html("#FFFFFF")  # Éclat pur
	}
	if not is_casting:
		var grid_idle: Array[String] = [
			"......hh........",
			".....hhhh.......",
			"....hhgghh......",
			"...hhhhhhhh.....",
			"..hhhhhhhhhh.c..",
			"....ffffff..cec.",
			"....febbbf...c..",
			"....bbbbbb...w..",
			"...pppppppp..w..",
			"..ppppggpppp.w..",
			"..pppppppppppw..",
			"...pppppppp..w..",
			"...pppppppp..w..",
			"...ppp..ppp..w..",
			"................",
			"................"
		]
		return _grid_to_texture(grid_idle, pal)
	else:
		var grid_cast: Array[String] = [
			".............ce.",
			"......hh....ceec",
			".....hhhh....ce.",
			"....hhgghh...w..",
			"..hhhhhhhhhh.w..",
			"....feebef...w..",
			"....bbbbbb..w...",
			".pp.pppppp.pp...",
			"ppppppggpppppp..",
			"pp..pppppp..pp..",
			"....pppppp......",
			"...pppppppp.....",
			"...ppp..ppp.....",
			"..ppp....ppp....",
			"................",
			"................"
		]
		return _grid_to_texture(grid_cast, pal)
