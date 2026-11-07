extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_supplier_truck.gd
##
## The supplier's truck NPC (expansion D-0601, supplier_truck.gd and supplier_truck_view.gd), in 10
## runs over different days, shed stages and delivery sizes:
## - there is no truck before it starts driving in, on a day without delivery, or once it is out;
## - it drives in during the SUPPLIER_DRIVE_IN_MIN minutes before the arrival minute and is parked
##   exactly at SupplierSchedule.arrival_minute();
## - the phases only go forward: driving in, reversing, parked, driving out, absent;
## - parked it is motionless until departure_minute(), inside the dock's lane (the wall gap), pointing
##   south (rear to the dock), close to the wall but not touching it;
## - during the whole drive no corner of the truck touches the shed's floor, its walls or the dock's
##   floor cells (the fixed area nothing can cover), and it never jumps (continuous position and yaw);
## - it is deterministic: the same inputs give the same pose, with a fresh calendar too;
## - the node that draws it (SupplierTruckView) follows the pose and hides when there is no truck;
## - it draws the model sm_vehicle_supplier_truck.glb, no primitive left: the size of
##   CompanyTuning.SUPPLIER_TRUCK_SIZE_M, narrower than the dock's gap, nose to -Z, wheels on the floor, the
##   lamps that glow at night, and nothing but the shutter where the bed's twelve pallets stand;
## - its rear shutter is shut on the road, rolls up in the first minutes of the wait, clears the tallest
##   stack of pallets, and rolls down before it leaves, with its top edge fixed under the header.

const STEP: float = 0.25
const FINE_STEP: float = 0.05
## The largest move allowed between two samples FINE_STEP game minutes apart (m): the way in is
## about 35 m in 6 minutes with an ease-out of twice the mean speed.
const MAX_JUMP_M: float = 1.0
const MAX_YAW_JUMP: float = 0.35
## What a model's part sticks out of the truck's footprint (m): grab handle, badge, tail lights.
const MODEL_TRIM_M: float = 0.1
## The model's width with its mirrors (m).
const MODEL_MIRRORS_WIDTH_M: float = 3.0
const MODEL_PARTS: Array[String] = ["Cab", "CargoBox", "Wheels", "Light", "TailLights", "RearDoor"]

## {day, stage, qty}: ten runs.
const RUNS: Array[Dictionary] = [
	{"day": 1, "stage": 0, "qty": 6}, {"day": 2, "stage": 0, "qty": 50},
	{"day": 3, "stage": 1, "qty": 1}, {"day": 5, "stage": 1, "qty": 24},
	{"day": 8, "stage": 2, "qty": 30}, {"day": 13, "stage": 2, "qty": 7},
	{"day": 21, "stage": 3, "qty": 48}, {"day": 34, "stage": 3, "qty": 2},
	{"day": 55, "stage": 0, "qty": 24}, {"day": 89, "stage": 1, "qty": 100},
]

var _failures: int = 0


class FakeCompany:
	extends RefCounted
	var day: int = 1
	var warehouse_stage: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for run: Dictionary in RUNS:
		_test_run(run)
	_test_no_delivery_day()
	_test_determinism()
	_test_view()
	_test_model()
	_test_rear_door()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _schedule_for(day: int, qty: int) -> SupplierSchedule:
	var s := SupplierSchedule.new()
	s.place(day - 1, [{"product": &"hen", "qty": qty}])
	return s


func _test_run(run: Dictionary) -> void:
	var day: int = run["day"]
	var stage: int = run["stage"]
	var tag := "day %d stage %d: " % [day, stage]
	var s: SupplierSchedule = _schedule_for(day, run["qty"])
	var arrival: float = float(SupplierSchedule.arrival_minute())
	var departure: float = float(SupplierSchedule.departure_minute())
	var starts: float = arrival - CompanyTuning.SUPPLIER_DRIVE_IN_MIN
	var ends: float = departure + CompanyTuning.SUPPLIER_DRIVE_OUT_MIN
	var floor_m: Vector2 = WarehouseStages.floor_size_m(stage)
	var half: Vector2 = floor_m * 0.5
	var wall: float = CompanyShed.WALL_THICKNESS
	# The shed with its walls, and the dock's floor cells in metres (shed-local, centre at the origin).
	var shed_block := Rect2(-half - Vector2(wall, wall), floor_m + Vector2(wall, wall) * 2.0)
	var dock: Rect2i = WarehouseStages.dock_rect(stage)
	var grid: Vector2i = WarehouseStages.grid_size_for(stage)
	var dock_m := Rect2(
		(Vector2(dock.position) - Vector2(grid) * 0.5) * CompanyTuning.WAREHOUSE_GRID_M,
		Vector2(dock.size) * CompanyTuning.WAREHOUSE_GRID_M)
	var span: Vector2 = SupplierTruck.gate_span_x(stage)

	_expect(not SupplierTruck.pose(s, day, starts - 0.5, stage)["present"], tag + "no truck before it drives in")
	_expect(not SupplierTruck.pose(s, day, 0.0, stage)["present"], tag + "no truck at midnight")
	_expect(SupplierTruck.pose(s, day, starts + 0.1, stage)["phase"] == SupplierTruck.Phase.DRIVING_IN,
		tag + "it drives in at the start of the window")
	var arrive: Dictionary = SupplierTruck.pose(s, day, arrival, stage)
	_expect(arrive["phase"] == SupplierTruck.Phase.PARKED, tag + "parked at the arrival minute")
	_expect(not SupplierTruck.pose(s, day, ends + 0.01, stage)["present"], tag + "gone once it is out")
	_expect(not SupplierTruck.pose(s, day, 1439.0, stage)["present"], tag + "gone at the end of the day")
	_expect(not SupplierTruck.pose(s, day + 1, arrival, stage)["present"], tag + "no truck the next day")
	_expect(not SupplierTruck.pose(s, day - 1, arrival, stage)["present"], tag + "no truck the day before")

	var last_phase: int = SupplierTruck.Phase.ABSENT
	var last: Dictionary = {}
	var seen: Dictionary = {}
	var minute: float = 0.0
	while minute < 1440.0:
		var pose: Dictionary = SupplierTruck.pose(s, day, minute, stage)
		var inside: bool = minute >= starts and minute < ends
		_expect(bool(pose["present"]) == inside, tag + "present exactly while driving or parked at %.2f" % minute)
		if bool(pose["present"]):
			var phase: int = pose["phase"]
			seen[phase] = true
			# Phases only go forward (the enum is in the order of the drive).
			_expect(phase >= last_phase, tag + "phase never goes back at %.2f" % minute)
			last_phase = phase
			var box: PackedVector2Array = SupplierTruck.corners(pose["position"], pose["heading"])
			_expect(not _bounds(box).intersects(shed_block),
				tag + "truck does not touch the shed's floor or walls at %.2f" % minute)
			_expect(not _bounds(box).intersects(dock_m),
				tag + "truck does not cover the dock's floor cells at %.2f" % minute)
			_expect(is_equal_approx((pose["heading"] as Vector2).length(), 1.0), tag + "heading is a unit vector")
		minute += STEP
	for phase: int in [SupplierTruck.Phase.DRIVING_IN, SupplierTruck.Phase.REVERSING,
			SupplierTruck.Phase.PARKED, SupplierTruck.Phase.DRIVING_OUT]:
		_expect(seen.has(phase), tag + "phase %d happens" % phase)

	# Parked: motionless, in the lane, rear to the dock, close to the wall but not touching it.
	var park_pos: Vector2 = arrive["position"]
	var spot: Rect2 = SupplierTruck.parked_rect(stage)
	_expect(is_equal_approx(spot.get_center().x, (span.x + span.y) * 0.5), tag + "parked on the dock's axis")
	_expect(spot.position.x >= span.x and spot.end.x <= span.y, tag + "parked inside the lane (the wall gap)")
	var gap: float = spot.position.y - half.y
	_expect(gap >= wall + 0.2 and gap <= wall + 0.5, tag + "rear %.2f m from the floor edge: close, not touching" % gap)
	_expect((arrive["heading"] as Vector2).is_equal_approx(Vector2(0.0, 1.0)), tag + "pointing south, rear to the dock")
	minute = arrival
	while minute < departure:
		var pose: Dictionary = SupplierTruck.pose(s, day, minute, stage)
		_expect(pose["phase"] == SupplierTruck.Phase.PARKED and (pose["position"] as Vector2) == park_pos,
			tag + "stays put while it waits at %.2f" % minute)
		minute += STEP
	_expect(SupplierTruck.pose(s, day, departure, stage)["phase"] == SupplierTruck.Phase.DRIVING_OUT,
		tag + "drives out at the departure minute")

	# Continuity: no teleport in the whole drive.
	minute = starts
	while minute < ends:
		var pose: Dictionary = SupplierTruck.pose(s, day, minute, stage)
		if not last.is_empty() and bool(pose["present"]):
			var step_m: float = (pose["position"] as Vector2).distance_to(last["position"])
			_expect(step_m <= MAX_JUMP_M, tag + "moves %.2f m in one sample at %.2f" % [step_m, minute])
			_expect(absf(angle_difference(float(last["yaw"]), float(pose["yaw"]))) <= MAX_YAW_JUMP,
				tag + "turns smoothly at %.2f" % minute)
		last = pose
		minute += FINE_STEP


func _bounds(corners: PackedVector2Array) -> Rect2:
	var box := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		box = box.expand(corner)
	return box


func _test_no_delivery_day() -> void:
	var s := SupplierSchedule.new()
	var minute: float = 0.0
	var any: bool = false
	while minute < 1440.0:
		any = any or bool(SupplierTruck.pose(s, 3, minute)["present"])
		minute += 5.0
	_expect(not any, "an empty calendar never shows a truck")


func _test_determinism() -> void:
	var a: SupplierSchedule = _schedule_for(4, 30)
	var b: SupplierSchedule = _schedule_for(4, 30)
	for minute: float in [500.0, 505.3, 508.9, 509.99, 510.0, 600.0, 690.0, 691.7, 693.99, 700.0]:
		var first: Dictionary = SupplierTruck.pose(a, 4, minute, 1)
		var again: Dictionary = SupplierTruck.pose(a, 4, minute, 1)
		_expect(first == SupplierTruck.pose(b, 4, minute, 1), "same pose from two calendars at %.2f" % minute)
		_expect(first == again, "same pose twice at %.2f" % minute)
	# The size of the order does not move the truck.
	var big: SupplierSchedule = _schedule_for(4, 200)
	_expect(SupplierTruck.pose(big, 4, 505.0, 1) == SupplierTruck.pose(a, 4, 505.0, 1),
		"the pose does not depend on the order's size")


func _test_view() -> void:
	var s: SupplierSchedule = _schedule_for(2, 10)
	var company := FakeCompany.new()
	company.day = 2
	var view := SupplierTruckView.new()
	view.schedule = s
	view.company = company
	view.origin = Vector3(100.0, 0.0, -50.0)
	var minute: Array[float] = [0.0]
	view.minute_now = func() -> float: return minute[0]
	root.add_child(view)
	view.refresh()
	_expect(not view.visible, "the view is hidden with no truck")
	minute[0] = float(SupplierSchedule.arrival_minute()) + 30.0
	view.refresh()
	_expect(view.visible, "the view shows the parked truck")
	var spot: Vector2 = SupplierTruck.parked_rect(0).get_center()
	_expect(view.position.is_equal_approx(Vector3(100.0 + spot.x, 0.0, -50.0 + spot.y)),
		"the view stands at the parking spot, around the shed's origin")
	# Its front (-Z of the model) points south (+Z of the world).
	var forward: Vector3 = view.transform.basis * Vector3(0.0, 0.0, -1.0)
	_expect(forward.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "the cab points south, the rear to the dock")
	company.day = 3
	view.refresh()
	_expect(not view.visible, "the view hides on a day without delivery")
	view.minute_now = Callable()
	view.refresh()
	_expect(not view.visible, "the view hides without a clock")
	view.free()


## The AABB of `mesh` in the frame of `body` (the truck's own: nose to -Z, wheels on y = 0).
func _bounds_in(body: Node3D, mesh: MeshInstance3D) -> AABB:
	return (body.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()


func _test_model() -> void:
	var size: Vector3 = CompanyTuning.SUPPLIER_TRUCK_SIZE_M
	var view := SupplierTruckView.new()
	root.add_child(view)
	var body: Node3D = view.get_node(^"Body")
	var meshes: Array[Node] = body.find_children("*", "MeshInstance3D", true, false)
	_expect(not meshes.is_empty(), "the body has the model's meshes")
	var bounds := AABB()
	var parts: Array[String] = []
	var tris: int = 0
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		parts.append(String(mesh.name))
		_expect(not mesh.mesh is PrimitiveMesh, "%s comes from the model, not from a primitive" % mesh.name)
		tris += mesh.mesh.get_faces().size() / 3
		var part: AABB = _bounds_in(body, mesh)
		bounds = part if bounds.size == Vector3.ZERO else bounds.merge(part)
	for part: String in MODEL_PARTS:
		_expect(parts.has(part), "the model has its %s" % part)
	_expect(tris < 3000, "low-poly: under 3k triangles (%d)" % tris)
	var gate: Vector2 = SupplierTruck.gate_span_x(0)
	_expect(bounds.size.x <= MODEL_MIRRORS_WIDTH_M and bounds.size.x < gate.y - gate.x,
		"mirrors and all it is narrower than the dock's gap (%.2f m)" % bounds.size.x)
	var box: AABB = _bounds_in(body, body.find_child("CargoBox", true, false) as MeshInstance3D)
	_expect(absf(box.size.x - size.x) <= MODEL_TRIM_M, "the box has the truck's width (%.2f m)" % box.size.x)
	_expect(is_equal_approx(bounds.position.y, 0.0), "the wheels stand on the floor (%.3f)" % bounds.position.y)
	_expect(absf(bounds.end.y - size.y) <= MODEL_TRIM_M, "it has the truck's height (%.2f m)" % bounds.end.y)
	var half: float = size.z * 0.5
	_expect(absf(bounds.position.z + half) <= MODEL_TRIM_M and absf(bounds.end.z - half) <= MODEL_TRIM_M,
		"it has the truck's length around its middle (%.2f to %.2f)" % [bounds.position.z, bounds.end.z])
	var cab: AABB = _bounds_in(body, body.find_child("Cab", true, false) as MeshInstance3D)
	var tail: AABB = _bounds_in(body, body.find_child("TailLights", true, false) as MeshInstance3D)
	_expect(cab.get_center().z < 0.0 and tail.get_center().z > 0.0, "the cab is at -Z and the rear at +Z")
	# Nothing of the truck but its shutter stands where the bed's pallets go.
	var stack := AABB()
	var turned := Vector3(CompanyTuning.PALLET_FOOTPRINT_M.y, PalletBox.height(), CompanyTuning.PALLET_FOOTPRINT_M.x)
	for rank: int in SupplierTruckView.BED_SLOTS:
		var at: Vector3 = SupplierTruckView.bed_slot(rank)
		var slot := AABB(at - Vector3(turned.x, 0.0, turned.z) * 0.5, turned)
		stack = slot if rank == 0 else stack.merge(slot)
	var inside: int = 0
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.name == "RearDoor":
			continue
		var to_body: Transform3D = body.global_transform.affine_inverse() * mesh.global_transform
		for corner: Vector3 in mesh.mesh.get_faces():
			if stack.grow(-0.005).has_point(to_body * corner):
				inside += 1
	_expect(inside == 0, "the bed is hollow where the pallets go (%d corners inside)" % inside)
	view.free()
	var glowing := SupplierTruckView.MODEL.instantiate() as Node3D
	LowpolyMaterials.apply(glowing)
	LowpolyMaterials.set_night_level(1.0)
	_expect(LowpolyMaterials.light_up(glowing, SupplierTruckView.NIGHT_LIGHTS) > 0, "its lamps light up at night")
	LowpolyMaterials.set_night_level(0.0)
	glowing.free()


func _test_rear_door() -> void:
	var arrival: float = float(SupplierSchedule.arrival_minute())
	var departure: float = float(SupplierSchedule.departure_minute())
	var roll: float = SupplierTruckView.REAR_DOOR_ROLL_MIN
	_expect(SupplierTruckView.door_opening(arrival - 1.0) == 0.0, "the shutter is shut driving in")
	_expect(SupplierTruckView.door_opening(arrival) == 0.0, "it is still shut as the truck parks")
	_expect(is_equal_approx(SupplierTruckView.door_opening(arrival + roll * 0.5), 0.5), "it rolls up gradually")
	_expect(SupplierTruckView.door_opening(arrival + roll) == 1.0, "it is open after the first minute of the wait")
	_expect(SupplierTruckView.door_opening(departure - roll) == 1.0, "it stays open until the last minute")
	_expect(SupplierTruckView.door_opening(departure) == 0.0, "it is shut when the truck leaves")
	_expect(SupplierTruckView.door_opening(departure + 1.0) == 0.0, "it stays shut driving out")
	var s: SupplierSchedule = _schedule_for(2, 10)
	var company := FakeCompany.new()
	company.day = 2
	var view := SupplierTruckView.new()
	view.schedule = s
	view.company = company
	var minute: Array[float] = [arrival - 2.0]
	view.minute_now = func() -> float: return minute[0]
	root.add_child(view)
	var body: Node3D = view.get_node(^"Body")
	var door := body.find_child("RearDoor", true, false) as MeshInstance3D
	var top: float = _bounds_in(body, door).end.y
	view.refresh()
	var shut: AABB = _bounds_in(body, door)
	_expect(is_equal_approx(door.scale.y, 1.0), "the view's shutter is shut driving in")
	_expect(shut.position.y <= SupplierTruckView.CARGO_FLOOR + SupplierTruckView.BED_WALL + 0.01,
		"shut, it reaches the bed's floor (%.2f)" % shut.position.y)
	minute[0] = arrival + 30.0
	view.refresh()
	var rolled: AABB = _bounds_in(body, door)
	var last: Vector3 = SupplierTruckView.bed_slot(SupplierTruckView.BED_SLOTS - 1)
	_expect(rolled.position.y >= last.y + PalletBox.height(),
		"rolled up it clears the top pallets (%.2f over %.2f)" % [rolled.position.y, last.y + PalletBox.height()])
	_expect(is_equal_approx(rolled.end.y, top), "its top edge stays under the header")
	minute[0] = departure + 1.0
	view.refresh()
	_expect(is_equal_approx(door.scale.y, 1.0), "the view's shutter is shut again driving out")
	view.free()
