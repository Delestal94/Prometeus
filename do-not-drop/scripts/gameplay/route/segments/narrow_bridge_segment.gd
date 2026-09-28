extends RouteSegment
class_name NarrowBridgeSegment
## A narrow deck with guard rails -- punishes drifting sideways, the
## opposite pressure from the chicane.
##
## Imported art since N-132 (assets/tools/build_route_pieces.py): deck
## modules, posts and the river under it. The collision is still the boxes
## this script always built, hidden.
##
## On the main route (continuous terrain, route.gd) the ground itself is
## carved into a riverbed under this span (route_terrain.gd's `rivers`,
## registered by route.gd next to this segment) instead of staying flat like
## every other segment's stretch of ground -- so unlike them, this deck (and
## the authored water/bank model, and the rails/posts) needs to float over a
## real drop rather than sink into it with the rest of the terrain. Every
## node this segment builds gets flagged &"ignore_river" (on the segment
## root; route_terrain.conform_geometry() carries the flag down to every
## child) so they all measure their height against the ground as if the
## river weren't there, same as it would be with no river at all.


const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const RAILING_MODEL := "res://assets/models/environment/props/sm_env_prop_bridge_railing.glb"
const MODELS: String = "res://assets/models/environment/route/"
const DECK_MODEL: String = MODELS + "sm_env_route_bridge_deck.glb"
const POST_MODEL: String = MODELS + "sm_env_route_bridge_post.glb"
const WATER_MODEL: String = MODELS + "sm_env_route_bridge_water.glb"
## How long one deck module and the river are authored.
const MODULE_LENGTH: float = 4.0
const WATER_LENGTH: float = 36.0
## How far the riverbed drops below the deck on the main route -- route.gd
## reads this to register the span with route_terrain.gd's `rivers`. Close
## to the authored water model's own depth (level -1.6, banks resting at
## -1.85) so the carved ground and the authored banks roughly agree.
@export var river_depth: float = 1.8
## Half the river's flat-bottomed width at full depth -- route.gd passes this
## on as the registered river's "full_width". Roughly half the span's own
## length (a river reads as wide as the crossing it forces), so the deck
## comfortably clears real water on both sides instead of just its edges.
@export var river_width: float = 18.0
## How far out from the centreline the riverbed is still fading back up to
## the ambient ground before it's lost in the landscape -- route.gd's
## "bank_width" ceiling. It shrinks this on its own if the river would
## otherwise run into another stretch of road, a house or the depot yard
## (see route.gd's _clamp_river_reach()).
@export var river_reach: float = 60.0


func _init() -> void:
	length = 36.0


func _build() -> void:
	if continuous_terrain:
		set_meta(&"ignore_river", true)
	_hide_box_visual(_box("BridgeDeck", Vector3(6.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true))
	var modules: int = maxi(1, roundi(length / MODULE_LENGTH))
	var module_length: float = length / float(modules)
	for index: int in range(modules):
		var deck: Node3D = _art("BridgeDeckModule", DECK_MODEL, Vector3(0.0, 0.0,
				-module_length * (float(index) + 0.5)))
		if deck != null:
			deck.scale.z = module_length / MODULE_LENGTH
	for side: float in [-1.0, 1.0]:
		var rail_collision := _box("BridgeGuardRailCollision", Vector3(0.25, 0.75, length), Vector3(side * 3.05, 0.7, -length * 0.5), CONCRETE, true)
		_hide_box_visual(rail_collision)
		# The authored railing repeats in short sections so it follows the
		# narrow deck and is readable from both the cab and the road below.
		for z: float in [-3.0, -9.0, -15.0, -21.0, -27.0, -33.0]:
			# The source railing is authored across local X. A quarter turn lays
			# it along the bridge instead of cutting through the driving lane.
			_model("BridgeRailing", RAILING_MODEL, Vector3(side * 3.05, 0.0, z), PI * 0.5)
		for z: int in range(-2, -int(length), -4):
			_hide_box_visual(_box("BridgePost", Vector3(0.3, 1.08, 0.3), Vector3(side * 3.05, 0.54, float(z)),
					Color("5d6b6c"), true))
			_art("BridgePostModel", POST_MODEL, Vector3(side * 3.05, 0.0, float(z)))
	# The river: water, banks, abutments and piers, stretched to the span.
	# Off the main route (endless, tests) this model's own flat "Water" plane
	# is the only sign of a river at all. On the main route the ground itself
	# is carved into a much wider, organic riverbed and route_terrain.gd
	# builds its own matching water mesh over it (route.gd registers this
	# same span with `rivers`) -- so this model's own water plane, sized and
	# edged for a 30 m-wide rectangle, would show through as a hard-edged
	# pool on top of it. Hide just that one surface; the banks, abutments,
	# piers, rocks and ripples right around the bridge stay for the detail.
	var water: Node3D = _art("BridgeWater", WATER_MODEL, Vector3(0.0, 0.0, -length * 0.5))
	if water != null:
		water.scale.z = length / WATER_LENGTH
		if continuous_terrain:
			var flat_water: Node = water.find_child("Water", true, false)
			if flat_water is VisualInstance3D:
				(flat_water as VisualInstance3D).visible = false
	_build_river_sound()


## Water running under the span (playtest polish 2026-09-27, docs/tareas-nacho.md
## #178 warns against repeating the depot's old zumbido): a normal positioned
## 3D loop at the water, not a wall-to-wall drone -- loud right over it,
## faded out well before the next segment (unit_size 6, well under the
## typical distance to it, so it never gets the depot's old near-field
## over-boost). Always on the Exterior bus: the river doesn't care whether
## the truck's own cabin is open or closed, it's outside either way.
func _build_river_sound() -> void:
	var river := AudioStreamPlayer3D.new()
	river.name = "RiverFlow"
	river.stream = SynthAudio.river_flow_loop()
	river.bus = &"Exterior"
	river.volume_db = WorldMix.RIVER_DB
	river.unit_size = 6.0
	river.max_distance = 45.0
	river.autoplay = true
	# Roughly at the water's surface: below the deck on a carved riverbed,
	# level with it on the flat test water model otherwise.
	var water_y: float = -river_depth * 0.5 if continuous_terrain else -0.3
	river.position = Vector3(0.0, water_y, -length * 0.5)
	add_child(river)
