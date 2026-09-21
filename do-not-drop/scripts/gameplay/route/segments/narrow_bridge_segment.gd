extends RouteSegment
class_name NarrowBridgeSegment
## A narrow deck with guard rails -- punishes drifting sideways, the
## opposite pressure from the chicane.


func _init() -> void:
	length = 36.0


func _build() -> void:
	_box("BridgeDeck", Vector3(6.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	for side: float in [-1.0, 1.0]:
		_box("BridgeGuardRail", Vector3(0.25, 0.75, length), Vector3(side * 3.05, 0.7, -length * 0.5), CONCRETE, true)
		_box("BridgeRailTop", Vector3(0.29, 0.12, length), Vector3(side * 3.05, 1.15, -length * 0.5), WARNING)
		for z: int in range(-2, -int(length), -4):
			_box("BridgePost", Vector3(0.35, 1.2, 0.35), Vector3(side * 3.05, 0.6, float(z)), Color("5d6b6c"), true)
	_box("WaterPlaceholder", Vector3(30.0, 0.025, length), Vector3(0.0, -0.27, -length * 0.5), Color("4d7d80"))
