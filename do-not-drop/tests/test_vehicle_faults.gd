extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_faults.gd
##
## N-214.1: truck faults (gameplay/vehicle/vehicle_faults.gd), decided by the
## host from the relayed EventBus.vehicle_impact:
## - a soft knock never breaks anything; a hard hit may;
## - the same world seed and the same hits break the same thing on the same
##   hit (deterministic by seed);
## - at most max_faults_per_run per delivery, and run_started resets it;
## - repair() relays vehicle_fault_repaired and every peer's list clears it.
## N-214.2: the effects, on a stand-in van:
## - a broken rear door swings open on the hit and again on every bump after
##   the crew closes it; soft knocks under door_pop_strength don't;
## - a broken mirror hides the driver's-side (-X) mirror parts only, leaves a
##   piece on the road, and a repair puts them back.
## N-214.3: the repair spots hung on the stand-in van:
## - they only offer a fix while their fault is active;
## - the rear door ties shut with a strap from the shared kit, which spends it;
##   with no strap and no spare, nothing fixes it;
## - the depot's spare part (a CrewProgression supply) fixes the door (only
##   when the kit has no strap) or the mirror and is used up; run_ended drops
##   the spares left.
## N-214.3b: the mirror's improvised fix, a passenger's phone:
## - offered only without a spare, never to the driver, one phone at a time;
## - the fault stays active and a phone shows where the mirror was;
## - walking away lets go; a spare mirror ends it;
## - a peer joining mid-run gets the faults (drawn without debris), the spares
##   and who holds the phone.
## N-214.4: each fault's line for the results screen (result_stories(), read
## by RunManager.world_stories()): how it was fixed, "replaced by a phone"
## even after letting go, or left broken (the door, with how many times it
## swung open); run_started clears them.

## Loaded at run time: the script uses the EventBus autoload, which a
## SceneTree test can't resolve while it compiles.
const VEHICLE_FAULTS_PATH: String = "res://scripts/gameplay/vehicle/vehicle_faults.gd"

var _failures: int = 0
var _started: Array = []
var _repaired: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	bus.connect(&"vehicle_fault_started", func(id: StringName, _at: Vector3) -> void: _started.append(id))
	bus.connect(&"vehicle_fault_repaired", func(id: StringName, how: StringName) -> void: _repaired.append([id, how]))
	var faults_script: Script = load(VEHICLE_FAULTS_PATH)
	var faults: Node = faults_script.new()
	root.add_child(faults)
	await process_frame

	# Soft knocks: nothing breaks, however many.
	faults.set(&"fault_chance", 1.0)
	for i: int in 20:
		bus.relay(&"vehicle_impact", [4.0, Vector3.ZERO])
	_expect(_started.is_empty(), "A pothole-sized knock never breaks anything")

	# A sure hard hit breaks one thing; the cap stops the rest.
	bus.relay(&"vehicle_impact", [12.0, Vector3(1, 0, 2)])
	bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	_expect(_started.size() == 1, "At most one fault per delivery (got %d)" % _started.size())
	var broken: StringName = _started[0] if not _started.is_empty() else &""
	_expect(broken in [&"rear_door", &"mirror"], "The fault is one of this version's two")
	_expect(bool(faults.call(&"is_broken", broken)), "Every peer's list has the fault")

	# Repair, relayed; a second repair does nothing.
	_expect(bool(faults.call(&"repair", broken, &"kit")), "The host can repair a broken fault")
	_expect(_repaired == [[broken, &"kit"]], "The repair is relayed with how it was done")
	_expect(not bool(faults.call(&"is_broken", broken)), "A repaired fault leaves the list")
	_expect(not bool(faults.call(&"repair", broken, &"kit")), "Repairing an intact part does nothing")
	bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	_expect(_started.size() == 1, "A repaired fault still counts toward the cap")

	# A new run resets the cap; with a cap of two, both faults can break, then no more.
	bus.emit_signal(&"run_started", &"test", [])
	faults.set(&"max_faults_per_run", 2)
	_started.clear()
	for i: int in 4:
		bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	_expect(_started.size() == 2 and _started[0] != _started[1],
			"Two different faults with a cap of two (got %s)" % [_started])

	# Deterministic by seed: same seed, same hits, same result.
	faults.set(&"fault_chance", 0.5)
	faults.set(&"max_faults_per_run", 1)
	var first: Array = _hits_with_seed(faults, network, 4242)
	var second: Array = _hits_with_seed(faults, network, 4242)
	_expect(first == second and not first.is_empty(),
			"Same seed and hits break the same thing on the same hit (%s vs %s)" % [first, second])
	var seen_any: bool = false
	for world_seed: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		seen_any = seen_any or not _hits_with_seed(faults, network, world_seed).is_empty()
	_expect(seen_any, "A 50% chance does break something across a few seeds")

	faults.queue_free()
	await process_frame
	await _check_effects(bus, faults_script)
	await _check_repairs(bus, faults_script)
	if _failures == 0:
		print("PASS: truck faults break on hard hits only, one per delivery, repeat by seed,"
				+ " repair on every peer, show on the van, get fixed with the kit, a spare or a held phone,"
				+ " and reach a peer that joins mid-run")
	quit(_failures)


## N-214.2 on a stand-in van: the door that won't stay shut and the mirror.
func _check_effects(bus: Node, faults_script: Script) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var van := FakeVan.new()
	world.add_child(van)
	var parts: Dictionary = {}
	for part_name: String in ["MirrorHousing_Left", "MirrorSurface_Left", "MirrorHousing_Right", "MirrorSurface_Right"]:
		var part := MeshInstance3D.new()
		part.name = part_name
		part.mesh = BoxMesh.new()
		part.position = Vector3(-1.3 if part_name.ends_with("Left") else 1.3, 2.0, -2.5)
		van.add_child(part)
		parts[part_name] = part
	var faults: Node = faults_script.new()
	faults.set(&"vehicle", van)
	world.add_child(faults)
	await process_frame

	# Rear door: open on the hit, and again on a bump once the crew closes it.
	bus.relay(&"vehicle_fault_started", [&"rear_door", Vector3.ZERO])
	_expect(van.rear_open, "The broken rear door swings open on the hit")
	van.rear_open = false
	bus.relay(&"vehicle_impact", [3.5, Vector3.ZERO])
	_expect(not van.rear_open, "A knock under door_pop_strength leaves it shut")
	bus.relay(&"vehicle_impact", [5.0, Vector3.ZERO])
	_expect(van.rear_open, "A bump swings the broken door open again")
	_expect(int(faults.get(&"door_pops")) == 2, "Two pops counted (got %d)" % int(faults.get(&"door_pops")))
	faults.call(&"repair", &"rear_door", &"kit")
	van.rear_open = false
	bus.relay(&"vehicle_impact", [6.0, Vector3.ZERO])
	_expect(not van.rear_open, "A repaired door stays shut on bumps")

	# Mirror: the driver's side (-X) breaks off, a piece lands on the road, repair restores it.
	var before: int = world.get_child_count()
	bus.relay(&"vehicle_fault_started", [&"mirror", Vector3.ZERO])
	_expect(not parts["MirrorHousing_Left"].visible and not parts["MirrorSurface_Left"].visible,
			"The driver's-side mirror is gone")
	_expect(parts["MirrorHousing_Right"].visible and parts["MirrorSurface_Right"].visible,
			"The passenger-side mirror stays")
	_expect(world.get_child_count() == before + 2, "The broken-off pieces are left in the world")
	faults.call(&"repair", &"mirror", &"shop")
	_expect(parts["MirrorHousing_Left"].visible and parts["MirrorSurface_Left"].visible,
			"A repair puts the mirror back")
	world.queue_free()
	await process_frame


## N-214.3 on a stand-in van: the repair spots, the kit's strap and the spare.
func _check_repairs(bus: Node, faults_script: Script) -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	var crew: Node = root.get_node(^"/root/CrewProgression")
	_expect((crew.get(&"SUPPLIES") as Dictionary).has(&"spare_part"), "The depot sells a spare part")
	var world := Node3D.new()
	root.add_child(world)
	var van := FakeVan.new()
	world.add_child(van)
	var mirror_part := MeshInstance3D.new()
	mirror_part.name = "MirrorHousing_Left"
	mirror_part.position = Vector3(-1.3, 2.0, -2.5)
	van.add_child(mirror_part)
	var faults: Node = faults_script.new()
	faults.set(&"vehicle", van)
	world.add_child(faults)
	await process_frame
	var door: Node = van.get_node_or_null(^"FaultRepair_rear_door")
	var mirror: Node3D = van.get_node_or_null(^"FaultRepair_mirror")
	_expect(door != null and mirror != null, "A repair spot hangs on the van for each fault")
	if door == null or mirror == null:
		world.queue_free()
		return
	_expect(mirror.position.is_equal_approx(mirror_part.position), "The mirror's spot sits on the driver's mirror")
	var player := Node3D.new()
	world.add_child(player)
	_expect(not bool(door.call(&"can_interact", player)), "An intact door offers no repair")

	# The kit's strap ties the door shut and is spent.
	_repaired.clear()
	(run.get(&"care_supplies") as Dictionary)[&"strap"] = 1
	bus.relay(&"vehicle_fault_started", [&"rear_door", Vector3.ZERO])
	_expect(String(door.call(&"get_prompt")) == tr("WORLD_FAULT_REAR_DOOR_STRAP"), "The door offers the strap")
	door.call(&"interact", player)
	_expect(_repaired == [[&"rear_door", &"strap"]], "The door is fixed with the strap (got %s)" % [_repaired])
	_expect(int(run.call(&"care_supply_count", &"strap")) == 0, "The strap is spent")

	# No strap and no spare: nothing fixes it.
	bus.relay(&"vehicle_fault_started", [&"rear_door", Vector3.ZERO])
	_expect(not bool(door.call(&"can_interact", player)), "Without a strap or a spare the door can't be fixed")
	door.call(&"interact", player)
	_expect(bool(faults.call(&"is_broken", &"rear_door")), "The door stays broken")

	# The spare part fixes it and is used up.
	faults.call(&"stock_spares", 1)
	(run.get(&"care_supplies") as Dictionary)[&"strap"] = 1
	_expect(StringName(faults.call(&"repair_method", &"rear_door")) == &"strap",
			"The kit's strap goes before the paid spare")
	(run.get(&"care_supplies") as Dictionary)[&"strap"] = 0
	_expect(StringName(faults.call(&"repair_method", &"rear_door")) == &"spare", "Without a strap, the spare")
	door.call(&"interact", player)
	_expect(_repaired.back() == [&"rear_door", &"spare"], "The door is fixed with the spare")
	_expect(int(faults.get(&"spares")) == 0, "The spare is used up")

	# The mirror without a spare: a passenger holds their phone up instead.
	var me: int = player.get_multiplayer_authority()
	bus.relay(&"vehicle_fault_started", [&"mirror", Vector3.ZERO])
	_expect(String(mirror.call(&"get_prompt")) == tr("WORLD_FAULT_MIRROR_PHONE"),
			"Without a spare the mirror offers the phone")
	van.driver_peer_id = me
	_expect(not bool(mirror.call(&"can_interact", player)), "The driver can't hold the phone")
	van.driver_peer_id = 0
	player.position = mirror.position
	mirror.call(&"interact", player)
	_expect(int(faults.get(&"phone_holder_id")) == me, "A passenger holds the phone up")
	_expect(bool(faults.call(&"is_broken", &"mirror")), "The phone isn't a repair: the mirror stays broken")
	var phone: Node3D = van.get_node_or_null(^"PhoneMirror")
	_expect(phone != null and phone.visible, "A phone shows where the mirror was")
	_expect(not bool(mirror.call(&"can_interact", player)), "One phone at a time")
	await physics_frame
	_expect(int(faults.get(&"phone_holder_id")) == me, "Staying by the mirror keeps it held")
	player.position = Vector3(0.0, 0.0, 20.0)
	await physics_frame
	_expect(int(faults.get(&"phone_holder_id")) == 0 and phone != null and not phone.visible,
			"Walking away lets go of the phone")
	player.position = mirror.position
	mirror.call(&"interact", player)
	faults.call(&"stock_spares", 2)
	_expect(StringName(faults.call(&"repair_method", &"mirror")) == &"spare", "A spare mirror goes before the phone")
	mirror.call(&"interact", player)
	_expect(_repaired.back() == [&"mirror", &"spare"] and int(faults.get(&"spares")) == 1,
			"The spare mirror goes on and one spare is left")
	_expect(int(faults.get(&"phone_holder_id")) == 0 and not phone.visible, "The spare mirror ends the phone's watch")

	# N-214.4: the results tell how each fault ended, through RunManager.
	var told: Array = faults.call(&"result_stories")
	_expect(told == [tr("WORLD_FAULT_STORY_REAR_DOOR_SPARE"), tr("WORLD_FAULT_STORY_MIRROR_SPARE")],
			"The results tell each fault's fix, in break order (got %s)" % [told])
	_expect(tr("WORLD_FAULT_STORY_MIRROR_SPARE") in (run.call(&"world_stories") as Array),
			"RunManager's results read the faults' lines")
	faults.call(&"reset_for_run")
	_expect((faults.call(&"result_stories") as Array).is_empty(), "A new run starts with no fault to tell")
	bus.relay(&"vehicle_fault_started", [&"mirror", Vector3.ZERO])
	_expect(faults.call(&"result_stories") == [tr("WORLD_FAULT_STORY_MIRROR_LOST")],
			"An unfixed mirror is told as lost")
	_expect(bool(faults.call(&"hold_phone", player)), "A passenger can hold the phone up")
	player.position = Vector3(0.0, 0.0, 20.0)
	await physics_frame
	_expect(faults.call(&"result_stories") == [tr("WORLD_FAULT_STORY_MIRROR_PHONE")],
			"A mirror held up by a phone is told as replaced by it, even after letting go")
	van.rear_open = false
	bus.relay(&"vehicle_fault_started", [&"rear_door", Vector3.ZERO])
	var pops: int = int(faults.get(&"door_pops"))
	var door_line: String = tr("WORLD_FAULT_STORY_REAR_DOOR_OPEN") % pops
	_expect(pops == 1 and (faults.call(&"result_stories") as Array).back() == door_line,
			"An unfixed door is told with how many times it swung open")
	player.position = mirror.position

	# A peer joining mid-run: the faults as they stand, without a new crack.
	faults.call(&"reset_for_run")
	var children: int = world.get_child_count()
	faults.call(&"_receive_state", [&"mirror", &"rear_door"], 1, 7)
	_expect(bool(faults.call(&"is_broken", &"mirror")) and bool(faults.call(&"is_broken", &"rear_door")),
			"The joiner gets the active faults")
	_expect(int(faults.get(&"spares")) == 1 and int(faults.get(&"phone_holder_id")) == 7,
			"The joiner gets the spares and who holds the phone")
	_expect(not mirror_part.visible and world.get_child_count() == children,
			"The joiner's mirror is gone without debris falling again")
	bus.emit_signal(&"run_ended", 0, {})
	_expect(int(faults.get(&"spares")) == 0, "The run's end drops the spares left")
	(run.get(&"care_supplies") as Dictionary)[&"strap"] = 2
	world.queue_free()
	await process_frame


## Stands in for vehicle.gd's door API (the only part of the van faults touch).
class FakeVan extends Node3D:
	var rear_open: bool = false
	var driver_peer_id: int = 0

	func is_door_open(door: StringName) -> bool:
		return rear_open if door == &"rear" else false

	func set_rear_cargo_open(open: bool) -> void:
		rear_open = open


## Ten hard hits on a fresh run with world_seed: [hit index, fault] of what broke.
func _hits_with_seed(faults: Node, network: Node, world_seed: int) -> Array:
	network.set(&"world_seed", world_seed)
	faults.call(&"reset_for_run")
	_started.clear()
	var result: Array = []
	for i: int in 10:
		root.get_node(^"/root/EventBus").relay(&"vehicle_impact", [12.0, Vector3.ZERO])
		if not _started.is_empty() and result.is_empty():
			result = [i, _started[0]]
	return result


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
