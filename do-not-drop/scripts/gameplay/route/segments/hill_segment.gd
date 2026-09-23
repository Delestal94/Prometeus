extends RouteSegment
class_name HillSegment
## A crest the road climbs over and drops down from (docs/tareas-nacho.md
## #56): hard on a Peso Creciente box, and the far side is hidden until
## you're on top. The height itself lives in the route's terrain (route.gd
## registers this stretch as a crest in route_terrain.gd), so road, ground,
## collision and dressing all follow it with no special cases. Built alone
## (endless mode, tests) it's a plain straight.

## Metres the road rises at the top of the crest.
@export var crest_height: float = 6.0


func _init() -> void:
	length = 70.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	# No passing on a blind crest: a solid centre line over the top third.
	for index: int in range(10):
		var z: float = -length * 0.33 - float(index) * (length * 0.34 / 10.0)
		_box("CrestCentreLine", Vector3(0.14, 0.02, length * 0.034), Vector3(0.0, 0.03, z), WARNING)
