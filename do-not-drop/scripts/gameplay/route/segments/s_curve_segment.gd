extends RouteSegment
class_name SCurveSegment
## A longer double weave than ChicaneSegment's single left-right: four
## alternating blocks instead of two, so the correction the driver just made
## immediately demands the opposite one, back and forth -- more sustained
## lateral pressure than a single chicane, closer to a real S-curve than a
## single dodge.


func _init() -> void:
	length = 60.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	var offsets: Array[float] = [0.18, 0.39, 0.61, 0.82]
	for index: int in range(offsets.size()):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var z: float = -length * offsets[index]
		var name_suffix: String = str(index)
		_box("SCurveBlock" + name_suffix, Vector3(4.4, 0.8, 1.0), Vector3(side * 3.8, 0.4, z), CONCRETE, true)
		_box("SCurveWarning" + name_suffix, Vector3(4.4, 0.24, 1.02), Vector3(side * 3.8, 0.61, z), WARNING)
