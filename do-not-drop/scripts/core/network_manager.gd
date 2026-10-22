extends NetSession
## Session setup and the peer roster for Take My Package, on the net_session
## module's NetSession (docs/modulos.md). Host-authoritative, per
## docs/requerimientos-tecnicos.md: clients send input, the host simulates,
## the result is replicated.
##
## The module runs the transports (Steam lobby or ENet), the versioned
## handshake, the roster, the restart and the failures. This file is what
## the handshake carries for *this* game -- the world every peer builds the
## same way, and the colour slot each player wears -- and where it comes
## from (UnlockManager, RunManager), plus the menu's texts for a failure and
## the F3 network overlay.

const MAX_PLAYERS: int = 8
## Increment whenever peers can no longer share the same replicated scene,
## handshake or meaning of a relayed payload (3: trap names travel as keys;
## 4: package hints and care messages travel as [key, args...];
## 5: the depot sends the Boss's radio lines as LocText, a new RPC on the depot;
## 6: the low-visibility event's late-join RPC;
## 7: the player gets a Sprint child with RPCs and anim_state can be Run,
## N-115;
## 8: truck radio node + _set_mode RPC, N-406;
## 9: house orders carry the content id and results complaints carry
## client + line key, S-604;
## 10: the handshake carries the colour slots ("colors") and the host sends
## them again through _sync_color_slots, N-226;
## 11: the restart RPC carries a dictionary and the event bus relays peer
## requests through one RPC, N-231;
## 12: cargo_animal_alert / cargo_animal_ended are relayed, N-109;
## 13: the host tells each client when to wait out its level loads
## (_host_load_timeout, NetSession), N-235;
## 14: the player replicates its nickname and the host relays the next-day
## newspaper (EventBus.newspaper_ready), N-606;
## 15: the handshake carries a session nonce and the ready reply an identity
## (rejoin), every any_peer RPC goes through RpcGuard, and a slot is kept for
## a peer who left so it gets it back when it rejoins, N-221;
## 16: the mud segment replicates its state and receives push beats over RPC, N-108;
## 17: the van has a seventh package mount (CargoBay/RightSeat3PackageMount, a new
## interactable) and three passenger seats tend it, N-228.4;
## 18: a package replicates lap_mount_path, the bay a lap box goes back to, N-228.8;
## 19: the van replicates net_wheel_heights instead of its four wheel transforms, N-228.5;
## 20: the handshake and _sync_color_slots carry the slots of those who left
## ("departed"), a full room takes back a player whose ghost still holds its
## place (decided from its ready reply on LAN), a LAN identity is a hash chain
## (each rejoin claims the link before), and _report_level_ready only counts a
## report the host owes, N-221 follow-ups;
## 21: the player spawn data may carry vehicle_position, where a mid-run joiner
## appears in the truck's own space, N-228.7;
## 22: the service stop's counter (_open_locally) and shop (_receive_state)
## RPCs, and shop votes whose offers carry a venue, N-110;
## 23: the player replicates net_yaw instead of rotation, and the player and the
## package a net_time pose clock, both at 30 Hz, N-217;
## 24: a package replicates carrier_peer_id and hold_offset, and
## submit_carry_transform carries the pose in the carrier's body space, N-217;
## 25: skipped (N-218 bumped to it but the merge kept main's 26: builds
## b68207e..7496de3 carry 26 without N-218 and c760998..805a8c9 carry 26 with
## it; 27 tells them apart);
## 26: a joiner to a full LAN room is asked who it is (the nonce alone, its
## identity reply) before it gets the state and loads the level, N-221;
## 27: the client driver predicts the truck: submit_driver_input carries an input
## sequence, the van replicates net_simulating, net_input_seq and its
## velocities, steering and engine force through net_* proxies, N-218 / N-922;
## 28: the restart payload carries the host's new world seed, applied before
## the client reloads its level, N-963;
## 29: CompanyNet's _request, _apply_event and _rejected RPCs (company mode
## business events), D-2003);
## 30: CompanyNet's _snapshot RPC (company mode late join and seq gaps,
## expansión), D-2004);
## 31: CompanyNet's _apply_event carries a new kind, clock_anchor, and its
## snapshot a "clock" part (the company day's clock from the host), D-0219;
## 32: CompanyNet's _apply_event carries a new kind, day_phase, and its
## snapshot a "day_cycle" part (the company day's phase and frozen shed from
## the host), D-0203;
## 33: CompanyNet's _request takes a new kind, units_drop, and units_moved
## events to floor:<n> carry pos; the snapshot carries floor positions
## (company mode, D-2006);
## 34: CompanyNet's _request takes four new kinds (layout_place, layout_move,
## layout_rotate, layout_sell) and _apply_event three (layout_placed,
## layout_moved, layout_sold): the shed layout the host builds (company mode, D-0910);
## 35: player.tscn replicates GelFaceReactions:base_face_id (the gel face a
## player picked, S-311.61 / #475), N-972;
## 36: a peer whose level comes up mid-run is sent the rescue hook's _set_armed by
## the host, and restores the doors already resolved from the session state's
## deliveries (EventBus.delivery_restored, local), N-975;
## 37: CompanyNet's _request takes seven new kinds (box_start, box_place,
## box_take_out, box_fill, box_label, box_stamp, box_tape), _apply_event seven
## (box_started ... box_sealed) and its snapshot a "packing" part: the shared
## packing tables (company mode, D-0715);
## 38: the company world (company_root.tscn) is in LEVEL_SCENES, so a joiner may
## be sent to it, and its World/PlayerSpawner spawns the crew (company mode
## online, D-0214);
## 39: CompanyNet's _request takes a new kind, cart_push, _apply_event a new one,
## cart_moved, and its snapshot a "carts" part: where the picking carts stand
## (company mode, D-0610.b);
## 40: CompanyNet's _apply_event carries three new kinds, trip_started,
## trip_refused and trip_closed, and its snapshot a "trips" part: the company
## vehicles out of the shed, as the host's CompanyTrips decides them (company
## mode, D-0302.2);
## 41: CompanyNet's _apply_event carries two new kinds, order_added and
## order_expired, and its snapshot an "orders" part: the day's order book from
## the host (company mode, D-0813);
## 42: box_sealed makes a DeliveryPackage on every peer, World/Packages/
## Package_<box id>; a client tells the host it has it with a new CompanyNet
## _request kind, package_ack, and only then does the host open that package's
## MultiplayerSynchronizer to it; a peer checks the event's node_name, pos, basis,
## trap, trap_intensity, absorption and quality first, and box_tape may be refused
## with no_trap (company mode, D-0715.b);
## 43: CompanyNet's _request takes three new kinds, jack_pick, jack_put and jack_push,
## _apply_event four, jack_picked, jack_placed, jack_moved and jack_loaded, and its
## snapshot a "pallets" part: the supplier pallets and the pallet jack (company
## mode, D-0605.b);
## 44: CompanyNet's _request takes a new kind, supplier_order, _apply_event a new
## one, supplier_ordered, and its snapshot a "supplier" part: the supplier
## calendar; the shed's SupplierBoardPoint has a new RPC, _open_here (company
## mode, D-0603.b.2);
## 45: the company's loose boxes (World/Packages) are sent only to the players
## near them and hidden on a far client: an older client keeps a stale copy of a
## box the host stops sending, and the host's consume() of a far box broadcasts
## _remote_consume only after it lets the box go (company mode, D-0316.3);
## 46: CompanyNet's _apply_event takes a fifth jack event, jack_departed {day, lines}
## (the supplier truck drove off with what was left on its bed), and the "pallets"
## snapshot part carries departed_day and the delivery note (company mode, D-0618.b).
## 47: CompanyNet's _apply_event carries a new host kind, wallet_moved {amount,
## reason, money, minute}: the company's money moved by the host with no request,
## set on every peer from the host's balance (company mode, D-0517);
## 48: CompanyNet's _request takes a new kind, fork_act (get on, mast with the stop's `at_height`,
## take or leave a pallet, get off: the forklift a player drives), jack_picked takes `by`, jack_placed takes
## `slot`, _apply_event a new kind, fork_state, and the "pallets" snapshot part a
## "forklift" entry (company mode, D-0606.b);
## 49: the company world has its vehicles on every peer, World/Vehicles/<vehicle
## id> (vehicle.tscn and its synchronizer, sent only to the players near it): the
## client builds them from the host's snapshot and acks them with a new RPC on
## World/Vehicles, CompanyFleet._have_fleet, and only then does the host open each
## one's synchronizer to it; an older client has no such node and would not hide a
## far copy; the van relays vehicle_telemetry only during a run (company mode,
## D-0302.2.b).
## 50: CompanyNet's _request takes a new kind, shop_buy, and _apply_event a new
## one, shop_bought {item, money, minute}: the company shop's purchases, only the
## host's go through and a client's is refused with host_only (company mode, D-0518).
## 51: CompanyNet's _apply_event takes a new host kind, units_spoiled {product, qty,
## location}: cold products left outside a fridge rotted, and every peer discards them
## from its stock (company mode, D-0616.b).
## 52: CompanyTripsView (the company world's TripsView) has a new RPC, _held_here(vehicle, cap): the
## host tells the driver of a company vehicle it holds at the gate why (one with cargo that may not
## leave with VEHICLES_FAR_MAX out: before, it crossed and counted as out); an older client gets an
## RPC it doesn't have (company mode, D-0316.2).
## 53: the "orders" snapshot part carries `stars` (1-5, the customer's rating) on a
## delivered order; an older client refuses that book (company mode, D-0816.b).
## 54: CompanyNet's _request takes two new kinds, box_restock {station, supply} and
## box_discard {station}, and _apply_event two, box_restocked {table, supply, count} and
## box_discarded {table, box, contents, to[, pos]}: a packing table restocked and its open
## box thrown away, the units back in the hands or in a floor bundle (company mode, D-0715.c).
## 55: CompanyNet's supplier_ordered may come from the host with no request and peer 0
## (AUTO_PEER): the host's automatic supplier order at the day's close; an older client applies
## it but shows no summary line (company mode, D-0151.3b).
## 56: CompanyNet's supplier_order request names the supplier (`supplier`, none: the
## default one), supplier_ordered carries it, and the "supplier" snapshot part a
## `suppliers` entry with the other suppliers' trucks; an older client refuses the
## event and that part (company mode, D-0621.b).
## 57: player.tscn and package.tscn replicate `net_vehicle` (which vehicle the pose's
## space is, VehiclePick.index_of(), -1 none) after their other properties, and the box's
## submit_carry_transform and request_drop take a trailing `vehicle` index: with several
## vehicles every copy goes on the one its owner rides (D-0302.2.b.4.b).
## 58: CompanyNet's _request takes a new kind, trip_tow {vehicle, rid}: any peer asks the host to tow a
## stuck or broken company vehicle home; it goes out as the wallet_moved (reason tow) and trip_closed events
## that already exist, and a refusal comes back with a WORLD_TOW_* key (company mode, D-0307.1).
## 59: CompanyNet's _request takes a new kind, shed_expand {stage}, and _apply_event a
## new one, shed_expanded {stage, minute, money}: the host grows the shed to its next
## stage and every peer redraws the bigger grid at once; a client's request is refused
## with host_only (company mode, D-0910.2).
## 60: a package no longer replicates hold_offset and submit_carry_transform drops its
## `in_hands`: every peer draws a box held on foot in its carrier's hands from that player's
## own pose, and the host sends its pose only every 5 s meanwhile (D-2002.5).
## Any change to an RPC, to what is replicated or to what a relayed payload
## means bumps it (docs/convenciones-godot.md 0.2).
## Both sides exchange it before either starts scene replication.
const PROTOCOL_VERSION: int = 60
## Valve's sample app. Fine for development -- it gives us P2P and NAT
## punch-through without owning an app id -- but not for shipping.
const APP_ID_SPACEWAR: int = 480

## The {peer_id: colour slot} map changed (N-226): a copy of the whole map.
## On a client a new peer may show up in roster_changed a moment before its
## slot arrives here, so colour readers listen to both.
signal color_slots_changed(slots: Dictionary)

## The number every peer's procedural world is built from.
##
## route.gd and route_streamer.gd used to call _rng.randomize() on each
## machine independently, which meant **every player got a different road**:
## the van's transform replicates from the host, so a client watched it
## drive through houses that weren't there and off a road that ran somewhere
## else entirely. Nothing caught it because both sides individually worked.
## The host picks a fresh seed when the room opens and on every restart,
## and hands it to each client before they load the level. Joining a run
## keeps its current seed. 0 means "no session decided one", i.e. solo play,
## where randomize() is exactly right.
var world_seed: int = 0
## How many delivery houses this session's route has (docs/tareas-nacho.md
## #104). The route used to work it out from each machine's own roster, but a
## client's roster starts as just [host, itself], so from three players up
## every peer built a different number of houses. The host's route decides it
## once per run, the first time it builds, and each joiner gets it with the
## seed. A host restart decides it afresh and clients rebuild with that
## count. 0 means "not decided yet" (and always, playing solo).
var world_house_count: int = 0
## Traps this session's depot leaves off the shelves: the ones the *host's*
## profile hasn't unlocked yet (UnlockManager.locked_traps()), fixed when the
## room is created and handed to each joiner. Every peer has to shelve the
## same boxes -- they're the same replicated nodes -- so a client's own
## profile doesn't get a say. Only read while world_seed != 0; solo play asks
## UnlockManager directly.
var world_locked_traps: Array = []
## The host profile's completed-run count drives order difficulty. Like the
## locked list, it must be shared: a joiner's local profile may be different.
var world_completed_runs: int = 0
## Which colour slot each peer wears, {peer_id: slot 0..MAX_PLAYERS-1}
## (N-226, ColorSlots). The host hands them out in arrival order -- itself 0,
## each joiner the lowest free one as it starts authenticating, so the join
## handshake already carries it -- and sends the whole map to everyone again
## whenever it changes (_sync_color_slots). The random ids ENet and Steam give
## made posmod(peer_id, 5) a new colour every session, often a shared one.
## Kept across a host restart; empty outside a session. Read it through
## color_slot().
var _color_slots: Dictionary = {}
## Every side: the last slot of peers who left, {peer_id: slot}, so their
## line in the results and the campaign entry the host keeps for them
## (CrewProgression captures a leaver after its slot was released) still
## match the colour they wore. The DEPARTED_MEMORY most recent. The host sends
## its own with the slot map, so a joiner who wasn't there reads the same.
var _departed_slots: Dictionary = {}
const DEPARTED_MEMORY: int = 16
## Host (N-221): slots kept for someone who left and may come back,
## {slot: {"identity": String, "peer": old peer id}}. A newcomer only gets one
## when no other slot is free (the reservation is then lost); the one who left
## gets it back when it rejoins (_peer_returned). One per slot at most.
var _slot_reservations: Dictionary = {}
## Host: peers who took a slot reserved for someone else because the room was
## otherwise full, {peer_id: the old peer id it was kept for}. They start
## clean instead of inheriting the merit and card the campaign keeps under
## that slot (inherits_color_slot()) -- unless they turn out to be that one.
var _fresh_slots: Dictionary = {}
## Host: the reservation a joiner took while it authenticated, {peer_id:
## {"slot": int, "reservation": {...}}}, until it is on the roster. If it never
## gets there, or turns out to be someone back for another kept slot, the
## reservation goes back to whoever it was kept for (N-221).
var _borrowed_reservations: Dictionary = {}

const DEFAULT_LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
## The scenes a room plays in (NetSession.level_scenes): the handshake sends a joiner to the
## host's and refuses any other. The company world (D-0214) is a room of its own (--host-company).
const LEVEL_SCENES: Array[String] = [
	"res://scenes/gameplay/level_base.tscn",
	"res://scenes/gameplay/level_endless.tscn",
	"res://scenes/gameplay/company_root.tscn",
]
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
## Loaded in _ready, not preloaded: it builds on UiTheme, which an autoload
## this early shouldn't compile along with itself.
const NET_STATS_OVERLAY_PATH: String = "res://scripts/presentation/net_stats_overlay.gd"
const FAILURE_KEYS: Dictionary = {
	"steam_unavailable": "UI_NET_STEAM_UNAVAILABLE",
	"no_lobby": "UI_NET_NO_LOBBY_ID",
	"lobby_create": "UI_NET_LOBBY_CREATE_FAILED",
	"lobby_join": "UI_NET_LOBBY_JOIN_FAILED",
	"host_lost": "UI_NET_HOST_LOST",
}


func _init() -> void:
	protocol_version = PROTOCOL_VERSION
	max_players = MAX_PLAYERS
	level_scenes = LEVEL_SCENES.duplicate()
	main_menu_scene = MAIN_MENU_SCENE


func _ready() -> void:
	# F3: ping, loss, KB/s and queue, on any screen (hidden until asked for).
	var overlay: Node = (load(NET_STATS_OVERLAY_PATH) as GDScript).new()
	overlay.set(&"session", self)
	add_child(overlay)
	super()


## The colour slot `peer_id` wears (N-226): 0..MAX_PLAYERS-1, handed out by
## the host in arrival order and the same on every peer for the whole session.
## A peer who left keeps the last one it wore (_departed_slots). Outside a
## session, or for a peer the host hasn't announced yet, it is
## posmod(peer_id, MAX_PLAYERS); PlayerColorSlot pins the host to 0 either way. Readers wrap it to their own
## palette size (Player.PLAYER_COLORS has MAX_PLAYERS colours): posmod(color_slot(id), palette.size()).
func color_slot(peer_id: int) -> int:
	if not _color_slots.has(peer_id) and _departed_slots.has(peer_id):
		return int(_departed_slots[peer_id])
	return ColorSlots.slot_of(_color_slots, peer_id, MAX_PLAYERS)


## Whether `peer_id` may take what the campaign keeps under its slot
## (CrewProgression): false for a newcomer who took the slot kept for someone
## who left, because the room was otherwise full (N-221).
func inherits_color_slot(peer_id: int) -> bool:
	return not _fresh_slots.has(peer_id)


## Who left the slot `peer_id` took without inheriting it (inherits_color_slot()
## false), 0 if nobody: what the campaign keeps under it is theirs.
func slot_kept_for(peer_id: int) -> int:
	return int(_fresh_slots.get(peer_id, 0))


# --- What the handshake carries for this game ----------------------------------

## Host: decided once, so every joiner gets the same world no matter which
## transport they arrive on. The seed is never 0: that value means "solo".
func _on_hosting() -> void:
	_roll_world_seed()
	world_house_count = 0
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	world_locked_traps = unlocks.call(&"locked_traps") if unlocks != null else []
	world_completed_runs = int(unlocks.get(&"completed_runs")) if unlocks != null else 0


## Only when the host starts a new world: clients take its wire seed.
## Zero is reserved for solo; reject a repeat of the immediately prior run.
func _roll_world_seed() -> void:
	var next_seed: int = randi() | 1
	while next_seed == world_seed:
		next_seed = randi() | 1
	world_seed = next_seed


## Host, on creating the room: a fresh slot map with itself on slot 0.
func _on_session_hosted() -> void:
	_start_color_slots_as_host()


## Its colour slot first, so the handshake already carries it (and the crew
## already has it when the newcomer shows up). No free slot means no room;
## NetSession asks again once a joiner whose ghost holds a slot says who it is.
func _admit_peer(id: int) -> String:
	if _assign_color_slot(id) < 0:
		return "full"
	_publish_color_slots()
	return ""


## Normally assigned while it authenticated; this only fills a gap. Everyone
## again, the newcomer included: its copy from the handshake may have gone
## stale while it loaded the level (others came and went).
func _peer_joined(id: int) -> void:
	if multiplayer.is_server():
		# On the roster: a reservation it took is spent for good.
		_borrowed_reservations.erase(id)
		_assign_color_slot(id)
		_publish_color_slots()


## Its slot is free for the next one in; nobody else's moves. If the host
## knows who it was (NetSession.peer_identity(), N-221) the slot is kept for
## it while others are free, so it finds its colour -- and with it its merit
## -- when it comes back. Also a joiner that never made it in (its
## authentication failed) and a ghost connection dropped for its rejoin. A
## joiner that never made it in gives back the reservation it took.
func _peer_left(id: int) -> void:
	if not multiplayer.is_server() or not _color_slots.has(id):
		return
	var slot: int = int(_color_slots[id])
	var borrowed: Dictionary = _borrowed_reservations.get(id, {})
	ColorSlots.release(_color_slots, id)
	_remember_departed(id, slot)
	_fresh_slots.erase(id)
	_borrowed_reservations.erase(id)
	var identity: String = peer_identity(id)
	if not borrowed.is_empty() and int(borrowed.slot) == slot:
		_slot_reservations[slot] = borrowed.reservation
	elif not identity.is_empty():
		_slot_reservations[slot] = {"identity": identity, "peer": id}
	_publish_color_slots()


## Host: `id` is `previous_id` back (N-221; the same id when Steam hands it
## out again). It was handed a free slot while it authenticated; the one kept
## for it replaces it. If the room was full and the only free slot was its
## own, it already wears it and isn't a newcomer after all. Everyone hears of
## it when `id` connects (_peer_joined).
func _peer_returned(id: int, previous_id: int) -> void:
	if _fresh_slots.has(id) and int(_fresh_slots[id]) == previous_id:
		_fresh_slots.erase(id)
		_borrowed_reservations.erase(id)
		return
	var kept: int = -1
	for slot: int in _slot_reservations:
		if int((_slot_reservations[slot] as Dictionary).get("peer", 0)) == previous_id:
			kept = slot
			break
	if kept >= 0:
		_slot_reservations.erase(kept)
		if not _slot_worn_by_other(kept, id):
			# The slot it was handed may have been kept for someone else: theirs again.
			var borrowed: Dictionary = _borrowed_reservations.get(id, {})
			if not borrowed.is_empty() and int(_color_slots.get(id, -1)) == int(borrowed.slot):
				_slot_reservations[int(borrowed.slot)] = borrowed.reservation
			_borrowed_reservations.erase(id)
			_color_slots[id] = kept
			_fresh_slots.erase(id)


func _session_state() -> Dictionary:
	return {"seed": world_seed, "houses": world_house_count, "locked": world_locked_traps,
		"runs": world_completed_runs, "colors": _color_slots, "departed": _departed_slots}


## A handshake without the world, or with a colour slot map (or the slots of
## those who left) that doesn't check out (N-226), is a connection error, not
## a version one.
func _validate_session_state(state: Dictionary) -> String:
	if not state.has_all(["seed", "houses", "locked", "runs", "colors"]):
		return "connection"
	if not ColorSlots.is_valid(state.colors, MAX_PLAYERS):
		return "connection"
	if not ColorSlots.is_valid_departed(state.get("departed", {}), MAX_PLAYERS, DEPARTED_MEMORY):
		return "connection"
	return ""


func _apply_session_state(state: Dictionary) -> void:
	world_seed = int(state.seed)
	world_house_count = int(state.houses)
	world_locked_traps = state.locked
	world_completed_runs = int(state.runs)
	_apply_departed_slots(state.get("departed", {}))
	_apply_color_slots(state.get("colors", {}))


## The next solo run must not keep building the old room's world. Every way
## out of a session comes through here (leaving, and a failure too), so the
## emptied colour map is announced here.
func _reset_session_state() -> void:
	world_seed = 0
	world_house_count = 0
	world_locked_traps = []
	world_completed_runs = 0
	_color_slots = {}
	_departed_slots = {}
	_slot_reservations = {}
	_fresh_slots = {}
	_borrowed_reservations = {}
	color_slots_changed.emit({})


## The crew may have grown since the level was built, so the house count is
## decided afresh; the host's profile may have completed a run meanwhile.
## An invite the menu can't take yet (its level is being built behind the
## loading screen): the next menu joins it on arrival (take_pending_lobby()).
func defer_lobby(lobby: int) -> void:
	_pending_lobby = lobby


## A host restart reloads the level behind the loading screen (N-408): a
## bare reload_current_scene() froze the window while the road was rebuilt.
func _reload_level() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or scene.scene_file_path.is_empty():
		super._reload_level()
		return
	LoadingScreen.go(get_tree(), scene.scene_file_path, tr("UI_LOADING_TAG_RESTART"))


## Host only (NetSession.begin_restart): choose the next world before its
## level builds. Existing clients get this seed when that level is ready.
func _before_restart() -> void:
	_roll_world_seed()
	world_house_count = 0
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	world_completed_runs = int(unlocks.get(&"completed_runs")) if unlocks != null else world_completed_runs


func _restart_state() -> Dictionary:
	return {"seed": world_seed, "houses": world_house_count, "runs": world_completed_runs}


## A client drops its run before reloading. Until this existed only the host
## reloaded: clients were left on the results screen, behind a depot door
## only their copy had closed, unable to drive.
func _apply_restart_state(state: Dictionary) -> void:
	world_seed = int(state.seed)
	world_house_count = int(state.get("houses", world_house_count))
	world_completed_runs = int(state.get("runs", world_completed_runs))
	var run: Node = get_node_or_null(^"/root/RunManager")
	if run != null:
		run.call(&"reset_run")


## The menu maps the short codes ("version", "timeout", "full", "connection")
## itself; these are the sentences with values in them, translated here.
func _failure_text(code: String, args: Array = []) -> String:
	match code:
		"port":
			return tr("UI_NET_PORT_FAILED") % args[0]
		"connect":
			return tr("UI_NET_CONNECT_FAILED") % [args[0], args[1]]
	return tr(String(FAILURE_KEYS[code])) if FAILURE_KEYS.has(code) else code


# --- Colour slots (N-226) -------------------------------------------------------

## Host, on creating the room: a fresh map with itself on slot 0.
func _start_color_slots_as_host() -> void:
	_color_slots = {}
	ColorSlots.assign(_color_slots, HOST_ID, MAX_PLAYERS)
	color_slots_changed.emit(_color_slots.duplicate())


## Host: `id`'s slot, handing it the lowest free one if it had none -- one
## kept for someone who left only if no other is free, and then that
## reservation is lost and `id` starts clean (_fresh_slots). The host is placed
## first if it somehow isn't, so it always wears 0. -1 when every slot is
## taken. Doesn't tell anyone: the caller publishes.
func _assign_color_slot(id: int) -> int:
	ColorSlots.assign(_color_slots, HOST_ID, MAX_PLAYERS)
	var had: bool = _color_slots.has(id)
	var slot: int = ColorSlots.assign_avoiding(_color_slots, id, MAX_PLAYERS, _slot_reservations.keys())
	if not had and slot >= 0:
		_departed_slots.erase(id)
		if _slot_reservations.has(slot):
			var reservation: Dictionary = _slot_reservations[slot]
			_fresh_slots[id] = int(reservation.get("peer", 0))
			_borrowed_reservations[id] = {"slot": slot, "reservation": reservation}
			_slot_reservations.erase(slot)
	return slot


func _slot_worn_by_other(slot: int, id: int) -> bool:
	for peer: int in _color_slots:
		if peer != id and int(_color_slots[peer]) == slot:
			return true
	return false


## Every side: `id` left wearing `slot`. The oldest are forgotten first.
func _remember_departed(id: int, slot: int) -> void:
	_departed_slots.erase(id)
	_departed_slots[id] = slot
	while _departed_slots.size() > DEPARTED_MEMORY:
		_departed_slots.erase(_departed_slots.keys()[0])


## Host: the map changed (or a newcomer needs it). Here and, online, on every
## connected client; one still authenticating gets it when it connects.
func _publish_color_slots() -> void:
	color_slots_changed.emit(_color_slots.duplicate())
	if is_online() and multiplayer.is_server():
		_sync_color_slots.rpc(_color_slots, _departed_slots)


## Host -> clients: the whole {peer_id: slot} map, and the slots of those who
## left. Whole rather than a change: it's a few ints, sent when someone joins
## or leaves, and a copy that went stale can't drift further. Only the host's
## is taken, and only if both check out.
@rpc("authority", "call_remote", "reliable")
func _sync_color_slots(slots: Variant, departed: Variant = {}) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != HOST_ID:
		return
	if not ColorSlots.is_valid(slots, MAX_PLAYERS) \
			or not ColorSlots.is_valid_departed(departed, MAX_PLAYERS, DEPARTED_MEMORY):
		push_warning("NetworkManager: ignored a colour slot map from the host that doesn't check out")
		return
	_apply_departed_slots(departed)
	_apply_color_slots(slots)


## Client: the host's memory of who left wearing what (handshake or
## _sync_color_slots), in place of this peer's own, before the map that may
## add to it: a joiner reads the same colour for them as everyone else.
func _apply_departed_slots(raw: Variant) -> bool:
	if not ColorSlots.is_valid_departed(raw, MAX_PLAYERS, DEPARTED_MEMORY):
		return false
	var received: Dictionary = raw
	_departed_slots = {}
	for peer: Variant in received:
		_departed_slots[int(peer)] = int(received[peer])
	return true


## Client: takes a map from the host (handshake or _sync_color_slots) if it is
## a proper one (ColorSlots.is_valid); a bad one leaves the previous in place.
func _apply_color_slots(raw: Variant) -> bool:
	if not ColorSlots.is_valid(raw, MAX_PLAYERS):
		return false
	var received: Dictionary = raw
	var applied: Dictionary = {}
	for peer: Variant in received:
		applied[int(peer)] = int(received[peer])
	for peer: int in _color_slots:
		if not applied.has(peer):
			_remember_departed(peer, int(_color_slots[peer]))
	for peer: int in applied:
		_departed_slots.erase(peer)
	_color_slots = applied
	color_slots_changed.emit(_color_slots.duplicate())
	return true
