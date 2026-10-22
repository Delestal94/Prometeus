extends RefCounted
## The cases of the company mode's bandwidth budgets (D-2002), counted with
## tests/bandwidth_model.gd: where the crew is (the shed, a trip out, vehicles far away), what the
## host sends each client then, its worst client and the culprits. Not a test:
## test_company_bandwidth_budget.gd preloads it, with what it read from the real company world
## (`world`: {mtu, syncs, events, ride}; that test's _open_world() and _print_world() say what each
## holds) and says why each number is what it is.
##
## A layout (case_layout()) is {kind, crew, budget, held, riders, near}; a client's case
## (client_case()) is MODEL.host_to_client()'s {host, relayed, framing, datagrams, total} plus
## events, events_data, keepalive, culprits ([what, bytes/s with its datagrams, of it datagrams],
## largest first), places (where each player is: -1 the shed, v aboard vehicle v; 0 is the host) and
## client.

const MODEL := preload("res://tests/bandwidth_model.gd")
const KB: float = 1024.0
## D-2002's budgets, host -> one client: in the shed, with one trip out, with two vehicles far away.
const SHED_BUDGET: float = 24.0 * KB
const TRIP_BUDGET: float = 40.0 * KB
const FAR_BUDGET: float = 64.0 * KB
## The crew D-2002 sets the budgets for (4 ENet peers): every case must fit with it.
const MEASURED_CREW: int = 4
## Whether the full crew (NetworkManager.MAX_PLAYERS) is held to each case's budget: the shed's
## since its pose rate (D-2002.3); a trip's and two far vehicles' don't fit yet (D-2002.2:
## over_budget and the culprits are printed, docs/rendimiento-pc.md says what would make them fit).
## The test says so when one fits: hold it then.
const FULL_CREW_FITS: Dictionary = {"shed": true, "trip": false, "far": false}
## Players aboard each vehicle out (roles-tripulacion.md §2.3-2.4, "Ruta 1-2"): a driver and a
## passenger who tends a box.
const TRIP_RIDERS: int = 2
## Players who stay in the shed while vehicles are out (reception and packing, §2.3; always someone,
## §2.4): with 4 players two vehicles out carry a driver each.
const SHED_STAYS: int = 2
## The design's ceiling aboard (§1: a driver and up to 3 passengers) with one player left in the
## shed: the crowded trips, printed only.
const CROWDED_RIDERS: int = 4
const CROWDED_STAYS: int = 1
## A busy packing line: every player does a business action (take, store, place, tape; aboard, a
## delivery: a request the host turns into an event for everyone) a second, plus the host's own
## rules (orders, the clock, the day's phases). A human does one every 2-3 s; RpcGuard caps a peer
## at 20.
const ACTIONS_PER_PLAYER_PER_SECOND: float = 1.0
const HOST_EVENTS_PER_SECOND: float = 1.0
## A trip event (trip_started, trip_closed) a second per vehicle out: a ceiling, a trip sends two.
const TRIP_EVENTS_PER_VEHICLE_PER_SECOND: float = 1.0
## How often a tended box publishes its care_state in a delivery (package_rescue.gd simulate_cargo():
## every PackageRescue.CARE_PUBLISH_SEC, an ON_CHANGE delta each time something in it moved, as it does
## while someone tends it; D-2002.4). A company box's rate is world.ride.care_hz (BoxToPackage.tune()).
const CARE_PUBLISH_HZ: float = 10.0
## A delta's framing (scene_replication_interface.cpp, _send_delta): the command byte, then per
## synchronizer its net id (4), its size (4) and the mask of the properties in it (8). Reliable, a
## packet of its own (a ceiling: two boxes publishing on one frame would share one).
const DELTA_HEADER: int = 17


## A case for `crew` players, `kind` "shed", "trip" or "far": {kind, crew, budget, held: whether the
## test fails over it, riders: the players aboard each vehicle out (at most `each`, `stays` left in
## the shed, a driver at least), near: whether the shed's clients get the vehicles out}. The
## vehicles out: none, one, or CompanyTuning.VEHICLES_FAR_MAX.
static func case_layout(kind: String, crew: int, each: int, stays: int) -> Dictionary:
	var vehicles: int = {"shed": 0, "trip": 1, "far": CompanyTuning.VEHICLES_FAR_MAX}[kind]
	var riders: Array = []
	riders.resize(vehicles)
	riders.fill(0)
	for seat: int in range(mini(vehicles * each, maxi(crew - stays, vehicles))):
		riders[seat % vehicles] += 1
	return {
		"kind": kind, "crew": crew, "riders": riders, "near": kind != "far",
		"budget": {"shed": SHED_BUDGET, "trip": TRIP_BUDGET, "far": FAR_BUDGET}[kind],
		"held": crew == MEASURED_CREW or bool(FULL_CREW_FITS[kind]),
	}


## Where each of `crew` players is (-1 in the shed, v aboard vehicle v), the host (index 0) at
## `host_place`, the vehicles filled to `riders` and the rest in the shed; [] if the host can't be
## there (nobody else stays in the shed, nobody rides v).
static func places(crew: int, riders: Array, host_place: int) -> Array:
	if host_place >= 0 and int(riders[host_place]) <= 0:
		return []
	var found: Array = [host_place]
	for vehicle: int in range(riders.size()):
		for _seat: int in range(int(riders[vehicle]) - (1 if vehicle == host_place else 0)):
			found.append(vehicle)
	while found.size() < crew:
		found.append(-1)
	return found if found.size() == crew else []


## `layout`'s worst client: the host in the shed or aboard each vehicle, every client
## (client_case()), with upload: what the host sends all its clients in that arrangement.
static func worst(world: Dictionary, layout: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for host_place: int in range(-1, (layout.riders as Array).size()):
		var where: Array = places(int(layout.crew), layout.riders, host_place)
		var upload: float = 0.0
		var top: Dictionary = {}
		for client: int in range(1, where.size()):
			var case: Dictionary = client_case(world, layout, where, client)
			upload += float(case.total)
			if top.is_empty() or float(case.total) > float(top.total):
				top = case
		if not top.is_empty() and (found.is_empty() or float(top.total) > float(found.total)):
			top.upload = upload
			found = top
	return found


## What the host sends client `client` of `where` (index 0 is the host) in `layout` (the header's
## case): the host's own synchronizers (_host_groups()), the other clients' players it relays
## (_relayed_groups()), the events (_event_items()) and CompanyInterest's keepalive
## (_keepalive_items()).
static func client_case(
	world: Dictionary, layout: Dictionary, where: Array, client: int
) -> Dictionary:
	var host: Array = _host_groups(world, layout, where, client)
	var relayed: Array = _relayed_groups(world, where, client)
	var case: Dictionary = MODEL.host_to_client(host[0], relayed[0], int(world.mtu))
	var culprits: Array = []
	var shares: Array = _host_shares(host[0], int(world.mtu))
	for index: int in range(host[0].size()):
		if int(host[0][index][2]) > 0:
			culprits.append([host[1][index], shares[index][0], shares[index][1]])
	for index: int in range(relayed[0].size()):
		var group: Array = relayed[0][index]
		var packets: float = int(group[2]) / float(group[0])
		var framing: float = packets * MODEL.PACKET_OVERHEAD_BYTES
		if packets > 0.0:
			var bytes: int = MODEL.RELAY_HEADER + MODEL.SYNC_PACKET_HEADER + int(group[1])
			var data: float = packets * bytes
			culprits.append([relayed[1][index], data + framing, framing])
	case.events = 0.0
	case.events_data = 0.0
	case.keepalive = 0.0
	case.care = 0.0
	for part: String in ["events", "keepalive", "care"]:
		var items: Array = (_event_items(world, layout) if part == "events"
			else _keepalive_items(world, layout, where, client) if part == "keepalive"
			else _care_items(world, layout, where, client))
		for item: Array in items:
			culprits.append([item[0], item[1], item[2]])
			case.framing = float(case.framing) + float(item[2])
			case.datagrams = float(case.datagrams) + float(item[3])
			case.total = float(case.total) + float(item[1])
			case[part] = float(case[part]) + float(item[1])
			if part == "events":
				case.events_data = float(case.events_data) + float(item[1]) - float(item[2])
	culprits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	case.culprits = culprits
	case.places = where
	case.client = client
	return case


## Players in the shed of `where` (the host too) while vehicles are out: each loads the next vehicle,
## a box in its hands moving at a box's full rate (D-2002.4, auditor-red's 3rd caveat of D-2002.2).
static func loading(layout: Dictionary, where: Array) -> int:
	return where.count(-1) if not (layout.riders as Array).is_empty() else 0


## The load of the first `out` vehicles of `riders`: (boxes tended, one by each passenger or by a
## lone driver; boxes riding still, the rest of each vehicle's cargo, `ride.cargo`).
static func cargo(ride: Dictionary, riders: Array, out: int) -> Vector2i:
	var boxes := Vector2i.ZERO
	for vehicle: int in range(out):
		var tended: int = mini(maxi(int(riders[vehicle]) - 1, 1), int(ride.cargo))
		boxes += Vector2i(tended, int(ride.cargo) - tended)
	return boxes


## The culprits of a case, the first `most`, as a line (KB/s).
static func culprit_text(culprits: Array, most: int) -> String:
	var parts: PackedStringArray = []
	for culprit: Array in culprits.slice(0, most):
		parts.append("%s %.1f (datagrams %.1f)" % [culprit[0], float(culprit[1]) / KB,
			float(culprit[2]) / KB])
	return "; ".join(parts)


## Who a case is about: where its client and the host are, and who rides.
static func who(layout: Dictionary, case: Dictionary) -> String:
	var where: Array = case.places
	return "a client %s, the host %s, aboard %s" % [place_name(int(where[int(case.client)])),
		place_name(int(where[0])), str(layout.riders)]


static func place_name(place: int) -> String:
	return "in the shed" if place < 0 else "aboard vehicle %d" % (place + 1)


static func key(layout: Dictionary) -> String:
	return "%s_crew%d" % [layout.kind, layout.crew]


static func title(layout: Dictionary) -> String:
	var what: String = {"shed": "the shed", "trip": "a trip out",
		"far": "%d vehicles far" % (layout.riders as Array).size()}[layout.kind]
	return "%s and %d players" % [what, layout.crew]


## The shortest interval of these synchronizer entries ([interval, entry bytes, name]).
static func fastest(entries: Array) -> float:
	var found: float = 1.0
	for entry: Array in entries:
		found = minf(found, float(entry[0]))
	return found


## What the host owns that reaches client `client` of `where`: [groups as MODEL.host_to_client()
## takes them ([interval, entry bytes, how many]), a name each]. The shed's synchronizers
## (everyone), the parked vehicles (those near the shed), the host's player (aboard or on foot), and
## the vehicles out with their loads (cargo()): to their riders and, near, to the shed.
static func _host_groups(world: Dictionary, layout: Dictionary, where: Array, client: int) -> Array:
	var syncs: Dictionary = world.syncs
	var ride: Dictionary = world.ride
	var riders: Array = layout.riders
	var aboard: bool = int(where[client]) >= 0
	var groups: Array = []
	var owners: Array[String] = []
	for entry: Array in syncs.shed:
		groups.append([entry[0], entry[1], 1])
		owners.append("shed %s" % entry[2])
	if not aboard or bool(layout.near):
		for entry: Array in (syncs.vehicles as Array).slice(riders.size()):
			groups.append([entry[0], entry[1], 1])
			owners.append("parked %s" % entry[2])
	for entry: Array in (ride.player if int(where[0]) >= 0 else syncs.player):
		groups.append([entry[0], entry[1], 1])
		owners.append("the host's player %s (%s)" % [place_name(int(where[0])), entry[2]])
	if riders.is_empty():
		return [groups, owners]
	var out: int = riders.size() if aboard or bool(layout.near) else 0
	var carried: int = loading(layout, where) if not aboard or bool(layout.near) else 0
	groups.append([ride.box_interval, ride.box_entry, carried])
	owners.append("%d boxes carried in the shed, loading" % carried)
	var boxes: Vector2i = cargo(ride, riders, out)
	groups.append([ride.vehicle[0], ride.vehicle[1], out])
	owners.append("%d vehicles out, moving (%s)" % [out, ride.vehicle[2]])
	groups.append([ride.box_interval, ride.box_entry, boxes.x])
	owners.append("%d boxes tended aboard" % boxes.x)
	groups.append([ride.box_rest, ride.box_entry, boxes.y])
	owners.append("%d boxes riding still" % boxes.y)
	return [groups, owners]


## The other clients' players, which reach client `client` of `where` through the host: [groups,
## names] as _host_groups(), those aboard at a rider's rate, those in the shed at the shed's.
static func _relayed_groups(world: Dictionary, where: Array, client: int) -> Array:
	var others := Vector2i.ZERO
	for index: int in range(1, where.size()):
		if index != client:
			others += Vector2i(1, 0) if int(where[index]) >= 0 else Vector2i(0, 1)
	var groups: Array = []
	var owners: Array[String] = []
	for entry: Array in world.ride.player:
		groups.append([entry[0], entry[1], others.x])
		owners.append("%d other riders relayed (%s)" % [others.x, entry[2]])
	for entry: Array in world.syncs.player:
		groups.append([entry[0], entry[1], others.y])
		owners.append("%d other players in the shed relayed (%s)" % [others.y, entry[2]])
	return [groups, owners]


## The events every client gets, [what, bytes/s with their datagrams, of it datagrams, datagrams/s]
## each: the busy line's business events and the trip events of the vehicles out, each the size of
## the largest real one of its kind (world.events.busy_bytes, world.ride.trip_bytes), in a datagram
## of its own.
static func _event_items(world: Dictionary, layout: Dictionary) -> Array:
	var business: float = int(layout.crew) * ACTIONS_PER_PLAYER_PER_SECOND + HOST_EVENTS_PER_SECOND
	var trips: float = (layout.riders as Array).size() * TRIP_EVENTS_PER_VEHICLE_PER_SECOND
	var items: Array = []
	for kind: Array in [["business events", business, int(world.events.busy_bytes)],
			["trip events, a ceiling", trips, int(world.ride.trip_bytes)]]:
		var rate: float = kind[1]
		if rate > 0.0:
			var framing: float = rate * MODEL.PACKET_OVERHEAD_BYTES
			var what: String = "%s (%.0f/s)" % [kind[0], rate]
			items.append([what, rate * int(kind[2]) + framing, framing, rate])
	return items


## The care_state deltas of the tended boxes client `client` of `where` sees (those of the vehicles it
## gets, as _host_groups()), items as _event_items(): CARE_PUBLISH_HZ each, the size of the largest real
## one (world.ride.care_bytes: publish_care()'s state of a tended box, the worst trap), in a datagram of
## its own.
static func _care_items(world: Dictionary, layout: Dictionary, where: Array, client: int) -> Array:
	var ride: Dictionary = world.ride
	var riders: Array = layout.riders
	if riders.is_empty() or int(ride.get("care_bytes", 0)) <= 0:
		return []
	var aboard: bool = int(where[client]) >= 0
	var tended: int = cargo(ride, riders, riders.size() if aboard or bool(layout.near) else 0).x
	if tended <= 0:
		return []
	var rate: float = tended * float(ride.get("care_hz", CARE_PUBLISH_HZ))
	var framing: float = rate * MODEL.PACKET_OVERHEAD_BYTES
	return [["care_state deltas of %d tended boxes (%.0f/s each)" % [tended, rate / tended],
		rate * (DELTA_HEADER + int(ride.care_bytes)) + framing, framing, rate]]


## CompanyInterest's keepalive while the vehicles are far from the shed, items as _event_items(). A
## client in the shed gets every hidden body for its pulse each keepalive (the longer of the pulse
## and two of the body's intervals, at its rate; a box riding still sends at the full rate for its
## settle_seconds of it if the pulse wakes its NetRestThrottle). A rider gets the boxes riding still
## at the full rate for settle_seconds each wake a pulse to a client in the shed gives them
## (ride.pulse_wakes: how many times a pulse, on and off, wakes a resting box's NetRestThrottle, as
## WorldCellInterest pulses it, 2 before D-2002.4; ride.pulse_wake_on: whether showing it does), for
## every client in the shed: each one's pulses
## have their own clock (hidden_at, D-2002.4: the clients hidden at different looks). A ceiling: a
## pulse's sends a packet each.
static func _keepalive_items(
	world: Dictionary, layout: Dictionary, where: Array, client: int
) -> Array:
	var ride: Dictionary = world.ride
	var riders: Array = layout.riders
	var every: float = float(ride.keepalive)
	if bool(layout.near) or riders.is_empty() or every <= 0.0:
		return []
	var boxes: Vector2i = cargo(ride, riders, riders.size())
	var settle: float = float(ride.box_settle)
	var full: float = float(ride.box_interval)
	var wakes: int = int(ride.get("pulse_wakes", 2))
	if int(where[client]) >= 0:
		var shed_clients: int = where.slice(1).count(-1)
		if shed_clients == 0 or boxes.y == 0 or wakes == 0:
			return []
		var extra: float = 1.0 / full - 1.0 / float(ride.box_rest)
		var woken: float = boxes.y * wakes * settle * extra / every * shed_clients
		return [[("keepalive wakes of %d boxes riding still (NetRestThrottle), %d clients in the shed"
			+ " pulsed apart") % [boxes.y, shed_clients], woken * int(ride.box_entry), 0.0, 0.0]]
	# [how many, interval when the pulse starts, entry bytes, woken by it]
	var bodies: Array = [
		[riders.size(), float(ride.vehicle[0]), int(ride.vehicle[1]), false],
		[boxes.x, full, int(ride.box_entry), false],
		[boxes.y, float(ride.box_rest), int(ride.box_entry), true],
	]
	var sends: float = 0.0
	var data: float = 0.0
	for body: Array in bodies:
		var span: float = maxf(float(ride.pulse), 2.0 * float(body[1]))
		var woken: bool = body[3] and bool(ride.get("pulse_wake_on", true))
		var awake: float = minf(span, settle) if woken else 0.0
		var count: float = int(body[0]) * (awake / full + (span - awake) / float(body[1]))
		sends += count
		data += count * (MODEL.SYNC_PACKET_HEADER + int(body[2]))
	var framing: float = sends * MODEL.PACKET_OVERHEAD_BYTES / every
	var hidden: int = riders.size() + boxes.x + boxes.y
	return [["keepalive pulses of %d hidden bodies (CompanyInterest)" % hidden,
		data / every + framing, framing, sends / every]]


## What each host-owned group costs a client, [bytes/s, of it datagrams]: the packets of its
## interval (at most `mtu` bytes each), headers and datagrams included, shared among the groups in
## them by bytes.
static func _host_shares(groups: Array, mtu: int) -> Array:
	var shares: Array = []
	for group: Array in groups:
		var together: Array = []
		var all: float = 0.0
		for other: Array in groups:
			if is_equal_approx(float(other[0]), float(group[0])):
				for index: int in range(int(other[2])):
					together.append(int(other[1]))
				all += int(other[1]) * int(other[2])
		var packed: Vector2i = MODEL.pack(together, mtu)
		var share: float = int(group[1]) * int(group[2]) / maxf(all, 1.0) / float(group[0])
		var framing: float = packed.x * MODEL.PACKET_OVERHEAD_BYTES * share
		shares.append([(packed.y + packed.x * MODEL.PACKET_OVERHEAD_BYTES) * share, framing])
	return shares
