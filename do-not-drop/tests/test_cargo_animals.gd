extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cargo_animals.gd
##
## N-109, the animals that go for the cargo (route/cargo_animals.gd, the plan in
## cargo_animal_plan.gd, the drawing in cargo_animal_view.gd, the stick in
## dog_distract_point.gd), with the real level, truck and boxes:
## - the plan comes from the session seed alone: the same seed deals the same
##   legs, other seeds deal others; the first leg is quiet, no two legs in a
##   row have one, all three animals turn up;
## - nothing acts without warning: the alert (EventBus.cargo_animal_alert, with
##   its cry, icon and HUD banner) comes WARN seconds before the animal starts,
##   and the horn already works during the warning;
## - GULL (.1): its own white-and-grey model with a yellow beak, wings spread in
##   flight and folded perched; with nobody holding the box it throws it out of the rear doors
##   onto the road -- still loaded, so it falls into N-213's rescue window, not
##   ruined; a box held (its passenger's primary, or picked up) or the horn
##   sends it off; it needs the rear doors open;
## - DOG (.2): it goes for an open box at a stop by a house and wears it down;
##   the horn, the lid, or "Tirarle un palo" (anyone with free hands) end it;
## - BEES (.3): they go for an open cake in open country, wear it down and
##   shove it; the lid, the horn or leaving the meadow end it;
## - the harm to the box happens only on the host: a peer that is not the host
##   never announces or hurts anything (but draws what the host relays), and
##   one that joins late is told again without restarting the animal;
## - rhythm: one animal per leg, at most MAX_PER_RUN a run, the pick among
##   boxes does not depend on the order of the list, and none is announced
##   while the last one is still leaving.

## The director and its view are only named at run time: naming their classes
## here would compile them (and the boxes and players they use) before the
## autoloads exist. The numbers below mirror CargoAnimals.Phase and
## CargoAnimalView.State.
const PHASE_IDLE: int = 0
const PHASE_ANNOUNCED: int = 1
const PHASE_ACTING: int = 2
const VIEW_NONE: int = 0
const VIEW_WARN: int = 1
const VIEW_ACT: int = 2
const VIEW_LEAVE: int = 3

var _failures: int = 0
var _animals_constants: Dictionary = {}
var _alerts: Array = []
var _ended: Array = []
var _banners: Array = []
var _damaged: Array = []
var _overboard: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_plan()
	_test_sounds()
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"cargo_animal_alert", func(kind: StringName, id: StringName, warn: float, act: float) -> void:
		_alerts.append([kind, id, warn, act]))
	bus.connect(&"cargo_animal_ended", func(kind: StringName, id: StringName, outcome: StringName, peer: int) -> void:
		_ended.append([kind, id, outcome, peer]))
	bus.connect(&"route_event_started", func(id: StringName, event: Dictionary) -> void:
		_banners.append([id, event]))
	bus.connect(&"package_damaged", func(id: StringName, amount: float) -> void: _damaged.append([id, amount]))
	bus.connect(&"cargo_overboard", func(id: StringName, _at: Vector3, _seconds: float) -> void: _overboard.append(id))

	_animals_constants = (load("res://scripts/gameplay/route/cargo_animals.gd") as Script).get_script_constant_map()
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var manager: Node = root.get_node(^"/root/RunManager")
	var player: Node = level.local_player
	var vehicle: RigidBody3D = level.get_node(^"World/Vehicle")
	var animals: Node = level.get_node(^"CargoAnimals")
	var view: Node = animals.view
	var package: Node = level.packages[0]
	var pickup: Node = package.get_node(^"InteractionArea")
	var mount: Node = vehicle.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea")
	var seat: Node = vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	vehicle.call(&"set_door_open", &"cab_left", true)
	pickup.interact(player)
	mount.interact(player)
	seat.interact(player)
	player.call(&"leave_seat")
	_expect(bool(manager.get(&"is_running")), "The run starts with the box aboard")
	_expect(bool(package.is_loaded), "The box sits on the rack")
	_expect(level.get_node_or_null(^"CargoAnimals") != null, "Every level carries the animals' director")

	await _test_gull(level, animals, view, vehicle, package, player, bus)
	await _test_dog(level, animals, view, vehicle, package, player, bus)
	await _test_bees(level, animals, view, vehicle, package, bus)
	await _test_client(level, animals, view, vehicle, package)
	_test_rhythm(level, animals, vehicle)

	level.queue_free()
	manager.call(&"reset_run")
	await process_frame
	if _failures == 0:
		print("PASS: gull, dog and bees are announced, can be stopped, and only the host hurts the box")
	quit(_failures)


# --- The plan ------------------------------------------------------------------

func _test_plan() -> void:
	var first: Array[Dictionary] = CargoAnimalPlan.for_run(4711, 40)
	var second: Array[Dictionary] = CargoAnimalPlan.for_run(4711, 40)
	_expect(first == second, "The same seed deals the same legs")
	var differs: bool = false
	for other_seed: int in [1, 2, 3, 99, 12345]:
		if CargoAnimalPlan.for_run(other_seed, 40) != first:
			differs = true
	_expect(differs, "Other seeds deal other legs")
	var kinds: Dictionary = {}
	var with_animal: int = 0
	var legs_total: int = 0
	var in_a_row: bool = false
	var early: bool = false
	for world_seed: int in range(1, 41):
		var plans: Array[Dictionary] = CargoAnimalPlan.for_run(world_seed * 7919, 24)
		early = early or not plans[0].is_empty()
		for leg: int in range(plans.size()):
			legs_total += 1
			if plans[leg].is_empty():
				continue
			with_animal += 1
			kinds[plans[leg]["kind"]] = true
			var seconds: float = float(plans[leg]["moving_seconds"])
			_expect(seconds >= CargoAnimalPlan.MIN_MOVING_SECONDS and seconds <= CargoAnimalPlan.MAX_MOVING_SECONDS,
				"The moment is inside its window (got %s)" % seconds)
			if leg > 0 and not plans[leg - 1].is_empty():
				in_a_row = true
	_expect(not early, "The first leg is always quiet")
	_expect(not in_a_row, "No two legs in a row have an animal")
	_expect(kinds.has(CargoAnimalPlan.GULL) and kinds.has(CargoAnimalPlan.DOG) and kinds.has(CargoAnimalPlan.BEES),
		"All three animals turn up across seeds (got %s)" % [kinds.keys()])
	var share: float = float(with_animal) / legs_total
	_expect(share > 0.2 and share < 0.5, "Animals are rare: some legs, not most (got %.2f)" % share)


func _test_sounds() -> void:
	var cry: AudioStreamWAV = CargoAnimalSounds.gull_cry()
	var buzz: AudioStreamWAV = CargoAnimalSounds.bee_buzz()
	_expect(cry.data.size() > 1000 and _has_signal(cry), "The gull's cry is real audio")
	_expect(buzz.data.size() > 1000 and _has_signal(buzz), "The bees' buzz is real audio")
	_expect(buzz.loop_mode == AudioStreamWAV.LOOP_FORWARD and buzz.loop_end == buzz.data.size() / 2,
		"The buzz loops over its whole length")
	_expect(CargoAnimalSounds.gull_cry() == cry, "Each sound is built once and shared")
	# Measured like the rest of the mix (test_world_audio_levels.gd): the cry is a
	# "signal" (loudest 100 ms, -18 dBFS), the buzz a "noise" bed (RMS, -35 dBFS).
	var mix: Script = load("res://scripts/presentation/world_mix.gd")
	var levels: Dictionary = mix.get_script_constant_map()
	var measure: Script = load("res://tests/test_world_audio_levels.gd")
	var cry_at: float = float(measure.call(&"measure_dbfs", cry, "loudest")) + float(levels[&"GULL_CRY_DB"])
	var buzz_at: float = float(measure.call(&"measure_dbfs", buzz, "rms")) + float(levels[&"BEE_BUZZ_DB"])
	_expect(absf(cry_at + 18.0) <= 2.0, "The gull's cry sits in the signal class (got %.1f dBFS)" % cry_at)
	_expect(absf(buzz_at + 35.0) <= 2.0, "The bees' buzz sits in the noise bed (got %.1f dBFS)" % buzz_at)


# --- The gull ------------------------------------------------------------------

func _test_gull(level: Node, animals: Node, view: Node, vehicle: RigidBody3D,
		package: Node, player: Node, bus: Node) -> void:
	_drive(vehicle, 15.0)
	_expect(vehicle.linear_velocity.length() >= _animals_const(&"MOVING_SPEED"),
			"The truck is driving (got %s)" % vehicle.linear_velocity.length())
	# Nothing planned for this leg: nothing comes.
	_force_plan(animals, {})
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE and _alerts.is_empty(), "A quiet leg has no gull")

	# Announced first.
	_force_plan(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	animals.advance(1.0)
	_expect(animals.phase == PHASE_ANNOUNCED and animals.kind == CargoAnimalPlan.GULL,
		"The gull is announced before it acts (phase %s)" % animals.phase)
	_expect(_alerts.size() == 1 and _alerts[0][0] == CargoAnimalPlan.GULL and _alerts[0][1] == package.package_id,
		"The alert names the animal and the box (got %s)" % [_alerts])
	_expect(float(_alerts[0][2]) >= 2.0 and float(_alerts[0][3]) >= 4.0,
		"It gives seconds of warning and seconds to react (got %s)" % [_alerts[0]])
	var banner: Dictionary = _banners[-1][1] if not _banners.is_empty() else {}
	_expect(bool(banner.get("incident", false)) and String(banner.get("title", "")) == "WORLD_GULL_ALERT_TITLE",
		"The HUD banner says a gull is coming")
	_expect(package.is_loaded and _box_in_bay(vehicle, package), "During the warning the box is still on its rack")
	await process_frame
	_expect(view.state == VIEW_WARN and view.animal != null and view.icon != null,
		"Every peer draws the gull swooping in with an icon over the box")
	_expect(view.icon.text.contains(tr("WORLD_GULL_ICON")),
			"The icon reads the animal's name (got %s)" % view.icon.text)
	_expect(view.animal.get_node_or_null(^"Voice") != null, "The gull has its cry")
	_test_gull_model(view.animal)

	# The horn works during the warning already.
	bus.call(&"request_horn")
	_expect(animals.phase == PHASE_IDLE and _ended.size() == 1 and _ended[0][2] == &"scared",
		"A honk during the warning scares it off (got %s)" % [_ended])
	await process_frame
	_expect(view.state == VIEW_LEAVE, "It flies away, drawn on every peer")

	# Held: the passenger's primary counts.
	_new_leg(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	animals.advance(1.0)
	for step: int in range(4):
		animals.advance(1.0)
	_expect(animals.phase == PHASE_ACTING, "After the warning it goes for the box (phase %s)" % animals.phase)
	package.player_input = {"steady_strength": 1.0, "steady": true}
	animals.advance(0.6)
	_expect(animals.phase == PHASE_ACTING, "A moment of holding is not yet enough")
	animals.advance(0.6)
	_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == &"held",
		"Holding the box sends the gull off (got %s)" % [_ended[-1]])
	_expect(package.is_loaded and _box_in_bay(vehicle, package), "A held box stays where it was")
	package.player_input = {}

	# Doors shut: it can't get in.
	_new_leg(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	vehicle.call(&"set_door_open", &"rear", false)
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE, "With the rear doors shut the gull does not come")
	vehicle.call(&"set_door_open", &"rear", true)

	# Left alone: it throws the box out, into the rescue window.
	_new_leg(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	_alerts.clear()
	animals.advance(1.0)
	animals.advance(3.5)
	_expect(animals.phase == PHASE_ACTING, "Its time to act begins after the warning")
	var integrity_before: float = package.integrity
	animals.advance(3.0)
	_expect(animals.phase == PHASE_ACTING, "It gives the crew its seconds before it takes the box")
	animals.advance(3.5)
	_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == &"snatched",
		"Nobody stops it: the gull takes the box (got %s)" % [_ended[-1]])
	_expect(not _box_in_bay(vehicle, package), "The box is out of the truck")
	var relative: Vector3 = vehicle.global_basis.inverse() * (package.linear_velocity - vehicle.linear_velocity)
	_expect(relative.z > 1.0, "It leaves out the back, toward the road (got %s)" % relative)
	_expect(bool(package.is_loaded), "It is still loaded, so the overboard window takes it (N-213)")
	_expect(int(package.trap_state) != ITrapBehavior.TrapState.RUINED
			and is_equal_approx(package.integrity, integrity_before),
		"The throw itself does not ruin it (integrity %s of %s)" % [package.integrity, integrity_before])
	_overboard.clear()
	package.global_position = vehicle.global_position + Vector3(0.0, 0.5, 20.0)
	level._check_lost_cargo()
	_expect(_overboard == [package.package_id], "It opens the rescue window (got %s)" % [_overboard])
	# Back on the rack for the next parts.
	_put_back(level, package, vehicle, player)


## The gull reads as one (N-109 visual review): a white bird with a yellow beak,
## grey wings with dark tips, spread when it swoops and folded when it perches.
func _test_gull_model(gull: Node) -> void:
	_expect(gull is CargoGull, "The gull is drawn by its own model, not the roadside bird")
	var beak := gull.get_node_or_null(^"Body/HeadGroup/Beak") as MeshInstance3D
	var torso := gull.get_node_or_null(^"Body/Torso") as MeshInstance3D
	var wing := gull.get_node_or_null(^"Body/WingL") as Node3D
	var wing_right := gull.get_node_or_null(^"Body/WingR") as Node3D
	_expect(beak != null and torso != null and wing != null and wing_right != null,
			"It has a beak, a body and two wings")
	if beak == null or torso == null or wing == null or wing_right == null:
		return
	var beak_colour: Color = (beak.material_override as StandardMaterial3D).albedo_color
	var torso_colour: Color = (torso.material_override as StandardMaterial3D).albedo_color
	_expect(beak_colour.r > 0.8 and beak_colour.g > 0.6 and beak_colour.b < 0.3,
			"The beak is yellow (got %s)" % beak_colour)
	_expect(torso_colour.get_luminance() > 0.85, "The body is white (got %s)" % torso_colour)
	var gull_b := CargoGull.new()
	_expect(gull_b.get_node("Body/Torso").material_override == torso.material_override,
		"Every gull shares its materials")
	gull_b.free()
	gull.call(&"pose", true, 0.05)
	var open_wing: Vector3 = (wing.basis * Vector3(-1.0, 0.0, 0.0)).normalized()
	gull.call(&"pose", false, 0.05)
	var folded_wing: Vector3 = (wing.basis * Vector3(-1.0, 0.0, 0.0)).normalized()
	_expect(absf(open_wing.dot(Vector3(-1.0, 0.0, 0.0))) > 0.7 and absf(folded_wing.dot(Vector3(0.0, 0.0, 1.0))) > 0.7,
		"The wings spread across when it flies and fold back along the body when it perches")
	var symmetric: bool = is_equal_approx(wing.rotation.y, -wing_right.rotation.y)
	_expect(symmetric, "Both wings fold the same way")


# --- The dog -------------------------------------------------------------------

func _test_dog(_level: Node, animals: Node, view: Node, vehicle: RigidBody3D,
		package: Node, player: Node, bus: Node) -> void:
	_drive(vehicle, 0.0)
	var stop := Node3D.new()
	root.add_child(stop)
	stop.global_position = vehicle.global_position
	animals.houses = [stop]
	package.set_open(false)
	_new_leg(animals, {"kind": CargoAnimalPlan.DOG, "moving_seconds": 0.0})
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE, "A closed box is not for the dog")
	package.set_open(true)
	_expect(package.is_open, "The box is open")
	_alerts.clear()
	animals.advance(1.0)
	_expect(animals.phase == PHASE_ANNOUNCED and animals.kind == CargoAnimalPlan.DOG,
		"The dog comes for an open box at a stop, announced (phase %s)" % animals.phase)
	_expect(_alerts.size() == 1 and _alerts[0][0] == CargoAnimalPlan.DOG, "The alert names the dog")
	await process_frame
	_expect(view.animal != null and view.animal.get_node_or_null(^"Voice") != null, "The dog barks as it comes")
	_expect(view.dog_point != null and view.dog_point.active, "It can be sent off while it comes")
	var integrity_before: float = package.integrity
	animals.advance(2.0)
	_expect(is_equal_approx(package.integrity, integrity_before), "During the warning the box is untouched")
	animals.advance(2.0)
	_expect(animals.phase == PHASE_ACTING, "Then it climbs on")
	for step: int in range(8):
		animals.advance(0.5)
	_expect(package.integrity < integrity_before - 5.0,
		"The dog wears the box down (from %s to %s)" % [integrity_before, package.integrity])
	_expect(not _damaged.is_empty(), "The wear is reported like any other damage")
	# Throw it a stick.
	await process_frame
	var point: Node = view.dog_point
	_expect(point != null and point.get_prompt() == tr("WORLD_DOG_THROW_PROMPT"), "The dog offers 'throw it a stick'")
	_expect(point.can_interact(player), "Free hands can throw it")
	_expect(view.animal.scale.x > 1.2, "The dog is drawn bigger than life so it reads from the rear doors")
	_tick_view(view, 4.0)
	var beside: Vector3 = vehicle.to_local(view.animal.global_position)
	_expect(beside.x > vehicle.to_local(package.global_position).x + 0.5 and beside.y > -0.1,
		"It stands in the aisle on the floor of the bay, by the box (got %s)" % beside)
	# Standing next to the rear-door control, looked at from two steps away, the
	# prompt is still the dog's: the control is closer and would take it.
	var control: Node = vehicle.get_node(^"CargoBay/RearDoorControl")
	var camera: Camera3D = player.get_node(^"Head/Camera3D")
	var old_nearby: Array[Node] = player._nearby.duplicate()
	player._nearby.clear()
	player._nearby.append(control)
	player._nearby.append(point)
	camera.global_position = vehicle.to_global(Vector3(0.45, 1.6, 5.9))
	camera.look_at(point.global_position)
	_expect(player.call(&"_closest_interactable") == point,
			"Aiming at the dog offers the stick, not the rear-door control")
	player._nearby.clear()
	player._nearby.append_array(old_nearby)
	var carried: Variant = player.get(&"carried_package")
	player.set(&"carried_package", package)
	_expect(not point.can_interact(player), "With a box in the arms there is no throwing a stick")
	player.set(&"carried_package", carried)
	point.interact(player)
	_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == &"distracted",
		"Throwing the stick sends the dog after it (got %s)" % [_ended[-1]])
	await process_frame
	_expect(view.state == VIEW_LEAVE and is_instance_valid(view.get_node_or_null(^"Stick")),
		"The stick flies and the dog runs off")
	_tick_view(view, 4.0)
	await process_frame
	_expect(view.state == VIEW_NONE and view.animal == null, "The dog is gone and everything it made is freed")

	# The honk, the lid, and picking the box up also end it.
	for way: String in ["horn", "lid", "lifted"]:
		_new_leg(animals, {"kind": CargoAnimalPlan.DOG, "moving_seconds": 0.0})
		package.set_open(true)
		animals.advance(1.0)
		animals.advance(4.0)
		var expected: StringName = &"scared"
		match way:
			"horn":
				bus.call(&"request_horn")
			"lid":
				package.set_open(false)
				animals.advance(0.2)
				expected = &"sealed"
			"lifted":
				package.is_held = true
				animals.advance(0.2)
				package.is_held = false
				expected = &"held"
		_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == expected,
			"The dog goes when the box is %s (got %s)" % [way, _ended[-1]])
	package.set_open(false)
	# Without being stopped it leaves on its own after a while (never for good).
	_new_leg(animals, {"kind": CargoAnimalPlan.DOG, "moving_seconds": 0.0})
	package.set_open(true)
	animals.advance(1.0)
	animals.advance(3.5)
	_expect(animals.phase == PHASE_ACTING, "It is on the box again")
	animals.set(&"_timer", 0.1)
	animals.advance(0.2)
	_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == &"left", "A dog nobody chases gets bored and leaves")
	var acting: float = float((_animals_const(&"ACT_SECONDS") as Dictionary)[CargoAnimalPlan.DOG])
	var most: float = acting * float(_animals_const(&"DOG_DAMAGE_PER_SECOND"))
	_expect(most < 100.0, "Even left alone for its whole time the dog does not ruin a box outright (%s)" % most)
	package.set_open(false)
	stop.free()
	animals.houses = []
	await process_frame


# --- The bees ------------------------------------------------------------------

func _test_bees(_level: Node, animals: Node, view: Node, vehicle: RigidBody3D,
		package: Node, bus: Node) -> void:
	_drive(vehicle, 12.0)
	var meadow: Array = [true]
	animals.zone_probe = func(_at: Vector3) -> bool: return bool(meadow[0])
	package.content = load("res://data/contents/wedding_cake.tres")
	package.set_open(false)
	_new_leg(animals, {"kind": CargoAnimalPlan.BEES, "moving_seconds": 0.0})
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE, "A closed cake is not for the bees")
	package.set_open(true)
	meadow[0] = false
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE, "Outside open country the bees do not come")
	meadow[0] = true
	_alerts.clear()
	animals.advance(1.0)
	_expect(animals.phase == PHASE_ANNOUNCED and animals.kind == CargoAnimalPlan.BEES,
		"An open cake in the meadow draws the bees, announced (phase %s)" % animals.phase)
	await process_frame
	_expect(view.bees != null and view.bees.multimesh.instance_count >= 12, "The swarm is drawn, with bees to be seen")
	_expect(view.bees.multimesh.mesh == CargoBeeMesh.mesh(), "Every bee is the one shared striped, winged mesh")
	_expect(_bee_has_both_colours(CargoBeeMesh.mesh()),
			"Each bee is yellow with black on it, and has see-through wings")
	var integrity_before: float = package.integrity
	animals.advance(3.5)
	_expect(animals.phase == PHASE_ACTING and is_equal_approx(package.integrity, integrity_before),
		"Only after the warning do they harm the cake")
	var spin_before: Vector3 = package.angular_velocity
	for step: int in range(8):
		animals.advance(0.5)
	_expect(package.integrity < integrity_before - 5.0,
		"They wear the cake down (from %s to %s)" % [integrity_before, package.integrity])
	_expect(package.freeze or package.angular_velocity != spin_before, "They shove the box so it tilts")
	package.set_open(false)
	animals.advance(0.2)
	_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == &"sealed",
		"Closing the lid sends them away (got %s)" % [_ended[-1]])
	for way: String in ["horn", "meadow"]:
		_new_leg(animals, {"kind": CargoAnimalPlan.BEES, "moving_seconds": 0.0})
		package.set_open(true)
		animals.advance(1.0)
		animals.advance(3.5)
		if way == "horn":
			bus.call(&"request_horn")
		else:
			meadow[0] = false
			animals.advance(0.6)
		_expect(animals.phase == PHASE_IDLE and _ended[-1][2] == (&"scared" if way == "horn" else &"left"),
			"The bees go with the %s (got %s)" % [way, _ended[-1]])
	package.set_open(false)
	_tick_view(view, 3.0)
	await process_frame
	_expect(view.state == VIEW_NONE and view.bees == null, "The swarm is freed once it has gone")


## A bee is one mesh with yellow, black and a translucent white in it, not a dot of one colour.
func _bee_has_both_colours(mesh: ArrayMesh) -> bool:
	var colours: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var yellow: bool = false
	var black: bool = false
	var wing: bool = false
	for colour: Color in colours:
		yellow = yellow or (colour.r > 0.9 and colour.g > 0.7 and colour.b < 0.3 and colour.a > 0.99)
		black = black or (colour.get_luminance() < 0.15 and colour.a > 0.99)
		wing = wing or (colour.get_luminance() > 0.95 and colour.a < 0.9)
	return yellow and black and wing


# --- Host and clients ----------------------------------------------------------

func _test_client(level: Node, animals: Node, view: Node, vehicle: RigidBody3D,
		package: Node) -> void:
	_drive(vehicle, 15.0)
	# A peer that is not the host: same director, but it never decides.
	var source := GDScript.new()
	source.source_code = "extends CargoAnimals\nfunc _is_host() -> bool:\n\treturn false\n"
	source.reload()
	var client: Node = source.new()
	client.name = "ClientAnimals"
	client.vehicle = vehicle
	client.packages = level.packages
	level.add_child(client)
	client.set(&"_plan", {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	_alerts.clear()
	client.advance(1.0)
	client.advance(10.0)
	_expect(client.phase == PHASE_IDLE and _alerts.is_empty(), "A client never announces an animal itself")
	_expect(package.is_loaded and _box_in_bay(vehicle, package), "A client never touches the box")
	client.queue_free()

	# What the host relays is drawn by whoever hears it, and changes no box.
	var integrity_before: float = package.integrity
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.emit_signal(&"cargo_animal_alert", CargoAnimalPlan.BEES, package.package_id, 2.0, 10.0)
	await process_frame
	_expect(view.state == VIEW_WARN and view.bees != null, "A relayed alert is drawn on every peer")
	_tick_view(view, 1.0)
	_expect(is_equal_approx(package.integrity, integrity_before),
			"Drawing the bees does not hurt the box: only the host does")
	# The host repeats the alert for a peer that joins late: no restart.
	var swarm: Node = view.bees
	bus.emit_signal(&"cargo_animal_alert", CargoAnimalPlan.BEES, package.package_id, 0.0, 6.0)
	await process_frame
	_expect(view.bees == swarm and view.state == VIEW_ACT,
		"A repeated alert moves the same swarm on instead of restarting it")
	bus.emit_signal(&"cargo_animal_ended", CargoAnimalPlan.BEES, package.package_id, &"left", 0)
	_expect(view.state == VIEW_LEAVE, "The relayed end sends them off on every peer")
	_tick_view(view, 3.0)
	_expect(view.state == VIEW_NONE, "And everything is freed")

	# The host re-sends the alert of an animal at work when someone joins.
	_new_leg(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	animals.advance(1.0)
	_alerts.clear()
	animals._on_peer_level_ready(2)
	_expect(_alerts.size() == 1 and _alerts[0][0] == CargoAnimalPlan.GULL and float(_alerts[0][2]) > 0.0,
		"A peer joining mid-warning is told again, with what is left of it (got %s)" % [_alerts])
	animals.end_event(&"left", 0, true)


# --- Rhythm --------------------------------------------------------------------

func _test_rhythm(_level: Node, animals: Node, vehicle: RigidBody3D) -> void:
	_drive(vehicle, 15.0)
	_new_leg(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	animals.advance(1.0)
	_expect(animals.phase == PHASE_ANNOUNCED, "The leg's animal comes")
	animals.end_event(&"left", 0, true)
	_alerts.clear()
	# Right after one leaves, no other is announced while the view draws its exit.
	animals.set(&"_fired", false)
	animals.set(&"_poll", 0.0)
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE and _alerts.is_empty(), "No new animal while the last one is still leaving")
	animals.set(&"_fired", true)
	for step: int in range(6):
		animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE and _alerts.is_empty(), "One animal per leg: no second one on the same stretch")
	animals.set(&"events_this_run", int(_animals_const(&"MAX_PER_RUN")))
	_force_plan(animals, {"kind": CargoAnimalPlan.GULL, "moving_seconds": 0.0})
	animals.advance(1.0)
	_expect(animals.phase == PHASE_IDLE, "A run has at most %d animals" % int(_animals_const(&"MAX_PER_RUN")))
	animals.set(&"events_this_run", 0)
	# The pick does not depend on the order the boxes are listed in.
	var boxes: Array = animals.packages.duplicate()
	if boxes.size() >= 2:
		var forward: Node = animals._pick(boxes.duplicate())
		var backward: Node = animals._pick(_reversed(boxes))
		_expect(forward == backward, "The box the animal picks does not depend on list order")
	# Endless: only the gull comes there.
	animals.endless = true
	var others: bool = false
	for step: int in range(80):
		animals._next_leg()
		var plan: Dictionary = animals.current_plan()
		others = others or (not plan.is_empty() and StringName(plan["kind"]) != CargoAnimalPlan.GULL)
	_expect(not others, "In Endless (no doors, no meadows) only the gull is planned")
	animals.endless = false


# --- Helpers -------------------------------------------------------------------

func _animals_const(constant_name: StringName) -> Variant:
	return _animals_constants[constant_name]


func _force_plan(animals: Node, plan: Dictionary) -> void:
	animals.set(&"_plan", plan)
	animals.set(&"_fired", false)
	animals.set(&"_poll", 0.0)
	animals.set(&"_leg_moving", 100.0)


## A fresh leg for the test: the plan given, nothing fired yet, no animal out.
func _new_leg(animals: Node, plan: Dictionary) -> void:
	if animals.phase != PHASE_IDLE:
		animals.end_event(&"left", 0, true)
	animals.set(&"events_this_run", 0)
	animals.set(&"_cooldown", 0.0)
	_force_plan(animals, plan)


## The view counts its own seconds from _process(delta); a headless frame is
## not a fixed slice of time, so the test hands it the seconds itself.
func _tick_view(view: Node, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		view._process(0.1)
		left -= 0.1


func _drive(vehicle: RigidBody3D, speed: float) -> void:
	vehicle.linear_velocity = Vector3(0.0, 0.0, -speed)


func _box_in_bay(vehicle: RigidBody3D, package: Node) -> bool:
	return bool(vehicle.call(&"carries", package.global_position))


func _put_back(level: Node, package: Node, vehicle: RigidBody3D, player: Node) -> void:
	var mount: Node = vehicle.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea")
	package.linear_velocity = Vector3.ZERO
	package.angular_velocity = Vector3.ZERO
	player.set(&"global_position", package.global_position)
	package.get_node(^"InteractionArea").interact(player)
	player.set(&"global_position", vehicle.global_position)
	mount.interact(player)
	_expect(bool(package.is_loaded) and _box_in_bay(vehicle, package), "The box is back on its rack for the next part")
	level.call(&"_check_lost_cargo")


func _reversed(items: Array) -> Array:
	var copy: Array = items.duplicate()
	copy.reverse()
	return copy


func _has_signal(stream: AudioStreamWAV) -> bool:
	for byte: int in stream.data:
		if byte != 0:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
