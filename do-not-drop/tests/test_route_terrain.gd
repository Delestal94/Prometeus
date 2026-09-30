extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_terrain.gd
## The route's terrain: collision matches what's drawn, no steps at the seams,
## real relief, an edge that doesn't drop into the void, the truck climbs the
## hill, imported models on the ground keep their materials; behind a rail
## tunnel portal a hill rises, the cut ahead stays level with the track and
## the ground leaves a hole where the bore would run, and the hill has no hole
## over the portal outside the bore: the rim of the hole stays under the portal
## model's Backfill (N-318.1), whichever way the tunnel points.
const Terrain = preload("res://scripts/gameplay/route/route_terrain.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _run() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.add_span(Vector3(0, 0, 20), Vector3(0, 0, -250))
	terrain.add_span(Vector3(0, 0, -250), Vector3(60, 0, -300), true)
	terrain.add_span(Vector3(60, 0, -300), Vector3(90, 0, -250))
	terrain.pads.append(Vector3(12, terrain.base_height(Vector2(12, -220)) - 0.08, -220))
	var before: int = Time.get_ticks_msec()
	terrain.build()
	print("Terrain fixture build: %d ms, %d tiles" % [Time.get_ticks_msec() - before, terrain.get_child_count()])
	await physics_frame
	await physics_frame
	var state := root.world_3d.direct_space_state
	# Both sides, the old box edges, tile joins, curves and former void.
	var checks: int = 0
	for z: float in [8.3, -30.01, -32.0, -32.01, -64.0, -159.7, -220.0, -250.0, -270.5]:
		for x: float in [-42.0, -32.0, -14.0, -12.0, -6.0, 0.0, 6.0, 12.0, 14.0, 32.0, 42.0]:
			var p := Vector3(x, 0.0, z)
			var height: float = terrain.height_at(p)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, height + 3.0, z), Vector3(x, height - 3.0, z), 1)
			var hit: Dictionary = state.intersect_ray(ray)
			expect(not hit.is_empty(), "Missing collision at %s" % p)
			if not hit.is_empty():
				expect(absf(hit.position.y - height) < 0.01, "Visual/collision mismatch at %s" % p)
			checks += 1
	var lowest: float = INF
	var highest: float = -INF
	for z: int in range(-240, -140):
		var a: float = terrain.height_at(Vector3(0, 0, z))
		var b: float = terrain.height_at(Vector3(0, 0, z + 1))
		expect(absf(a - b) < 0.2, "Abrupt driving slope at %d" % z)
		lowest = minf(lowest, a)
		highest = maxf(highest, a)
	expect(highest - lowest > 1.0, "Road must have real relief")
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 24, -100), Vector3(150, 24, -100), 1)
	expect(not state.intersect_ray(wall_ray).is_empty(), "Exterior boundary must stop players before the void")
	var player: CharacterBody3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.position = Vector3(1, 1, 1)
	root.add_child(player)
	# Headless cannot capture the mouse. Drive the real CharacterBody physics
	# explicitly, then use the same recovery hook as the on-foot controller.
	for i: int in range(45):
		await physics_frame
		player.velocity.y -= 18.0 / 60.0
		player.move_and_slide()
		player._update_ground_safety()
	expect(player.is_on_floor(), "Player settles on the rendered terrain")
	var safe: Vector3 = player.global_position
	player.global_position.y -= 20.0
	for i: int in range(3):
		await physics_frame
		player._update_ground_safety()
	expect(player.global_position.distance_to(safe) < 1.0, "Falling player returns to their last grounded position")
	player.free()
	# Exercise actual wheel suspension across tile seams and a long climb.
	var van: VehicleBody3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	van.position = Vector3(0, terrain.height_at(Vector3(0, 0, -150)) + 0.9, -150)
	root.add_child(van)
	van.controls_enabled = false
	root.get_node("RunManager").is_running = true
	var travelled: float = 0.0
	for i: int in range(900):
		van.set_controls(0.65, 0.0, false)
		await physics_frame
		var clearance: float = van.position.y - terrain.height_at(van.position)
		expect(clearance > -0.2 and clearance < 3.0, "Wheel suspension left terrain at %s" % van.position)
		expect(van.global_basis.y.dot(Vector3.UP) > 0.8, "Van destabilized on a gentle hill")
		travelled = -150.0 - van.position.z
		if travelled > 75.0:
			break
	expect(travelled > 75.0, "Van traverses the hill without getting stuck")
	root.get_node("RunManager").is_running = false
	van.free()
	# An imported model laid on the terrain keeps every surface and its
	# material: the road barrier used to come out in the default grey, with
	# no stripes and no orange legs (playtest 2026-09-25).
	var barrier: Node3D = (load("res://assets/models/environment/props/sm_env_prop_road_barrier.glb") as PackedScene).instantiate()
	terrain.add_child(barrier)
	barrier.position = Vector3(3.0, 0.0, -160.0)
	var before_surfaces: Dictionary = {}
	for part: MeshInstance3D in barrier.find_children("*", "MeshInstance3D", true, false):
		before_surfaces[part.name] = part.mesh.get_surface_count()
	terrain.conform_geometry(barrier)
	var bare: Array[String] = []
	for part: MeshInstance3D in barrier.find_children("*", "MeshInstance3D", true, false):
		if part.mesh.get_surface_count() != int(before_surfaces[part.name]):
			bare.append("%s lost surfaces" % part.name)
		for surface: int in range(part.mesh.get_surface_count()):
			if part.mesh.surface_get_material(surface) == null:
				bare.append("%s surface %d" % [part.name, surface])
	expect(bare.is_empty(), "Laid on the terrain, the road barrier keeps its materials (bare: %s)" % str(bare))
	terrain.free()
	await process_frame
	await _check_tunnel()
	await _check_tunnel_hill_gaps(Vector2(1.0, 0.0))
	await _check_tunnel_hill_gaps(Vector2.from_angle(deg_to_rad(33.0)))
	if failures == 0:
		print("PASS: %d terrain rays, seams, hills, boundary, on-foot recovery and a railway tunnel's hill" % checks)
	quit(failures)


## A level crossing's tunnel (RouteTerrain.tunnels, 2026-09-29): a hill rises
## behind the portal, the cutting in front stays level with the track, and the
## ground leaves a hole where it would cross the bore -- a vertical ray over
## the bore just behind the facade finds no ground, one further in, over the
## bore's roof, does.
func _check_tunnel() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.add_span(Vector3(0, 0, 20), Vector3(0, 0, -120))
	var level: float = terrain.base_height(Vector2(0.0, -40.0))
	var x: float = -42.0
	while x <= 42.0:
		terrain.pads.append(Vector3(x, level, -40.0))
		x += 7.0
	var crown: float = RailCrossingSegment.BORE_CROWN
	terrain.tunnels.append({"at": Vector2(42.0, -40.0), "dir": Vector2(1.0, 0.0), "level": level,
		"bore_half": RailCrossingSegment.BORE_HALF_WIDTH, "bore_length": RailCrossingSegment.BORE_LENGTH,
		"crown": crown, "face_half": RailCrossingSegment.PORTAL_HALF_WIDTH,
		"height": RailCrossingSegment.PORTAL_HEIGHT + 3.0})
	terrain.build()
	await physics_frame
	await physics_frame
	var behind: float = terrain.height_at(Vector3(52.0, 0.0, -40.0)) - level
	expect(behind > crown + 1.0, "A hill stands over the tunnel behind the portal (%.1f m)" % behind)
	var cutting: float = terrain.height_at(Vector3(37.0, 0.0, -40.0)) - level
	expect(absf(cutting) < 0.3, "The cutting in front of the portal is level with the track (%.2f m)" % cutting)
	var state := root.world_3d.direct_space_state
	var near := PhysicsRayQueryParameters3D.create(
		Vector3(45.0, level + 30.0, -40.0), Vector3(45.0, level - 2.0, -40.0), 1)
	expect(state.intersect_ray(near).is_empty(), "No ground cuts through the bore behind the facade")
	var far := PhysicsRayQueryParameters3D.create(
		Vector3(52.0, level + 30.0, -40.0), Vector3(52.0, level - 2.0, -40.0), 1)
	var roof: Dictionary = state.intersect_ray(far)
	expect(not roof.is_empty() and roof.position.y > level + crown, "The hill closes over the bore further in")
	terrain.free()
	await process_frame


## The hill behind a portal has no window under it (N-318.1): the ramp rises
## ~11 m within 3 m of the facade, and on the terrain's 2 m grid the cell just
## behind the mouth used to be dropped for the bore with its back rim at the
## full height, standing over the model's Backfill (which tops out ~7 m) with
## the sky showing between them. A vertical ray grid behind the mouth, with the
## tunnel pointing along `dir`, finds every hole in the ground: each one must
## lie within the portal model (bore or Backfill) and the ground touching it
## (the rim) must not rise above the Backfill's top.
func _check_tunnel_hill_gaps(dir: Vector2) -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.add_span(Vector3(0, 0, 20), Vector3(0, 0, -120))
	var centre := Vector2(0.0, -40.0)
	var level: float = terrain.base_height(centre)
	var x: float = -42.0
	while x <= 42.0:
		var pad: Vector2 = centre + dir * x
		terrain.pads.append(Vector3(pad.x, level, pad.y))
		x += 7.0
	var crown: float = RailCrossingSegment.BORE_CROWN
	var at: Vector2 = centre + dir * 42.0
	terrain.tunnels.append({"at": at, "dir": dir, "level": level,
		"bore_half": RailCrossingSegment.BORE_HALF_WIDTH, "bore_length": RailCrossingSegment.BORE_LENGTH,
		"crown": crown, "face_half": RailCrossingSegment.PORTAL_HALF_WIDTH,
		"height": RailCrossingSegment.PORTAL_HEIGHT + 3.0})
	terrain.build()
	await physics_frame
	await physics_frame
	var state := root.world_3d.direct_space_state
	var side := Vector2(-dir.y, dir.x)
	var step: float = 0.25
	var columns: int = int(16.0 / step) + 1
	var rows: int = int(14.0 / step) + 1
	# Ground height above the track at each grid point (NAN where a ray finds none).
	var ground: Array[float] = []
	for row: int in range(rows):
		for column: int in range(columns):
			var local := Vector2(-2.0 + row * step, -8.0 + column * step)
			var point: Vector2 = at + dir * local.x + side * local.y
			var ray := PhysicsRayQueryParameters3D.create(
				Vector3(point.x, level + 30.0, point.y), Vector3(point.x, level - 2.0, point.y), 1)
			var hit: Dictionary = state.intersect_ray(ray)
			ground.append(NAN if hit.is_empty() else hit.position.y - level)
	var holes: int = 0
	var stray: Array[String] = []
	var rim: float = -INF
	for row: int in range(rows):
		for column: int in range(columns):
			if not is_nan(ground[row * columns + column]):
				continue
			holes += 1
			var along: float = -2.0 + row * step
			var across: float = absf(-8.0 + column * step)
			var in_bore: bool = (across <= RailCrossingSegment.BORE_HALF_WIDTH + 0.45
				and along <= RailCrossingSegment.BORE_LENGTH)
			var in_backfill: bool = (along <= RailCrossingSegment.BACKFILL_LENGTH
				and across <= RailCrossingSegment.BACKFILL_HALF_WIDTH)
			if not (in_bore or in_backfill):
				stray.append("(%.2f, %.2f)" % [along, across])
			var neighbours: Array[Vector2i] = [
				Vector2i(row - 1, column), Vector2i(row + 1, column),
				Vector2i(row, column - 1), Vector2i(row, column + 1)]
			for neighbour: Vector2i in neighbours:
				if neighbour.x < 0 or neighbour.x >= rows or neighbour.y < 0 or neighbour.y >= columns:
					continue
				var height: float = ground[neighbour.x * columns + neighbour.y]
				if not is_nan(height):
					rim = maxf(rim, height)
	var label: String = "%d deg" % roundi(rad_to_deg(dir.angle()))
	expect(holes > 0, "The bore leaves a hole in the hill's ground (%s)" % label)
	expect(stray.is_empty(), "Every hole in the hill lies within the portal model (%s; outside it: %s)"
		% [label, ", ".join(stray.slice(0, 8))])
	expect(rim <= crown + RailCrossingSegment.BACKFILL_ABOVE_CROWN,
		"The hill's rim round the bore hole never stands over the portal's Backfill (max %.2f m, %s)" % [rim, label])
	print("Tunnel hill gaps at %s: %d hole points, rim up to %.2f m over the track" % [label, holes, rim])
	terrain.free()
	await process_frame
