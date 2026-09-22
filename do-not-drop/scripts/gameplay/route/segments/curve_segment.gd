extends RouteSegment
class_name CurveSegment
## A road that actually bends the route's heading, not just an obstacle
## course on a straight lane (every other segment type is that). Built as a
## chain of short straight chords, each one turned a little more than the
## last -- same trick as approximating an arc with a polyline -- so it can
## reuse the same box-building helpers as every other segment instead of
## needing curved geometry/collision. `exit_offset`/`exit_turn` (declared on
## RouteSegment) are computed here to the *exact* endpoint of that polyline,
## so whatever chains this segment (RouteStreamer, or route.gd's procedural
## spine) can place the next piece with no gap or twist, regardless of how
## sharp the turn is.
##
## `turn_deg` is signed: positive turns right, negative turns left (yaw
## around +Y, matching Godot's Basis(Vector3.UP, angle) convention).

@export var turn_deg: float = 45.0
## Roughly one chord per 12° keeps each kink subtle at the low-poly scale
## the rest of the game already uses; sharper turns get more chords instead
## of fewer, longer (harsher-kinked) ones.
const DEGREES_PER_CHORD: float = 12.0
const CHORD_LENGTH: float = 10.0
const MIN_CHORDS: int = 3

## Each chord's own local transform (pre-advance cursor), for
## get_dressing_slots() below -- dressing needs to walk the same bent path
## the road actually takes, not a straight-line guess from this segment's
## own origin.
var _chord_transforms: Array[Transform3D] = []


func _init() -> void:
	# Overwritten precisely in _build() below once the real chord count is
	# known -- this is just a reasonable default for anything that reads
	# .length before _ready() runs (RouteStreamer's culling math, mainly).
	length = CHORD_LENGTH * 5.0


func _build() -> void:
	var chord_count: int = maxi(MIN_CHORDS, roundi(absf(turn_deg) / DEGREES_PER_CHORD))
	var turn_per_chord: float = deg_to_rad(turn_deg) / float(chord_count)
	length = CHORD_LENGTH * float(chord_count)

	# Walk a local cursor through the chords, same Transform3D-composition
	# pattern the outer chain uses on this segment as a whole -- a curve is
	# just a chain of tiny straight segments one level down.
	var cursor := Transform3D.IDENTITY
	_chord_transforms.clear()
	for index: int in range(chord_count):
		var chord := Node3D.new()
		chord.name = "Chord%d" % index
		chord.transform = cursor
		add_child(chord)
		_build_chord(chord)
		_chord_transforms.append(cursor)
		cursor = cursor * Transform3D(Basis(Vector3.UP, turn_per_chord), Vector3(0.0, 0.0, -CHORD_LENGTH))

	exit_offset = cursor.origin
	exit_turn = turn_per_chord * float(chord_count)


func get_dressing_slots(spacing: float) -> Array[Transform3D]:
	var slots: Array[Transform3D] = []
	for chord_transform: Transform3D in _chord_transforms:
		var z: float = 0.0
		while z > -CHORD_LENGTH:
			slots.append(chord_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z)))
			z -= spacing
	return slots


func _build_chord(chord: Node3D) -> void:
	# +3m (1.5m past each end) so adjacent chords overlap through the pivot
	# instead of leaving a wedge-shaped gap at the kink -- two rotated
	# rectangles sharing only a single edge point don't tile cleanly, and a
	# gap in the *collision* there is a real "wheel drops through" risk, not
	# just a visual seam.
	var ground := _chord_box(Vector3(24.0, 1.0, CHORD_LENGTH + 3.0), Vector3(0.0, -0.8, -CHORD_LENGTH * 0.5), SHOULDER, true)
	chord.add_child(ground)
	var road := _chord_box(Vector3(12.0, 0.4, CHORD_LENGTH + 3.0), Vector3(0.0, -0.2, -CHORD_LENGTH * 0.5), ROAD, true)
	chord.add_child(road)
	var edge_marking := _chord_box(Vector3(0.12, 0.015, CHORD_LENGTH - 1.0), Vector3(5.7, 0.011, -CHORD_LENGTH * 0.5), MARKING)
	chord.add_child(edge_marking)
	var edge_marking_other := _chord_box(Vector3(0.12, 0.015, CHORD_LENGTH - 1.0), Vector3(-5.7, 0.011, -CHORD_LENGTH * 0.5), MARKING)
	chord.add_child(edge_marking_other)


## Same shape as RouteSegment._box(), but returns the node instead of
## add_child()-ing it directly to `self` -- each chord needs its own boxes
## parented under ITS transform, not the CurveSegment's local origin.
func _chord_box(size: Vector3, location: Vector3, color: Color, solid: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.position = location
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	root.add_child(mesh)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 6
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)
	return root
