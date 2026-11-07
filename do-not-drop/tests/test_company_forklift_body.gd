extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_forklift_body.gd
##
## The shed forklift collides as a forklift, not as its driver's capsule (expansion D-0606.c4: forklift_body.gd,
## forklift_view.gd):
## - the boxes: the rear behind the seat, the mast in front of it, the forks out to their tips at their height with
##   the pallet they carry; none touches the floor, the rear and the mast clear a kerb the capsule steps up, the seat
##   is left to the capsule, and a stand-in that is not a body gets none;
## - on the real shed (CompanyShed, stage 0) with the real Player (player.tscn: its capsule and layers) moved as its
##   own step moves it (character_step, at the forklift's pace while it drives):
##   on foot it walks up to a shelf and to the east wall with only its capsule; getting on puts the boxes on it and
##   the forks follow the mast and the pallet; with the forks down it drives through the dock's gate and takes a
##   pallet off the truck's bed; with the forks at the low deck it stops with the tips of the forks at the shelf's face
##   (not inside it) and leaves the pallet on the shelf's slot from there, the stock rising once; with the forks above
##   the shelf they pass over it: against the wall behind it (a shelf is 1 m deep, the forks 1.2 m) their tips stop
##   first, and on a shelf out on the floor, with nothing behind it, the mast stops it; backing up, the counterweight
##   stops at the wall;
## - the boxes follow the forks through a real burst of the mast, not only at the event that starts it;
## - whatever stands on the shed's floor has its collider rooted under it, and a turn in one tick that swings the forks
##   into a wall or a bench pushes the body back out on the floor, the tips at the face (not down and under it, the
##   way out of a box whose collider ends at floor level);
## - the mast key stops the forks on what is under them, with the driver's body on the floor, and over nothing they go
##   all the way down; the driver does not jump;
## - getting on looking at a wall: the boxes that land inside it stay out, the body is not pushed through it, driving
##   on is no trap, and they come in as soon as they are clear;
## - a peer that joins late, from the snapshot, puts the boxes on the driver's player by itself;
## - getting off takes the boxes off: on foot again it walks up to the wall as before.
## The boxes on a driver that is another peer's player: test_company_forklift_net. Not covered: a quarter of a circle
## in a single tick at under a metre from a wall goes past it (the mast ends up in the wall, and turning takes it out).

const HEN: StringName = &"hen"
const DAY: int = 2
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
const CHARACTER_STEP := preload("res://modules/character_step/character_step.gd")
## The shelf in front (shelf_1, x from -6 to -5, z from -4 to -2) and its low slot; the east wall's inner face.
const LANE_Z: float = -3.0
const SHELF_FACE_X: float = -5.0
const SHELF_TOP_M: float = 2.0
const LOW_SLOT: StringName = &"shelf_1-0"
const EAST_WALL_X: float = 6.0
const WEST_WALL_X: float = -6.0
## A shelf the crew set out on the floor (x from -3 to -2, z from -1 to 1), nothing behind it: its cell, and the lane
## that meets its face.
const OPEN_SHELF_CELL := Vector2i(3, 3)
const OPEN_SHELF_FACE_X: float = -2.0
const OPEN_LANE_Z: float = 0.0
## West and east, as Node3D rotation.y (it faces -Z at 0).
const FACE_WEST: float = PI * 0.5
const FACE_EAST: float = -PI * 0.5
const FACE_SOUTH: float = PI
## How close a stop must be to where the boxes say (m): the physics' margins.
const SLACK_M: float = 0.08
## The inner face of the south wall, beside the dock's gate, and the bench against the east wall (x from 5, 0.9 m high,
## z from 0 to 2).
const SOUTH_WALL_Z: float = 4.0
const BENCH_FACE_X: float = 5.0
const BENCH_LANE_Z: float = 1.0

class FakeCompany extends RefCounted:
	var day: int = 2
	var warehouse_stage: int = 0

var _failures: int = 0
var _company := FakeCompany.new()
var _schedule := SupplierSchedule.new()
var _minute: Array[float] = [0.0]
var _net: CompanyNet
var _shed: CompanyShed
var _truck: SupplierTruckView
var _player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_boxes()
	await _test_driving()
	if _failures == 0:
		print("PASS: the driven forklift stops at shelves and walls with its forks and counterweight, not its capsule")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


# --- The boxes ---


func _test_boxes() -> void:
	var tip: float = CompanyTuning.FORKLIFT_TIP_M
	var footprint: Vector2 = CompanyTuning.PALLET_FOOTPRINT_M
	var down: Dictionary = ForkliftBody.boxes(0.0, false)
	var forks: Dictionary = down[ForkliftBody.FORKS]
	_expect(is_equal_approx(_front(forks), -(tip + footprint.x * 0.5))
		and is_equal_approx(_back(forks), -tip + footprint.x * 0.5)
		and is_equal_approx((forks["size"] as Vector3).x, footprint.y),
		"The forks' box runs out to their tips and is as wide as a pallet on them (%s)" % [forks])
	for part: StringName in ForkliftBody.PARTS:
		var box: Dictionary = down[part]
		_expect(_bottom(box) >= ForkliftBody.FORK_FLOOR_GAP_M - 0.0001,
			"The %s box keeps clear of the floor (%.3f m)" % [part, _bottom(box)])
		# The seat (the capsule, radius 0.35 m) is not inside any box.
		_expect(_back(box) <= -0.35 or _front(box) >= 0.35, "The %s box leaves the seat to the capsule" % part)
	_expect(_back(down[ForkliftBody.REAR]) > 0.0 and is_equal_approx(_back(down[ForkliftBody.REAR]), 1.2)
		and _front(down[ForkliftBody.MAST]) < 0.0 and is_equal_approx(_back(down[ForkliftBody.MAST]), -0.4)
		and is_equal_approx(_front(down[ForkliftBody.MAST]), _back(forks)),
		"The rear is behind the seat, the mast in front of it and the forks from the mast on")
	_expect(_top(down[ForkliftBody.MAST]) >= ForkliftView.MAST_HEIGHT - 0.001,
		"The mast's box is as high as the mast")
	for part: StringName in [ForkliftBody.REAR, ForkliftBody.MAST]:
		_expect(_bottom(down[part]) > CHARACTER_STEP.MAX_HEIGHT,
			"The %s box clears a kerb the capsule steps up (%.2f m)" % [part, _bottom(down[part])])
	var deck: float = CompanyShed.SHELF_DECKS[0]
	var loaded: Dictionary = ForkliftBody.boxes(deck, true)[ForkliftBody.FORKS]
	_expect(is_equal_approx(_bottom(loaded), deck)
		and is_equal_approx(_top(loaded), deck + ForkliftView.FORK_THICKNESS + PalletBox.height()),
		"At a deck, carrying, the forks' box goes from the forks up over the pallet (%.3f to %.3f)"
		% [_bottom(loaded), _top(loaded)])
	var high: Dictionary = ForkliftBody.boxes(CompanyTuning.FORKLIFT_MAX_LIFT_M, false)[ForkliftBody.FORKS]
	_expect(_bottom(high) > SHELF_TOP_M,
		"At the top of the mast the bare forks are over a shelf (%.3f)" % _bottom(high))
	_expect(ForkliftBody.boxes(-1.0, false) == down and ForkliftBody.boxes(9.0, false)
		== ForkliftBody.boxes(CompanyTuning.FORKLIFT_MAX_LIFT_M, false), "A height off the mast is clamped to it")
	var stand_in := Node3D.new()
	_expect(not ForkliftBody.attach(stand_in, 0.0, false) and stand_in.get_child_count() == 0
		and not ForkliftBody.is_on(stand_in), "A stand-in that is not a body gets no boxes")
	stand_in.free()


# --- The real shed and the real Player ---


func _test_driving() -> void:
	var state := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(state)
	var stock: Inventory = state.stock()
	var open_shelf: Dictionary = DefaultShed.load_default().placement().place(state, PlaceableShop.definition(&"shelf"),
		OPEN_SHELF_CELL.x, OPEN_SHELF_CELL.y, 1, true)
	_expect(open_shelf["ok"], "A shelf goes out on the floor (%s)" % [open_shelf])
	CompanyLayoutNet.stamp_uids(state.layout)
	_schedule.place(DAY - 1, [{"product": HEN, "qty": 30}])
	_minute[0] = float(SupplierSchedule.arrival_minute()) + 30.0
	_net = CompanyNet.new()
	_net.name = "ForkNet"
	_net.company = state
	_net.inventory = stock
	root.add_child(_net)
	_shed = CompanyShed.new()
	_shed.name = "Shed"
	root.add_child(_shed)
	_shed.follow(_net)
	_shed.rebuild(state, stock)
	_truck = SupplierTruckView.new()
	_truck.name = "Truck"
	_truck.schedule = _schedule
	_truck.company = _company
	_truck.minute_now = func() -> float: return _minute[0]
	_truck.pallets = _net.pallets.book
	root.add_child(_truck)
	_shed.truck = _truck
	_net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		if CompanyPallets.EVENT_KINDS.has(kind):
			_truck.refresh_bed())
	_net.stations = _shed.station_for
	_expect(_net.publish(CompanyPallets.LOADED, _net.pallets.loaded_event(DAY, _schedule.pallets_for(DAY), stock)),
		"The truck brings the day's pallets")
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	await physics_frame
	var fork: ForkliftView = _shed.yard.forklift
	var book: PalletJack = _net.pallets.book

	# On foot: only the capsule (radius 0.35 m) stops it.
	var walked: float = await _drive(Vector2(-3.0, LANE_Z), FACE_WEST, -1.0)
	_expect(not ForkliftBody.is_on(_player) and walked < SHELF_FACE_X + 0.35 + SLACK_M,
		"On foot it walks up to the shelf with its capsule (x %.3f)" % walked)
	var backed: float = await _drive(Vector2(4.0, LANE_Z), FACE_WEST, 1.0)
	_expect(backed > EAST_WALL_X - 0.35 - SLACK_M, "... and backs up to the east wall (x %.3f)" % backed)

	# Getting on puts the forklift's boxes on the driver's body.
	_place(PalletYardView.fork_home(0), FACE_SOUTH)
	_expect(PalletJackUse.use(_net, _shed.yard, PalletJackPoint.ACTION_BOARD, 1, _player.global_position)
		== PalletJackUse.RESULT_BOARDED and _net.pallets.forklift.driver == 1, "The player gets on the forklift")
	await process_frame
	_expect(ForkliftBody.is_on(_player) and _fits(_player, 0.0, false),
		"The driver's body carries the forklift's boxes, the forks down and bare")

	# Forks down: through the dock's gate, up to the truck's bed, and a pallet off it.
	var rear: Vector2 = SupplierTruckView.rear_of(0)
	var reach_z: float = rear.y - CompanyTuning.FORKLIFT_TIP_M - 0.4
	var at_gate: float = await _drive(Vector2(rear.x, 1.0), FACE_SOUTH, -1.0, reach_z)
	_expect(at_gate >= reach_z, "With the forks down it drives through the gate up to the truck (z %.3f)" % at_gate)
	var seq_pick: int = _net.seq
	_ask(CompanyForklift.ACT_WORK)
	var lifted: StringName = book.carrying
	_expect(_net.seq == seq_pick + 1 and lifted != &"" and _net.pallets.forklift.holds,
		"From there it takes a pallet off the bed (%s)" % lifted)
	await process_frame
	_expect(fork.carried_id() == lifted and _fits(_player, 0.0, true), "The forks' box now holds the pallet")

	# Forks at the low deck: the tips stop at the shelf's face, and the pallet goes on the shelf from there.
	var deck: float = CompanyShed.SHELF_DECKS[0]
	await _set_height(deck)
	_expect(_fits(_player, deck, true), "The forks' box went up with the forks")
	await _check_burst(fork, deck)
	var at_shelf: float = await _drive(Vector2(-1.0, LANE_Z), FACE_WEST, -1.0)
	var tips: float = at_shelf - CompanyTuning.FORKLIFT_TIP_M - CompanyTuning.PALLET_FOOTPRINT_M.x * 0.5
	_expect(tips > SHELF_FACE_X - SLACK_M and tips < SHELF_FACE_X + SLACK_M,
		"Driving into the shelf, the tips of the forks stop at its face (x %.3f, the face at %.1f)"
		% [tips, SHELF_FACE_X])
	var units_before: int = _net.inventory.total_units()
	var qty: int = int(book.places[lifted]["pallet"]["qty"])
	_ask(CompanyForklift.ACT_WORK)
	_expect(book.places[lifted]["at"] == PalletJack.AT_RACK and book.places[lifted].get("slot") == LOW_SLOT
		and _net.inventory.total_units() == units_before + qty,
		"From there the pallet is left on the shelf's low slot and the stock rises by its %d units (%s)"
		% [qty, book.places[lifted]])
	await process_frame
	_expect(_fits(_player, deck, false), "The forks' box is bare again")

	# Forks above the shelf: they pass over it. This one stands against the west wall and is shorter than the forks, so
	# their tips meet the wall before the mast meets the shelf.
	await _set_height(CompanyTuning.FORKLIFT_MAX_LIFT_M)
	var over: float = await _drive(Vector2(-2.5, LANE_Z), FACE_WEST, -1.0)
	var over_tips: float = over - CompanyTuning.FORKLIFT_TIP_M - CompanyTuning.PALLET_FOOTPRINT_M.x * 0.5
	_expect(over_tips > WEST_WALL_X - SLACK_M and over_tips < WEST_WALL_X + SLACK_M,
		"With the forks over a shelf against the wall, their tips stop at the wall behind it (x %.3f)" % over_tips)

	# ... and on a shelf out on the floor nothing stops the tips: it goes on until the mast meets the shelf.
	var open_over: float = await _drive(Vector2(0.5, OPEN_LANE_Z), FACE_WEST, -1.0)
	var mast_front: float = open_over - (CompanyTuning.FORKLIFT_TIP_M - CompanyTuning.PALLET_FOOTPRINT_M.x * 0.5)
	_expect(mast_front > OPEN_SHELF_FACE_X - SLACK_M and mast_front < OPEN_SHELF_FACE_X + SLACK_M,
		"With the forks over the shelf it goes on until the mast meets the shelf (x %.3f)" % mast_front)

	# Backing up, the counterweight meets the wall.
	await _set_height(0.0)
	var back: float = await _drive(Vector2(3.5, LANE_Z), FACE_WEST, 1.0)
	_expect(absf(back + ForkliftBody.REAR_TO_M - EAST_WALL_X) < SLACK_M,
		"Backing up, the counterweight stops at the east wall (x %.3f)" % back)

	_check_rooted()
	await _check_flicks()
	await _check_mast_stops(fork)
	await _check_no_jump()
	await _check_boarding_at_a_wall()
	await _check_late_peer(state)

	# Getting off takes the boxes off: on foot it backs up to the wall again.
	await _set_height(0.0)
	_place(Vector2(3.0, LANE_Z), FACE_WEST)
	await physics_frame
	_ask(CompanyForklift.ACT_LEAVE)
	await process_frame
	_expect(_net.pallets.forklift.driver == 0 and not ForkliftBody.is_on(_player),
		"Getting off takes the forklift's boxes off the player")
	var afoot: float = await _drive(Vector2(4.0, LANE_Z), FACE_WEST, 1.0)
	_expect(afoot > EAST_WALL_X - 0.35 - SLACK_M, "On foot again it backs up to the wall (x %.3f)" % afoot)
	var hop: float = await _jump_peak()
	_expect(hop > 0.2, "... and it jumps again (%.3f m)" % hop)

	for node: Node in [_player, _truck, _shed, _net]:
		node.free()
	await process_frame


## A real burst of the mast (a dir event, the forks rising from there by the clock): the boxes are those of the forks
## as drawn halfway through it, not of the event's height.
func _check_burst(fork: ForkliftView, from: float) -> void:
	var pose: Dictionary = fork.pose()
	_net.publish(CompanyPallets.FORK, CompanyForklift.state_event(_net.pallets.forklift.driver, pose["body"],
		pose["yaw"], 1, from))
	await create_timer(0.15).timeout
	_expect(_net.pallets.forklift.moving_at(Time.get_ticks_msec()) and fork.fork_height() > from + 0.02
		and _fits(_player, fork.fork_height(), true),
		"Halfway through a burst of the mast the boxes follow the forks (%.3f from %.3f)"
		% [fork.fork_height(), from])
	await _set_height(from)

	# Forks that met something (_steer_mast()) stay there while the host's answer to the stop is on its way, here with
	# no such answer: only the event that ends the burst lets them go on what the state says.
	pose = fork.pose()
	_net.publish(CompanyPallets.FORK, CompanyForklift.state_event(_net.pallets.forklift.driver, pose["body"],
		pose["yaw"], -1, from + 0.1))
	fork._brake_dir = -1
	fork._brake_at = from + 0.1
	await create_timer(0.1).timeout
	_expect(_net.pallets.forklift.moving_at(Time.get_ticks_msec()) and absf(fork.fork_height() - from - 0.1) < 0.001,
		"Braked, the forks hold where they met something while the burst runs out (%.3f)" % fork.fork_height())
	await _set_height(from)
	_expect(absf(fork.fork_height() - from) < 0.001, "... and the host's answer moves them (%.3f)" % fork.fork_height())


## Whatever stands on the shed's floor, walls and furniture and the pallets of the reception, goes on under it.
func _check_rooted() -> void:
	var feet: Array = []
	_collect_feet(_shed, feet)
	var loose: Array = feet.filter(func(foot: Array) -> bool: return foot[1] > -CompanyShed.FLOOR_ROOT_M + 0.01)
	_expect(feet.size() >= 6 and loose.is_empty(),
		"What stands on the floor has its collider rooted under it (%d colliders, loose: %s)" % [feet.size(), loose])


## Every box collider under `node` that stands on the floor or goes under it: [name, foot y]. Not the floor itself,
## which is under everything; a lintel stands on nothing.
func _collect_feet(node: Node, into: Array) -> void:
	for child: Node in node.get_children():
		_collect_feet(child, into)
		var shape := child as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D) or node.name == &"Floor":
			continue
		var foot: float = shape.global_position.y - (shape.shape as BoxShape3D).size.y * 0.5
		if foot < 0.02:
			into.append([String(node.name), snappedf(foot, 0.001)])


## The turn of one tick that swings the forks into something: the body stays on the floor and the tips at the face.
func _check_flicks() -> void:
	await _set_height(0.0)
	# Along the south wall, 1.4 m off it, and a quarter of a circle in one go: the forks would end 0.4 m inside it.
	_place(Vector2(3.0, 2.6), FACE_EAST)
	await _settle(10)
	await _flick(-PI * 0.5)
	var tips: float = _player.global_position.z + _fork_reach()
	_expect(absf(_player.global_position.y) < 0.02 and _player.is_on_floor(),
		"A turn in one tick into the wall leaves the body on the floor (y %.3f)" % _player.global_position.y)
	_expect(tips > SOUTH_WALL_Z - SLACK_M and tips < SOUTH_WALL_Z + SLACK_M,
		"... pushed back until the tips are at the wall's face (z %.3f)" % tips)
	await _hold(-1.0, 60)
	_expect(absf(_player.global_position.y) < 0.02
		and _player.global_position.z + _fork_reach() < SOUTH_WALL_Z + SLACK_M,
		"... and driving on, it does not go through (tips z %.3f)" % [_player.global_position.z + _fork_reach()])
	var before: float = _player.global_position.z
	await _hold(1.0, 40)
	_expect(_player.global_position.z < before - 0.5, "... and it backs off the wall (z %.3f to %.3f)"
		% [before, _player.global_position.z])

	# The same into a bench: a piece of furniture, not a wall.
	_place(Vector2(BENCH_FACE_X - 1.4, BENCH_LANE_Z), 0.0)
	await _settle(10)
	await _flick(-PI * 0.5)
	var bench_tips: float = _player.global_position.x + _fork_reach()
	_expect(absf(_player.global_position.y) < 0.02 and bench_tips < BENCH_FACE_X + SLACK_M,
		"A turn in one tick into a bench: on the floor, the tips at its face (y %.3f, x %.3f)"
		% [_player.global_position.y, bench_tips])


## The mast's key while the forks are over something, and over nothing.
func _check_mast_stops(fork: ForkliftView) -> void:
	fork.keys_need_capture = false
	await _set_height(CompanyTuning.FORKLIFT_MAX_LIFT_M)
	var seen: float = await _drive(Vector2(0.5, OPEN_LANE_Z), FACE_WEST, -1.0)
	_expect(seen < OPEN_SHELF_FACE_X + 1.2, "The mast stands at the open shelf with the forks over it (x %.3f)" % seen)
	Input.action_press(&"forklift_mast_down")
	var highest: float = await _ride_mast(fork, 2.0)
	Input.action_release(&"forklift_mast_down")
	_expect(fork.fork_height() > SHELF_TOP_M - 0.01 and fork.fork_height() < SHELF_TOP_M + 0.2,
		"The key lowers the forks down to the top of the shelf and no further (%.3f, the top at %.1f)"
		% [fork.fork_height(), SHELF_TOP_M])
	_expect(highest < 0.02 and absf(_player.global_position.y) < 0.02 and _player.is_on_floor(),
		"... and the driver's body stays on the floor (at most %.3f m, now %.3f)"
		% [highest, _player.global_position.y])
	await _settle(5)
	var state: CompanyForklift = _net.pallets.forklift
	var now: int = Time.get_ticks_msec()
	_expect(not state.moving_at(now) and absf(state.height_at(now) - fork.fork_height()) < 0.02,
		"... with the forks still for the host too, at the height it drew (%.3f, drawn %.3f)"
		% [state.height_at(now), fork.fork_height()])
	var seq_before: int = _net.seq
	Input.action_press(&"forklift_mast_down")
	await create_timer(0.2).timeout
	Input.action_release(&"forklift_mast_down")
	_expect(_net.seq == seq_before, "Held against it, the key asks for nothing (%d events)" % (_net.seq - seq_before))

	# Backed off the shelf they go on down, to the floor: the floor under them does not stop them.
	await _hold(1.0, 90)
	await _set_height(0.2)
	Input.action_press(&"forklift_mast_down")
	await create_timer(0.6).timeout
	Input.action_release(&"forklift_mast_down")
	await process_frame
	_expect(fork.fork_height() < 0.01, "Over nothing the forks go all the way down (%.3f)" % fork.fork_height())


## Steps the body while the mast runs for `seconds` (or until the forks are well under the top of the shelf): the
## highest it got.
func _ride_mast(fork: ForkliftView, seconds: float) -> float:
	var highest: float = 0.0
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and fork.fork_height() > SHELF_TOP_M - 0.3:
		await _settle(1)
		highest = maxf(highest, _player.global_position.y)
	return highest


func _check_no_jump() -> void:
	_place(Vector2(1.0, LANE_Z), FACE_WEST)
	await _settle(5)
	var driving: float = await _jump_peak()
	_expect(driving < 0.02, "The driver does not jump (%.3f m)" % driving)


## The jump key: the highest the player's own step takes it within a few ticks.
func _jump_peak() -> float:
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	await physics_frame
	Input.action_press(&"jump")
	var peak: float = 0.0
	for tick: int in 12:
		Player.Movement.on_foot_step(_player, delta)
		await physics_frame
		peak = maxf(peak, _player.global_position.y)
		Input.action_release(&"jump")
	await _settle(40)
	return peak


## Getting on where the boxes do not fit: those that do not stay out until they do.
func _check_boarding_at_a_wall() -> void:
	for gap: float in [0.8, 1.3]:
		await _reboard(Vector2(3.0, SOUTH_WALL_Z - gap), FACE_SOUTH)
		_expect(ForkliftBody.is_on(_player) and not _part_in(ForkliftBody.FORKS) and _part_in(ForkliftBody.REAR),
			"Getting on %.1f m from a wall the forks' box stays out, the rear's goes in" % gap)
		_expect(absf(_player.global_position.y) < 0.02
			and absf(_player.global_position.z - (SOUTH_WALL_Z - gap)) < 0.02,
			"... and the body stays where it is, on the floor (%s)" % _player.global_position)
		await _hold(-1.0, 40)
		_expect(absf(_player.global_position.y) < 0.02, "... also driving on (y %.3f)" % _player.global_position.y)
		await _hold(1.0, 120)
		await process_frame
		_expect(_part_in(ForkliftBody.FORKS),
			"... backing off the forks' box comes in (z %.3f)" % _player.global_position.z)
		await _hold(-1.0, 150)
		var tips: float = _player.global_position.z + _fork_reach()
		_expect(tips > SOUTH_WALL_Z - SLACK_M and tips < SOUTH_WALL_Z + SLACK_M,
			"... and now the tips stop at the wall (z %.3f)" % tips)
	# Right against the wall the mast's stays out as well, and turning away brings them in where it stands.
	await _reboard(Vector2(3.0, SOUTH_WALL_Z - 0.5), FACE_SOUTH)
	_expect(not _part_in(ForkliftBody.MAST) and not _part_in(ForkliftBody.FORKS),
		"Getting on 0.5 m from a wall the mast's box stays out too")
	_player.rotate_y(PI)
	await _settle(3)
	await process_frame
	await process_frame
	_expect(_part_in(ForkliftBody.MAST) and _part_in(ForkliftBody.FORKS) and absf(_player.global_position.y) < 0.02,
		"... and turning away from it brings them in")


## A peer that joins while somebody drives, from the snapshot: its view finds the driver's player and puts the boxes on
## it. The body is one here, so the other view keeps out of it. A freed view takes its driver's marks with it, so this
## test does nothing on foot or at the wheel after this but get off.
func _check_late_peer(state: Object) -> void:
	var late := CompanyNet.new()
	late.name = "LateNet"
	late.company = state
	root.add_child(late)
	_expect(late.pallets.put_snapshot(_net.snapshot()["pallets"]), "The late peer takes the pallets part")
	late.inventory.from_dict(_net.snapshot()["inventory"])
	var late_shed := CompanyShed.new()
	late_shed.name = "LateShed"
	root.add_child(late_shed)
	late_shed.follow(late)
	late_shed.rebuild(state, late.inventory)
	_shed.yard.forklift.set_process(false)
	ForkliftBody.detach(_player)
	await process_frame
	await process_frame
	_expect(ForkliftBody.is_on(_player), "A peer that joins late puts the boxes on the driver's player by itself")
	_shed.yard.forklift.set_process(true)
	late_shed.free()
	late.free()
	await process_frame
	await process_frame


# --- Helpers ---


## One go that turns the player `yaw` at once, and the body left to settle.
func _flick(yaw: float) -> void:
	_player.rotate_y(yaw)
	await _settle(30)


## How far ahead of the driver the tips of the forks are.
func _fork_reach() -> float:
	return CompanyTuning.FORKLIFT_TIP_M + CompanyTuning.PALLET_FOOTPRINT_M.x * 0.5


## `ticks` physics ticks of the player's step standing still.
func _settle(ticks: int) -> void:
	await _hold(0.0, ticks)


## `ticks` physics ticks of the driver's step ahead (`way` -1) or back (+1), from where it is.
func _hold(way: float, ticks: int) -> void:
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	for tick: int in ticks:
		var pace: float = CompanyTuning.FORKLIFT_DRIVE_SPEED_MPS if ForkliftBody.is_on(_player) else Player.WALK_SPEED
		var ahead: Vector3 = _player.global_basis.z * way * pace
		var fall: float = -0.2 if _player.is_on_floor() else _player.velocity.y - 9.8 * delta
		_player.velocity = Vector3(ahead.x, fall, ahead.z)
		CHARACTER_STEP.move_and_slide(_player, delta)
		await physics_frame


## Whether the `part` box is in (collides) on the player.
func _part_in(part: StringName) -> bool:
	var shape := _player.get_node_or_null(NodePath(ForkliftBody.SHAPE_PREFIX + String(part))) as CollisionShape3D
	return shape != null and not shape.disabled


## The forklift parked out of the way and the driver back on it at `at` facing `heading`, as the seat does.
func _reboard(at: Vector2, heading: float) -> void:
	_net.publish(CompanyPallets.FORK, CompanyForklift.state_event(0, PalletYardView.fork_home(0), 0.0, 0, 0.0))
	await process_frame
	await process_frame
	_place(at, heading)
	await _settle(5)
	_net.publish(CompanyPallets.FORK, CompanyForklift.state_event(1, at, heading, 0, 0.0))
	await process_frame
	await process_frame
	await _settle(20)


## Stands the player at `at` (shed frame, on the floor) facing `heading`.
func _place(at: Vector2, heading: float) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(at.x, 0.0, at.y)
	_player.rotation = Vector3(0.0, heading, 0.0)
	_player.reset_physics_interpolation()


## Puts the player at `from` facing `heading` and walks it ahead (`way` -1) or back (+1) as its own step does
## (character_step at its pace: the forklift's while it drives), until it stops or, when `until_z` is given, it is that
## far south. The x where it ended up, or its z for `until_z`.
func _drive(from: Vector2, heading: float, way: float, until_z: float = INF) -> float:
	_place(from, heading)
	await physics_frame
	var pace: float = CompanyTuning.FORKLIFT_DRIVE_SPEED_MPS if ForkliftBody.is_on(_player) else Player.WALK_SPEED
	var still: int = 0
	var last: Vector3 = _player.global_position
	for frame: int in 600:
		var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
		var ahead: Vector3 = _player.global_basis.z * way * pace
		var fall: float = -0.2 if _player.is_on_floor() else _player.velocity.y - 9.8 * delta
		_player.velocity = Vector3(ahead.x, fall, ahead.z)
		CHARACTER_STEP.move_and_slide(_player, delta)
		await physics_frame
		if until_z != INF and _player.global_position.z >= until_z:
			break
		still = still + 1 if _player.global_position.distance_to(last) < 0.0005 else 0
		last = _player.global_position
		if still >= 15:
			break
	_player.velocity = Vector3.ZERO
	return _player.global_position.z if until_z != INF else _player.global_position.x


## The host sets the forks straight at `height` (a fork_state event, as for a driver that is gone), and a frame
## draws it.
func _set_height(height: float) -> void:
	var pose: Dictionary = _shed.yard.forklift.pose()
	_net.publish(CompanyPallets.FORK, CompanyForklift.state_event(_net.pallets.forklift.driver, pose["body"],
		pose["yaw"], 0, height))
	await process_frame


func _ask(act: StringName) -> void:
	_net.request(CompanyPallets.FORK_ACT, {"act": act})


## Whether the forklift's boxes on `body` are those of forks at `height`, carrying or not.
func _fits(body: Node, height: float, carrying: bool) -> bool:
	var wanted: Dictionary = ForkliftBody.boxes(height, carrying)
	for part: StringName in ForkliftBody.PARTS:
		var shape := body.get_node_or_null(NodePath(ForkliftBody.SHAPE_PREFIX + String(part))) as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			return false
		if not ((shape.shape as BoxShape3D).size.is_equal_approx(wanted[part]["size"])
				and shape.position.is_equal_approx(wanted[part]["center"])):
			return false
	return true


func _bottom(box: Dictionary) -> float:
	return (box["center"] as Vector3).y - (box["size"] as Vector3).y * 0.5


func _top(box: Dictionary) -> float:
	return (box["center"] as Vector3).y + (box["size"] as Vector3).y * 0.5


## The box's end toward -Z (ahead) and toward +Z (behind), in the forklift's frame.
func _front(box: Dictionary) -> float:
	return (box["center"] as Vector3).z - (box["size"] as Vector3).z * 0.5


func _back(box: Dictionary) -> float:
	return (box["center"] as Vector3).z + (box["size"] as Vector3).z * 0.5
