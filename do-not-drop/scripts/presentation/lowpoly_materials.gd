extends RefCounted
class_name LowpolyMaterials
## Take My Package's palette on top of the render_budget module's
## DetailMaterials (docs/modulos.md): which authored material gets which
## detail map, the barn's lifted red, the autumn tints, what glows at night.
## The mechanism (triplanar detail copies, seasonal tint, emissive twins,
## caches) lives in the module; this file is only the game's tables and the
## same static API every caller already uses.
##
## Every authored GLB names its materials after the palette entry that made
## them in Blender ("wood", "roof", "leaf", ... -- see assets/tools/
## lowpoly_kit.py and build_lowpoly_glb_assets.py).

const DETAIL_DIR: String = "res://assets/textures/detail/tx_detail_%s_512.png"
## Detail maps average ~0.86 (art/tools/make_detail_textures.py); this puts
## the average colour back where the palette had it.
const DETAIL_GAIN: float = 1.16
## palette material -> [detail map, metres per repeat]
const DETAIL: Dictionary = {
	"wood": ["wood_planks", 1.4],
	"barn_red": ["wood_planks", 1.8],
	"wall": ["plaster", 2.4],
	"plaster": ["plaster", 2.4],
	"roof": ["roof_shingles", 1.4],
	"roof_blue": ["roof_shingles", 1.4],
	"chimney": ["stone", 1.2],
	"stone": ["stone", 1.6],
	"concrete": ["stone", 2.2],
	"portal_stone": ["stone", 1.3],
	"portal_trim": ["stone", 0.9],
	"tunnel_soot": ["stone", 1.6],
	"trunk": ["bark", 1.1],
	"birch": ["bark", 1.1],
	"leaf": ["foliage", 0.9],
	"leaf_dark": ["foliage", 0.9],
	"leaf_light": ["foliage", 0.9],
	"fern": ["foliage", 1.0],
	"grass": ["grass", 1.0],
	"hay": ["grass", 0.8],
}

## Palette entries lifted before the detail goes on: palette entry -> the
## colour it takes instead. The barn's red (linear 0.42, 0.06, 0.04) reflects
## almost nothing but red, and the light that reaches a wall turned from the
## sun is cold -- sky ambient by day, blue moonlight and ambient by night -- so
## that wall went black (N-318.2: 0.04 mean on its backlit wall at night).
## Same hue, more green and blue in it: it still reads barn red in the sun.
const LIFTED: Dictionary = {
	"barn_red": Color(0.72, 0.36, 0.29),
}

## Foliage by season (N-305, WorldMood.Season): palette entry -> [autumn
## colour, how far toward it]. Summer keeps the palette as authored. Each
## green lands on its own ochre, so a tree's light and dark leaves still
## read apart; grass only dries a little (it's everywhere, and a whole
## orange landscape reads as fire, not autumn).
const AUTUMN: Dictionary = {
	"leaf": [Color(0.78, 0.42, 0.14), 0.78],
	"leaf_dark": [Color(0.55, 0.22, 0.1), 0.72],
	"leaf_light": [Color(0.92, 0.66, 0.2), 0.8],
	"fern": [Color(0.62, 0.42, 0.18), 0.6],
	"grass": [Color(0.62, 0.55, 0.28), 0.45],
}

## Models that keep their green all year: a conifer's needles don't turn
## (matched against the model's file name; they share the broadleaf trees'
## leaf palette, so it can't go by material).
const EVERGREEN: Array[String] = ["pine"]

## What glows after dark (N-304): palette entry -> [light colour, emission
## energy at full night]. Only where light_up() is asked to -- a car's
## "window" is glass, a house's "window" is a lit room.
const NIGHT_GLOW: Dictionary = {
	"lamp_glass": [Color(1.0, 0.8, 0.52), 3.2],
	"lamp": [Color(1.0, 0.9, 0.72), 2.2],
	"window": [Color(1.0, 0.72, 0.38), 1.3],
}

## The session's season and how dark it is live in DetailMaterials
## (`season`, `night_level`): WorldMood.pick() sets them before anything is
## dressed. configure() runs at startup (GameSettings) so the module knows
## the palette before the first model is dressed.
static var _configured: bool = false


## Hands the game's tables to the module once, before its first use.
static func configure() -> void:
	if _configured:
		return
	_configured = true
	DetailMaterials.detail_dir = DETAIL_DIR
	DetailMaterials.detail_gain = DETAIL_GAIN
	DetailMaterials.detail = DETAIL
	DetailMaterials.lifted = LIFTED
	DetailMaterials.autumn = AUTUMN
	DetailMaterials.evergreen_words = EVERGREEN
	DetailMaterials.night_glow = NIGHT_GLOW


static func set_season(value: int) -> void:
	configure()
	DetailMaterials.set_season(value)


static func set_night_level(value: float) -> void:
	configure()
	DetailMaterials.set_night_level(value)


## Switches on the NIGHT_GLOW `keys` under `root` for the current night_level.
static func light_up(root: Node, keys: Array) -> int:
	configure()
	return DetailMaterials.light_up(root, keys)


## The palette colour this season: summer as authored, autumn per AUTUMN.
static func seasonal_color(key: String, color: Color, evergreen: bool = false) -> Color:
	configure()
	return DetailMaterials.seasonal_color(key, color, evergreen)


## Re-dresses every mesh under `root` in place. Safe to call more than once.
static func apply(root: Node) -> void:
	configure()
	DetailMaterials.apply(root)


## Whether the model at `path` keeps its green in autumn (EVERGREEN).
static func is_evergreen(path: String) -> bool:
	configure()
	return DetailMaterials.is_evergreen(path)


## The detailed twin of a palette material, or null when it has no detail
## entry (glass, paint, signs -- those stay flat on purpose).
static func textured_for(source: BaseMaterial3D, vertex_colour: bool = false,
		evergreen: bool = false) -> BaseMaterial3D:
	configure()
	return DetailMaterials.textured_for(source, vertex_colour, evergreen)
