extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_truck_radio.gd
##
## N-406: the truck's radio (gameplay/vehicle/truck_radio.gd, truck_radio_knob.gd,
## presentation/truck_radio_view.gd, synth_audio_radio.gd):
## - the mode starts off and the knob turns calm -> loud -> news -> off -> calm;
##   only the host sets it, an unknown mode is refused, and every mode has a name;
## - the state syncs: a second copy of the radio (a client) that gets the host's
##   _set_mode lands on the same mode and fires mode_changed; a bad mode is ignored;
## - the newscast: with it on, a started route event is read out in the
##   translated line ("inspección más adelante"); calm, loud and off stay quiet,
##   a deer-hit incident isn't announced, and turning the newscast on while an
##   event is open repeats it;
## - on the real truck (vehicle.tscn) the knob hangs by the GPS inside the cab,
##   its prompt shows the mode and the next, a hand-full player can't turn it,
##   and turning it changes what every peer's view plays (calm and loud loops
##   on the Interior bus, silence for news and off, a jingle for the news);
## - Ruidoso (noisy_trap_behavior.gd): with the radio off nothing changes; calm
##   music settles it faster, loud music makes each shake bigger and settles it
##   slower, the newscast changes nothing, and a fully worked up box still
##   needs a hand; through package_rescue.gd the box reads its truck's radio;
## - level_common.gd builds it on the real level's truck.

const TRUCK_RADIO_PATH: String = "res://scripts/gameplay/vehicle/truck_radio.gd"

var _failures: int = 0
var _modes_seen: Array = []
var _news_seen: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var radio_script: Script = load(TRUCK_RADIO_PATH)
	_check_dial(radio_script)
	await _check_sync_and_news(radio_script)
	await _check_real_truck(radio_script)
	await _check_noisy(radio_script)
	await _check_level()
	if _failures == 0:
		print("PASS: the truck radio turns calm/loud/news/off on the host, syncs to every peer,"
				+ " reads out the route event, and calms or stirs Ruidoso")
	quit(_failures)


func _check_dial(radio_script: Script) -> void:
	var constants: Dictionary = radio_script.get_script_constant_map()
	var modes: Array = constants["MODES"]
	_expect(modes == [&"calm", &"loud", &"news", &"off"], "The dial has four positions (got %s)" % [modes])
	_expect(constants["DEFAULT_MODE"] == &"off", "A session starts with the radio off")
	var walked: Array = []
	var mode: StringName = &"off"
	for i: int in 5:
		mode = radio_script.call(&"next_mode", mode)
		walked.append(mode)
	_expect(walked == [&"calm", &"loud", &"news", &"off", &"calm"], "The knob cycles the dial (got %s)" % [walked])
	for each: StringName in modes:
		var key: String = radio_script.call(&"mode_key", each)
		_expect(tr(key) != key and not tr(key).is_empty(), "%s has a translated name (%s)" % [each, key])
	_expect(radio_script.call(&"mode_key", &"bogus") == constants["MODE_KEYS"][&"off"], "An unknown mode reads as off")


## Host and a second copy standing in for a client, plus the newscast.
func _check_sync_and_news(radio_script: Script) -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var world := Node3D.new()
	root.add_child(world)
	var host: Node = radio_script.new()
	world.add_child(host)
	var client: Node = radio_script.new()
	world.add_child(client)
	await process_frame
	_modes_seen.clear()
	client.connect(&"mode_changed", func(new_mode: StringName) -> void: _modes_seen.append(new_mode))
	_expect(host.get(&"mode") == &"off" and client.get(&"mode") == &"off", "Both peers start with the radio off")

	_expect(not bool(host.call(&"set_mode", &"bogus")), "The host refuses a mode that isn't on the dial")
	_expect(host.get(&"mode") == &"off", "A refused mode leaves the radio as it was")
	_expect(StringName(host.call(&"cycle")) == &"calm" and host.get(&"mode") == &"calm",
			"One click on the host: off -> calm")
	# What the host's rpc delivers to every other peer.
	client.call(&"_set_mode", host.get(&"mode"))
	_expect(client.get(&"mode") == &"calm", "The client lands on the host's mode (got %s)" % client.get(&"mode"))
	_expect(_modes_seen == [&"calm"], "The client's mode_changed fires once (got %s)" % [_modes_seen])
	client.call(&"_set_mode", &"calm")
	_expect(_modes_seen == [&"calm"], "Hearing the same mode again changes nothing")
	client.call(&"_set_mode", &"bogus")
	_expect(client.get(&"mode") == &"calm", "A client ignores a mode that isn't on the dial")
	host.call(&"cycle")
	client.call(&"_set_mode", host.get(&"mode"))
	_expect(host.get(&"mode") == &"loud" and client.get(&"mode") == &"loud", "Both peers follow a second click")

	# The newscast: only with it on.
	var inspection_line: String = tr("WORLD_RADIO_NEWS_INSPECTION")
	_expect(inspection_line != "WORLD_RADIO_NEWS_INSPECTION" and not inspection_line.is_empty(),
			"The inspection line is translated")
	_news_seen.clear()
	for radio: Node in [host, client]:
		radio.connect(&"news_announced", func(line: String) -> void: _news_seen.append(line))
	for quiet: StringName in [&"calm", &"loud", &"off"]:
		host.call(&"set_mode", quiet)
		client.call(&"_set_mode", quiet)
		bus.emit_signal(&"route_event_started", &"inspection", {})
	_expect(_news_seen.is_empty(), "Calm, loud and off music don't read out route events (got %s)" % [_news_seen])
	# The manager keeps the last event it heard; none is open for the next check.
	root.get_node(^"/root/RouteEventManager").set(&"active_event_id", &"")
	host.call(&"set_mode", &"news")
	client.call(&"_set_mode", &"news")
	_expect(_news_seen.is_empty(), "Turning the newscast on with no event open says nothing")
	bus.emit_signal(&"route_event_started", &"inspection", {})
	_expect(_news_seen == [inspection_line, inspection_line],
			"The newscast announces the inspection on both peers (got %s)" % [_news_seen])
	_expect(host.get(&"last_news") == inspection_line, "The radio remembers its last line")
	_news_seen.clear()
	bus.emit_signal(&"route_event_started", &"deer_hit", {"incident": true})
	bus.emit_signal(&"route_event_started", &"nothing_known", {})
	_expect(_news_seen.is_empty(), "An incident and an unknown event aren't announced (got %s)" % [_news_seen])
	# Every event the manager can draw has a line.
	var manager: Node = root.get_node(^"/root/RouteEventManager")
	var events: Dictionary = manager.get_script().get_script_constant_map()["EVENTS"]
	for event_id: StringName in events:
		_expect(not String(host.call(&"news_line", event_id)).is_empty(), "The newscast has a line for %s" % event_id)

	# Turning the newscast on while an event is open repeats it.
	host.call(&"set_mode", &"off")
	client.call(&"_set_mode", &"off")
	_news_seen.clear()
	manager.set(&"active_event_id", &"parasite_box")
	host.call(&"set_mode", &"news")
	client.call(&"_set_mode", &"news")
	_expect(_news_seen == [tr("WORLD_RADIO_NEWS_PARASITE"), tr("WORLD_RADIO_NEWS_PARASITE")],
			"Turning the newscast on repeats the open event, on both peers (got %s)" % [_news_seen])
	manager.set(&"active_event_id", &"")
	world.free()
	await process_frame


## The knob and the sound on the real truck.
func _check_real_truck(radio_script: Script) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var van: VehicleBody3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	van.freeze = true
	world.add_child(van)
	var radio: Node = radio_script.new()
	radio.set(&"vehicle", van)
	world.add_child(radio)
	await process_frame
	await physics_frame
	var knob: Node3D = van.get_node_or_null(^"TruckRadioKnob")
	_expect(knob != null and radio.get(&"knob") == knob, "The knob hangs on the van under a fixed name")
	if knob == null:
		world.free()
		return
	_expect(int(knob.get(&"collision_layer")) == 16, "The knob is on the interaction layer")
	var driver_eye: Vector3 = (van.get_node(^"CabinInterior/DriverEyePoint") as Node3D).position
	_expect(knob.position.distance_to(driver_eye) < 2.5 and knob.position.z < driver_eye.z,
			"The knob is on the dash, ahead of the driver and within reach (%s, eye %s)" % [knob.position, driver_eye])
	var gps: Node3D = van.find_child("DashboardGps", true, false) as Node3D
	var offset: Vector3 = radio_script.get_script_constant_map()["KNOB_OFFSET_FROM_GPS"]
	_expect(gps != null and knob.position.is_equal_approx(van.to_local(gps.global_position) + offset),
			"The knob follows the model's GPS (knob %s)" % knob.position)

	var player := FakePlayer.new()
	world.add_child(player)
	var expected_prompt: String = tr("WORLD_RADIO_PROMPT") % [tr("WORLD_RADIO_MODE_OFF"), tr("WORLD_RADIO_MODE_CALM")]
	_expect(String(knob.call(&"get_prompt")) == expected_prompt,
			"The prompt names the mode and the next one (got %s)" % knob.call(&"get_prompt"))
	player.carried_package = Node.new()
	_expect(not bool(knob.call(&"can_interact", player)), "A player with a box in their arms can't turn it")
	knob.call(&"interact", player)
	_expect(radio.get(&"mode") == &"off", "A refused press changes nothing")
	player.carried_package.free()
	player.carried_package = null
	_expect(bool(knob.call(&"can_interact", player)), "Anyone else can turn it")

	var view: Node3D = radio.get(&"view")
	var program: AudioStreamPlayer3D = view.get(&"music_player")
	_expect(program != null and program.bus == &"Interior", "The program plays through the Interior bus")
	_expect(not program.playing, "Off is silent")
	var started: int = Time.get_ticks_msec()
	knob.call(&"interact", player)
	_expect(radio.get(&"mode") == &"calm", "Pressing the knob cycles the host's mode")
	var loop_mode: int = (program.stream as AudioStreamWAV).loop_mode if program.stream != null else -1
	var loops: bool = loop_mode == AudioStreamWAV.LOOP_FORWARD
	_expect(program.playing and loops,
			"Calm plays a looping program")
	var calm_stream: AudioStream = program.stream
	knob.call(&"interact", player)
	_expect(radio.get(&"mode") == &"loud" and program.playing and program.stream != calm_stream,
			"Loud plays its own program")
	knob.call(&"interact", player)
	_expect(radio.get(&"mode") == &"news" and not program.playing, "The newscast has no music")
	var cue: AudioStreamPlayer3D = view.get(&"cue_player")
	_expect(cue != null and cue.bus == &"Interior", "The jingle plays through the Interior bus")
	root.get_node(^"/root/EventBus").emit_signal(&"route_event_started", &"inspection", {})
	var news_label: Label3D = view.get(&"news_label")
	_expect(news_label.text == tr("WORLD_RADIO_NEWS_INSPECTION"),
			"The newscast's line shows above the dial (got %s)" % news_label.text)
	_expect(cue.playing, "The newscast opens with its jingle")
	var label: Label3D = view.get(&"mode_label")
	_expect(label.text == tr("WORLD_RADIO_MODE_NEWS"), "The dial's label names the mode (got %s)" % label.text)
	knob.call(&"interact", player)
	_expect(radio.get(&"mode") == &"off" and news_label.text.is_empty(), "Off clears the newscast's line")
	print("radio: cycling through every mode and building its sounds took ", Time.get_ticks_msec() - started, " ms")
	world.free()
	await process_frame


## Ruidoso's agitation under each mode, on the behavior and through the box.
func _check_noisy(radio_script: Script) -> void:
	var definition: Resource = load("res://data/traps/noisy.tres")
	var params: Dictionary = definition.get(&"params")
	for key: String in ["radio_calm_extra_decay", "radio_loud_gain_mult", "radio_loud_passive_mult"]:
		_expect(params.has(key), "noisy.tres carries the radio's %s" % key)
	var extra: float = float(params["radio_calm_extra_decay"])
	var loud_gain: float = float(params["radio_loud_gain_mult"])
	var loud_passive: float = float(params["radio_loud_passive_mult"])
	var gain: float = float(params["agitation_gain_per_shake"])
	var passive: float = float(params["agitation_passive_decay"])
	_expect(extra > 0.0 and loud_gain > 1.0 and loud_passive < 1.0, "Calm helps and loud hurts in the numbers")
	var results: Dictionary = {}
	for mode: StringName in [&"off", &"calm", &"loud", &"news"]:
		var trap: Resource = definition.call(&"create_behavior")
		trap.call(&"on_setup", null, params)
		trap.call(&"on_physics_process", null, 1.0 / 60.0, {"radio_mode": mode})
		trap.call(&"on_impact", 0.30)
		var shaken: float = trap.get(&"agitation")
		for i: int in 60:
			trap.call(&"on_physics_process", null, 1.0 / 60.0, {"radio_mode": mode})
		results[mode] = [shaken, float(trap.get(&"agitation"))]
	_expect(is_equal_approx(results[&"off"][0], gain),
			"Off: a shake adds the tuned agitation (got %s)" % results[&"off"][0])
	_expect(absf(results[&"off"][1] - (gain - passive)) < 0.01,
			"Off: it settles at the passive rate (got %s)" % results[&"off"][1])
	_expect(results[&"news"] == results[&"off"],
			"The newscast changes nothing (%s vs %s)" % [results[&"news"], results[&"off"]])
	_expect(results[&"calm"][1] < results[&"off"][1] and is_equal_approx(results[&"calm"][0], gain),
			"Calm music settles it faster, shakes unchanged (calm %s, off %s)" % [results[&"calm"], results[&"off"]])
	_expect(is_equal_approx(results[&"loud"][0], gain * loud_gain),
			"Loud music makes each shake bigger (got %s)" % results[&"loud"][0])
	_expect(results[&"loud"][1] - results[&"loud"][0] > results[&"off"][1] - results[&"off"][0],
			"Loud music settles it slower (loud %s, off %s)" % [results[&"loud"], results[&"off"]])
	# Fully worked up: the radio doesn't pull it back, only a hand does.
	var pinned: Resource = definition.call(&"create_behavior")
	pinned.call(&"on_setup", null, params)
	for i: int in 10:
		pinned.call(&"on_impact", 0.30)
	pinned.call(&"on_physics_process", null, 0.1, {"radio_mode": &"calm"})
	_expect(is_equal_approx(float(pinned.get(&"agitation")), 100.0),
			"Calm music doesn't rescue a box already at the limit")

	# Through the box: package_rescue.gd reads the radio in the truck's level.
	var world := Node3D.new()
	root.add_child(world)
	var radio: Node = radio_script.new()
	world.add_child(radio)
	var rescue: Script = load("res://scripts/gameplay/package/package_rescue.gd")
	var package_scene: PackedScene = load("res://scenes/gameplay/package/package.tscn")
	var agitation: Dictionary = {}
	for mode: StringName in [&"off", &"calm"]:
		radio.call(&"set_mode", mode)
		var package: RigidBody3D = package_scene.instantiate()
		world.add_child(package)
		package.set(&"trap_definition", definition)
		package.call(&"initialize_trap")
		package.freeze = true
		var trap: Resource = package.get(&"trap_behavior")
		_expect(rescue.call(&"radio_mode", package) == mode, "The box reads its truck's radio (%s)" % mode)
		trap.set(&"agitation", 50.0)
		for i: int in 60:
			rescue.call(&"simulate_cargo", package, 1.0 / 60.0)
		agitation[mode] = float(trap.get(&"agitation"))
		package.free()
	_expect(is_equal_approx(agitation[&"off"], 50.0 - passive) and agitation[&"calm"] < agitation[&"off"],
			"In the game's own loop calm leaves it calmer (calm %s, off %s)" % [agitation[&"calm"], agitation[&"off"]])
	world.free()
	var alone: RigidBody3D = package_scene.instantiate()
	root.add_child(alone)
	_expect(rescue.call(&"radio_mode", alone) == &"off", "With no radio in the level the box reads it as off")
	alone.free()
	await process_frame


## The level builds the radio for the real truck, with the same node paths on every peer.
func _check_level() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var radio: Node = level.get_node_or_null(^"TruckRadio")
	_expect(radio != null and radio.is_in_group(&"truck_radio"), "The level has the truck radio")
	var van: Node = level.get("vehicle")
	_expect(van != null and van.get_node_or_null(^"TruckRadioKnob") != null,
			"The level's truck has the knob on its dash")
	_expect(radio != null and radio.get(&"mode") == &"off", "The radio starts off in a level")
	level.queue_free()
	await process_frame


## Stands in for a Player (the knob only asks whether their hands are full).
class FakePlayer extends Node3D:
	var carried_package: Node = null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
