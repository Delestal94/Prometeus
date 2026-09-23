extends RouteSegment
class_name StraightSegment
## Plain road, no hazard -- the "breather" segment between curated pieces.


func _init() -> void:
	length = 30.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	for z: int in range(-2, -int(length), -6):
		for side: float in [-1.0, 1.0]:
			_box("EdgeMarking", Vector3(0.12, 0.015, 4.0), Vector3(side * 5.7, 0.03, float(z)), MARKING)
		_box("CenterMarking", Vector3(0.12, 0.012, 2.0), Vector3(0.0, 0.028, float(z)), Color("8c9994"))
