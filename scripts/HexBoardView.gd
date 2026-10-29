class_name HexBoardView
extends Control

signal rotation_changed(new_rotation: int)
signal cast_confirmed()
signal candidate_target_selected(monster_dict: Dictionary)

const HEX_SIZE: float = 28.0

var all_tiles: Array[Vector2i] = []
var monsters: Array[Dictionary] = []
var tower_hp: int = 50
var tower_max_hp: int = 50

# État d'aperçu du sort prêt à être orienté / lancé
var preview_active: bool = false
var preview_element: int = SpellData.Element.FIRE
var preview_shape: int = SpellData.Shape.LINE
var preview_double_size: bool = false
var preview_extra_offsets: Array[Vector2i] = []
var preview_origin_hex: Vector2i = Vector2i.ZERO
var preview_rotation: int = 0

# Survol souris
var hovered_hex: Vector2i = Vector2i(999, 999)

# Effets visuels temporaires, projectiles, animations de mort et zones persistantes ("Reste 1 Tour")
var tile_flashes: Array[Dictionary] = []
var lingering_zones: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []
var active_projectiles: Array[Dictionary] = []
var projectile_particles: Array[Dictionary] = []
var dying_monsters: Array[Dictionary] = []

# Animation d'incantation du Sorcier sur la Tour (0, 0)
var wizard_cast_timer: float = 0.0
var wizard_cast_max_timer: float = 0.65
var wizard_cast_element: int = SpellData.Element.NEUTRAL

var anim_time: float = 0.0
var vfx_rng := RandomNumberGenerator.new()

func _init() -> void:
	vfx_rng.randomize()
	all_tiles = HexMath.get_all_board_tiles()
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func is_busy_animating() -> bool:
	return not active_projectiles.is_empty()

func _process(delta: float) -> void:
	anim_time += delta

	if wizard_cast_timer > 0.0:
		wizard_cast_timer = maxf(0.0, wizard_cast_timer - delta)

	# 1. Mise à jour des projectiles de sort (Tour -> Hexagone ciblé)
	var center: Vector2 = get_board_center()
	for i in range(active_projectiles.size() - 1, -1, -1):
		var proj: Dictionary = active_projectiles[i]
		proj["elapsed"] = float(proj["elapsed"]) + delta
		var t: float = clampf(float(proj["elapsed"]) / float(proj["duration"]), 0.0, 1.0)

		# Position actuelle avec arc parabolique
		var start_px: Vector2 = proj["start_px"]
		var target_px: Vector2 = proj["target_px"]
		var cur_px: Vector2 = start_px.lerp(target_px, t) + Vector2(0, -sin(t * PI) * 28.0)
		proj["current_px"] = cur_px

		# Génère des particules de traînée derrière le projectile
		var el_col: Color = SpellData.get_element_color(int(proj["element"]))
		for _p in range(2):
			var rand_vel := Vector2(vfx_rng.randf_range(-22.0, 22.0), vfx_rng.randf_range(-22.0, 22.0))
			projectile_particles.append({
				"pos": cur_px + Vector2(vfx_rng.randf_range(-4.0, 4.0), vfx_rng.randf_range(-4.0, 4.0)),
				"vel": rand_vel,
				"color": el_col.lightened(vfx_rng.randf_range(0.1, 0.45)),
				"size": vfx_rng.randf_range(2.2, 4.5),
				"timer": 0.26,
				"max_timer": 0.26
			})

		if t >= 1.0:
			# Le projectile touche l'hexagone ciblé : déploiement de l'effet sur chaque case du gabarit !
			var origin_hex: Vector2i = proj["origin_hex"]
			var affected_hexes: Array[Vector2i] = proj["affected_hexes"]
			var el: int = int(proj["element"])
			var is_linger: bool = bool(proj["is_linger"])
			var base_dmg: int = int(proj["base_dmg"])
			var cb: Callable = proj["on_impact"]

			# Éclat de particules à l'impact sur l'origine
			for _k in range(14):
				var ang: float = vfx_rng.randf_range(0.0, TAU)
				var spd: float = vfx_rng.randf_range(30.0, 95.0)
				projectile_particles.append({
					"pos": target_px,
					"vel": Vector2(cos(ang), sin(ang)) * spd,
					"color": el_col.lightened(0.35),
					"size": vfx_rng.randf_range(2.8, 5.2),
					"timer": 0.38,
					"max_timer": 0.38
				})

			add_spell_effect_deployed(origin_hex, affected_hexes, el, is_linger, base_dmg)
			active_projectiles.remove_at(i)
			if cb.is_valid():
				cb.call()

	# 2. Particules de traînée et d'impact
	for i in range(projectile_particles.size() - 1, -1, -1):
		var pt: Dictionary = projectile_particles[i]
		pt["timer"] = float(pt["timer"]) - delta
		pt["pos"] = Vector2(pt["pos"]) + Vector2(pt["vel"]) * delta
		if float(pt["timer"]) <= 0.0:
			projectile_particles.remove_at(i)

	# 3. Déploiement progressif des flashs de tuiles sur le gabarit
	for i in range(tile_flashes.size() - 1, -1, -1):
		var tf: Dictionary = tile_flashes[i]
		var delay: float = float(tf.get("delay", 0.0))
		if delay > 0.0:
			tf["delay"] = maxf(0.0, delay - delta)
		else:
			tf["age"] = float(tf.get("age", 0.0)) + delta
			tf["timer"] = float(tf["timer"]) - delta
			if float(tf["timer"]) <= 0.0:
				tile_flashes.remove_at(i)

	# 4. Déploiement progressif des zones persistantes
	for lz in lingering_zones:
		var delay: float = float(lz.get("delay", 0.0))
		if delay > 0.0:
			lz["delay"] = maxf(0.0, delay - delta)
		else:
			lz["age"] = float(lz.get("age", 0.0)) + delta

	# 5. Animations de mort des monstres
	for i in range(dying_monsters.size() - 1, -1, -1):
		var dm: Dictionary = dying_monsters[i]
		dm["timer"] = float(dm["timer"]) - delta
		var parts: Array = dm["particles"]
		for p in parts:
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
			p["vel"] = Vector2(p["vel"]) + Vector2(0, 90.0 * delta) # Légère gravité
		if float(dm["timer"]) <= 0.0:
			dying_monsters.remove_at(i)

	# 6. Textes flottants
	for i in range(floating_texts.size() - 1, -1, -1):
		floating_texts[i]["timer"] -= delta
		floating_texts[i]["pos"] += Vector2(0, -32.0 * delta)
		if floating_texts[i]["timer"] <= 0.0:
			floating_texts.remove_at(i)

	queue_redraw()

func get_board_center() -> Vector2:
	return size * 0.5

func trigger_wizard_cast_anim(element: int) -> void:
	wizard_cast_element = element
	wizard_cast_max_timer = 0.65
	wizard_cast_timer = wizard_cast_max_timer
	queue_redraw()

func launch_spell_projectile(
	origin_hex: Vector2i,
	affected_hexes: Array[Vector2i],
	element: int,
	is_linger: bool,
	base_dmg: int,
	on_impact: Callable
) -> void:
	trigger_wizard_cast_anim(element)
	var center: Vector2 = get_board_center()
	var start_px: Vector2 = center + Vector2(6, -16) # Sommet du bâton du Sorcier
	var target_px: Vector2 = center + HexMath.hex_to_pixel(origin_hex, HEX_SIZE)
	var dist_hex: int = HexMath.distance(Vector2i.ZERO, origin_hex)
	var duration: float = clampf(0.20 + float(dist_hex) * 0.04, 0.22, 0.44)

	active_projectiles.append({
		"origin_hex": origin_hex,
		"affected_hexes": affected_hexes.duplicate(),
		"element": element,
		"is_linger": is_linger,
		"base_dmg": base_dmg,
		"start_px": start_px,
		"target_px": target_px,
		"current_px": start_px,
		"elapsed": 0.0,
		"duration": duration,
		"on_impact": on_impact
	})
	queue_redraw()

func add_spell_effect_deployed(
	origin_hex: Vector2i,
	hexes: Array[Vector2i],
	element: int,
	is_lingering: bool = false,
	base_dmg: int = 10
) -> void:
	for h in hexes:
		if HexMath.is_in_board(h):
			# Délai progressif selon la distance à l'hexagone d'origine pour voir l'effet se déployer sur le gabarit !
			var dist_from_origin: int = HexMath.distance(origin_hex, h)
			var deploy_delay: float = float(dist_from_origin) * 0.065

			tile_flashes.append({
				"hex": h,
				"element": element,
				"delay": deploy_delay,
				"age": 0.0,
				"timer": 0.70,
				"max_timer": 0.70
			})
			# Remplace un éventuel effet existant sur cet hexagone
			for j in range(lingering_zones.size() - 1, -1, -1):
				if lingering_zones[j]["hex"] == h:
					lingering_zones.remove_at(j)

			lingering_zones.append({
				"hex": h,
				"element": element,
				"damage": base_dmg,
				"turns_left": 2 if is_lingering else 1,
				"is_lingering": is_lingering,
				"delay": deploy_delay,
				"age": 0.0
			})
	queue_redraw()

func add_spell_effect(hexes: Array[Vector2i], element: int, is_lingering: bool = false, base_dmg: int = 10) -> void:
	var origin: Vector2i = hexes[0] if not hexes.is_empty() else Vector2i.ZERO
	add_spell_effect_deployed(origin, hexes, element, is_lingering, base_dmg)

func add_monster_death_anim(m: Dictionary, element: int = SpellData.Element.NEUTRAL) -> void:
	var el_col: Color = SpellData.get_element_color(element)
	var m_col: Color = m.get("color", Color(0.9, 0.35, 0.3))
	var parts: Array[Dictionary] = []
	for i in range(12):
		var ang: float = (TAU / 12.0) * float(i) + vfx_rng.randf_range(-0.2, 0.2)
		var spd: float = vfx_rng.randf_range(28.0, 78.0)
		var p_col: Color = el_col.lightened(0.25) if (i % 2 == 0) else m_col.lightened(0.2)
		parts.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd - 22.0),
			"size": vfx_rng.randf_range(2.5, 5.0),
			"color": p_col
		})

	dying_monsters.append({
		"hex": m["hex"],
		"archetype": int(m.get("archetype", int(m.get("id", 0)) % 4)),
		"color": m_col,
		"element": element,
		"timer": 0.65,
		"max_timer": 0.65,
		"particles": parts
	})
	queue_redraw()

func add_floating_text(hex: Vector2i, text: String, color: Color) -> void:
	var px: Vector2 = get_board_center() + HexMath.hex_to_pixel(hex, HEX_SIZE)
	floating_texts.append({
		"pos": px + Vector2(0, -14),
		"text": text,
		"color": color,
		"timer": 1.1,
		"max_timer": 1.1
	})
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if is_busy_animating():
		return
	var center: Vector2 = get_board_center()

	if event is InputEventMouseMotion:
		var local_pos: Vector2 = event.position - center
		var new_hex: Vector2i = HexMath.pixel_to_hex(local_pos, HEX_SIZE)
		if new_hex != hovered_hex:
			hovered_hex = new_hex
			# Le joueur vise librement la tuile de son choix sur le plateau
			if preview_active and HexMath.is_in_board(hovered_hex):
				preview_origin_hex = hovered_hex
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed:
		if preview_active:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_RIGHT:
				preview_rotation = (preview_rotation + 1) % 6
				rotation_changed.emit(preview_rotation)
				queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				preview_rotation = (preview_rotation + 5) % 6
				rotation_changed.emit(preview_rotation)
				queue_redraw()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var clicked_hex: Vector2i = HexMath.pixel_to_hex(event.position - center, HEX_SIZE)
				if HexMath.is_in_board(clicked_hex):
					preview_origin_hex = clicked_hex
					cast_confirmed.emit()

func _draw() -> void:
	var center: Vector2 = get_board_center()
	var font: Font = ThemeDB.fallback_font

	# Calcule les tuiles affectées par la forme du sort en cours de visée
	var preview_hexes: Array[Vector2i] = []
	if preview_active:
		var offsets: Array[Vector2i] = SpellData.get_shape_offsets(preview_shape, preview_double_size).duplicate()
		for ext in preview_extra_offsets:
			if not offsets.has(ext):
				offsets.append(ext)
		preview_hexes = HexMath.get_transformed_shape(offsets, preview_origin_hex, preview_rotation)

	# 1. Dessin des 127 tuiles hexagonales du plateau avec herbe, touffes et fleurs
	for hex in all_tiles:
		_draw_grass_tile(center, hex)

	# 2. Dessin de l'aperçu de la Forme et de son Origine sur la tuile visée
	if preview_active:
		var el_col: Color = SpellData.get_element_color(preview_element)
		for i in range(preview_hexes.size()):
			var h: Vector2i = preview_hexes[i]
			var px: Vector2 = center + HexMath.hex_to_pixel(h, HEX_SIZE)
			var is_origin: bool = (h == preview_origin_hex)
			var in_board: bool = HexMath.is_in_board(h)
			var corners: PackedVector2Array = HexMath.get_hex_corners(px, HEX_SIZE - 2.0)

			var overlay_col: Color = el_col
			overlay_col.a = 0.55 if in_board else 0.18
			draw_colored_polygon(corners, overlay_col)

			var ring_col: Color = Color(1.0, 0.95, 0.35) if is_origin else el_col.lightened(0.35)
			if not in_board:
				ring_col.a = 0.35
			var closed := corners.duplicate()
			closed.append(corners[0])
			draw_polyline(closed, ring_col, 3.2 if is_origin else 2.2, true)

			if is_origin:
				draw_arc(px, HEX_SIZE * 0.42, 0, TAU, 20, Color(1.0, 0.95, 0.35), 2.2)

	# 3. Dessin des zones élémentaires persistantes (après leur délai de déploiement)
	for lz in lingering_zones:
		if float(lz.get("delay", 0.0)) <= 0.0:
			var bloom: float = clampf(float(lz.get("age", 0.2)) / 0.18, 0.2, 1.0)
			var pulse_alpha: float = 0.42 + 0.14 * sin(anim_time * 4.0)
			_draw_elemental_hex_effect(center, lz["hex"], int(lz["element"]), pulse_alpha, true, bloom)

	# 4. Dessin des effets élémentaires lors du déploiement du sort sur le gabarit
	for f in tile_flashes:
		if float(f.get("delay", 0.0)) <= 0.0:
			var bloom: float = clampf(float(f.get("age", 0.0)) / 0.16, 0.15, 1.0)
			var ratio: float = clampf(float(f["timer"]) / float(f["max_timer"]), 0.0, 1.0)
			_draw_elemental_hex_effect(center, f["hex"], int(f.get("element", 0)), ratio * 0.72, false, bloom)

	# 5. Dessin de la Tour et du Sorcier animé au centre (0, 0)
	_draw_wizard_tower(center, font)

	# 6. Dessin des Monstres vivants
	for m in monsters:
		_draw_monster(center, m, font)

	# 6b. Dessin des animations de mort des Monstres
	for dm in dying_monsters:
		_draw_dying_monster(center, dm, font)

	# 6c. Dessin des particules de traînée et des projectiles de sort en vol
	for pt in projectile_particles:
		var p_ratio: float = clampf(float(pt["timer"]) / float(pt["max_timer"]), 0.0, 1.0)
		var pc: Color = pt["color"]
		pc.a = p_ratio * 0.9
		draw_circle(pt["pos"], float(pt["size"]) * p_ratio, pc)

	for proj in active_projectiles:
		_draw_spell_projectile(proj)

	# 7. Dessin des textes flottants (dégâts, effets)
	for ft in floating_texts:
		var alpha: float = clampf(ft["timer"] / ft["max_timer"], 0.0, 1.0)
		var c: Color = ft["color"]
		c.a = alpha
		draw_string(font, ft["pos"] + Vector2(-45, 0), ft["text"], HORIZONTAL_ALIGNMENT_CENTER, 90, 14, c)

	# 8. Info-bulle du monstre survolé en bas du plateau
	for m in monsters:
		if m["hex"] == hovered_hex:
			_draw_monster_tooltip(m, font)
			break

func _tile_hash(hex: Vector2i, salt: int) -> int:
	var n: int = hex.x * 374761393 + hex.y * 668265263 + salt * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n ^ (n >> 16))

func _draw_grass_tile(center: Vector2, hex: Vector2i) -> void:
	var px: Vector2 = center + HexMath.hex_to_pixel(hex, HEX_SIZE)
	var dist: int = HexMath.distance(Vector2i.ZERO, hex)
	var outer_corners: PackedVector2Array = HexMath.get_hex_corners(px, HEX_SIZE - 1.2)
	var inner_corners: PackedVector2Array = HexMath.get_hex_corners(px, HEX_SIZE - 4.2)

	var h_val: int = _tile_hash(hex, 1)
	var shade_offset: float = float(h_val % 100) / 100.0 * 0.045 - 0.022

	var base_grass: Color
	var inner_grass: Color

	if hex == Vector2i.ZERO:
		# Sanctuaire verdoyant et dalles de pierre sous la Tour
		base_grass = Color(0.24, 0.46, 0.25)
		inner_grass = Color(0.32, 0.54, 0.30)
	elif dist == HexMath.BOARD_RADIUS:
		# Bordure d'apparition des monstres : herbes hautes sombres & lisière terreuse
		base_grass = Color(0.17 + shade_offset, 0.33 + shade_offset, 0.17)
		inner_grass = Color(0.21 + shade_offset, 0.39 + shade_offset, 0.20)
	elif (hex.x + hex.y * 2) % 2 == 0:
		# Prairie claire
		base_grass = Color(0.20 + shade_offset, 0.44 + shade_offset, 0.19)
		inner_grass = Color(0.25 + shade_offset, 0.52 + shade_offset, 0.23)
	else:
		# Prairie soutenue
		base_grass = Color(0.18 + shade_offset, 0.40 + shade_offset, 0.18)
		inner_grass = Color(0.22 + shade_offset, 0.48 + shade_offset, 0.21)

	if hex == hovered_hex:
		base_grass = base_grass.lightened(0.14)
		inner_grass = inner_grass.lightened(0.14)

	draw_colored_polygon(outer_corners, base_grass)
	draw_colored_polygon(inner_corners, inner_grass)

	# Dessin des touffes d'herbe (qui ondulent légèrement au vent) et petites fleurs sauvages
	if hex != Vector2i.ZERO:
		var tuft_count: int = 2 + (h_val % 3)
		var wind: float = sin(anim_time * 2.2 + float(hex.x) * 0.5 + float(hex.y) * 0.4) * 1.4
		for t_idx in range(tuft_count):
			var th: int = _tile_hash(hex, 10 + t_idx)
			var ang: float = float(th % 360) * (PI / 180.0)
			var rad: float = 3.0 + float((th >> 8) % 12)
			var t_pos: Vector2 = px + Vector2(cos(ang), sin(ang)) * rad
			var blade_col: Color = inner_grass.lightened(0.18) if (t_idx % 2 == 0) else base_grass.darkened(0.15)
			blade_col.a = 0.85

			# 3 brins d'herbe par touffe : \ | /
			draw_line(t_pos, t_pos + Vector2(-2.6 + wind * 0.7, -4.2), blade_col, 1.3)
			draw_line(t_pos, t_pos + Vector2(wind, -5.2), blade_col.lightened(0.08), 1.3)
			draw_line(t_pos, t_pos + Vector2(2.6 + wind * 0.7, -4.0), blade_col, 1.3)

		# Petite fleur sauvage occasionnelle sur certaines tuiles
		if (h_val % 5) == 0:
			var fh: int = _tile_hash(hex, 99)
			var f_ang: float = float(fh % 360) * (PI / 180.0)
			var f_pos: Vector2 = px + Vector2(cos(f_ang), sin(f_ang)) * 9.5
			var flower_col: Color = Color(1.0, 0.92, 0.35) if (fh % 2 == 0) else Color(0.95, 0.88, 1.0)
			draw_circle(f_pos, 1.8, flower_col)

	# Contour hexagonal herbeux (et contour runique sur la bordure d'apparition)
	var stroke_col := Color(0.13, 0.28, 0.13, 0.75)
	if dist == HexMath.BOARD_RADIUS:
		stroke_col = Color(0.46, 0.36, 0.26, 0.82)
	var closed_corners := outer_corners.duplicate()
	closed_corners.append(outer_corners[0])
	draw_polyline(closed_corners, stroke_col, 1.4, true)

func _draw_elemental_hex_effect(
	center: Vector2,
	hex: Vector2i,
	element: int,
	alpha: float,
	is_persistent: bool,
	bloom_scale: float = 1.0
) -> void:
	var px: Vector2 = center + HexMath.hex_to_pixel(hex, HEX_SIZE)
	var scaled_radius: float = (HEX_SIZE - 2.0) * bloom_scale
	var corners: PackedVector2Array = HexMath.get_hex_corners(px, scaled_radius)
	var base_col: Color = SpellData.get_element_color(element)

	# Fond hexagonal en transparence teinté selon l'élément
	var fill_col: Color = base_col
	fill_col.a = alpha * 0.55
	draw_colored_polygon(corners, fill_col)

	# Bordure lumineuse si l'effet reste 1 tour (persistant) ou lors de l'impact
	var closed := corners.duplicate()
	closed.append(corners[0])
	var border_col: Color = base_col.lightened(0.35)
	border_col.a = alpha * (0.95 if is_persistent else 0.80)
	draw_polyline(closed, border_col, 2.5 if is_persistent else 2.0, true)

	if bloom_scale < 0.5:
		return

	# Motifs élémentaires animés en transparence à l'intérieur de l'hexagone
	var phase: float = anim_time * 5.0 + float(hex.x * 7 + hex.y * 13)
	match element:
		SpellData.Element.FIRE:
			for i in range(3):
				var ang: float = phase + float(i) * (TAU / 3.0)
				var offset := Vector2(cos(ang) * 7.0, sin(ang * 1.3) * 5.0 - 2.0) * bloom_scale
				var flame_col := Color(1.0, 0.85, 0.25, alpha * 0.85)
				var f_pts := PackedVector2Array([
					px + offset + Vector2(0, -7) * bloom_scale,
					px + offset + Vector2(4, 3) * bloom_scale,
					px + offset + Vector2(-4, 3) * bloom_scale
				])
				draw_colored_polygon(f_pts, flame_col)
		SpellData.Element.ICE:
			var ice_col := Color(0.82, 0.96, 1.0, alpha * 0.88)
			for i in range(3):
				var a: float = float(i) * (PI / 3.0) + sin(phase * 0.4) * 0.15
				var dir := Vector2(cos(a), sin(a)) * 11.0 * bloom_scale
				draw_line(px - dir, px + dir, ice_col, 2.0)
			draw_arc(px, 5.5 * bloom_scale, 0, TAU, 6, ice_col, 1.6)
		SpellData.Element.POISON:
			for i in range(4):
				var p_off := Vector2(
					sin(phase * 0.7 + float(i) * 1.9) * 8.5,
					fmod(phase * 6.0 + float(i) * 6.0, 18.0) - 9.0
				) * bloom_scale
				var r: float = (2.5 + float(i % 2) * 1.5) * bloom_scale
				draw_circle(px + p_off, r, Color(0.75, 1.0, 0.35, alpha * 0.80))
				draw_arc(px + p_off, r, 0, TAU, 12, Color(0.95, 1.0, 0.75, alpha * 0.9), 1.0)
		SpellData.Element.EARTH:
			var rock_col := Color(0.92, 0.74, 0.45, alpha * 0.85)
			var spike1 := PackedVector2Array([
				px + Vector2(-8, 6) * bloom_scale,
				px + Vector2(-3, -7) * bloom_scale,
				px + Vector2(2, 6) * bloom_scale
			])
			var spike2 := PackedVector2Array([
				px + Vector2(0, 7) * bloom_scale,
				px + Vector2(6, -5) * bloom_scale,
				px + Vector2(10, 7) * bloom_scale
			])
			draw_colored_polygon(spike1, rock_col.darkened(0.2))
			draw_colored_polygon(spike2, rock_col)
			draw_arc(px, 11.0 * bloom_scale, 0, TAU, 6, Color(0.95, 0.82, 0.55, alpha * 0.65), 1.6)
		SpellData.Element.NEUTRAL, SpellData.Element.FALLBACK_WEAK:
			var neut_col := Color(0.90, 0.94, 1.0, alpha * 0.80)
			var r_wave: float = (5.0 + fmod(phase * 2.2, 9.0)) * bloom_scale
			draw_arc(px, r_wave, 0, TAU, 18, neut_col, 1.8)
			draw_circle(px, 3.0 * bloom_scale, neut_col)

func _draw_spell_projectile(proj: Dictionary) -> void:
	var pos: Vector2 = proj["current_px"]
	var el: int = int(proj["element"])
	var el_col: Color = SpellData.get_element_color(el)

	# Halo externe lumineux
	draw_circle(pos, 11.0, Color(el_col.r, el_col.g, el_col.b, 0.38))
	draw_circle(pos, 7.0, el_col.lightened(0.25))
	draw_circle(pos, 3.8, Color.WHITE)

	# Détail selon l'élément du projectile
	match el:
		SpellData.Element.ICE:
			for i in range(3):
				var a: float = anim_time * 10.0 + float(i) * (PI / 3.0)
				var d := Vector2(cos(a), sin(a)) * 9.5
				draw_line(pos - d, pos + d, Color(0.88, 0.98, 1.0), 1.8)
		SpellData.Element.EARTH:
			draw_arc(pos, 8.5, anim_time * 8.0, anim_time * 8.0 + TAU, 6, Color(0.95, 0.78, 0.45), 2.2)
		SpellData.Element.POISON:
			for i in range(3):
				var a: float = anim_time * 7.0 + float(i) * (TAU / 3.0)
				draw_circle(pos + Vector2(cos(a), sin(a)) * 6.5, 2.5, Color(0.8, 1.0, 0.35))

func _draw_wizard_tower(center: Vector2, font: Font) -> void:
	var is_casting: bool = wizard_cast_timer > 0.0
	var cast_ratio: float = clampf(wizard_cast_timer / wizard_cast_max_timer, 0.0, 1.0) if is_casting else 0.0
	var cast_el_col: Color = SpellData.get_element_color(wizard_cast_element)

	# Socle de pierre et halo magique au sol
	draw_circle(center + Vector2(0, 6), 18.0, Color(0.22, 0.24, 0.30, 0.85))
	draw_arc(center, 19.5, 0, TAU, 24, Color(0.85, 0.72, 1.0, 0.85), 2.0)

	# Cercle runique en expansion quand le Sorcier lance un sort
	if is_casting:
		var rune_radius: float = 18.0 + (1.0 - cast_ratio) * 20.0
		var rune_col: Color = cast_el_col.lightened(0.3)
		rune_col.a = cast_ratio
		draw_arc(center, rune_radius, 0, TAU, 28, rune_col, 2.8)
		for i in range(6):
			var r_ang: float = anim_time * 6.0 + float(i) * (TAU / 6.0)
			var p1: Vector2 = center + Vector2(cos(r_ang), sin(r_ang)) * (rune_radius - 5.0)
			var p2: Vector2 = center + Vector2(cos(r_ang), sin(r_ang)) * (rune_radius + 4.0)
			draw_line(p1, p2, rune_col, 2.2)

	# Sprite de la Tour
	var tower_tex: Texture2D = SpriteFactory.get_tower_texture()
	if tower_tex != null:
		var t_size := Vector2(36, 36)
		draw_texture_rect(tower_tex, Rect2(center - t_size * 0.5 + Vector2(0, 1), t_size), false)

	# Sprite du Sorcier au sommet de la Tour (avec saut et bras levés pendant l'incantation !)
	var wiz_tex: Texture2D = SpriteFactory.get_wizard_texture(is_casting)
	if wiz_tex != null:
		var idle_bob: float = sin(anim_time * 3.5) * 1.2
		var cast_jump: float = -sin(cast_ratio * PI) * 8.0 if is_casting else 0.0
		var w_scale: float = 1.0 + sin(cast_ratio * PI) * 0.18 if is_casting else 1.0
		var w_size: Vector2 = Vector2(28, 28) * w_scale
		var w_pos: Vector2 = center - w_size * 0.5 + Vector2(0, -10.0 + idle_bob + cast_jump)
		var w_mod: Color = Color(1.0, 0.96, 0.85) if is_casting else Color.WHITE
		draw_texture_rect(wiz_tex, Rect2(w_pos, w_size), false, w_mod)

		# Éclat magique au bout du bâton du Sorcier lors du lancement d'un sort
		if is_casting:
			var staff_tip: Vector2 = w_pos + Vector2(w_size.x * 0.85, w_size.y * 0.15)
			draw_circle(staff_tip, 7.5 * cast_ratio, Color(cast_el_col.r, cast_el_col.g, cast_el_col.b, 0.65))
			draw_circle(staff_tip, 4.0 * cast_ratio, Color.WHITE)

	draw_string(font, center + Vector2(-28, -28), "TOUR", HORIZONTAL_ALIGNMENT_CENTER, 56, 11, Color(0.95, 0.9, 1.0))
	var hp_str: String = "%d/%d" % [tower_hp, tower_max_hp]
	draw_string(font, center + Vector2(-30, 29), hp_str, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(0.4, 1.0, 0.55))

func _draw_monster(center: Vector2, m: Dictionary, font: Font) -> void:
	var px: Vector2 = center + HexMath.hex_to_pixel(m["hex"], HEX_SIZE)
	var radius: float = 15.5

	# Ombre au sol sous les pieds du monstre
	draw_circle(px + Vector2(0, 8), 11.0, Color(0, 0, 0, 0.45))

	# Couronne élémentaire au sol : Gauche = Faiblesse (x2), Droite = Résistance (x0.5)
	var weak_col: Color = SpellData.get_element_color(int(m["weakness"]))
	var res_col: Color = SpellData.get_element_color(int(m["resistance"]))
	draw_arc(px, radius, PI * 0.5, PI * 1.5, 14, weak_col, 3.0)
	draw_arc(px, radius, -PI * 0.5, PI * 0.5, 14, res_col, 2.0)

	# Sprite pixel-art animé (léger rebond idle)
	var archetype: int = int(m.get("archetype", int(m.get("id", 0)) % 4))
	var tex: Texture2D = SpriteFactory.get_monster_texture(archetype)
	var bob: float = sin(anim_time * 4.2 + float(m.get("id", 0)) * 1.3) * 1.8
	var sprite_size := Vector2(32, 32)
	var modulate_col := Color.WHITE
	if int(m.get("slow_turns", 0)) > 0:
		modulate_col = Color(0.75, 0.92, 1.0)
	elif int(m.get("poison_turns", 0)) > 0:
		modulate_col = Color(0.85, 1.0, 0.75)

	if tex != null:
		draw_texture_rect(tex, Rect2(px - sprite_size * 0.5 + Vector2(0, -3.0 + bob), sprite_size), false, modulate_col)

	# Barre de PV au-dessus du sprite + texte des PV
	var bar_w: float = 30.0
	var bar_h: float = 5.0
	var bar_pos: Vector2 = px + Vector2(-bar_w * 0.5, -23)
	var hp_ratio: float = clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.08, 0.08, 0.10, 0.92), true)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_ratio, bar_h)), Color(0.95, 0.28, 0.28), true)

	var hp_txt: String = str(m["hp"])
	draw_string(font, px + Vector2(-19, 10), hp_txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 12, Color(0, 0, 0, 0.9))
	draw_string(font, px + Vector2(-20, 9), hp_txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 12, Color.WHITE)

	# Badges Vitesse (en bas à gauche) et Dégâts (en bas à droite)
	var eff_speed: int = maxi(0, int(m["speed"]) - (1 if int(m.get("slow_turns", 0)) > 0 else 0))
	var spd_col: Color = Color(0.4, 0.85, 1.0) if int(m.get("slow_turns", 0)) > 0 else Color(0.95, 0.92, 0.45)
	draw_string(font, px + Vector2(-22, 19), "V%d" % eff_speed, HORIZONTAL_ALIGNMENT_LEFT, 24, 10, spd_col)
	draw_string(font, px + Vector2(2, 19), "A%d" % int(m["damage"]), HORIZONTAL_ALIGNMENT_RIGHT, 20, 10, Color(1.0, 0.65, 0.45))

	# Indicateurs d'états (Poison / Gel / Fragile)
	if int(m.get("poison_turns", 0)) > 0:
		draw_circle(px + Vector2(13, -13), 4.5, Color(0.55, 0.95, 0.2))
	if int(m.get("slow_turns", 0)) > 0:
		draw_circle(px + Vector2(-13, -13), 4.5, Color(0.25, 0.8, 1.0))
	if int(m.get("vulnerable_turns", 0)) > 0:
		draw_circle(px + Vector2(0, -25), 4.5, Color(1.0, 0.45, 0.9))

func _draw_dying_monster(center: Vector2, dm: Dictionary, font: Font) -> void:
	var px: Vector2 = center + HexMath.hex_to_pixel(dm["hex"], HEX_SIZE)
	var ratio_left: float = clampf(float(dm["timer"]) / float(dm["max_timer"]), 0.0, 1.0)
	var progress: float = 1.0 - ratio_left

	# Onde de choc au sol lors de la mort
	var shock_r: float = 8.0 + progress * 22.0
	var el_col: Color = SpellData.get_element_color(int(dm.get("element", SpellData.Element.NEUTRAL)))
	draw_arc(px, shock_r, 0, TAU, 18, Color(el_col.r, el_col.g, el_col.b, ratio_left * 0.85), 2.2)

	# Sprite du monstre qui tremble, flashe puis se dissout en rétrécissant
	var tex: Texture2D = SpriteFactory.get_monster_texture(int(dm["archetype"]))
	if tex != null:
		var shake_x: float = sin(progress * 45.0) * 5.0 * ratio_left
		var scale_f: float = clampf(1.15 - progress * 1.05, 0.05, 1.2)
		var s_size: Vector2 = Vector2(32, 32) * scale_f
		var lift_y: float = -progress * 12.0
		var mod_col := Color(1.0, 0.45, 0.35, ratio_left)
		if progress < 0.25:
			mod_col = Color(1.0, 1.0, 1.0, 1.0) # Flash blanc d'impact fatal
		draw_texture_rect(tex, Rect2(px - s_size * 0.5 + Vector2(shake_x, -3.0 + lift_y), s_size), false, mod_col)

	# Particules d'âme / éclats élémentaires projetés autour du monstre
	var parts: Array = dm["particles"]
	for p in parts:
		var p_col: Color = p["color"]
		p_col.a = ratio_left
		var p_sz: float = float(p["size"]) * ratio_left
		draw_circle(px + Vector2(p["pos"]), p_sz, p_col)

	# Petit crâne / âme qui s'élève au-dessus du monstre vaincu
	var skull_pos: Vector2 = px + Vector2(-16, -8.0 - progress * 24.0)
	draw_string(font, skull_pos, "💀", HORIZONTAL_ALIGNMENT_CENTER, 32, 14, Color(1.0, 1.0, 1.0, ratio_left))

func _draw_monster_tooltip(m: Dictionary, font: Font) -> void:
	var rect := Rect2(Vector2(16, size.y - 84), Vector2(size.x - 32, 70))
	draw_rect(rect, Color(0.08, 0.10, 0.15, 0.94), true)
	draw_rect(rect, Color(0.45, 0.52, 0.68), false, 2.0)

	var eff_speed: int = maxi(0, int(m["speed"]) - (1 if int(m.get("slow_turns", 0)) > 0 else 0))
	var line1: String = "%s  |  PV: %d/%d  |  Vitesse: %d case(s)/tour  |  Dégâts Tour: %d  |  Distance: %d" % [
		m["name"], m["hp"], m["max_hp"], eff_speed, m["damage"], HexMath.distance(Vector2i.ZERO, m["hex"])
	]
	var weak_name: String = SpellData.get_element_name(int(m["weakness"]))
	var res_name: String = SpellData.get_element_name(int(m["resistance"]))
	var status_parts: Array[String] = []
	if int(m.get("poison_turns", 0)) > 0:
		status_parts.append("Poison (%d tours)" % int(m["poison_turns"]))
	if int(m.get("slow_turns", 0)) > 0:
		status_parts.append("Gelé (-1 Vit, %d tours)" % int(m["slow_turns"]))
	if int(m.get("vulnerable_turns", 0)) > 0:
		status_parts.append("Fragile (+50%% DG, %d tours)" % int(m["vulnerable_turns"]))
	var status_str: String = "  |  États: " + ", ".join(status_parts) if status_parts.size() > 0 else ""
	var line2: String = "Faiblesse (x2 dégâts): %s   |   Résistance (x0.5 dégâts): %s%s" % [weak_name, res_name, status_str]

	draw_string(font, rect.position + Vector2(14, 26), line1, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28, 14, Color.WHITE)
	draw_string(font, rect.position + Vector2(14, 50), line2, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28, 13, Color(0.85, 0.90, 1.0))
