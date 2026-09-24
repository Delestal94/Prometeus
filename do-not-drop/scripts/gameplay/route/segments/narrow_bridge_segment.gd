extends RouteSegment
class_name NarrowBridgeSegment
## A narrow deck with guard rails -- punishes drifting sideways, the
## opposite pressure from the chicane.


func _init() -> void:
	length = 36.0


func _build() -> void:
	_box("BridgeDeck", Vector3(6.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	for side: float in [-1.0, 1.0]:
		var rail_collision := _box("BridgeGuardRailCollision", Vector3(0.25, 0.75, length), Vector3(side * 3.05, 0.7, -length * 0.5), CONCRETE, true)
		_hide_box_visual(rail_collision)
		# The authored railing repeats in short sections so it follows the
		# narrow deck and is readable from both the cab and the road below.
		for z: float in [-3.0, -9.0, -15.0, -21.0, -27.0, -33.0]:
			_model("BridgeRailing", RAILING_MODEL, Vector3(side * 3.05, 0.0, z), 0.0 if side < 0.0 else PI)
		for z: int in range(-2, -int(length), -4):
			_box("BridgePost", Vector3(0.3, 1.08, 0.3), Vector3(side * 3.05, 0.54, float(z)), Color("5d6b6c"), true)
	_box("WaterPlaceholder", Vector3(30.0, 0.025, length), Vector3(0.0, -0.27, -length * 0.5), Color("4d7d80"))
const RAILING_MODEL := "res://assets/models/environment/props/sm_env_prop_bridge_railing.glb"
