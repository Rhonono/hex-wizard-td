class_name SpellData
extends RefCounted

enum CompCategory {
	ELEMENT = 0,
	SHAPE = 1,
	BONUS = 2
}

enum Element {
	# Éléments puissants (0..3)
	FIRE = 0,
	ICE = 1,
	POISON = 2,
	EARTH = 3,
	# Élément faible de départ (4)
	NEUTRAL = 4,
	# Élément par défaut si la carte n'a pas de composant Élément (5 dégâts)
	FALLBACK_WEAK = 5
}

enum Shape {
	# Formes puissantes de 7 hexagones (0..3)
	LINE = 0,
	HEX = 1,
	TRIANGLE = 2,
	ZIGZAG = 3,
	# Formes faibles de 3 hexagones (4..6)
	SMALL_LINE = 4,
	SMALL_V = 5,
	SMALL_TRIANGLE = 6,
	# Forme par défaut si la carte n'a pas de composant Gabarit (1 hexagone)
	SINGLE_HEX = 7
}

enum BonusType {
	# Bonus puissants (0..6)
	DAMAGE_BOOST = 0,   # Dégâts +25%
	DRAW_CARD = 1,      # Piocher 1 carte
	EXPAND_SIZE = 2,    # Agrandissement du gabarit (+3 hexagones)
	KNOCKBACK = 3,      # Repousse l'ennemi (2 cases)
	LEECH = 4,          # Soigne la tour (+2 PV / ennemi touché)
	VULNERABLE = 5,     # Fragilise (+50% dégâts subis pendant 2 tours)
	LINGER = 6,         # Reste 1 tour de plus sur le plateau
	# Bonus faibles de départ (7..10)
	WEAK_EXPAND_1 = 7,  # +1 Hexa en contact aléatoire
	WEAK_DAMAGE_10 = 8, # +10% Dégâts
	BUY_MARKET_CARD = 9,# Acheter 1 carte du marché
	GAIN_1_GOLD = 10,   # +1 Pièce d'Or
	# Bonus par défaut si la carte n'a pas de composant Bonus (aucun effet)
	NONE = 11
}

## Données d'une carte bi-composant séparée par une diagonale
class CardItem extends RefCounted:
	var uid: int
	var comp1_cat: int
	var comp1_val: int
	var comp2_cat: int
	var comp2_val: int

	func _init(p_uid: int, c1_cat: int, c1_val: int, c2_cat: int, c2_val: int) -> void:
		uid = p_uid
		comp1_cat = c1_cat
		comp1_val = c1_val
		comp2_cat = c2_cat
		comp2_val = c2_val

	func has_category(cat: int) -> bool:
		return comp1_cat == cat or comp2_cat == cat

	func get_value_for_category(cat: int) -> int:
		if comp1_cat == cat:
			return comp1_val
		if comp2_cat == cat:
			return comp2_val
		# Valeur diminuée par défaut si la carte ne possède pas ce type de composant
		match cat:
			CompCategory.ELEMENT:
				return Element.FALLBACK_WEAK
			CompCategory.SHAPE:
				return Shape.SINGLE_HEX
			CompCategory.BONUS:
				return BonusType.NONE
		return -1

	func get_other_category(active_cat: int) -> int:
		if comp1_cat == active_cat:
			return comp2_cat
		return comp1_cat

	func get_other_value(active_cat: int) -> int:
		if comp1_cat == active_cat:
			return comp2_val
		return comp1_val

	func duplicate_card(new_uid: int) -> CardItem:
		return CardItem.new(new_uid, comp1_cat, comp1_val, comp2_cat, comp2_val)


## Indique si un composant est considéré comme "Puissant" (Marché) ou "Faible" (Départ)
static func is_component_strong(cat: int, val: int) -> bool:
	match cat:
		CompCategory.ELEMENT:
			return val in [Element.FIRE, Element.ICE, Element.POISON, Element.EARTH]
		CompCategory.SHAPE:
			return val in [Shape.LINE, Shape.HEX, Shape.TRIANGLE, Shape.ZIGZAG]
		CompCategory.BONUS:
			return val in [
				BonusType.DAMAGE_BOOST,
				BonusType.DRAW_CARD,
				BonusType.EXPAND_SIZE,
				BonusType.KNOCKBACK,
				BonusType.LEECH,
				BonusType.VULNERABLE,
				BonusType.LINGER
			]
	return false

## Nombre de composants puissants sur une carte (0, 1 ou 2)
static func get_card_strong_count(card: CardItem) -> int:
	var c: int = 0
	if is_component_strong(card.comp1_cat, card.comp1_val):
		c += 1
	if is_component_strong(card.comp2_cat, card.comp2_val):
		c += 1
	return c

## Prix de la carte au marché : 1 composant puissant = 3 Or, 2 composants puissants = 8 Or
static func get_card_market_cost(card: CardItem) -> int:
	var strong_cnt: int = get_card_strong_count(card)
	if strong_cnt >= 2:
		return 8
	elif strong_cnt == 1:
		return 3
	return 1

static func get_element_name(el: int) -> String:
	match el:
		Element.FIRE: return "Feu"
		Element.ICE: return "Glace"
		Element.POISON: return "Poison"
		Element.EARTH: return "Terre"
		Element.NEUTRAL: return "Neutre"
		Element.FALLBACK_WEAK: return "Sans Élém."
	return "?"

static func get_element_desc(el: int) -> String:
	match el:
		Element.FIRE: return "18 Dégâts directs"
		Element.ICE: return "11 Dégâts + Gel (-1 Vit. 2t)"
		Element.POISON: return "9 Dégâts + 7 Poison/tour (3t)"
		Element.EARTH: return "13 Dégâts + Repousse (1 case)"
		Element.NEUTRAL: return "11 Dégâts neutres (sans bonus/malus ni effet)"
		Element.FALLBACK_WEAK: return "5 Dégâts (carte sans composant Élément)"
	return ""

static func get_element_base_damage(el: int) -> int:
	match el:
		Element.FIRE: return 18
		Element.ICE: return 11
		Element.POISON: return 9
		Element.EARTH: return 13
		Element.NEUTRAL: return 11
		Element.FALLBACK_WEAK: return 5
	return 5

static func get_element_color(el: int) -> Color:
	match el:
		Element.FIRE: return Color(0.95, 0.32, 0.18)
		Element.ICE: return Color(0.22, 0.72, 0.96)
		Element.POISON: return Color(0.58, 0.86, 0.22)
		Element.EARTH: return Color(0.76, 0.54, 0.28)
		Element.NEUTRAL: return Color(0.66, 0.70, 0.78)
		Element.FALLBACK_WEAK: return Color(0.50, 0.53, 0.60)
	return Color.WHITE

static func get_shape_name(sh: int) -> String:
	match sh:
		Shape.LINE: return "Ligne (7)"
		Shape.HEX: return "Hexagone (7)"
		Shape.TRIANGLE: return "Triangle+1 (7)"
		Shape.ZIGZAG: return "Zigzag (7)"
		Shape.SMALL_LINE: return "Ligne (3)"
		Shape.SMALL_V: return "Forme V (3)"
		Shape.SMALL_TRIANGLE: return "Triangle (3)"
		Shape.SINGLE_HEX: return "1 Hexa (Défaut)"
	return "?"

static func get_shape_desc(sh: int) -> String:
	match sh:
		Shape.LINE: return "Ligne de 7 tuiles (Origine: bout)"
		Shape.HEX: return "Hexagone côté 2 (Origine: centre)"
		Shape.TRIANGLE: return "Triangle côté 3 + sommet (Origine: pointe)"
		Shape.ZIGZAG: return "Zigzag de 7 tuiles (Origine: bout)"
		Shape.SMALL_LINE: return "Petite ligne de 3 tuiles"
		Shape.SMALL_V: return "Petit V de 3 tuiles (Origine: pointe)"
		Shape.SMALL_TRIANGLE: return "Petit triangle de 3 tuiles"
		Shape.SINGLE_HEX: return "1 seul hexagone (carte sans composant Forme)"
	return ""

## Retourne les tuiles de chaque forme en coordonnées axiales locales où (0,0) est l'origine.
## Si expand_size est actif (Bonus puissant "Gabarit +3"), ajoute +3 hexagones au gabarit !
static func get_shape_offsets(sh: int, expand_size: bool = false) -> Array[Vector2i]:
	if not expand_size:
		match sh:
			Shape.LINE:
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
					Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)
				]
			Shape.HEX:
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
					Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
				]
			Shape.TRIANGLE:
				return [
					Vector2i(0, 0), Vector2i(1, 0),
					Vector2i(2, 0), Vector2i(1, 1),
					Vector2i(3, 0), Vector2i(2, 1), Vector2i(1, 2)
				]
			Shape.ZIGZAG:
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1),
					Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)
				]
			Shape.SMALL_LINE:
				# Hexagone d'origine (0,0) connecté sur ses faces 1 (1,0) et 4 (-1,0) => ligne centrée (180°)
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)
				]
			Shape.SMALL_V:
				# Hexagone d'origine (0,0) connecté sur ses faces 1 (1,0) et 3 (0,-1) => vrai V à 120°
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)
				]
			Shape.SMALL_TRIANGLE:
				# Hexagone d'origine (0,0) connecté sur ses faces 1 (1,0) et 2 (1,-1) => triangle compact (60°)
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1)
				]
			Shape.SINGLE_HEX:
				return [
					Vector2i(0, 0)
				]
	else:
		# Gabarit agrandi de +3 hexagones
		match sh:
			Shape.LINE:
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
					Vector2i(7, 0), Vector2i(6, 1), Vector2i(7, -1)
				]
			Shape.HEX:
				return [
					Vector2i(0, 0),
					Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
					Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
					Vector2i(2, -1), Vector2i(-1, 2), Vector2i(-1, -1)
				]
			Shape.TRIANGLE:
				return [
					Vector2i(0, 0), Vector2i(1, 0),
					Vector2i(2, 0), Vector2i(1, 1),
					Vector2i(3, 0), Vector2i(2, 1), Vector2i(1, 2),
					Vector2i(4, 0), Vector2i(3, 1), Vector2i(2, 2)
				]
			Shape.ZIGZAG:
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3),
					Vector2i(4, 3), Vector2i(4, 4), Vector2i(5, 4)
				]
			Shape.SMALL_LINE:
				# Ligne centrée (faces 1 et 4) agrandie de +3 = 6 hexagones alignés
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0),
					Vector2i(2, 0), Vector2i(-2, 0), Vector2i(3, 0)
				]
			Shape.SMALL_V:
				# V à 120° (faces 1 et 3) agrandi de +3 = branches de longueur 2 + bissectrice
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1),
					Vector2i(2, 0), Vector2i(0, -2), Vector2i(1, -1)
				]
			Shape.SMALL_TRIANGLE:
				# Triangle de 3 + 3 = 6 hexagones
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1),
					Vector2i(2, 0), Vector2i(2, -1), Vector2i(2, -2)
				]
			Shape.SINGLE_HEX:
				# 1 + 3 = 4 hexagones
				return [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1)
				]
	return [Vector2i.ZERO]

## Tire 1 offset local aléatoire en contact direct avec les offsets locaux de la forme (pour l'afficher dès l'aperçu)
static func pick_random_contact_local_offset(base_offsets: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for h in base_offsets:
		for dir in HexMath.DIRECTIONS:
			var n: Vector2i = h + dir
			if not base_offsets.has(n) and not candidates.has(n):
				candidates.append(n)
	if candidates.is_empty():
		return Vector2i.ZERO
	return candidates[rng.randi_range(0, candidates.size() - 1)]

## Ajoute N hexagones aléatoires en contact direct avec le gabarit existant
static func add_random_contact_hexes(base_hexes: Array[Vector2i], count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var result: Array[Vector2i] = base_hexes.duplicate()
	for _i in range(count):
		var candidates: Array[Vector2i] = []
		for h in result:
			for dir in HexMath.DIRECTIONS:
				var n: Vector2i = h + dir
				if HexMath.is_in_board(n) and not result.has(n) and not candidates.has(n):
					candidates.append(n)
		if candidates.is_empty():
			break
		var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		result.append(pick)
	return result

static func get_bonus_name(bn: int) -> String:
	match bn:
		BonusType.DAMAGE_BOOST: return "Dégâts +25%"
		BonusType.DRAW_CARD: return "Piocher +1"
		BonusType.EXPAND_SIZE: return "Gabarit +3 Hex"
		BonusType.KNOCKBACK: return "Repousse +2"
		BonusType.LEECH: return "Soin Tour"
		BonusType.VULNERABLE: return "Fragilise"
		BonusType.LINGER: return "Reste 1 Tour"
		BonusType.WEAK_EXPAND_1: return "+1 Hex Aléa."
		BonusType.WEAK_DAMAGE_10: return "Dégâts +10%"
		BonusType.BUY_MARKET_CARD: return "Acheter Carte"
		BonusType.GAIN_1_GOLD: return "+1 Pièce d'Or"
		BonusType.NONE: return "Aucun Bonus"
	return "?"

static func get_bonus_short_badge(bn: int) -> String:
	match bn:
		BonusType.DAMAGE_BOOST: return "+25%"
		BonusType.DRAW_CARD: return "+1🃏"
		BonusType.EXPAND_SIZE: return "+3⬡"
		BonusType.KNOCKBACK: return ">>"
		BonusType.LEECH: return "+PV"
		BonusType.VULNERABLE: return "BRK"
		BonusType.LINGER: return "1T"
		BonusType.WEAK_EXPAND_1: return "+1⬡"
		BonusType.WEAK_DAMAGE_10: return "+10%"
		BonusType.BUY_MARKET_CARD: return "🛒"
		BonusType.GAIN_1_GOLD: return "+1💰"
		BonusType.NONE: return "—"
	return "+"

static func get_bonus_desc(bn: int) -> String:
	match bn:
		BonusType.DAMAGE_BOOST: return "Augmente les dégâts du sort de +25%"
		BonusType.DRAW_CARD: return "Pioche immédiatement 1 carte supplémentaire"
		BonusType.EXPAND_SIZE: return "Agrandit le gabarit de la forme de +3 hexagones"
		BonusType.KNOCKBACK: return "Repousse tous les ennemis touchés de 2 cases"
		BonusType.LEECH: return "Rend +2 PV à la Tour par ennemi touché"
		BonusType.VULNERABLE: return "Fragilise les cibles (+50% dégâts subis pendant 2 tours)"
		BonusType.LINGER: return "L'effet élémentaire reste sur les hexagones pendant 1 tour de plus"
		BonusType.WEAK_EXPAND_1: return "Ajoute +1 hexagone aléatoire en contact avec le gabarit"
		BonusType.WEAK_DAMAGE_10: return "Augmente les dégâts du sort de +10%"
		BonusType.BUY_MARKET_CARD: return "Permet d'acheter 1 carte du Marché avec votre Or (va en défausse)"
		BonusType.GAIN_1_GOLD: return "Gagne immédiatement +1 Pièce d'Or lors du lancement du sort"
		BonusType.NONE: return "Aucun effet bonus (carte sans composant Bonus)"
	return ""

static func get_category_name(cat: int) -> String:
	match cat:
		CompCategory.ELEMENT: return "1. ÉLÉMENT"
		CompCategory.SHAPE: return "2. FORME"
		CompCategory.BONUS: return "3. BONUS"
	return ""

static func get_component_title(cat: int, val: int) -> String:
	match cat:
		CompCategory.ELEMENT: return get_element_name(val)
		CompCategory.SHAPE: return get_shape_name(val)
		CompCategory.BONUS: return get_bonus_name(val)
	return "?"

static func get_component_bg_color(cat: int, val: int) -> Color:
	var strong: bool = is_component_strong(cat, val)
	match cat:
		CompCategory.ELEMENT:
			if val == Element.FALLBACK_WEAK:
				return Color(0.22, 0.23, 0.27)
			return get_element_color(val).darkened(0.22 if strong else 0.42)
		CompCategory.SHAPE:
			if val == Shape.SINGLE_HEX:
				return Color(0.20, 0.22, 0.26)
			return Color(0.22, 0.29, 0.48) if strong else Color(0.18, 0.21, 0.30)
		CompCategory.BONUS:
			if val == BonusType.NONE:
				return Color(0.22, 0.20, 0.24)
			return Color(0.46, 0.24, 0.48) if strong else Color(0.28, 0.22, 0.32)
	return Color(0.2, 0.2, 0.2)
