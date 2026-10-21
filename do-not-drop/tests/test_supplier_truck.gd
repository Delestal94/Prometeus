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
## - the node that draws it (SupplierTruckView) follows the pose and hides when there is no truck.

const STEP: float = 0.25
const FINE_STEP: float = 0.05
## The largest move allowed between two samples FINE_STEP game minutes apart (m): the way in is
## about 35 m in 6 minutes with an ease-out of twice the mean speed.
const MAX_JUMP_M: float = 1.0
const MAX_YAW_JUMP: float = 0.35

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
