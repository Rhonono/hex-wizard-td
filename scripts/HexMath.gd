class_name HexMath
extends RefCounted

## Rayon d'un plateau hexagonal de côté 7 tuiles :
## Côté N = 7 => Rayon R = N - 1 = 6 (centre = (0,0), bordure à distance 6, total = 127 tuiles)
const BOARD_SIDE: int = 7
const BOARD_RADIUS: int = BOARD_SIDE - 1 # 6

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1)
]

## Distance hexagonale entre deux coordonnées axiales (q, r)
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (abs(dq) + abs(dq + dr) + abs(dr)) / 2

## Vérifie si une tuile (q, r) est dans le plateau hexagonal de côté 7
static func is_in_board(hex: Vector2i) -> bool:
	return distance(Vector2i.ZERO, hex) <= BOARD_RADIUS

## Génère toutes les 127 tuiles du plateau hexagonal de côté 7
static func get_all_board_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for q in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var r1: int = max(-BOARD_RADIUS, -q - BOARD_RADIUS)
		var r2: int = min(BOARD_RADIUS, -q + BOARD_RADIUS)
		for r in range(r1, r2 + 1):
			tiles.append(Vector2i(q, r))
	return tiles

## Génère toutes les tuiles en bordure du plateau (distance == 6, soit 36 tuiles)
static func get_border_tiles() -> Array[Vector2i]:
	var border: Array[Vector2i] = []
	for tile in get_all_board_tiles():
		if distance(Vector2i.ZERO, tile) == BOARD_RADIUS:
			border.append(tile)
	return border

## Rotation d'un vecteur axial (q, r) par pas de 60° dans le sens horaire autour de (0, 0)
static func rotate_60(hex: Vector2i, steps: int) -> Vector2i:
	var n: int = ((steps % 6) + 6) % 6
	var q: int = hex.x
	var r: int = hex.y
	var s: int = -q - r
	for _i in range(n):
		var new_q: int = -r
		var new_r: int = -s
		var new_s: int = -q
		q = new_q
		r = new_r
		s = new_s
	return Vector2i(q, r)

## Transforme une forme locale (liste de Vector2i avec origine (0,0)) sur une cible et une rotation (0..5)
static func get_transformed_shape(local_offsets: Array[Vector2i], origin_hex: Vector2i, rotation_steps: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in local_offsets:
		var rotated: Vector2i = rotate_60(offset, rotation_steps)
		result.append(origin_hex + rotated)
	return result

## Conversion Axial (q, r) -> Pixel 2D (orientation Pointy-Top)
static func hex_to_pixel(hex: Vector2i, hex_size: float) -> Vector2:
	var x: float = hex_size * sqrt(3.0) * (float(hex.x) + float(hex.y) * 0.5)
	var y: float = hex_size * (1.5 * float(hex.y))
	return Vector2(x, y)

## Conversion Pixel 2D -> Axial (q, r) le plus proche
static func pixel_to_hex(pixel: Vector2, hex_size: float) -> Vector2i:
	var q: float = (sqrt(3.0) / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / hex_size
	var r: float = (2.0 / 3.0 * pixel.y) / hex_size
	return axial_round(Vector2(q, r))

static func axial_round(frac: Vector2) -> Vector2i:
	var q: float = frac.x
	var r: float = frac.y
	var s: float = -q - r
	var rq: int = roundi(q)
	var rr: int = roundi(r)
	var rs: int = roundi(s)
	var q_diff: float = abs(float(rq) - q)
	var r_diff: float = abs(float(rr) - r)
	var s_diff: float = abs(float(rs) - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(rq, rr)

## Retourne les sommets d'un hexagone Pointy-Top pour le dessin
static func get_hex_corners(center: Vector2, hex_size: float) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for i in range(6):
		var angle_deg: float = 60.0 * float(i) - 30.0
		var angle_rad: float = deg_to_rad(angle_deg)
		corners.append(center + Vector2(cos(angle_rad), sin(angle_rad)) * hex_size)
	return corners

## Trouve la prochaine case vers la tour (0,0) en évitant si possible les cases occupées
static func get_step_toward_center(from_hex: Vector2i, occupied: Dictionary, hex_size: float = 1.0) -> Vector2i:
	if from_hex == Vector2i.ZERO:
		return Vector2i.ZERO
	var current_dist: int = distance(from_hex, Vector2i.ZERO)
	var best_hex: Vector2i = from_hex
	var best_euclidean: float = INF
	var from_px: Vector2 = hex_to_pixel(from_hex, hex_size)

	# Cherche d'abord une case libre qui réduit la distance hexagonale à la tour
	for dir in DIRECTIONS:
		var neighbor: Vector2i = from_hex + dir
		if neighbor == Vector2i.ZERO:
			return Vector2i.ZERO
		if distance(neighbor, Vector2i.ZERO) < current_dist and not occupied.has(neighbor):
			var eucl: float = hex_to_pixel(neighbor, hex_size).length_squared()
			# Favorise le chemin le plus droit vers (0,0)
			if eucl < best_euclidean:
				best_euclidean = eucl
				best_hex = neighbor

	# Si toutes les cases plus proches sont occupées, reste sur place
	return best_hex

## Trouve une case pour repousser un monstre d'une case vers l'extérieur (effet Terre)
static func get_knockback_hex(from_hex: Vector2i, occupied: Dictionary) -> Vector2i:
	var current_dist: int = distance(from_hex, Vector2i.ZERO)
	if current_dist >= BOARD_RADIUS:
		return from_hex
	var best_hex: Vector2i = from_hex
	var best_dot: float = -INF
	var dir_from_center: Vector2 = hex_to_pixel(from_hex, 1.0).normalized()

	for dir in DIRECTIONS:
		var neighbor: Vector2i = from_hex + dir
		if is_in_board(neighbor) and distance(neighbor, Vector2i.ZERO) > current_dist and not occupied.has(neighbor):
			var step_vec: Vector2 = (hex_to_pixel(neighbor, 1.0) - hex_to_pixel(from_hex, 1.0)).normalized()
			var dot: float = step_vec.dot(dir_from_center)
			if dot > best_dot:
				best_dot = dot
				best_hex = neighbor
	return best_hex
