extends Node
class_name TruckRadio
## The truck's radio (tareas de Nacho N-406): a knob on the dashboard anyone
## in the cab can turn, calm / loud / newscast / off. Lives next to the van,
## not inside it, like VehicleFaults.
##
## The host owns the mode: a crewmate's press reaches TruckRadioKnob.interact()
## on the host (Interactable.request_interact), which calls cycle(); the host
## applies it and sends it to every peer (_set_mode), and a peer that joins
## mid-run is handed the current one. What the mode does:
## - calm eases the Ruidoso trap, loud stirs it (noisy_trap_behavior.gd reads
##   `mode` from the "truck_radio" group, through package_rescue.gd's context);
## - the newscast reads out the route event the run drew ("inspección más
##   adelante"): EventBus.route_event_started reaches every peer, so each one
##   announces it itself, and turning the newscast on while an event is open
##   repeats it.
## Sound and the lit dial are pure presentation (TruckRadioView), on every peer.

## The dial's positions in turning order; off is where a session starts.
const MODES: Array[StringName] = [&"calm", &"loud", &"news", &"off"]
const DEFAULT_MODE: StringName = &"off"
## Spelled out, not built, so the translation test finds every key in use.
const MODE_KEYS: Dictionary = {
	&"calm": "WORLD_RADIO_MODE_CALM",
	&"loud": "WORLD_RADIO_MODE_LOUD",
	&"news": "WORLD_RADIO_MODE_NEWS",
	&"off": "WORLD_RADIO_MODE_OFF",
}
## What the newscast says for each route event (RouteEventManager.EVENTS).
const NEWS_KEYS: Dictionary = {
	&"inspection": "WORLD_RADIO_NEWS_INSPECTION",
	&"impatient_client": "WORLD_RADIO_NEWS_IMPATIENT",
	&"rear_door_jam": "WORLD_RADIO_NEWS_DOOR_JAM",
	&"mixed_labels": "WORLD_RADIO_NEWS_MIXED_LABELS",
	&"mimetic_package": "WORLD_RADIO_NEWS_MIMIC",
	&"parasite_box": "WORLD_RADIO_NEWS_PARASITE",
	&"confusing_shop": "WORLD_RADIO_NEWS_SHOP",
}
## Preloaded, not by class_name: a new global class isn't in the class cache
## until the editor imports again, and headless runs load this first.
const KNOB: Script = preload("res://scripts/gameplay/vehicle/truck_radio_knob.gd")
const VIEW: Script = preload("res://scripts/presentation/truck_radio_view.gd")
## Where the knob hangs when the truck's model has no GPS to hang it by, and
## how far from the GPS (van frame: -Z ahead, +X to the passenger side) when
## it has: right of the screen, at the same height.
const KNOB_FALLBACK_POSITION: Vector3 = Vector3(0.35, 1.5, -2.0)
const KNOB_OFFSET_FROM_GPS: Vector3 = Vector3(0.3, -0.02, 0.0)

## The mode changed (every peer; also when a peer is handed the state).
signal mode_changed(new_mode: StringName)
## The newscast said something (every peer with the newscast on).
signal news_announced(line: String)

## The van the knob hangs on. LevelCommon sets it before adding the node;
## null (a rules-only test) leaves just the state.
var vehicle: Node3D

## Every peer: the current mode.
var mode: StringName = DEFAULT_MODE
## Every peer: the last newscast line ("" until one is said).
var last_news: String = ""
var knob: Interactable
var view: Node3D


func _ready() -> void:
	add_to_group(&"truck_radio")
	EventBus.route_event_started.connect(_on_route_event_started)
	NetworkManager.peer_level_ready.connect(_on_peer_level_ready)
	view = VIEW.new()
	view.name = "View"
	view.set(&"radio", self)
	if vehicle != null:
		_hang_knob()
	else:
		add_child(view)


## The mode after `from`, in turning order.
static func next_mode(from: StringName) -> StringName:
	var index: int = MODES.find(from)
	return MODES[(index + 1) % MODES.size()]


## Translation key of a mode's name.
static func mode_key(of_mode: StringName) -> String:
	return String(MODE_KEYS.get(of_mode, MODE_KEYS[DEFAULT_MODE]))


## Host-only: one click of the knob. Returns the new mode, &"" if this peer
## isn't the host.
func cycle() -> StringName:
	if not set_mode(next_mode(mode)):
		return &""
	return mode


## Host-only: sets the mode here and on every peer. Returns false if this
## isn't the host or the mode isn't one of MODES.
func set_mode(new_mode: StringName) -> bool:
	if not NetworkManager.is_host() or not MODES.has(new_mode):
		return false
	_apply_mode(new_mode)
	if NetworkManager.is_online():
		_set_mode.rpc(new_mode)
	return true


@rpc("authority", "call_remote", "reliable")
func _set_mode(new_mode: StringName) -> void:
	if MODES.has(new_mode):
		_apply_mode(new_mode)


func _apply_mode(new_mode: StringName) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	mode_changed.emit(mode)
	if mode == &"news":
		announce(RouteEventManager.active_event_id)


## The newscast's line for a route event, translated; "" for an event it
## has nothing to say about.
func news_line(event_id: StringName) -> String:
	return tr(String(NEWS_KEYS[event_id])) if NEWS_KEYS.has(event_id) else ""


## Says the event on the newscast, if it's on and knows the event. Returns
## whether it said anything.
func announce(event_id: StringName) -> bool:
	if mode != &"news":
		return false
	var line: String = news_line(event_id)
	if line.is_empty():
		return false
	last_news = line
	news_announced.emit(line)
	return true


func _on_route_event_started(event_id: StringName, event: Dictionary) -> void:
	# A deer on the road (an incident) is over before the radio could warn of it.
	if not bool(event.get("incident", false)):
		announce(event_id)


## Host-only: a peer that joins mid-run gets the mode. Deferred so it lands
## after the level is up on that peer.
func _on_peer_level_ready(peer_id: int) -> void:
	if not NetworkManager.is_host() or not NetworkManager.is_online() or peer_id == NetworkManager.HOST_ID:
		return
	_set_mode.rpc_id.call_deferred(peer_id, mode)


func _hang_knob() -> void:
	knob = KNOB.new()
	knob.name = "TruckRadioKnob"
	knob.set(&"radio", self)
	knob.position = _knob_position()
	vehicle.add_child(knob)
	knob.add_child(view)


## By the dashboard's GPS when the model has one (the same dash, so it follows
## the truck variant), else where the reference truck's cab has room.
func _knob_position() -> Vector3:
	var gps: Node3D = vehicle.find_child("DashboardGps", true, false) as Node3D
	if gps != null and gps.is_inside_tree() and vehicle.is_inside_tree():
		return vehicle.to_local(gps.global_position) + KNOB_OFFSET_FROM_GPS
	return KNOB_FALLBACK_POSITION
