extends RefCounted
## The driving stages of the company-day bot (tests/bot_company_day.gd: drive, deliver and return, D-2016.2 and
## D-2016.3), apart from the bot so that file stays under the linter's length. Not a test: preloaded.
## drive: the player takes the van out of the yard (bot_company_van.gd drive_out) and the autopilot follows the
## street graph to the house of the Trip's first stop. deliver: at each stop the van is at the house (it drives
## there if it is not) and the door settles the orders. return: the autopilot takes the van back by the same
## streets, the yard's leg and into the playon, where the gate closes the Trip. Each stage answers
## {"status": "ok"|"fail", "reason"}; what the autopilot measured goes to ctx.autopilot[leg] (drive_to()'s dictionary:
## metres, off_road_max, turn_strokes...). A stage fails when the autopilot did not get there or when the van went
## farther than VAN.OFF_ROAD_LIMIT_M outside the roadway (D-0304.3: OFF_ROAD = 0 is "in the street"; a K-turn may
## use VAN.TURN_OFF_ROAD_LIMIT_M).

const VAN := preload("res://tests/bot_company_van.gd")
## The yard's leg (VAN.leg) joins the street here: the shed's first avenue, this far from the node `shed`
## (the shed's centre, so past its walls and its playon). The graph has no street through the playon.
const ENTRY_EDGE: StringName = &"avenida_este_1"
const ENTRY_ALONG_M: float = 40.0
## The van is at a house when it is this close to it (m): the house stands up to MAX_STREET_GAP from the
## edge of the roadway (half of 12 m at most) and the autopilot ends a few metres short of the street point.
const HOUSE_REACH_M: float = 26.0


## The loaded van, parked in the playon, is driven out of the yard by the player: the gate sees the
## node cross and starts the Trip (its orders go OUT). Then the autopilot (VAN.drive_to, D-2016.3) takes it
## along the street graph to the house of the Trip's first stop and the bot checks it stayed in the
## street (off_road_max under VAN.OFF_ROAD_LIMIT_M outside the roadway: D-0304.3's OFF_ROAD). With ctx.drive_cap_m > 0
## the way ends after that many metres of the line (a test's short run).
static func drive(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var vehicle: StringName = ctx["vehicle_id"]
	if vehicle == &"" or ctx["box"] == null:
		return _fail("nothing_loaded")
	var van: VehicleBody3D = VAN.van_of(level, vehicle)
	if van != null:
		ctx["park_point"] = VAN.ground_of(van)
	var driven: Dictionary = await VAN.drive_out(tree, level, vehicle)
	ctx["drive_m"] = float(driven["metres"])
	if driven["reason"] != "":
		return _fail(driven["reason"])
	var trip: Trip = level.trips.trip_of(vehicle)
	if trip == null:
		return _fail("trip_not_started")
	if level.trips.book.state_of(ctx["order"]["id"]) != Order.STATE_OUT:
		return _fail("order_not_out")
	ctx["trip"] = trip
	ctx["yard_exit"] = VAN.ground_of(van)
	ctx["yard_dir"] = VAN.forward_of(van)
	var net: RoadGraph = RoadGraph.load_default()
	var house: HouseSpot = HouseMap.load_default().spot(trip.next_stop())
	if net == null or house == null:
		return _fail("unknown_house_%s" % trip.next_stop())
	var entry: Dictionary = street_entry(net)
	var out_leg: PackedVector2Array = VAN.leg(
		ctx["yard_exit"], ctx["yard_dir"], entry["point"], entry["dir"])
	var piloted: Dictionary = await VAN.drive_to(
		tree, level, vehicle, street_point(net, house), out_leg, PackedVector2Array(),
		float(ctx["drive_cap_m"]))
	return _piloted(ctx, "drive", piloted)


## Stop by stop, the van goes to the stop's house (the autopilot; it stays if it is there) and each house
## is checked against the fixed map and the door settles its orders: the customer pays into the wallet
## (OrderSettlement) and the Trip records the delivery. The door is still OrderSettlement.settle: the
## company world has no delivery at a house's door yet (DeliveryHouse is the delivery run's: doorbell
## and carried package); the van stands within HOUSE_REACH_M of the house first.
static func deliver(
	tree: SceneTree, level: CompanyRoot, ctx: Dictionary, products: Dictionary
) -> Dictionary:
	var vehicle: StringName = ctx["vehicle_id"]
	var box: PackedBox = ctx["box"]
	if vehicle == &"" or box == null:
		return _fail("nothing_loaded")
	var trips: CompanyTrips = level.trips
	var trip: Trip = ctx["trip"]
	if trip == null or trips.trip_of(vehicle) != trip:
		return _fail("not_driven_out")
	var book: OrderBook = trips.book
	var houses: HouseMap = HouseMap.load_default()
	var wallet: Node = level.net.company as Node
	while trip.next_stop() != &"":
		var house_id: StringName = trip.next_stop()
		var house: HouseSpot = houses.spot(house_id) if houses != null else null
		if house == null:
			return _fail("unknown_house_%s" % house_id)
		var arrived: String = await _drive_to_house(tree, level, ctx, house)
		if arrived != "":
			return _fail(arrived)
		for stop: Dictionary in trip.stops:
			if stop["house_id"] != house_id:
				continue
			for order_id: StringName in stop["order_ids"]:
				if house.zone != StringName(book.get_order(order_id)["zone"]):
					return _fail("house_out_of_zone")
				var money: int = int(wallet.get("money"))
				var settled: Dictionary = OrderSettlement.settle(
					book, wallet, order_id, box, trips.minute(), [], products)
				if not bool(settled["ok"]) or int(settled["paid"]) <= 0:
					return _fail("not_settled")
				if int(wallet.get("money")) != money + int(settled["paid"]) + int(settled["tip"]):
					return _fail("not_paid")
				if not trip.record_settled(order_id, book):
					return _fail("not_recorded")
				ctx["deliveries"] = int(ctx["deliveries"]) + 1
	return _ok() if trip.pending_stops().is_empty() else _fail("stops_left")


## The driver takes the van back with the autopilot, the way it came: along the street graph to the
## avenue, the yard's leg in and into the playon (VAN.drive_in), where the gate closes the Trip with nothing
## failed; no vehicle is out (the day may close) and its summary has the deliveries and both clocks. The
## player gets out. The way must stay in the street like the way out.
static func come_back(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var trip: Trip = ctx["trip"]
	if trip == null:
		return _fail("no_trip_out")
	var trips: CompanyTrips = level.trips
	var vehicle: StringName = ctx["vehicle_id"]
	var net: RoadGraph = RoadGraph.load_default()
	var entry: Dictionary = street_entry(net)
	var in_leg: PackedVector2Array = VAN.leg(
		entry["point"], -(entry["dir"] as Vector2), ctx["park_point"],
		(ctx["park_point"] as Vector2) - (ctx["yard_exit"] as Vector2))
	var back: Dictionary = await VAN.drive_in(tree, level, vehicle, entry["point"], in_leg)
	var piloted: Dictionary = _piloted(ctx, "return", back)
	if piloted["status"] != "ok":
		return piloted
	if trip.is_out() or trips.trips_out() != 0 or trips.trip_of(vehicle) != null:
		return _fail("trip_not_closed")
	if not trip.failed_ids.is_empty():
		return _fail("orders_failed")
	var result: Dictionary = TripResult.build(trip, trips.book)
	if int(result["delivered"]) != int(ctx["deliveries"]) or int(result["failed"]) != 0:
		return _fail("result_counts")
	if str(result["return_clock"]) == "" or int(result["duration_min"]) < 0:
		return _fail("result_clock")
	return _ok()


## Where the yard's leg joins the street: {point: Vector2 (x z), dir: Vector2 unit, the way the avenue goes}.
static func street_entry(net: RoadGraph) -> Dictionary:
	var point: Vector2 = net.point_at(ENTRY_EDGE, ENTRY_ALONG_M)
	var ahead: Vector2 = net.point_at(ENTRY_EDGE, ENTRY_ALONG_M + 1.0)
	return {"point": point, "dir": (ahead - point).normalized()}


## The point of the street in front of a house (the nearest one of the graph): where the autopilot goes.
static func street_point(net: RoadGraph, house: HouseSpot) -> Vector2:
	return net.nearest_point(house.position)["point"]


## Records what the autopilot reported for a leg (ctx.autopilot[leg]) and turns it into a stage result:
## it has to have got there (or to the cap) and stayed in the street (off_road_max under
## VAN.OFF_ROAD_LIMIT_M outside the roadway, D-0304.3).
static func _piloted(ctx: Dictionary, leg: String, report: Dictionary) -> Dictionary:
	(ctx["autopilot"] as Dictionary)[leg] = report
	if str(report["reason"]) != "":
		return _fail("%s_%s" % [leg, report["reason"]])
	if float(report["off_road_max"]) > VAN.OFF_ROAD_LIMIT_M:
		return _fail("%s_off_road_%.1f_m" % [leg, float(report["off_road_max"])])
	if float(report.get("turn_off_road_max", 0.0)) > VAN.TURN_OFF_ROAD_LIMIT_M:
		return _fail("%s_turn_off_road_%.1f_m" % [leg, float(report["turn_off_road_max"])])
	return _ok()


## The van is taken to `house` with the autopilot unless it stands within HOUSE_REACH_M of it (or the
## run is capped, ctx.drive_cap_m: it never got there). "" when it is at the house, else why.
static func _drive_to_house(
	tree: SceneTree, level: CompanyRoot, ctx: Dictionary, house: HouseSpot
) -> String:
	if float(ctx["drive_cap_m"]) > 0.0:
		return ""
	var vehicle: StringName = ctx["vehicle_id"]
	var van: VehicleBody3D = VAN.van_of(level, vehicle)
	if van == null:
		return "no_van"
	if VAN.ground_of(van).distance_to(house.position) > HOUSE_REACH_M:
		var net: RoadGraph = RoadGraph.load_default()
		var piloted: Dictionary = await VAN.drive_to(tree, level, vehicle, street_point(net, house))
		var verdict: Dictionary = _piloted(ctx, "deliver", piloted)
		if verdict["status"] != "ok":
			return str(verdict["reason"])
	if VAN.ground_of(van).distance_to(house.position) > HOUSE_REACH_M:
		return "van_far_from_house"
	return ""


static func _ok() -> Dictionary:
	return {"status": "ok", "reason": ""}


static func _fail(reason: String) -> Dictionary:
	return {"status": "fail", "reason": reason}
