class_name ShedExteriorPlan
extends RefCounted
## What the outside of the shed looks like at each stage (expansion D-0936, "Modo Empresa").
##
## Four variants, one per stage: a sign over the dock wall and a paved yard (playón) in front of the
## dock. Both grow with the stage so the player sees the company grow before walking in. Pure data
## over the stage index and the floor width: ShedExterior draws it, and two peers with the same
## stage draw the same outside (no RPC, no random roll). The sign text is a translation key.

## Per stage: sign size (m, width x height), the sign's and the yard's model (sm_env_shed_sign_<model>,
## sm_env_shed_yard_<model>, assets/tools/build_depot_props.py), where the name goes on the sign's face (m: x from
## its centre, y up from its base: the part each model leaves free), yard depth (m, from the dock wall), yard colour
## and detail map, and lamp posts along the dock wall.
const VARIANTS: Array[Dictionary] = [
	{"sign": Vector2(4.0, 0.9), "model": "small", "text": Rect2(-1.15, 0.16, 3.0, 0.68), "yard": 2.5,
		"yard_color": Color(0.46, 0.43, 0.38), "detail": "concrete", "lamps": 0,
		"key": &"WORLD_SHED_SIGN_SMALL"},
	{"sign": Vector2(6.0, 1.2), "model": "medium", "text": Rect2(-2.0, 0.58, 4.8, 0.56), "yard": 4.5,
		"yard_color": Color(0.42, 0.41, 0.40), "detail": "concrete", "lamps": 2,
		"key": &"WORLD_SHED_SIGN_MEDIUM"},
	{"sign": Vector2(8.0, 1.6), "model": "large", "text": Rect2(-2.48, 0.52, 6.2, 0.96), "yard": 6.5,
		"yard_color": Color(0.36, 0.36, 0.38), "detail": "asphalt", "lamps": 4,
		"key": &"WORLD_SHED_SIGN_LARGE"},
	{"sign": Vector2(11.0, 2.0), "model": "logistics", "text": Rect2(-3.1, 0.62, 8.2, 0.96), "yard": 8.5,
		"yard_color": Color(0.30, 0.30, 0.33), "detail": "asphalt", "lamps": 6,
		"key": &"WORLD_SHED_SIGN_LOGISTICS"},
]


static func variant_count() -> int:
	return VARIANTS.size()


## The variant of `stage` (clamped to the stages that exist).
static func variant(stage: int) -> Dictionary:
	return VARIANTS[clampi(stage, 0, VARIANTS.size() - 1)]


## Sign size in metres: never wider than the wall it hangs on.
static func sign_size(stage: int, floor_width_m: float) -> Vector2:
	var size: Vector2 = variant(stage)["sign"]
	return Vector2(minf(size.x, floor_width_m), size.y)


## Yard depth in metres from the dock wall.
static func yard_depth(stage: int) -> float:
	return float(variant(stage)["yard"])


## X positions (m from the shed's centre) of the lamp posts along the dock wall, in pairs on both
## sides of the dock gate: none within LAMP_CLEAR of the centre line, where the supplier truck backs in.
const LAMP_CLEAR: float = 3.5


static func lamp_xs(stage: int, floor_width_m: float) -> Array[float]:
	var per_side: int = int(variant(stage)["lamps"]) / 2
	var xs: Array[float] = []
	var span: float = maxf(floor_width_m * 0.5 - LAMP_CLEAR, 0.0)
	for i: int in per_side:
		var x: float = LAMP_CLEAR + (float(i) + 0.5) / float(per_side) * span
		xs.append(-x)
		xs.append(x)
	return xs
