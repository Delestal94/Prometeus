extends RouteSegment
class_name NarrowBridgeSegment
## A narrow deck with guard rails -- punishes drifting sideways, the
## opposite pressure from the chicane.
##
## Imported art since N-132 (assets/tools/build_route_pieces.py): deck
## modules, posts and the river under it. The collision is still the boxes
## this script always built, hidden. On the main route (continuous terrain)
## the deck and the river are left out, as the deck and water boxes were.

const RAILING_MODEL := "res://assets/models/environment/props/sm_env_prop_bridge_railing.glb"
const MODELS: String = "res://assets/models/environment/route/"
const DECK_MODEL: String = MODELS + "sm_env_route_bridge_deck.glb"
const POST_MODEL: String = MODELS + "sm_env_route_bridge_post.glb"
const WATER_MODEL: String = MODELS + "sm_env_route_bridge_water.glb"
## How long one deck module and the river are authored.
const MODULE_LENGTH: float = 4.0
const WATER_LENGTH: float = 36.0


func _init() -> void:
	length = 36.0


func _build() -> void:
	_hide_box_visual(_box("BridgeDeck", Vector3(6.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true))
	if not continuous_terrain:
		var modules: int = maxi(1, roundi(length / MODULE_LENGTH))
		var module_length: float = length / float(modules)
		for index: int in range(modules):
			var deck: Node3D = _art("BridgeDeckModule", DECK_MODEL, Vector3(0.0, 0.0, -module_length * (float(index) + 0.5)))
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
			_hide_box_visual(_box("BridgePost", Vector3(0.3, 1.08, 0.3), Vector3(side * 3.05, 0.54, float(z)), Color("5d6b6c"), true))
			_art("BridgePostModel", POST_MODEL, Vector3(side * 3.05, 0.0, float(z)))
	# The river: water, banks, abutments and piers, stretched to the span.
	if not continuous_terrain:
		var water: Node3D = _art("BridgeWater", WATER_MODEL, Vector3(0.0, 0.0, -length * 0.5))
		if water != null:
			water.scale.z = length / WATER_LENGTH
