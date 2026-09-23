extends RouteSegment
class_name ChicaneSegment
## Two offset concrete blocks force a left-then-right weave -- tests the
## Balance trap and general handling under lateral movement.


func _init() -> void:
	length = 40.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	_box("ChicaneLeft", Vector3(4.4, 0.8, 1.0), Vector3(-3.8, 0.4, -length * 0.35), CONCRETE, true)
	_box("ChicaneLeftWarning", Vector3(4.44, 0.24, 1.02), Vector3(-3.8, 0.61, -length * 0.35), WARNING)
	_box("ChicaneRight", Vector3(4.4, 0.8, 1.0), Vector3(3.8, 0.4, -length * 0.65), CONCRETE, true)
	_box("ChicaneRightWarning", Vector3(4.44, 0.24, 1.02), Vector3(3.8, 0.61, -length * 0.65), WARNING)
