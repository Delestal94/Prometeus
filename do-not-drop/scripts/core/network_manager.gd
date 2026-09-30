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
## 12: the player replicates its nickname and the host relays the next-day
## newspaper (EventBus.newspaper_ready), N-606).
## Both sides exchange it before either starts scene replication.
const PROTOCOL_VERSION: int = 12
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
## The host picks the seed and hands it to each joiner before they load the
## level; 0 means "no session decided one", i.e. solo play, where randomize()
## is exactly right.
var world_seed: int = 0
## How many delivery houses this session's route has (docs/tareas-nacho.md
## #104). The route used to work it out from each machine's own roster, but a
## client's roster starts as just [host, itself], so from three players up
## every peer built a different number of houses. The host's route decides it
## once, the first time it builds, and each joiner gets it with the seed; a
## host restart keeps it, since clients don't reload their world. 0 means
## "not decided yet" (and always, playing solo).
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

const DEFAULT_LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const LEVEL_SCENES: Array[String] = ["res://scenes/gameplay/level_base.tscn", "res://scenes/gameplay/level_endless.tscn"]
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
## Outside a session, or for a peer the host hasn't announced yet, it is
## posmod(peer_id, MAX_PLAYERS), as before slots existed: solo play (id 1)
## keeps slot 1. Readers wrap it to their own palette size.
func color_slot(peer_id: int) -> int:
	return ColorSlots.slot_of(_color_slots, peer_id, MAX_PLAYERS)


# --- What the handshake carries for this game ----------------------------------

## Host: decided once, so every joiner gets the same world no matter which
## transport they arrive on. The seed is never 0: that value means "solo".
func _on_hosting() -> void:
	world_seed = randi() | 1
	world_house_count = 0
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	world_locked_traps = unlocks.call(&"locked_traps") if unlocks != null else []
	world_completed_runs = int(unlocks.get(&"completed_runs")) if unlocks != null else 0


## Host, on creating the room: a fresh slot map with itself on slot 0.
func _on_session_hosted() -> void:
	_start_color_slots_as_host()


func _on_session_left() -> void:
	color_slots_changed.emit(_color_slots.duplicate())


## Its colour slot first, so the handshake already carries it (and the crew
## already has it when the newcomer shows up). No free slot means no room:
## MAX_PLAYERS is also the transports' cap.
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
		_assign_color_slot(id)
		_publish_color_slots()


## Its slot goes to the next one in; nobody else's moves. Also a joiner that
## never made it in (its authentication failed).
func _peer_left(id: int) -> void:
	if multiplayer.is_server() and ColorSlots.release(_color_slots, id):
		_publish_color_slots()


func _session_state() -> Dictionary:
	return {"seed": world_seed, "houses": world_house_count, "locked": world_locked_traps,
		"runs": world_completed_runs, "colors": _color_slots}


## A handshake without the world, or with a colour slot map that doesn't
## check out (N-226), is a connection error, not a version one.
func _validate_session_state(state: Dictionary) -> String:
	if not state.has_all(["seed", "houses", "locked", "runs", "colors"]):
		return "connection"
	if not ColorSlots.is_valid(state.colors, MAX_PLAYERS):
		return "connection"
	return ""


func _apply_session_state(state: Dictionary) -> void:
	world_seed = int(state.seed)
	world_house_count = int(state.houses)
	world_locked_traps = state.locked
	world_completed_runs = int(state.runs)
	_apply_color_slots(state.get("colors", {}))


## The next solo run must not keep building the old room's world.
func _reset_session_state() -> void:
	world_seed = 0
	world_house_count = 0
	world_locked_traps = []
	world_completed_runs = 0
	_color_slots = {}


## The crew may have grown since the level was built, so the house count is
## decided afresh; the host's profile may have completed a run meanwhile.
func _before_restart() -> void:
	world_house_count = 0
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	world_completed_runs = int(unlocks.get(&"completed_runs")) if unlocks != null else world_completed_runs


func _restart_state() -> Dictionary:
	return {"houses": world_house_count, "runs": world_completed_runs}


## A client drops its run before reloading. Until this existed only the host
## reloaded: clients were left on the results screen, behind a depot door
## only their copy had closed, unable to drive.
func _apply_restart_state(state: Dictionary) -> void:
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


## Host: `id`'s slot, handing it the lowest free one if it had none. The host
## is placed first if it somehow isn't, so it always wears 0. -1 when every
## slot is taken. Doesn't tell anyone: the caller publishes.
func _assign_color_slot(id: int) -> int:
	ColorSlots.assign(_color_slots, HOST_ID, MAX_PLAYERS)
	return ColorSlots.assign(_color_slots, id, MAX_PLAYERS)


## Host: the map changed (or a newcomer needs it). Here and, online, on every
## connected client; one still authenticating gets it when it connects.
func _publish_color_slots() -> void:
	color_slots_changed.emit(_color_slots.duplicate())
	if is_online() and multiplayer.is_server():
		_sync_color_slots.rpc(_color_slots)


## Host -> clients: the whole {peer_id: slot} map. Whole rather than a change:
## it's a few ints, sent when someone joins or leaves, and a copy that went
## stale can't drift further. Only the host's is taken, and only if it checks out.
@rpc("authority", "call_remote", "reliable")
func _sync_color_slots(slots: Variant) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != HOST_ID:
		return
	if not _apply_color_slots(slots):
		push_warning("NetworkManager: ignored a colour slot map from the host that doesn't check out")


## Client: takes a map from the host (handshake or _sync_color_slots) if it is
## a proper one (ColorSlots.is_valid); a bad one leaves the previous in place.
func _apply_color_slots(raw: Variant) -> bool:
	if not ColorSlots.is_valid(raw, MAX_PLAYERS):
		return false
	var received: Dictionary = raw
	var applied: Dictionary = {}
	for peer: Variant in received:
		applied[int(peer)] = int(received[peer])
	_color_slots = applied
	color_slots_changed.emit(_color_slots.duplicate())
	return true
