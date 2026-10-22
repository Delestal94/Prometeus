class_name PalletJackUse
extends RefCounted
## What one use of the pallet jack asks of the host (expansion D-0605.b), the jack's counterpart of
## PickingCartUse: the jack's points say who used it and how (PalletJackPoint.used), this turns it into the
## host's own requests on that peer's behalf (CompanyNet.request_for), which check reach and the floor again
## before anything moves.
##
## - the forks with the jack empty: jack_pick of the first pallet of the truck's bed when the truck is parked
##   and the bed is in reach of the jack, else of the nearest pallet on the floor in reach (plan_pick());
## - the forks with a pallet on them: jack_put, the pallet lands where the jack stands;
## - the handle: jack_push, one step (CompanyTuning.JACK_PUSH_STEP_M) away from the player;
## - the forklift's seat (D-0606.b): fork_act board, the rest of its requests come from the driver's own peer.
##
## Host only; nothing here changes state by itself. The answer is what happened: RESULT_* or a reason.

const RESULT_PICKED: StringName = &"picked"
const RESULT_PUT: StringName = &"put"
const RESULT_PUSHED: StringName = &"pushed"
const RESULT_BOARDED: StringName = &"boarded"
## The request reached the host's checks and they said no (out of reach, no room, blocked...).
const REASON_REFUSED: StringName = &"refused"
const REASON_NO_JACK: StringName = &"no_jack"
## Nothing the jack could pick up is in its reach.
const REASON_NOTHING_THERE: StringName = &"nothing_there"


## `from` is where the user stands (world), `peer` who they are. Returns RESULT_* or a reason.
static func use(net: CompanyNet, yard: PalletYardView, action: StringName, peer: int, from: Vector3) -> StringName:
	if net == null or not net.is_host() or yard == null or not is_instance_valid(yard) or not yard.is_inside_tree():
		return REASON_NO_JACK
	var station: Dictionary = {}
	if net.stations.is_valid():
		station = net.stations.call(CompanyPallets.STATION)
	match action:
		PalletJackPoint.ACTION_WORK:
			return _work(net, station, peer)
		PalletJackPoint.ACTION_PUSH:
			return _push(net, yard, station, peer, from)
		PalletJackPoint.ACTION_BOARD:
			var before: int = net.seq
			net.request_for(peer, CompanyPallets.FORK_ACT, {"act": CompanyForklift.ACT_BOARD})
			return RESULT_BOARDED if net.seq != before else REASON_REFUSED
	return REASON_NO_JACK


## The pallet the forks would take: the first of the bed (by id) when `station` says the truck is parked and the
## jack is within PALLET_JACK_REACH_M of its rear, else the nearest on the floor within that reach of the jack;
## &"" when there is none, or the jack is full.
static func plan_pick(pallets: CompanyPallets, station: Dictionary) -> StringName:
	var at: Variant = station.get("at")
	if pallets.book.carrying != &"" or not at is Vector2:
		return &""
	var reach: float = CompanyTuning.PALLET_JACK_REACH_M
	var rear: Variant = station.get("bed_at")
	var on_bed: Array[StringName] = pallets.book.ids_at(PalletJack.AT_BED)
	if bool(station.get("bed_open")) and rear is Vector2 and (at as Vector2).distance_to(rear) <= reach \
			and not on_bed.is_empty():
		return on_bed[0]
	var nearest: StringName = &""
	var best: float = reach
	for id: StringName in pallets.book.ids_at(PalletJack.AT_FLOOR):
		var apart: float = (at as Vector2).distance_to(pallets.book.places[id]["pos"])
		if apart <= best:
			best = apart
			nearest = id
	return nearest


static func _work(net: CompanyNet, station: Dictionary, peer: int) -> StringName:
	var carrying: bool = net.pallets.book.carrying != &""
	var kind: StringName = CompanyPallets.PUT if carrying else CompanyPallets.PICK
	var data: Dictionary = {}
	if not carrying:
		var id: StringName = plan_pick(net.pallets, station)
		if id == &"":
			return REASON_NOTHING_THERE
		data["pallet"] = id
	var before: int = net.seq
	net.request_for(peer, kind, data)
	if net.seq == before:
		return REASON_REFUSED
	return RESULT_PUT if carrying else RESULT_PICKED


## Away from the player: from where they stand to the jack, flattened, in the shed's frame.
static func _push(net: CompanyNet, yard: PalletYardView, station: Dictionary, peer: int, from: Vector3) -> StringName:
	var shed := yard.get_parent() as Node3D
	var at: Variant = station.get("at")
	if shed == null or not shed.is_inside_tree() or not at is Vector2:
		return REASON_NO_JACK
	var player: Vector3 = shed.to_local(from)
	var before: int = net.seq
	net.request_for(peer, CompanyPallets.PUSH, {"dir": (at as Vector2) - Vector2(player.x, player.z)})
	return RESULT_PUSHED if net.seq != before else REASON_REFUSED
