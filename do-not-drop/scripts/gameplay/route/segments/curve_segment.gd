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
const EDGE_LINE_OFFSET: float = 5.7
const EDGE_LINE_WIDTH: float = 0.12
const EDGE_LINE_HEIGHT: float = 0.03
## 2 m steps: the terrain's own grid spacing, so the warped line hugs it.
const EDGE_LINE_STEPS: int = 5

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
	for side: float in [-1.0, 1.0]:
		_build_edge_line(side * EDGE_LINE_OFFSET, cursor)


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
	if not continuous_terrain:
		var ground := _chord_box(Vector3(24.0, 1.0, CHORD_LENGTH + 3.0), Vector3(0.0, -0.8, -CHORD_LENGTH * 0.5), SHOULDER, true)
		chord.add_child(ground)
		var road := _chord_box(Vector3(12.0, 0.4, CHORD_LENGTH + 3.0), Vector3(0.0, -0.2, -CHORD_LENGTH * 0.5), ROAD, true)
		chord.add_child(road)


## One unbroken painted line along the whole bend, `offset` metres off the
## centreline. A straight stick per chord (the old way) left a gap and a
## visible kink at every pivot; here the line's corners are mitred -- pushed
## out along the bisector by 1/cos(half the kink) -- so neighbouring pieces
## meet exactly, and each chord is cut into short steps so the line can
## follow the terrain once conform_geometry() warps it.
func _build_edge_line(offset: float, exit: Transform3D) -> void:
	var frames: Array[Transform3D] = _chord_transforms.duplicate()
	frames.append(exit)
	var corners: Array[Vector3] = []
	for index: int in range(frames.size()):
		var right: Vector3 = frames[index].basis.x
		var miter: float = 1.0
		# The exit mitres too: the last chord points one turn step short of
		# the exit heading the next segment continues along.
		if index > 0:
			right = (frames[index - 1].basis.x + frames[index].basis.x).normalized()
			miter = 1.0 / maxf(right.dot(frames[index].basis.x), 0.5)
		corners.append(right * miter)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	var half_width: float = EDGE_LINE_WIDTH * 0.5
	for index: int in range(frames.size() - 1):
		var a: Vector3 = frames[index].origin
		var b: Vector3 = frames[index + 1].origin
		for step: int in range(EDGE_LINE_STEPS):
			var t0: float = float(step) / float(EDGE_LINE_STEPS)
			var t1: float = float(step + 1) / float(EDGE_LINE_STEPS)
			var left0: Vector3 = a.lerp(b, t0) + corners[index].lerp(corners[index + 1], t0) * (offset - half_width)
			var right0: Vector3 = a.lerp(b, t0) + corners[index].lerp(corners[index + 1], t0) * (offset + half_width)
			var left1: Vector3 = a.lerp(b, t1) + corners[index].lerp(corners[index + 1], t1) * (offset - half_width)
			var right1: Vector3 = a.lerp(b, t1) + corners[index].lerp(corners[index + 1], t1) * (offset + half_width)
			# Clockwise seen from above (Godot's front face), travelling -Z.
			for vertex: Vector3 in [left0, left1, right0, right0, left1, right1]:
				surface.add_vertex(vertex + Vector3(0.0, EDGE_LINE_HEIGHT, 0.0))
	# The mitred exit corner sits a little off the square-across point where
	# the next segment's own line starts: short of it on the inside of the
	# bend (bridge that gap), past it on the outside (this quad then faces
	# away and is culled -- the line already covers that stretch).
	var last: Vector3 = corners[corners.size() - 1]
	var tail: Array[Vector3] = [
		exit.origin + last * (offset - half_width), exit.origin + exit.basis.x * (offset - half_width),
		exit.origin + last * (offset + half_width), exit.origin + exit.basis.x * (offset + half_width),
	]
	for vertex: Vector3 in [tail[0], tail[1], tail[2], tail[2], tail[1], tail[3]]:
		surface.add_vertex(vertex + Vector3(0.0, EDGE_LINE_HEIGHT, 0.0))
	var line := MeshInstance3D.new()
	line.name = "EdgeLine"
	line.mesh = surface.commit()
	line.material_override = _material(MARKING)
	add_child(line)


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
