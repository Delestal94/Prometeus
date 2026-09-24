extends SceneTree
## Run WITHOUT --headless:
##   Godot --path do-not-drop --script res://tests/render_player_character.gd
## Visual check of the rounded player character (sm_char_player_rounded.glb)
## as teammates see it: standing next to the truck in several crew colours,
## seated as driver (hands on the wheel via SkeletonIK3D) and in the cargo-bay
## seats, plus mid-clip Jump / PickUpPackage frames.
## Saves user://player_character_*.png and prints:
## - "SURVEY" lines: for every seat anchor, the cushion right under it.
## - "MEASURE" lines: the seated bodies' skinned vertices (CPU-skinned from the
##   live pose, IK included) tested against every truck mesh (trimesh on a
##   private physics layer, ray-parity inside test), grouped by dominant bone
##   with the deepest penetration; headroom, butt-over-cushion, seat-local
##   extents, the driver's shoulder-to-grip reach vs arm length, and "try
##   seat_offset" rows scoring small deltas around player.gd's own
##   _seat_body_offset() (read live, never hardcoded here).
## - "PROPOSAL" + player_character_proposed_*.png: only when PREVIEW_DELTAS
##   is filled in: those seats re-rendered at current offset + delta
##   (players frozen, BodyVisual moved by hand; player.gd is not touched).
## Players get multiplayer authority 2..4 (offline the local id is 1), so their
## bodies render on the WORLD layer like any teammate's.

const SEAT_PROBE_LAYER: int = 1 << 19
## Seat name -> delta on top of player.gd's current offset, rendered as
## player_character_proposed_*.png. Empty: no preview pass.
const PREVIEW_DELTAS: Dictionary = {}
## Deltas (up, back) scored by the "try" rows, relative to the current offset.
const TRY_DELTAS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(-0.03, 0.0), Vector2(0.0, -0.03), Vector2(0.0, 0.03)]

var _level: Node3D
var _van: VehicleBody3D
var _camera: Camera3D
var _players: Array[Node3D] = []
var _probe_bodies: Dictionary = {}  # RID -> mesh name
var _probe_meshes: Dictionary = {}  # RID -> MeshInstance3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	_level.get_node("HUD").hide()
	_van = _level.vehicle
	_van.set_physics_process(false)
	_van.get_node("VehicleInputComponent").set_physics_process(false)
	_van.steering = 0.0
	_van.get_node("VehiclePresentation").audio_enabled = false
	for i: int in range(20):
		await physics_frame
	for child in _level.get_node("World").get_children():
		if child.is_in_group(&"player"):
			child.hide()
			child.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = Camera3D.new()
	_level.add_child(_camera)
	_camera.fov = 55.0
	_camera.near = 0.03
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# --- 1. Standing crew beside the driver's door, one walking. -----------
	var standing_spots: Array[Vector3] = [Vector3(-2.0, 0, -1.9), Vector3(-2.3, 0, -0.9), Vector3(-2.0, 0, 0.2)]
	for i: int in range(3):
		var player := _spawn_player(i + 2, _ground(_van.to_global(standing_spots[i])))
		player.look_at(_van.to_global(Vector3(-6.0, 0, -0.8)), Vector3.UP)
		player.rotation.x = 0.0
		player.rotation.z = 0.0
	_players[1].set(&"anim_state", &"Walk")
	for i: int in range(40):
		await physics_frame
	_aim(Vector3(-6.2, 1.55, -0.6), Vector3(-2.1, 1.0, -0.9))
	await _save("standing_crew")
	_aim(Vector3(-4.2, 1.6, -3.6), Vector3(-2.1, 1.0, -0.9))
	await _save("standing_crew_three_quarter")
	# Close front view of the walking one: shirt/shorts seams and skinning.
	_aim(Vector3(-3.7, 1.1, -0.6), Vector3(-2.3, 0.6, -0.9))
	await _save("standing_closeup")

	# --- 4. Jump / PickUpPackage mid-clip (before boarding). ---------------
	_players[0].set(&"anim_state", &"Jump")
	_players[2].set(&"anim_state", &"PickUpPackage")
	_players[1].set(&"anim_state", &"Idle")
	for i: int in range(3):
		await process_frame
	_freeze_clip(_players[0], 0.55)
	_freeze_clip(_players[2], 0.8)
	for i: int in range(10):
		await process_frame
	_aim(Vector3(-6.2, 1.4, -0.6), Vector3(-2.1, 0.9, -0.9))
	await _save("jump_pickup_midclip")
	for player: Node3D in _players:
		var anim: AnimationPlayer = player.get(&"_anim_player")
		anim.speed_scale = 1.0
		player.set(&"anim_state", &"Idle")

	# --- 2/3. Seated: driver, a wall seat and a rack seat. ------------------
	_van.set_door_open(&"cab_left", true)
	_van.set_door_open(&"rear", true)
	var seats: Array[NodePath] = [^"CabinInterior/DriverEyePoint", ^"CargoBay/LeftSeat1EyePoint", ^"CargoBay/RackSeat1EyePoint",
		^"CargoBay/RightSeat1EyePoint", ^"CargoBay/CenterSeatEyePoint", ^"CargoBay/LeftSeat3EyePoint"]
	for peer: int in [5, 6, 7]:
		_spawn_player(peer, _van.to_global(Vector3(0.0, 1.0, 1.0)))
	for i: int in range(seats.size()):
		var seat: Node3D = _van.get_node(seats[i])
		_players[i].call(&"board_seat", seat.get_node(^"FirstPersonCamera").get_path(), seat.get_path())
	for i: int in range(40):
		await physics_frame
	_camera.make_current()
	for i: int in range(3):
		await process_frame
	_build_seat_probes()
	await physics_frame
	_survey_seats()
	for i: int in range(seats.size()):
		await _measure(_players[i], _van.get_node(seats[i]))

	# Driver from outside, through the open driver's door.
	_aim(Vector3(-2.4, 1.55, -1.0), Vector3(-0.5, 1.0, -1.45))
	await _save("driver_through_door")
	# Driver from the side at seat height (door frame edge), to judge the belly/wheel gap.
	_aim(Vector3(-1.45, 1.1, -1.35), Vector3(-0.5, 0.95, -1.55))
	await _save("driver_side_closeup")
	# Driver from the passenger side of the cab, looking across.
	_aim(Vector3(0.45, 1.35, -1.1), Vector3(-0.5, 1.0, -1.6))
	await _save("driver_from_passenger_seat")
	# Driver through the windscreen.
	_aim(Vector3(-0.4, 1.6, -4.2), Vector3(-0.5, 1.1, -1.5))
	await _save("driver_through_windscreen")
	# Cargo-bay seats, from the open rear doors and from inside the bay.
	_aim(Vector3(0.0, 1.7, 5.2), Vector3(-0.1, 0.9, 1.9))
	await _save("bay_from_rear_doors")
	_aim(Vector3(0.45, 1.45, 3.0), Vector3(-0.68, 0.8, 1.43))
	await _save("wall_seat_closeup")
	# Left wall seat 1 from across the aisle, at knee height.
	_aim(Vector3(0.35, 1.0, 1.95), Vector3(-0.68, 0.7, 1.43))
	await _save("left_seat_side")
	# Right wall seat 1 from across the aisle.
	_aim(Vector3(-0.4, 1.2, 1.7), Vector3(0.68, 0.7, 1.1))
	await _save("right_seat_side")
	_aim(Vector3(-0.45, 1.45, 3.3), Vector3(0.74, 0.8, 2.3))
	await _save("rack_seat_closeup")
	# Front wall seats (CenterSeat, LeftSeat3) from across the aisle.
	_aim(Vector3(0.25, 1.55, 2.0), Vector3(-0.68, 0.8, 0.1))
	await _save("front_left_seats_side")
	# The bulkhead behind the cab, from the cab side: CenterSeat is against it.
	_aim(Vector3(0.3, 1.55, -1.45), Vector3(-0.7, 1.0, -0.35))
	await _save("bulkhead_from_cab")
	# Driver's shorts/legs from the passenger footwell, low.
	_aim(Vector3(0.2, 0.9, -1.75), Vector3(-0.5, 0.75, -1.5))
	await _save("driver_lap_closeup")

	# --- Optional preview of candidate offsets (render-only). ---------------
	# PREVIEW_DELTAS maps a seat name to a delta added to what player.gd's
	# _seat_body_offset() returns now. The players stop processing so
	# _pose_seated_body() doesn't undo it; BodyVisual keeps animating (and
	# the driver's IK keeps solving).
	if not PREVIEW_DELTAS.is_empty():
		for i: int in range(seats.size()):
			var seat: Node3D = _van.get_node(seats[i])
			if not PREVIEW_DELTAS.has(String(seat.name)):
				continue
			var offset: Vector3 = _current_offset(_players[i], seat) + PREVIEW_DELTAS[String(seat.name)]
			var body: Node3D = _players[i].get_node(^"BodyVisual")
			_players[i].process_mode = Node.PROCESS_MODE_DISABLED
			body.process_mode = Node.PROCESS_MODE_ALWAYS
			var lean: float = body.rotation.x
			body.global_transform = seat.global_transform.translated_local(offset)
			body.rotation.x = lean
			print("PROPOSAL %s at %s: seat_offset %s" % [_players[i].name, seat.name, offset])
		for i: int in range(10):
			await physics_frame
		_aim(Vector3(-2.4, 1.55, -1.0), Vector3(-0.5, 1.0, -1.45))
		await _save("proposed_driver_through_door")
		_aim(Vector3(0.0, 1.7, 5.2), Vector3(-0.1, 0.9, 1.9))
		await _save("proposed_bay_from_rear_doors")
		_aim(Vector3(0.35, 1.0, 1.95), Vector3(-0.68, 0.7, 1.43))
		await _save("proposed_left_seat_side")
		_aim(Vector3(-0.45, 1.45, 3.3), Vector3(0.74, 0.8, 2.3))
		await _save("proposed_rack_seat_closeup")

	_level.free()
	await process_frame
	quit(0)


## The offset player.gd itself uses for this seat, so every row below stays
## relative to the live code.
func _current_offset(player: Node3D, seat: Node3D) -> Vector3:
	return player.call(&"_seat_body_offset", seat.name)


func _spawn_player(peer: int, at: Vector3) -> Node3D:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % peer
	player.position = at
	_level.add_child(player)
	player.set(&"net_position", at)
	_players.append(player)
	return player


func _ground(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 5.0, point + Vector3.DOWN * 10.0, 1)
	var hit: Dictionary = _level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else point


func _freeze_clip(player: Node3D, at_seconds: float) -> void:
	var anim: AnimationPlayer = player.get(&"_anim_player")
	anim.seek(at_seconds, true)
	anim.speed_scale = 0.0


## Camera position and target given in the van's own space.
func _aim(local_from: Vector3, local_to: Vector3) -> void:
	_camera.global_position = _van.to_global(local_from)
	_camera.look_at(_van.to_global(local_to), _van.global_basis.y)


func _save(label: String) -> void:
	for i: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var output: String = "user://player_character_%s.png" % label
	if root.get_texture().get_image().save_png(output) != OK:
		push_error("Screenshot failed: %s" % output)
		return
	print("RENDER: ", ProjectSettings.globalize_path(output))


## Every mesh of the truck model becomes a static trimesh (back faces on) on
## a private physics layer, for the rays and inside tests below.
func _build_seat_probes() -> void:
	for mesh_instance: MeshInstance3D in _find_meshes(_van):
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var body := StaticBody3D.new()
		body.collision_layer = SEAT_PROBE_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh_instance.mesh.create_trimesh_shape()
		if shape.shape == null:
			continue
		(shape.shape as ConcavePolygonShape3D).backface_collision = true
		body.add_child(shape)
		_level.add_child(body)
		body.global_transform = mesh_instance.global_transform
		# Procedural props have auto names (@MeshInstance3D@123): add the parent
		# and mesh type so the report says what they are.
		var label := String(mesh_instance.name)
		if label.begins_with("@"):
			label = "%s/%s" % [mesh_instance.get_parent().name, mesh_instance.mesh.get_class()]
		_probe_bodies[body.get_rid()] = label
		_probe_meshes[body.get_rid()] = mesh_instance


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_find_meshes(child))
	return out


func _measure(player: Node3D, seat: Node3D) -> void:
	var body: Node3D = player.get_node(^"BodyVisual")
	var skeleton := _find_skeleton(body)
	var mesh_instance := _find_skinned_mesh(body)
	var verts: Array = []  # [world position, dominant bone name]
	var capture := func() -> void:
		if verts.is_empty():
			verts.append_array(_skinned_vertices(skeleton, mesh_instance))
	skeleton.skeleton_updated.connect(capture)
	for i: int in range(3):
		await process_frame
	skeleton.skeleton_updated.disconnect(capture)
	var space := _level.get_world_3d().direct_space_state
	# Inside test: a vertex is inside a closed mesh if rays toward +Y and -Y
	# both hit that same mesh's back faces first. Depth: shortest of six axis
	# rays from the vertex to that mesh's surface.
	var report: Dictionary = {}  # "mesh|bone" -> [count, max depth]
	for entry: Array in verts:
		var p: Vector3 = entry[0]
		var inside := _inside_mesh(space, p)
		if inside.is_empty():
			continue
		var key: String = "%s|%s" % [inside.mesh, entry[1]]
		var depth: float = inside.depth
		if not report.has(key):
			report[key] = [0, 0.0]
		report[key][0] += 1
		report[key][1] = maxf(report[key][1], depth)
	var aabb := AABB(verts[0][0], Vector3.ZERO)
	for entry: Array in verts:
		aabb = aabb.expand(entry[0])
	var seat_local_aabb := AABB(_van.to_local(aabb.position), Vector3.ZERO).expand(_van.to_local(aabb.end))
	print("MEASURE %s at %s: %d verts, body bounds (van space) %s" % [player.name, seat.name, verts.size(), seat_local_aabb])
	var keys: Array = report.keys()
	keys.sort()
	for key: String in keys:
		print("MEASURE   inside %-40s %4d verts, deepest %.3f m" % [key, report[key][0], report[key][1]])
	# Headroom: roof above the head's highest vertex.
	var top: Vector3 = verts[0][0]
	var bottom: Vector3 = verts[0][0]
	for entry: Array in verts:
		if (entry[0] as Vector3).y > top.y:
			top = entry[0]
		if (entry[0] as Vector3).y < bottom.y:
			bottom = entry[0]
	var up := _ray(space, top, top + Vector3.UP * 2.0)
	print("MEASURE   head top y=%.3f, first surface above: %s" % [top.y, _hit_text(up, top)])
	var down := _ray(space, bottom + Vector3.UP * 0.02, bottom + Vector3.DOWN * 1.0)
	print("MEASURE   lowest vertex (%s) y=%.3f, first surface below: %s" % [_bone_at(verts, bottom), bottom.y, _hit_text(down, bottom)])
	# Seat gap: from the pelvis straight down to the cushion.
	var hips: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(0).origin)
	var under := _ray(space, hips, hips + Vector3.DOWN * 1.2)
	print("MEASURE   root bone %s at y=%.3f, surface below: %s" % [skeleton.get_bone_name(0), hips.y, _hit_text(under, hips)])
	var butt_low := INF
	for entry: Array in verts:
		var q: Vector3 = entry[0]
		if Vector2(q.x - hips.x, q.z - hips.z).length() < 0.12:
			butt_low = minf(butt_low, q.y)
	if not under.is_empty():
		print("MEASURE   lowest vertex within 12 cm of the root bone axis y=%.3f -> %.3f m above that surface (negative = sunk in)" % [butt_low, butt_low - (under.position as Vector3).y])
	var current := _current_offset(player, seat)
	print("MEASURE   player.gd seat_offset for %s: %s, lean %.2f rad" % [seat.name, current, (player.get_node(^"BodyVisual") as Node3D).rotation.x])
	_fit_report(seat, verts, current)
	if seat.name == &"DriverEyePoint":
		_measure_wheel(verts)
		_reach_analysis(player, seat, verts, current)
	for candidate: Vector2 in TRY_DELTAS:
		_try_offset(player, seat, verts, candidate.x, candidate.y, current)


func _measure_wheel(verts: Array) -> void:
	var rim := _van.find_child("SteeringWheel", true, false).find_child("Rim", true, false) as MeshInstance3D
	if rim == null:
		return
	var torus := rim.mesh as TorusMesh
	var major: float = (torus.inner_radius + torus.outer_radius) * 0.5
	var tube: float = (torus.outer_radius - torus.inner_radius) * 0.5
	var inv := rim.global_transform.affine_inverse()
	var closest: Dictionary = {}  # bone -> signed distance to the tube surface
	for entry: Array in verts:
		var local: Vector3 = inv * (entry[0] as Vector3)
		var radial: float = Vector2(local.x, local.z).length() - major
		var d: float = Vector2(radial, local.y).length() - tube
		var bone: String = entry[1]
		closest[bone] = minf(closest.get(bone, INF), d)
	var bones: Array = closest.keys()
	bones.sort_custom(func(a: String, b: String) -> bool: return closest[a] < closest[b])
	for bone: String in bones.slice(0, 8):
		print("MEASURE   wheel rim vs %-14s closest %+.3f m (negative = inside the rim tube)" % [bone, closest[bone]])
	# Belly vs the wheel's disc: nearest torso vertex to the wheel plane, inside the rim circle.
	var worst := INF
	for entry: Array in verts:
		if not String(entry[1]).begins_with("spine") and not String(entry[1]).begins_with("torso") and String(entry[1]) != "hips" and not String(entry[1]).begins_with("chest"):
			continue
		var local: Vector3 = inv * (entry[0] as Vector3)
		if Vector2(local.x, local.z).length() < major + tube:
			worst = minf(worst, absf(local.y))
	print("MEASURE   torso distance to the wheel plane inside the rim circle: %.3f m" % worst)
	var wheel_node := rim.get_parent() as Node3D
	print("MEASURE   wheel centre (van space) %s, radius %.3f, axis %s" % [_van.to_local(rim.global_position), major, _van.global_basis.inverse() * rim.global_basis.y])


## For every seat anchor: what's right under it (the cushion) and how far
## above that the eye marker is. In the Sit clip the butt is about 0.2 m
## below the body root, so offset.y ~= -(cushion depth) + 0.2 seats it.
func _survey_seats() -> void:
	var space := _level.get_world_3d().direct_space_state
	var bulkhead := _van.find_child("BulkheadLower", true, false) as MeshInstance3D
	if bulkhead != null:
		var box := AABB()
		for i: int in range(8):
			var corner := _van.to_local(bulkhead.global_transform * bulkhead.get_aabb().get_endpoint(i))
			box = AABB(corner, Vector3.ZERO) if i == 0 else box.expand(corner)
		print("SURVEY BulkheadLower (van space) z %.3f..%.3f  y %.3f..%.3f" % [box.position.z, box.end.z, box.position.y, box.end.y])
	for marker: Node in _van.find_children("*EyePoint", "Marker3D", true, false):
		var eye: Vector3 = (marker as Node3D).global_position
		var hit := _ray(space, eye, eye + Vector3.DOWN * 2.0)
		var floor_hit: Dictionary = {}
		var from := eye
		for i: int in range(8):
			var h := _ray(space, from, eye + Vector3.DOWN * 2.0)
			if h.is_empty():
				break
			floor_hit = h
			from = (h.position as Vector3) + Vector3.DOWN * 0.0005
		var local_eye := _van.to_local(eye)
		print("SURVEY %-22s eye (van) %s | first surface below: %s | lowest: %s" % [marker.name, local_eye,
			_hit_text(hit, eye), _hit_text(floor_hit, eye)])


## How far the body must move so the seat of the shorts rests on the cushion
## right under the eye marker and the back just touches what's behind it.
func _fit_report(seat: Node3D, verts: Array, current: Vector3) -> void:
	var space := _level.get_world_3d().direct_space_state
	var eye := seat.global_position
	var cushion := _ray(space, eye, eye + Vector3.DOWN * 2.0)
	var butt_low := INF
	var back_extent := -INF
	var back_dir: Vector3 = seat.global_basis.z.normalized()
	for entry: Array in verts:
		var q: Vector3 = entry[0]
		if entry[1] == "pelvis":
			butt_low = minf(butt_low, q.y)
		if entry[1] in ["pelvis", "spine", "chest", "neck", "head"]:
			back_extent = maxf(back_extent, (q - eye).dot(back_dir))
	var behind := _ray(space, eye + Vector3.DOWN * 0.45, eye + Vector3.DOWN * 0.45 + back_dir * 1.2)
	var line := "MEASURE   fit: "
	if not cushion.is_empty():
		var dy: float = (cushion.position as Vector3).y - butt_low
		line += "cushion %s top is %.3f m under the eye marker; butt is %.3f m %s it -> raise body %+.3f m (seat_offset.y %.2f)" % [
			_probe_bodies.get(cushion.rid, "?"), eye.y - (cushion.position as Vector3).y, absf(dy), "below" if dy > 0 else "above", dy, current.y + dy]
	if not behind.is_empty():
		var room: float = eye.distance_to(behind.position - Vector3.DOWN * 0.45) - back_extent
		line += "; backrest/wall %s is %.3f m behind the eye, back of the body reaches %.3f m -> %s" % [
			_probe_bodies.get(behind.rid, "?"), eye.distance_to(behind.position - Vector3.DOWN * 0.45), back_extent,
			"clear by %.3f m" % room if room >= 0.0 else "move body forward %.3f m (seat_offset.z %+.3f)" % [-room, current.z + room]]
	print(line)
	# Seat-local geometry (x right, y up, z back, origin at the eye marker).
	var inv := seat.global_transform.affine_inverse()
	for pair: Array in [["cushion", cushion], ["backrest", behind]]:
		if pair[1].is_empty():
			continue
		var mesh := _probe_meshes.get(pair[1].rid) as MeshInstance3D
		if mesh == null:
			continue
		var box := AABB()
		var first := true
		var aabb := mesh.get_aabb()
		for i: int in range(8):
			var corner: Vector3 = inv * (mesh.global_transform * aabb.get_endpoint(i))
			if first:
				box = AABB(corner, Vector3.ZERO)
				first = false
			else:
				box = box.expand(corner)
		print("MEASURE   seat-local %s %s: y %.3f..%.3f  z %.3f..%.3f" % [pair[0], mesh.name, box.position.y, box.end.y, box.position.z, box.end.z])
	var ranges: Dictionary = {}
	for entry: Array in verts:
		var q: Vector3 = inv * (entry[0] as Vector3)
		var group: String = String(entry[1]).trim_suffix(".L").trim_suffix(".R")
		if not ranges.has(group):
			ranges[group] = [q, q]
		ranges[group][0] = Vector3(minf(ranges[group][0].x, q.x), minf(ranges[group][0].y, q.y), minf(ranges[group][0].z, q.z))
		ranges[group][1] = Vector3(maxf(ranges[group][1].x, q.x), maxf(ranges[group][1].y, q.y), maxf(ranges[group][1].z, q.z))
	for group: String in ["head", "neck", "chest", "belly", "spine", "pelvis", "thigh", "shin", "foot", "upper_arm", "forearm", "hand"]:
		if ranges.has(group):
			print("MEASURE   seat-local body %-9s x %+.3f..%+.3f  y %.3f..%.3f  z %.3f..%.3f" % [group, ranges[group][0].x, ranges[group][1].x,
				ranges[group][0].y, ranges[group][1].y, ranges[group][0].z, ranges[group][1].z])


## What the body would look like moved by (up, back) in the seat's own
## frame (back = +Z) from player.gd's current offset. Every 4th vertex is
## tested.
func _try_offset(player: Node3D, seat: Node3D, verts: Array, up: float, back: float, current: Vector3) -> void:
	var space := _level.get_world_3d().direct_space_state
	var shift: Vector3 = seat.global_basis * Vector3(0.0, up, back)
	var line := "MEASURE   try seat_offset (%.2f, %.2f, %.2f):" % [current.x, current.y + up, current.z + back]
	var top := -INF
	var top_p := Vector3.ZERO
	var butt_low := INF
	var foot_low := INF
	var inside: Dictionary = {}
	for i: int in range(verts.size()):
		var q: Vector3 = (verts[i][0] as Vector3) + shift
		var bone: String = verts[i][1]
		if q.y > top:
			top = q.y
			top_p = q
		if bone == "pelvis":
			butt_low = minf(butt_low, q.y)
		if bone.begins_with("foot"):
			foot_low = minf(foot_low, q.y)
		if i % 4 == 0 and not (bone.begins_with("hand") or bone.begins_with("thumb")):
			var hit := _inside_mesh(space, q)
			if not hit.is_empty() and hit.depth > 0.01:
				var key: String = "%s/%s" % [hit.mesh, bone]
				inside[key] = maxf(inside.get(key, 0.0), hit.depth)
	var roof := _ray(space, top_p, top_p + Vector3.UP * 2.0)
	line += " headroom %s" % ("%.3f" % top_p.distance_to(roof.position) if not roof.is_empty() else "?")
	var pelvis_axis := Vector3.ZERO
	var skeleton := _find_skeleton(player.get_node(^"BodyVisual"))
	pelvis_axis = skeleton.to_global(skeleton.get_bone_global_pose(0).origin) + shift
	var cushion := _ray(space, pelvis_axis + Vector3.UP * 0.6, pelvis_axis + Vector3.DOWN * 1.5)
	if not cushion.is_empty():
		line += " | butt %+.3f over %s" % [butt_low - (cushion.position as Vector3).y, _probe_bodies.get(cushion.rid, "?")]
	var floor_hit := _ray(space, Vector3(pelvis_axis.x, foot_low + 0.6, pelvis_axis.z) - seat.global_basis.z * 0.3, Vector3(pelvis_axis.x, foot_low - 1.0, pelvis_axis.z) - seat.global_basis.z * 0.3)
	if not floor_hit.is_empty():
		line += " | feet %+.3f over %s" % [foot_low - (floor_hit.position as Vector3).y, _probe_bodies.get(floor_hit.rid, "?")]
	if seat.name == &"DriverEyePoint":
		for side: String in ["Left", "Right"]:
			var target := _van.find_child("DriverHandTarget" + side, true, false) as Node3D
			var bone: int = skeleton.find_bone("upper_arm." + side.left(1))
			var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(bone).origin) + shift
			line += " | %s shoulder-grip %.3f/0.508" % [side, shoulder.distance_to(target.global_position)]
	var keys: Array = inside.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key: String in keys:
		parts.append("%s %.2f" % [key, inside[key]])
	line += " | inside(>1cm): " + (", ".join(parts) if not parts.is_empty() else "none")
	print(line)


func _reach_analysis(player: Node3D, seat: Node3D, verts: Array, current: Vector3) -> void:
	var skeleton := _find_skeleton(player.get_node(^"BodyVisual"))
	var rim := _van.find_child("SteeringWheel", true, false).find_child("Rim", true, false) as MeshInstance3D
	var space := _level.get_world_3d().direct_space_state
	var arms: Array = []
	for pair: Array in [[&"upper_arm.L", &"forearm.L", &"hand.L", "DriverHandTargetLeft"], [&"upper_arm.R", &"forearm.R", &"hand.R", "DriverHandTargetRight"]]:
		var ua: int = skeleton.find_bone(pair[0])
		var fa: int = skeleton.find_bone(pair[1])
		var hd: int = skeleton.find_bone(pair[2])
		var target := _van.find_child(pair[3], true, false) as Node3D
		if ua < 0 or fa < 0 or hd < 0 or target == null:
			print("MEASURE   reach: missing bone/target ", pair)
			return
		var a := skeleton.to_global(skeleton.get_bone_global_rest(ua).origin)
		var b := skeleton.to_global(skeleton.get_bone_global_rest(fa).origin)
		var c := skeleton.to_global(skeleton.get_bone_global_rest(hd).origin)
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(ua).origin)
		arms.append([pair[2], shoulder, target.global_position, a.distance_to(b) + b.distance_to(c)])
	var pelvis := skeleton.to_global(skeleton.get_bone_global_pose(0).origin)
	var inv := rim.global_transform.affine_inverse()
	var torus := rim.mesh as TorusMesh
	var major: float = (torus.inner_radius + torus.outer_radius) * 0.5
	print("MEASURE   driver reach table (seat_offset.z -> shoulder-to-grip / arm chain; torso-to-wheel-plane; pelvis-over-cushion):")
	for dz: float in [-0.15, -0.1, -0.05, 0.0, 0.05, 0.1]:
		var z_offset: float = current.z + dz
		var shift: Vector3 = seat.global_basis * Vector3(0, 0, dz)
		var line := "MEASURE     z=%+.2f" % z_offset
		for arm: Array in arms:
			line += "  %s %.3f/%.3f" % [arm[0], (arm[1] + shift).distance_to(arm[2]), arm[3]]
		var torso_gap := INF
		var butt_low := INF
		for entry: Array in verts:
			var bone := String(entry[1])
			var q: Vector3 = (entry[0] as Vector3) + shift
			if bone in ["pelvis", "spine", "chest", "belly", "neck"]:
				var local: Vector3 = inv * q
				if Vector2(local.x, local.z).length() < major + 0.03:
					torso_gap = minf(torso_gap, absf(local.y) - 0.03)
			if bone == "pelvis":
				butt_low = minf(butt_low, q.y)
		line += "  torso-to-rim-plane %.3f" % torso_gap if torso_gap < INF else "  torso clear of the rim circle"
		var p := pelvis + shift
		var hit := _ray(space, p + Vector3.UP * 0.6, p + Vector3.DOWN * 1.0)
		if not hit.is_empty():
			line += "  cushion %s: butt %+.3f m above it" % [_probe_bodies.get(hit.rid, "?"), butt_low - (hit.position as Vector3).y]
		print(line)


func _inside_mesh(space: PhysicsDirectSpaceState3D, p: Vector3) -> Dictionary:
	# Parity test along +Y and -Y: a point is inside a closed mesh when a ray
	# leaving it crosses that mesh's surface an odd number of times (both ways).
	var up_counts := _crossings(space, p, Vector3.UP)
	var down_counts := _crossings(space, p, Vector3.DOWN)
	for rid: RID in up_counts:
		if up_counts[rid] % 2 == 1 and down_counts.get(rid, 0) % 2 == 1:
			var depth: float = INF
			for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var hit := _ray_on(space, p, dir, rid)
				if not hit.is_empty():
					depth = minf(depth, p.distance_to(hit.position))
			return {"mesh": _probe_bodies.get(rid, "?"), "depth": depth}
	return {}


func _crossings(space: PhysicsDirectSpaceState3D, p: Vector3, dir: Vector3) -> Dictionary:
	var counts: Dictionary = {}
	var from := p
	for i: int in range(24):
		var hit := _ray(space, from, p + dir * 4.0)
		if hit.is_empty():
			break
		counts[hit.rid] = counts.get(hit.rid, 0) + 1
		from = (hit.position as Vector3) + dir * 0.0005
	return counts


## First surface of one given probe body along dir (others are skipped).
func _ray_on(space: PhysicsDirectSpaceState3D, p: Vector3, dir: Vector3, rid: RID) -> Dictionary:
	var from := p
	for i: int in range(24):
		var hit := _ray(space, from, p + dir * 2.0)
		if hit.is_empty():
			return {}
		if hit.rid == rid:
			return hit
		from = (hit.position as Vector3) + dir * 0.0005
	return {}


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, SEAT_PROBE_LAYER)
	query.hit_back_faces = true
	return space.intersect_ray(query)


func _hit_text(hit: Dictionary, from: Vector3) -> String:
	if hit.is_empty():
		return "none"
	return "%s at %.3f m" % [_probe_bodies.get(hit.rid, "?"), from.distance_to(hit.position)]


func _bone_at(verts: Array, p: Vector3) -> String:
	for entry: Array in verts:
		if entry[0] == p:
			return entry[1]
	return "?"


func _skinned_vertices(skeleton: Skeleton3D, mesh_instance: MeshInstance3D) -> Array:
	var out: Array = []
	var skin: Skin = mesh_instance.skin
	var bind_bones: PackedInt32Array = []
	for b: int in range(skin.get_bind_count()):
		var bone: int = skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		bind_bones.append(bone)
	var palette: Array[Transform3D] = []
	for b: int in range(skin.get_bind_count()):
		palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bind_bones[b]) * skin.get_bind_pose(b))
	var mesh := mesh_instance.mesh
	for s: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null:
			continue
		var per: int = bones.size() / positions.size()
		for v: int in range(positions.size()):
			var acc := Vector3.ZERO
			var best_w := -1.0
			var best_bone := 0
			for k: int in range(per):
				var w: float = weights[v * per + k]
				if w <= 0.0:
					continue
				var bind: int = bones[v * per + k]
				acc += (palette[bind] * positions[v]) * w
				if w > best_w:
					best_w = w
					best_bone = bind_bones[bind]
			out.append([acc, String(skeleton.get_bone_name(best_bone))])
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_skinned_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
		return node
	for child: Node in node.get_children():
		var found := _find_skinned_mesh(child)
		if found != null:
			return found
	return null
