extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_voice_options.gd
##
## The voice chat options (N-212.3), in the options screen (options_panel.gd,
## options_voice_section.gd):
## - the "Chat de voz" and "Pulsar para hablar" checkboxes write into
##   GameSettings, push-to-talk is greyed out while voice is off, and both
##   come back in line after a reset;
## - the talk key (voice_talk) has a rebind button like the others;
## - the crew list has one row per crewmate except this player (fed from a
##   roster, no Steam session needed), each with a mute and a volume that land
##   in ProximityVoice, shows what is already set when it is rebuilt, and says
##   so when nobody else is there; a rebuild keeps a gamepad player's focus
##   (on the same crewmate's control, or on the voice switch if they left).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var voice: Node = root.get_node("ProximityVoice")
	var original_enabled: bool = settings.voice_chat_enabled
	var original_ptt: bool = settings.voice_push_to_talk
	voice.clear_peers()

	# By load(), not by class name: the section names autoloads, which don't
	# exist yet when this script is compiled.
	var section_script: GDScript = load("res://scripts/ui/options_voice_section.gd")
	var options: Control = load("res://scripts/ui/options_panel.gd").new()
	root.add_child(options)
	await process_frame
	settings.voice_chat_enabled = false
	settings.voice_push_to_talk = true
	options.call(&"open")
	var section: Node = options.find_child("VoiceSection", true, false)
	_expect(section != null, "The options screen has a voice section")
	if section == null:
		options.queue_free()
		quit(1)
		return

	# --- the two switches ---
	var voice_check: CheckBox = section.find_child("VoiceChat", true, false)
	var talk_check: CheckBox = section.find_child("PushToTalk", true, false)
	_expect(voice_check != null and talk_check != null, "Voice chat and push-to-talk checkboxes exist")
	_expect(not voice_check.button_pressed and talk_check.button_pressed, "They show the current settings")
	_expect(talk_check.disabled, "Push-to-talk is greyed out while voice chat is off")
	voice_check.button_pressed = true
	_expect(settings.voice_chat_enabled, "Ticking Voice chat switches it on in GameSettings")
	_expect(not talk_check.disabled, "...and push-to-talk becomes usable")
	talk_check.button_pressed = false
	_expect(not settings.voice_push_to_talk, "Unticking push-to-talk switches to open mic")
	options.call(&"_reset")
	_expect(not voice_check.button_pressed and not settings.voice_chat_enabled,
		"Reset puts voice chat back to off, and the checkbox follows")
	_expect(talk_check.button_pressed and settings.voice_push_to_talk,
		"Reset puts push-to-talk back on, and the checkbox follows")
	_expect(talk_check.disabled, "...and greys it out again")

	# --- the talk key ---
	var buttons: Dictionary = options.get(&"_binding_buttons")
	_expect(buttons.has(&"voice_talk"), "The talk key has a rebind button")
	if buttons.has(&"voice_talk"):
		_expect((buttons[&"voice_talk"] as Button).text == settings.binding_label(&"voice_talk"),
			"...showing the key it is bound to")

	# --- the crew list ---
	var entries: Array[Dictionary] = section_script.call(&"crew_entries", [1, 2, 3], {}, 1, true)
	_expect(entries.size() == 2 and int(entries[0]["peer_id"]) == 2 and int(entries[1]["peer_id"]) == 3,
		"The crew list leaves out this player and keeps the roster order")
	section.call(&"render_crew", entries)
	_expect(section.find_child("Peer_1", true, false) == null, "No row for yourself")
	var row2: Node = section.find_child("Peer_2", true, false)
	var row3: Node = section.find_child("Peer_3", true, false)
	_expect(row2 != null and row3 != null, "One row per crewmate")
	_expect(section.find_child("Nobody", true, false) == null, "...and no 'nobody here' line")
	if row2 != null and row3 != null:
		var mute2: CheckBox = row2.find_child("Mute", true, false)
		var volume3: HSlider = row3.find_child("Volume", true, false)
		_expect(not voice.is_peer_muted(2) and mute2 != null and not mute2.button_pressed, "Nobody starts muted")
		mute2.button_pressed = true
		_expect(voice.is_peer_muted(2) and not voice.is_peer_muted(3),
			"Muting a crewmate reaches ProximityVoice, only theirs")
		_expect(is_equal_approx(volume3.value, 1.0), "Volume starts at full")
		volume3.value = 0.4
		_expect(is_equal_approx(voice.peer_volume(3), 0.4) and is_equal_approx(voice.peer_volume(2), 1.0),
			"Moving a volume slider reaches ProximityVoice, only theirs")
		# Rebuilt (say, someone joined): the rows show what is already set.
		section.call(&"render_crew", entries)
		var again_mute: CheckBox = section.find_child("Peer_2", true, false).find_child("Mute", true, false)
		var again_volume: HSlider = section.find_child("Peer_3", true, false).find_child("Volume", true, false)
		_expect(again_mute.button_pressed and is_equal_approx(again_volume.value, 0.4),
			"A rebuilt list shows the mutes and volumes already set")
		# A gamepad player on a crewmate's control keeps the focus through a rebuild...
		again_volume.grab_focus()
		section.call(&"render_crew", entries)
		var focused: Control = options.get_viewport().gui_get_focus_owner()
		_expect(focused != null and focused.is_inside_tree() and focused.name == &"Volume"
			and section.find_child("Peer_3", true, false).is_ancestor_of(focused),
			"A rebuild gives the focus back to the same crewmate's control")
		# ...and lands on the voice switch when that crewmate left.
		section.call(&"render_crew", section_script.call(&"crew_entries", [1, 2], {}, 1, true))
		_expect(options.get_viewport().gui_get_focus_owner() == voice_check,
			"When that crewmate left, the focus goes to the voice switch")
	section.call(&"render_crew", section_script.call(&"crew_entries", [1], {}, 1, false))
	_expect(section.find_child("Nobody", true, false) != null and section.find_child("Peer_2", true, false) == null,
		"With nobody else, one line says so")
	section.call(&"render_crew", entries)
	options.call(&"open")
	_expect(section.find_child("Nobody", true, false) != null and section.find_child("Peer_2", true, false) == null,
		"Opening the options rebuilds the list from the real roster (solo here: nobody)")

	# --- put everything back ---
	voice.clear_peers()
	settings.voice_chat_enabled = original_enabled
	settings.voice_push_to_talk = original_ptt
	options.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: voice chat options (switches, talk key, per-crewmate mute and volume)")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
