extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_mud_segment.gd
## MudSegment (tareas de Nacho N-108, mud_segment.gd): the stretch of road
## where the truck can bog down and the crew gets it out together.
##   - Generation: rare (a few percent of routes, at most one per route),
##     counted as a hard moment by the pacing, never in the calm last
##     QUIET_ZONE metres before a house nor in the first SAFE_START_LENGTH,
##     announced by its own board and the road's hazard sign; Endless spaces
##     it out and starts it late.
##   - Physics, on the real van: slow into the pit it bogs (held in place, the
##     level's stuck rule stands down); with speed it ploughs through; grip
##     drops in the mud and is restored, never compounded.
##   - The way out: two passengers on foot push quicker than one, a seated
##     passenger can't push (their boxes stay tended, the cost of pushing), the
##     tow strap hauls it out at once and is used up, and the crane comes after
##     crane_delay, hauls it out and fines the team without ever taking the
##     balance under zero, leaving its line for the results.
##   - Holding the primary button near the truck is what sends a push.
##   - Neither level ends the run on "stuck" while the truck is in the mud.
## Pass -- --measure to print the pass/bog table by entry speed.

const Route = preload("res://scripts/gameplay/route/route.gd")
const SEEDS: int = 400
const FLAT_ARENA_LENGTH: float = 200.0
## Headless paces physics at wall-clock speed and the rescue runs ~140 s of it
## (pushes, strap, a 45 s crane): FAST_FORWARD ticks per real tick, ticks/s and
## time_scale raised together so each tick is still 1/60 s of game time, as in
## test_vehicle_stress. MudSegment only counts physics delta, never the clock.
const FAST_FORWARD: int = 8

var _failures: int = 0
var _manager: Node
var _crew: Node
var _network: Node
var _start_money: int = 0


## Stands in for a player: what MudSegment reads off one.
class FakePlayer:
	extends Node3D
	var seat_node_path: NodePath = NodePath()
	var carried_package: Node = null
	var local: bool = false
	var _seated: bool = false
	var _ragdolled: bool = false

	func is_local() -> bool:
		return local


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_manager = root.get_node(^"/root/RunManager")
	_crew = root.get_node(^"/root/CrewProgression")
	_network = root.get_node(^"/root/NetworkManager")
	_start_money = int(_crew.get(&"team_money"))
	if "--measure" in OS.get_cmdline_user_args():
		await _measure()
		quit(0)
		return
	Engine.physics_ticks_per_second = 60 * FAST_FORWARD
	Engine.time_scale = float(FAST_FORWARD)
	Engine.max_physics_steps_per_frame = 8 * FAST_FORWARD
	_check_generation()
	await _check_real_route()
	await _check_endless_pool()
	_manager.set(&"is_running", true)
	await _check_bog_and_grip()
	await _check_push()
	await _check_strap()
	await _check_crane()
	await _check_input_polling()
	await _check_pusher_rules()
	await _check_run_end()
	await _check_grip_zones()
	await _check_one_rescue_per_stretch()
	await _check_endless_crane()
	_manager.set(&"is_running", false)
	await _check_replication()
	_check_request_state_rpc()
	await _check_level_stuck_rules()
	_network.set(&"world_seed", 0)
	_network.set(&"world_house_count", 0)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	if _failures == 0:
		print("PASS: mud is rare and announced, bogs a slow truck, and pushing, the strap or the crane free it")
	quit(_failures)


# --- Generation -------------------------------------------------------------------


func _check_generation() -> void:
	var with_mud: int = 0
	var routes: int = 0
	var most_in_one: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var houses: int = 1 + seed_value % 4
		var plan: Dictionary = RoutePlanner.plan_spine(seed_value, houses)
		routes += 1
		var count: int = 0
		for segment: Dictionary in plan.segments:
			if segment.script != MudSegment:
				continue
			count += 1
			_expect(bool(segment.hard) and bool(segment.moment),
					"Seed %d: the mud counts as a hard moment for the pacing" % seed_value)
			_expect(float(segment.start) >= RoutePlanner.SAFE_START_LENGTH,
					"Seed %d: no mud in the first %.0f m (starts at %.0f)" % [
							seed_value, RoutePlanner.SAFE_START_LENGTH, segment.start])
			for stop: float in plan.house_distances:
				var reaches_calm_zone: bool = segment.start < stop \
						and segment.start + segment.length > stop - RoutePlanner.QUIET_ZONE
				_expect(not reaches_calm_zone,
						"Seed %d: the mud (%.0f m) is clear of the calm %.0f m before the house at %.0f m" % [
						seed_value, segment.start, RoutePlanner.QUIET_ZONE, stop])
			_expect(float(segment.length) <= RoutePlanner.MAX_SEGMENT_LENGTH,
					"The mud is no longer than the planner's longest segment")
		most_in_one = maxi(most_in_one, count)
		with_mud += int(count > 0)
	_expect(most_in_one <= 1, "At most one mud pit per route (got %d)" % most_in_one)
	_expect(with_mud >= 1, "Some routes do get mud (got %d of %d)" % [with_mud, routes])
	_expect(with_mud <= routes * 0.35, "Mud is rare: %d of %d routes" % [with_mud, routes])
	print("mud routes: %d of %d" % [with_mud, routes])
	_expect(RouteSignage.HAZARD_SIGNS.has("MudSegment"), "The road puts up a hazard sign before the mud")


## Builds a real route with mud in it: the road has the planned mud, its own
## board, the road's sign in front of it and the terrain lays it as loose dirt.
func _check_real_route() -> void:
	var found_seed: int = 0
	var found_houses: int = 2
	for seed_value: int in range(1, SEEDS + 1):
		for segment: Dictionary in RoutePlanner.plan_spine(seed_value, 2).segments:
			if segment.script == MudSegment:
				found_seed = seed_value
				break
		if found_seed != 0:
			break
	_expect(found_seed != 0, "Some seed among the first %d builds a route with mud" % SEEDS)
	if found_seed == 0:
		return
	_network.set(&"world_seed", found_seed)
	_network.set(&"world_house_count", found_houses)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	await process_frame
	var mud: MudSegment = null
	for segment: RouteSegment in route.get(&"_segments"):
		if segment is MudSegment:
			mud = segment as MudSegment
	_expect(mud != null, "The built route has its MudSegment (seed %d)" % found_seed)
	if mud != null:
		_expect(mud.get_node_or_null(^"MudSignBoard") != null, "The mud carries its own warning board")
		var title: Label3D = mud.get_node_or_null(^"MudSignTitle") as Label3D
		_expect(title != null and title.text != "", "The board has a title in words")
		var sign_found: bool = false
		for node: Node in route.find_children("*", "Node3D", true, false):
			if node.get_meta(&"rule", &"") == &"hazard_sign" \
					and (node as Node3D).global_position.distance_to(mud.global_position) < 20.0:
				sign_found = true
		_expect(sign_found, "The road's hazard sign stands at the mud's entry")
		_expect(mud.get_node_or_null(^"PushSpot") != null and mud.get_node_or_null(^"StrapSpot") != null,
				"Both rescue spots exist on every peer under fixed names")
	route.free()
	_network.set(&"world_seed", 0)
	_network.set(&"world_house_count", 0)
	await process_frame


## Endless: mud is in the pool and counted hard, but starts late and is spaced out.
func _check_endless_pool() -> void:
	var probe := RouteStreamer.new()
	root.add_child(probe)
	_expect(probe.segment_scripts.has(MudSegment), "Endless can draw mud")
	_expect(probe.hard_segments.has(MudSegment), "Endless counts mud as a hard segment")
	probe.free()
	var muds: Array[float] = []
	var stats: Dictionary = {"segments": 0}
	for seed_value: int in [31337, 777, 90210]:
		_network.set(&"world_seed", seed_value)
		var streamer := RouteStreamer.new()
		root.add_child(streamer)
		streamer.child_entered_tree.connect(func(node: Node) -> void:
			if node is RouteSegment:
				stats.segments += 1
				if node is MudSegment:
					muds.append(float(node.get_meta(&"route_distance", 0.0))))
		var target := Node3D.new()
		root.add_child(target)
		streamer.start(target)
		var ridden: float = 0.0
		while ridden < 6000.0:
			ridden += 40.0
			target.global_position = streamer.point_at(ridden)
			streamer.call(&"_fill_ahead")
			streamer.call(&"_cull_behind")
			await process_frame
		streamer.free()
		target.free()
		muds.append(-1.0)
	_network.set(&"world_seed", 0)
	var previous: float = -INF
	for at: float in muds:
		if at < 0.0:
			previous = -INF
			continue
		_expect(at >= RouteStreamer.MUD_FIRST_AT,
				"Endless mud starts after %.0f m (got %.0f)" % [RouteStreamer.MUD_FIRST_AT, at])
		_expect(at - previous >= RouteStreamer.MUD_MIN_GAP,
				"Endless mud is at least %.0f m apart (got %.0f)" % [RouteStreamer.MUD_MIN_GAP, at - previous])
		previous = at
	var real_muds: int = muds.filter(func(at: float) -> bool: return at >= 0.0).size()
	_expect(real_muds * 10 <= int(stats.segments), "Endless mud is rare: %d in %d segments" % [real_muds,
			int(stats.segments)])


# --- The arena --------------------------------------------------------------------


## A flat world with a MudSegment at the origin (road along -Z) and the real van
## parked before it.
func _arena(crane_delay: float = 45.0) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, FLAT_ARENA_LENGTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 60.0)
	ground.add_child(shape)
	world.add_child(ground)
	var segment := MudSegment.new()
	segment.crane_delay = crane_delay
	world.add_child(segment)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(0.0, 0.8, 40.0)
	world.add_child(van)
	return {"world": world, "segment": segment, "van": van}


func _free_arena(arena: Dictionary) -> void:
	(arena.world as Node).queue_free()
	await process_frame


## Drives into the mud at `entry_speed` (m/s at the segment's start) with the
## pedal down and waits for the outcome; returns whether it bogged.
func _drive_in(arena: Dictionary, entry_speed: float) -> bool:
	var van: VehicleBody3D = arena.van
	var segment: MudSegment = arena.segment
	var launched: bool = false
	var frames: int = 0
	while frames < 60 * 14:
		van.set_controls(1.0, 0.0, false)
		await physics_frame
		frames += 1
		var z: float = segment.to_local(van.global_position).z
		if not launched and z < 6.0:
			launched = true
			van.linear_velocity = -van.global_basis.z * entry_speed
		if segment.state == MudSegment.State.BOGGED:
			return true
		if z < -segment.length - 4.0:
			return false
	return false


## Puts the van in the pit crawling and waits for it to bog.
func _bog_now(arena: Dictionary) -> bool:
	var van: VehicleBody3D = arena.van
	var segment: MudSegment = arena.segment
	for _i: int in range(20):
		await physics_frame
	van.global_position = segment.to_global(Vector3(0.0, 0.8, -segment.pit_start - 1.0))
	van.reset_physics_interpolation()
	van.linear_velocity = -van.global_basis.z * 4.0
	for _i: int in range(60 * 5):
		van.set_controls(1.0, 0.0, false)
		await physics_frame
		if segment.state == MudSegment.State.BOGGED:
			return true
	return false


func _player(arena: Dictionary, peer_id: int, offset: Vector3 = Vector3(0.0, 0.0, 7.0)) -> FakePlayer:
	var van: VehicleBody3D = arena.van
	var player := FakePlayer.new()
	player.name = "Fake%d" % peer_id
	player.add_to_group(&"player")
	player.set_multiplayer_authority(peer_id)
	(arena.world as Node).add_child(player)
	player.global_position = van.global_transform * offset
	return player


## Pushers hold the button for `seconds`; returns the seconds it took the truck
## to be free (state back to IDLE), or -1.0 if it never was.
func _push_until_free(arena: Dictionary, players: Array, pedal: float, limit: float) -> float:
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	var frames: int = 0
	while float(frames) / 60.0 < limit:
		if frames % 6 == 0:
			for player: FakePlayer in players:
				# They walk with the truck as it creeps and stay at its tail.
				player.global_position = van.global_transform * Vector3(0.0, 0.0, 7.0)
				segment.set_pusher(player.get_multiplayer_authority(), true)
		van.set_controls(pedal, 0.0, false)
		await physics_frame
		frames += 1
		if segment.state == MudSegment.State.IDLE and frames > 10:
			return float(frames) / 60.0
	return -1.0


# --- Bog and grip ----------------------------------------------------------------


func _check_bog_and_grip() -> void:
	var arena: Dictionary = _arena()
	var van: VehicleBody3D = arena.van
	var segment: MudSegment = arena.segment
	var wheels: Array[VehicleWheel3D] = []
	for child: Node in van.get_children():
		if child is VehicleWheel3D:
			wheels.append(child as VehicleWheel3D)
	var original: float = wheels[0].wheel_friction_slip
	_expect(not bool(van.get_meta(&"in_mud", false)), "Outside the mud the van is not marked as in it")
	var bogged: bool = await _drive_in(arena, 4.0)
	_expect(bogged, "A slow truck sinks in the pit (state %d)" % segment.state)
	_expect(bool(van.get_meta(&"in_mud", false)) and bool(van.get_meta(&"mud_bogged", false)),
			"A bogged van carries the in_mud and mud_bogged marks the levels read")
	for wheel: VehicleWheel3D in wheels:
		_expect(is_equal_approx(wheel.wheel_friction_slip, segment.reduced_friction_slip),
				"Grip is down in the mud (got %.2f)" % wheel.wheel_friction_slip)
	# Held: with the pedal to the floor it stays put.
	var held_at: Vector3 = van.global_position
	for _i: int in range(60 * 5):
		van.set_controls(1.0, 0.0, false)
		await physics_frame
	_expect(van.global_position.distance_to(held_at) < 3.0,
			"A bogged truck stays put with the pedal down (moved %.1f m)" % van.global_position.distance_to(held_at))
	_expect(van.linear_velocity.length() < 1.5, "...and is nearly still (%.2f m/s)" % van.linear_velocity.length())
	_expect(is_finite(van.global_position.x + van.global_position.y + van.global_position.z),
			"No NaN in the truck's position")
	# Out the side (teleport): the marks and the grip restore.
	van.global_position = segment.to_global(Vector3(0.0, 0.8, 30.0))
	van.linear_velocity = Vector3.ZERO
	van.reset_physics_interpolation()
	for _i: int in range(20):
		await physics_frame
	_expect(not bool(van.get_meta(&"in_mud", false)) and not bool(van.get_meta(&"mud_bogged", false)),
			"Leaving the mud clears the marks")
	_expect(segment.state == MudSegment.State.IDLE, "...and the bog with them (state %d)" % segment.state)
	for wheel: VehicleWheel3D in wheels:
		_expect(wheel.wheel_friction_slip == original,
				"Grip is restored on leaving (got %.2f)" % wheel.wheel_friction_slip)
	# Re-entry never compounds.
	for _round: int in range(2):
		van.global_position = segment.to_global(Vector3(0.0, 0.8, -5.0))
		van.reset_physics_interpolation()
		for _i: int in range(10):
			await physics_frame
	for wheel: VehicleWheel3D in wheels:
		_expect(is_equal_approx(wheel.wheel_friction_slip, segment.reduced_friction_slip),
				"Entering twice lowers the grip once, not twice (got %.2f)" % wheel.wheel_friction_slip)
	# Culling the segment with the van in it restores everything.
	(arena.world as Node).remove_child(segment)
	for wheel: VehicleWheel3D in wheels:
		_expect(wheel.wheel_friction_slip == original,
				"Freeing the segment restores the grip too (got %.2f)" % wheel.wheel_friction_slip)
	_expect(not bool(van.get_meta(&"in_mud", false)), "...and the marks")
	segment.free()
	await _free_arena(arena)

	# With speed it ploughs through and never bogs.
	arena = _arena()
	segment = arena.segment
	var bogged_fast: bool = await _drive_in(arena, 12.0)
	_expect(not bogged_fast, "At 12 m/s the truck ploughs through the pit (state %d)" % segment.state)
	_expect(segment.to_local((arena.van as Node3D).global_position).z < -segment.pit_end,
			"...and comes out the far side")
	await _free_arena(arena)


# --- Ways out -----------------------------------------------------------------------


func _check_push() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	_expect(await _bog_now(arena), "The van is bogged for the push test")
	var seated := _player(arena, 1003)
	seated.seat_node_path = NodePath("World/Vehicle/Seat")
	var loaded := _player(arena, 1004)
	var box := Node.new()
	loaded.carried_package = box
	_expect(not segment.can_use_spot(&"push", seated), "A seated passenger can't push: their boxes stay tended")
	_expect(not segment.can_use_spot(&"push", loaded), "Nobody pushes with a box in their hands")
	segment.set_pusher(1003, true)
	segment.set_pusher(1004, true)
	for _i: int in range(30):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	_expect(segment.pushers == 0,
			"Neither the seated nor the loaded passenger adds any push (got %d)" % segment.pushers)
	loaded.carried_package = null
	box.free()
	# Engine alone: barely moves the needle.
	var progress_before: float = segment.progress
	for _i: int in range(60 * 4):
		van.set_controls(1.0, 0.0, false)
		await physics_frame
	_expect(segment.state == MudSegment.State.BOGGED and segment.progress < progress_before + 0.1,
			"The engine alone barely helps: %.2f after 4 s" % (segment.progress - progress_before))
	# Someone on the truck's bed doesn't count as pushing either (too far from the spot).
	var far := _player(arena, 1005, Vector3(0.0, 0.0, 30.0))
	segment.set_pusher(1005, true)
	await physics_frame
	await physics_frame
	_expect(not segment._may_push(far), "A passenger far from the truck's tail can't push")
	far.free()
	seated.free()
	loaded.free()
	await _free_arena(arena)

	var times: Dictionary = {}
	for pushers: int in [1, 2]:
		arena = _arena(1000.0)
		segment = arena.segment
		_expect(await _bog_now(arena), "Bogged for the %d-pusher run" % pushers)
		var team: Array = []
		for index: int in range(pushers):
			team.append(_player(arena, 2000 + index))
		var took: float = await _push_until_free(arena, team, 1.0, 40.0)
		times[pushers] = took
		_expect(took > 0.0, "%d pusher(s) get the truck out" % pushers)
		_expect(segment.to_local((arena.van as Node3D).global_position).z <= -segment.pit_end + 0.5,
				"...to the far end of the pit (z %.1f)" % segment.to_local((arena.van as Node3D).global_position).z)
		_expect(not bool((arena.van as Node3D).get_meta(&"mud_bogged", false)), "The freed truck is no longer held")
		_expect(is_finite((arena.van as Node3D).global_position.y), "No NaN after the push")
		var push_line: String = tr("WORLD_MUD_STORY_PUSH")
		_expect(_manager.call(&"world_stories").has(push_line), "Pushing leaves its line in the run's story")
		await _free_arena(arena)
	print("push times: 1 pusher %.1f s, 2 pushers %.1f s" % [times[1], times[2]])
	_expect(times[1] > 10.0 and times[1] < 25.0, "One pusher plus the engine is slow (%.1f s)" % times[1])
	_expect(times[2] > 4.0 and times[2] < times[1] * 0.75,
			"Two pushers are clearly quicker (%.1f s against %.1f s)" % [times[2], times[1]])


func _check_strap() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	van.set_meta(&"tow_straps", 1)
	var money: int = int(_crew.get(&"team_money"))
	_expect(await _bog_now(arena), "Bogged with a strap on board")
	var player := _player(arena, 3000, Vector3(0.0, 0.0, -6.0))
	_expect(segment.strap_ready and segment.can_use_spot(&"strap", player), "The strap is on offer to anyone on foot")
	segment.use_spot(&"strap", player)
	_expect(segment.state == MudSegment.State.HAULING and segment.haul_method == &"strap",
			"Using it hauls the truck (state %d)" % segment.state)
	_expect(int(van.get_meta(&"tow_straps", -1)) == 0, "The strap is used up")
	var frames: int = 0
	while segment.state != MudSegment.State.IDLE and frames < 60 * 12:
		van.set_controls(0.0, 0.0, false)
		await physics_frame
		frames += 1
	_expect(segment.state == MudSegment.State.IDLE and segment.to_local(van.global_position).z <= -segment.pit_end,
			"The strap gets it out of the pit in %.1f s (z %.1f)" % [float(frames) / 60.0,
					segment.to_local(van.global_position).z])
	_expect(int(_crew.get(&"team_money")) == money, "The strap costs no fine")
	player.free()
	await _free_arena(arena)


func _check_crane() -> void:
	for balance: int in [100, 15]:
		_crew.set(&"team_money", balance)
		var arena: Dictionary = _arena(2.0)
		var segment: MudSegment = arena.segment
		var van: VehicleBody3D = arena.van
		_expect(await _bog_now(arena), "Bogged for the crane test")
		var frames: int = 0
		var saw_crane: bool = false
		while not (segment.state == MudSegment.State.IDLE and frames > 30) and frames < 60 * 25:
			van.set_controls(0.0, 0.0, false)
			await physics_frame
			frames += 1
			saw_crane = saw_crane or (segment.get_node_or_null(^"MudCrane") != null)
		_expect(saw_crane, "The crane drives in")
		_expect(segment.state == MudSegment.State.IDLE and segment.to_local(van.global_position).z <= -segment.pit_end,
				"The crane gets the truck out of the pit (z %.1f, state %d)" % [segment.to_local(van.global_position).z,
						segment.state])
		var expected: int = maxi(0, balance - segment.crane_fine)
		_expect(int(_crew.get(&"team_money")) == expected,
				"The fine is %d out of %d (team has %d)" % [segment.crane_fine, balance, int(_crew.get(&"team_money"))])
		_expect(int(_crew.get(&"team_money")) >= 0, "The balance never goes negative")
		var lines: Array[String] = _manager.call(&"world_stories")
		var fine_paid: int = balance - expected
		_expect(lines.has(tr("WORLD_MUD_STORY_CRANE") % fine_paid),
				"The results tell the crane story with its fine (%s)" % [lines])
		# The crane leaves and frees itself.
		for _i: int in range(60 * 5):
			await physics_frame
		var crane: Node = segment.get_node_or_null(^"MudCrane")
		_expect(crane == null or crane.is_queued_for_deletion(), "The crane drives off and is freed")
		await _free_arena(arena)
	_crew.set(&"team_money", _start_money)


func _check_input_polling() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	_expect(await _bog_now(arena), "Bogged for the input test")
	var player := _player(arena, 1)
	player.local = true
	var mouse_before: Input.MouseMode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	segment.require_captured_mouse = true
	Input.action_press(&"package_action_primary")
	for _i: int in range(40):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	_expect(segment.pushers == 0, "A click with the mouse free (a menu open) is not a push (got %d)" % segment.pushers)
	Input.action_release(&"package_action_primary")
	# A headless run never captures the mouse: the gate is lifted for the rest.
	segment.require_captured_mouse = false
	for _i: int in range(20):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	_expect(segment.pushers == 0, "Standing behind the truck alone pushes nothing")
	Input.action_press(&"package_action_primary")
	for _i: int in range(40):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	_expect(segment.pushers == 1, "Holding the primary button behind the truck pushes (got %d)" % segment.pushers)
	Input.action_release(&"package_action_primary")
	for _i: int in range(60):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	_expect(segment.pushers == 0, "Letting go stops the push (got %d)" % segment.pushers)
	Input.action_press(&"package_action_primary")
	player.seat_node_path = NodePath("Seat")
	for _i: int in range(30):
		await physics_frame
	_expect(segment.pushers == 0, "Sitting down stops it too (got %d)" % segment.pushers)
	Input.action_release(&"package_action_primary")
	Input.mouse_mode = mouse_before
	player.free()
	await _free_arena(arena)


func _check_replication() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	await physics_frame
	# What a client receives from the host.
	segment._apply_state(MudSegment.State.BOGGED, 0.42, 2, true, 31.0, &"", 0.0)
	var status: Label3D = segment.get_node(^"PushSpot/Status") as Label3D
	_expect(status.visible and status.text.contains("42") and status.text.contains("31"),
			"The board over the truck shows the push and the crane's clock (%s)" % status.text)
	_expect(segment.pushers == 2 and segment.strap_ready and is_equal_approx(segment.progress, 0.42),
			"The client keeps the host's numbers")
	segment._apply_state(MudSegment.State.CRANE_COMING, 0.42, 0, false, 0.0, &"", 0.0)
	_expect(segment.get_node_or_null(^"MudCrane") != null, "A client sees the crane arrive")
	segment._apply_state(MudSegment.State.IDLE, 1.0, 0, false, 0.0, &"crane", 0.0)
	_expect(not status.visible, "...and the board goes away when the truck is free")
	await _free_arena(arena)
	await _check_late_join()


## A peer that joins while the crane is hauling (or arriving) gets the state
## from the host in one packet: the crane has to exist, parked beside the
## truck, and the cable must not sit at the origin.
func _check_late_join() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	await physics_frame
	van.global_position = segment.to_global(Vector3(0.0, 0.8, -24.0))
	segment._apply_state(MudSegment.State.HAULING, 1.0, 0, false, 0.0, &"crane", 0.0)
	_expect(segment.get_node_or_null(^"MudCrane") != null, "Joining mid-haul: the crane is there")
	var crane := segment.get_node_or_null(^"MudCrane") as Node3D
	var truck_gap: float = crane.global_position.distance_to(van.global_position) if crane != null else INF
	_expect(truck_gap < 25.0, "...parked near the truck, not at the origin (%.1f m away)" % truck_gap)
	for _i: int in range(3):
		await process_frame
	var cable := segment.get_node_or_null(^"HaulCable") as Node3D
	_expect(cable != null and cable.visible and cable.global_position.distance_to(van.global_position) < 25.0,
			"...and the cable runs from it to the truck")
	segment._apply_state(MudSegment.State.IDLE, 1.0, 0, false, 0.0, &"crane", 0.0)
	await _free_arena(arena)
	# Joining while the crane is still arriving: it is where the host's is by now.
	arena = _arena(1000.0)
	segment = arena.segment
	van = arena.van
	await physics_frame
	van.global_position = segment.to_global(Vector3(0.0, 0.8, -24.0))
	segment._apply_state(MudSegment.State.CRANE_COMING, 0.4, 0, false, 0.0, &"", 2.0)
	var arriving := segment.get_node_or_null(^"MudCrane") as Node3D
	_expect(arriving != null and is_equal_approx(float(segment.get("_crane_time")), 2.0),
			"Joining mid-arrival puts the crane two thirds of the way in")
	await _free_arena(arena)


## The segment asks the host for its state when it is built on a client
## (rail_crossing_segment.gd does the same): the request itself is an RPC.
func _check_request_state_rpc() -> void:
	var probe := MudSegment.new()
	_expect(probe.has_method(&"_request_state"), "The segment can ask the host for its state")
	probe.free()


# --- Pushing rules --------------------------------------------------------------------


func _check_pusher_rules() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	_expect(await _bog_now(arena), "Bogged for the pusher rules")
	for _i: int in range(10):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	var behind := _player(arena, 4001)
	_expect(segment.can_use_spot(&"push", behind), "A passenger behind the truck can push (the spot's own rule)")
	var down := _player(arena, 4002)
	down._ragdolled = true
	_expect(not segment._may_push(down) and not segment.can_use_spot(&"push", down), "Nobody pushes from a ragdoll")
	var beside := _player(arena, 4003, Vector3(2.4, 0.0, 4.0))
	_expect(not segment._may_push(beside), "Standing level with the cab's side is not behind the truck")
	# Hysteresis: once pushing, a step back still counts; a newcomer at that
	# distance does not start.
	var spot := Vector3(0.0, 0.0, MudSegment.PUSH_SPOT_LOCAL.z)
	behind.global_position = van.global_transform * (spot + Vector3(0.0, 0.0, MudSegment.PUSH_REACH - 0.5))
	segment.set_pusher(4001, true)
	_expect(segment._valid_pushers() == 1, "A pusher inside the reach counts")
	behind.global_position = van.global_transform * (spot + Vector3(0.0, 0.0, MudSegment.PUSH_REACH + 0.3))
	segment.set_pusher(4001, true)
	_expect(segment._valid_pushers() == 1, "...and keeps counting a step past it (hysteresis)")
	var newcomer := _player(arena, 4004, spot + Vector3(0.0, 0.0, MudSegment.PUSH_REACH + 0.3))
	segment.set_pusher(4004, true)
	_expect(segment._valid_pushers() == 1, "...but someone arriving there does not start (still 1)")
	behind.global_position = van.global_transform * (spot + Vector3(0.0, 0.0, MudSegment.PUSH_REACH_STAY + 0.5))
	segment.set_pusher(4001, true)
	_expect(segment._valid_pushers() == 0, "Past the stay distance the push stops")
	behind.free()
	down.free()
	beside.free()
	newcomer.free()
	await _free_arena(arena)


# --- The run ending mid-rescue ------------------------------------------------------------


func _check_run_end() -> void:
	_crew.set(&"team_money", 100)
	var arena: Dictionary = _arena(3.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	_expect(await _bog_now(arena), "Bogged when the run ends")
	var lines_before: int = (_manager.call(&"world_stories") as Array).size()
	_manager.call(&"finish_run", false, "test")
	van.freeze = true
	for _i: int in range(60 * 8):
		await physics_frame
	_expect(segment.state == MudSegment.State.IDLE, "The run ending drops the rescue (state %d)" % segment.state)
	_expect(int(_crew.get(&"team_money")) == 100, "...with no crane fine (balance %d)" % int(_crew.get(&"team_money")))
	_expect(van.freeze, "...and the frozen truck stays frozen past the crane's time")
	_expect(not bool(van.get_meta(&"mud_bogged", false)) and not bool(van.get_meta(&"keep_awake", false)),
			"...and is no longer marked as bogged or kept awake")
	_expect((_manager.call(&"world_stories") as Array).size() == lines_before, "...and leaves no crane story behind")
	_expect(segment.get_node_or_null(^"MudCrane") == null, "...and no crane comes")
	await _free_arena(arena)
	_crew.set(&"team_money", _start_money)
	_manager.set(&"is_running", true)


# --- Grip next to other grip zones ----------------------------------------------------------


func _wheels_slip(van: Node) -> Array[float]:
	var out: Array[float] = []
	for child: Node in van.get_children():
		if child is VehicleWheel3D:
			out.append((child as VehicleWheel3D).wheel_friction_slip)
	return out


func _all_slip(van: Node, expected: float) -> bool:
	for slip: float in _wheels_slip(van):
		if not is_equal_approx(slip, expected):
			return false
	return true


func _put_van(arena: Dictionary, z: float) -> void:
	var van: VehicleBody3D = arena.van
	van.global_position = (arena.segment as MudSegment).to_global(Vector3(0.0, 0.8, z))
	van.linear_velocity = Vector3.ZERO
	for _i: int in range(10):
		await physics_frame


func _check_grip_zones() -> void:
	var arena: Dictionary = _arena(1000.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	var gravel := GravelSegment.new()
	(arena.world as Node).add_child(gravel)
	gravel.position = Vector3(0.0, 0.0, 500.0)
	await physics_frame
	var base: float = _wheels_slip(van)[0]
	# Gravel, then the mud at its seam, then out of the gravel, then out of the mud.
	gravel._on_body_entered(van)
	_expect(_all_slip(van, gravel.reduced_friction_slip), "Gravel lowers the grip")
	await _put_van(arena, -5.0)
	_expect(_all_slip(van, minf(gravel.reduced_friction_slip, segment.reduced_friction_slip)),
			"In both, the lowest of the two holds")
	gravel._on_body_exited(van)
	_expect(_all_slip(van, segment.reduced_friction_slip), "Leaving the gravel leaves the mud's grip, not the gravel's")
	await _put_van(arena, 40.0)
	_expect(_all_slip(van, base), "Out of both, the grip is the original (%s, base %.2f)" % [_wheels_slip(van), base])
	# The other way round: mud first, then the gravel.
	await _put_van(arena, -5.0)
	gravel._on_body_entered(van)
	await _put_van(arena, 40.0)
	_expect(_all_slip(van, gravel.reduced_friction_slip), "Out of the mud into the gravel: the gravel's grip stays")
	gravel._on_body_exited(van)
	_expect(_all_slip(van, base), "...and the original comes back when that one is left too (%s)" % [_wheels_slip(van)])
	await _free_arena(arena)


# --- Once freed, freed -------------------------------------------------------------------------


func _check_one_rescue_per_stretch() -> void:
	_crew.set(&"team_money", 100)
	var arena: Dictionary = _arena(2.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	_expect(await _bog_now(arena), "Bogged for the one-rescue test")
	for _i: int in range(60 * 10):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
		if segment.state == MudSegment.State.IDLE and int(_crew.get(&"team_money")) != 100:
			break
	var after_first: int = int(_crew.get(&"team_money"))
	_expect(after_first == 100 - segment.crane_fine, "The crane fined once (%d)" % after_first)
	# Back into the pit crawling: it does not sink again in this stretch.
	van.global_position = segment.to_global(Vector3(0.0, 0.8, -segment.pit_start - 1.0))
	van.reset_physics_interpolation()
	van.linear_velocity = -van.global_basis.z * 4.0
	for _i: int in range(60 * 5):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
	_expect(segment.state == MudSegment.State.IDLE,
			"A freed truck does not sink again in the same stretch (state %d)" % segment.state)
	_expect(int(_crew.get(&"team_money")) == after_first, "...so there is no second fine")
	await _free_arena(arena)
	_crew.set(&"team_money", _start_money)


# --- Endless: the crane is free ---------------------------------------------------------------------


func _check_endless_crane() -> void:
	_crew.set(&"team_money", 100)
	var mode_before: StringName = _manager.get(&"current_mode")
	_manager.set(&"current_mode", &"endless")
	var arena: Dictionary = _arena(2.0)
	var segment: MudSegment = arena.segment
	var van: VehicleBody3D = arena.van
	_expect(await _bog_now(arena), "Bogged in Endless")
	for _i: int in range(60 * 10):
		van.set_controls(0.0, 0.0, false)
		await physics_frame
		if segment.haul_method == &"crane":
			break
	_expect(segment.haul_method == &"crane", "The crane comes in Endless too")
	for _i: int in range(60 * 6):
		await physics_frame
	_expect(int(_crew.get(&"team_money")) == 100, "...and costs nothing (balance %d)" % int(_crew.get(&"team_money")))
	_expect(_manager.call(&"world_stories").has(tr("WORLD_MUD_STORY_CRANE_FREE")), "...and tells so in the results")
	await _free_arena(arena)
	_manager.set(&"current_mode", mode_before)
	_crew.set(&"team_money", _start_money)


# --- The levels' stuck rules -----------------------------------------------------------


func _check_level_stuck_rules() -> void:
	_network.set(&"world_seed", 4242)
	_network.set(&"world_house_count", 1)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	level.call(&"start_debug_delivery")
	await physics_frame
	var van: VehicleBody3D = level.get(&"vehicle")
	# Stood on the road, well out of the depot and the houses, with the pedal down.
	var route: Node3D = level.get(&"route")
	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	van.global_position = route.to_global(path[3]) + Vector3.UP * 1.0
	van.linear_velocity = Vector3.ZERO
	van.reset_physics_interpolation()
	van.set(&"driver_peer_id", int(_network.call(&"local_id")))
	van.set(&"controls_enabled", false)
	van.set(&"engine_force", -100.0)
	van.set_meta(&"in_mud", false)
	_expect(bool(level.call(&"_should_count_as_stuck")),
			"Pinned on plain road with the pedal down counts as stuck (sanity)")
	van.set_meta(&"in_mud", true)
	_expect(not bool(level.call(&"_should_count_as_stuck")), "In the mud it does not count as stuck")
	van.set_meta(&"in_mud", false)
	level.queue_free()
	await process_frame
	_manager.call(&"reset_run")

	# Endless: nothing to deliver, so being still is what ends it -- except in the mud.
	_network.set(&"world_seed", 0)
	level = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	level.get_node(^"World/RouteStreamer").set(&"segment_scripts", [StraightSegment])
	level.call(&"start_debug_delivery")
	await physics_frame
	van = level.get(&"vehicle")
	van.controls_enabled = false
	van.set_controls(0.0, 0.0, true)
	van.set_meta(&"in_mud", true)
	for _i: int in range(60 * 9):
		van.set_meta(&"in_mud", true)
		await physics_frame
	_expect(bool(_manager.get(&"is_running")), "Endless: 9 s stopped in the mud does not end the run")
	van.set_meta(&"in_mud", false)
	for _i: int in range(60 * 8):
		await physics_frame
	_expect(not bool(_manager.get(&"is_running")),
			"Endless: the same stop outside the mud does end it (the rule still works)")
	level.queue_free()
	await process_frame
	_manager.call(&"reset_run")


# --- Tuning table ------------------------------------------------------------------------


func _measure() -> void:
	_manager.set(&"is_running", true)
	for entry_speed: float in [4.0, 6.0, 8.0, 9.0, 10.0, 12.0, 14.0]:
		var arena: Dictionary = _arena()
		var bogged: bool = await _drive_in(arena, entry_speed)
		var at_z: float = (arena.segment as MudSegment).to_local((arena.van as Node3D).global_position).z
		print("entry %.1f m/s (%.0f km/h): %s at z %.1f" % [
				entry_speed, entry_speed * 3.6, "BOGGED" if bogged else "through", at_z])
		await _free_arena(arena)
	_manager.set(&"is_running", false)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
