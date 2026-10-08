extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_proportion_network.gd
##
## S-311.23 persists clamped body values, encodes exactly one byte per
## parameter and exposes one host-authoritative, spawn/on-change packet on
## every player. The real two-process peer visibility check lives in net_pair.

const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Profile := preload("res://scripts/core/unlock_manager.gd")
const PROFILE_PATH: String = "user://gel_proportion_network_test.json"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	_check_quantization()
	_check_profile()
	_check_player_wire()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	if _failures == 0:
		print("PASS: gel proportions persist clamped and replicate as 17 host-owned bytes")
	quit(_failures)


func _check_quantization() -> void:
	var source := Proportions.new()
	for definition: Dictionary in Proportions.parameter_definitions():
		var name_: StringName = definition[&"name"]
		source.set(name_, lerpf(float(definition[&"minimum"]), float(definition[&"maximum"]), 0.37))
	var packet: PackedByteArray = source.to_packet()
	_expect(packet.size() == Proportions.PACKET_SIZE and packet.size() == 17,
		"the wire packet is exactly one byte for each of the 17 parameters")
	var restored := Proportions.new()
	_expect(restored.apply_packet(packet), "a complete packet is accepted")
	for definition: Dictionary in Proportions.parameter_definitions():
		var name_: StringName = definition[&"name"]
		var step: float = (float(definition[&"maximum"]) - float(definition[&"minimum"])) / 255.0
		_expect(absf(float(restored.get(name_)) - float(source.get(name_))) <= step * 0.51,
			"%s round-trips within half one-byte step" % name_)
	var before: Dictionary = restored.as_dictionary()
	_expect(not restored.apply_packet(PackedByteArray([0, 255])), "a malformed packet is rejected")
	_expect(restored.as_dictionary() == before, "a rejected packet leaves the proportions unchanged")


func _check_profile() -> void:
	var profile := Profile.new()
	profile.storage_path = PROFILE_PATH
	profile.reset_profile()
	profile.set_gel_proportions({
		"total_height": 99.0,
		"leg_length": -99.0,
		"general_thickness": NAN,
		"belly": 0.44,
		"unknown": 12.0,
	})
	_expect(is_equal_approx(float(profile.gel_proportions[&"total_height"]), 1.20),
		"profile input is clamped to the height maximum")
	_expect(is_equal_approx(float(profile.gel_proportions[&"leg_length"]), 0.75),
		"profile input is clamped to the leg minimum")
	_expect(is_equal_approx(float(profile.gel_proportions[&"general_thickness"]), 0.0),
		"non-finite profile input falls back to Delgada")
	_expect(not profile.gel_proportions.has(&"unknown"), "unknown profile keys are discarded")
	var restored := Profile.new()
	restored.storage_path = PROFILE_PATH
	restored.load_profile()
	_expect(restored.gel_proportions == profile.gel_proportions, "all clamped values survive save/load")
	profile.free()
	restored.free()


func _check_player_wire() -> void:
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	var state: Node = player.get_node(^"GelProportions")
	var sync := state.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var path := NodePath(".:packet")
	_expect(state.get(&"packet") is PackedByteArray and (state.get(&"packet") as PackedByteArray).size() == 17,
		"every player starts with a compact proportion packet")
	_expect(sync.replication_config.has_property(path), "the compact packet is in the replication contract")
	_expect(sync.replication_config.property_get_spawn(path), "late joiners receive the packet at spawn")
	_expect(sync.replication_config.property_get_replication_mode(path) \
			== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE, "the packet travels only when it changes")
	player.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
