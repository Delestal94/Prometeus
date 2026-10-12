extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_sound_subtitles.gd
##
## Sound subtitles for everything that only sounds (N-965), the queue in
## ui/hud/hud_prompts.gd over ui/hud/sound_subtitle_queue.gd:
## - with GameSettings.sound_subtitles off nothing shows; turning it off clears
##   what was up;
## - each EventBus event with a game meaning shows its translated HUD_SUB_* text:
##   another player's horn (with who, and the arrow to the truck; your own does
##   not), the doorbell of that house and the customer's cheer or groan by
##   outcome (a box lost on the road rang nothing), a wrong box refused at the
##   door, the three animals that go for a box, and the rain when the run starts;
## - several at once, highest priority first, at most MAX_VISIBLE lines; the
##   same event again refreshes its line instead of stacking;
## - each expires on its own clock (horn 1.5 s, bell 2.5 s) as the HUD ticks;
## - the at-risk trap's standing subtitle (refresh_sound_subtitle) still shows,
##   above the queue;
## - arrow(): ahead, behind, left, right, and none when it is on top of you.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var bus: Node = root.get_node("EventBus")
	var network: Node = root.get_node("NetworkManager")
	var run_manager: Node = root.get_node("RunManager")
	var original: bool = settings.sound_subtitles
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var me: int = network.local_id()
	var other: int = me + 6

	# --- off: silence ---
	settings.sound_subtitles = false
	bus.horn_honked.emit(other)
	bus.cargo_animal_alert.emit(&"gull", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(String(hud.interaction_label.text).is_empty(),
		"Subtitles off: no subtitle at all (got '%s')" % hud.interaction_label.text)

	# --- the horn ---
	settings.sound_subtitles = true
	bus.horn_honked.emit(me)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(String(hud.interaction_label.text).is_empty(),
		"Your own horn is not captioned (got '%s')" % hud.interaction_label.text)
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	var horn_text: String = hud.prompts.tr("HUD_SUB_HORN") % (hud.prompts.tr("UI_PLAYER_N") % other)
	_expect(_text(hud) == horn_text,
		"Another player's horn names who honked (want '%s', got '%s')" % [horn_text, _text(hud)])
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == horn_text, "A second honk refreshes the line, it does not stack (got '%s')" % _text(hud))

	# --- the horn with a direction: the truck is to the right of the camera ---
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var truck := Node3D.new()
	truck.add_to_group(&"vehicle")
	root.add_child(truck)
	truck.global_position = Vector3(12.0, 0.0, 0.0)
	await process_frame
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == "→ " + horn_text,
		"The horn shows the arrow to the truck (got '%s')" % _text(hud))
	truck.global_position = Vector3(0.0, 0.0, -12.0)
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == "↑ " + horn_text, "A truck ahead gets the up arrow (got '%s')" % _text(hud))
	truck.free()
	camera.free()
	hud.prompts.refresh_sound_subtitle(5.0)
	_expect(_text(hud).is_empty(), "Everything expires after its seconds (got '%s')" % _text(hud))

	# --- the doorbell and the customer ---
	var bell_two: String = hud.prompts.tr("HUD_SUB_DOORBELL") % 3
	bus.house_delivery_recorded.emit(2, &"delivered_ok", &"p1")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(bell_two) and _text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_CHEER")),
		"A good delivery captions the bell of house 3 and the cheer (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(0, &"delivered_ruined", &"p2")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(hud.prompts.tr("HUD_SUB_DOORBELL") % 1)
			and _text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_GROAN")),
		"A ruined delivery captions the bell and the groan (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(0, &"delivered_at_risk", &"p2")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_GROAN")), "A dented delivery also groans (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(1, &"missed", &"")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == hud.prompts.tr("HUD_SUB_DOORBELL") % 2,
		"Ringing with no box is just the bell (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(1, &"lost", &"p3")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "A box lost on the road rang no bell (got '%s')" % _text(hud))
	bus.house_refused_package.emit(3, "A-1")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(hud.prompts.tr("HUD_SUB_DOORBELL") % 4)
			and _text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_REFUSE")),
		"A wrong box captions the bell and the grumble (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)

	# --- the animals ---
	for animal: Array in [[&"gull", "HUD_SUB_GULL"], [&"dog", "HUD_SUB_DOG"], [&"bees", "HUD_SUB_BEES"]]:
		bus.cargo_animal_alert.emit(animal[0], &"box", 3.0, 4.0)
		hud.prompts.refresh_sound_subtitle(0.0)
		_expect(_text(hud) == hud.prompts.tr(animal[1]),
			"The %s alert shows %s (got '%s')" % [animal[0], animal[1], _text(hud)])
		hud.prompts.refresh_sound_subtitle(5.0)
	bus.cargo_animal_alert.emit(&"unicorn", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "An animal with no sound of its own shows nothing (got '%s')" % _text(hud))

	# --- the rain ---
	bus.run_started.emit(&"test_route", [])
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "A dry route captions no rain (got '%s')" % _text(hud))
	var rain := AudioStreamPlayer.new()
	rain.name = "RainSound"
	root.add_child(rain)
	bus.run_started.emit(&"test_route", [])
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == hud.prompts.tr("HUD_SUB_RAIN"), "A raining route captions the rain (got '%s')" % _text(hud))
	rain.free()
	hud.prompts.refresh_sound_subtitle(10.0)

	# --- several at once: priority order, a cap, expiry on each one's clock ---
	bus.house_delivery_recorded.emit(0, &"delivered_ok", &"p")
	bus.horn_honked.emit(other)
	bus.cargo_animal_alert.emit(&"dog", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	var lines: PackedStringArray = _text(hud).split("\n")
	_expect(lines.size() == 3, "At most 3 subtitles show at once (got %d: '%s')" % [lines.size(), _text(hud)])
	_expect(lines[0] == hud.prompts.tr("HUD_SUB_DOG"), "The animal outranks the rest (got '%s')" % lines[0])
	_expect(lines[1] == horn_text, "The horn comes before the bell (got '%s')" % lines[1])
	hud.prompts.refresh_sound_subtitle(1.6)
	_expect(not _text(hud).contains(horn_text), "The horn expired after 1.5 s while the bell stays (got '%s')" % _text(hud))
	_expect(_text(hud).contains(bell_one(hud)), "The bell lasts longer than the horn (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	_expect(_text(hud).is_empty(), "All of it expired (got '%s')" % _text(hud))

	# --- the at-risk trap's standing subtitle stays, on top ---
	run_manager.cargo[&"sub_box"] = {"integrity": 35.0, "maximum": 100.0, "state": 1}
	bus.cargo_registered.emit(&"sub_box", "HUD_TRAP_FRAGILE")
	bus.package_state_changed.emit(&"sub_box", 1)
	bus.interaction_prompt_changed.emit("")
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	var standing: PackedStringArray = _text(hud).split("\n")
	_expect(standing.size() == 2 and standing[0] == hud.prompts.tr("HUD_SUB_FRAGILE") and standing[1] == horn_text,
		"The trap's subtitle keeps its place above the queue (got '%s')" % _text(hud))
	run_manager.cargo.erase(&"sub_box")

	# --- turning the option off clears the queue ---
	settings.sound_subtitles = false
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(not _text(hud).contains(horn_text), "Turning subtitles off clears the queue (got '%s'" % _text(hud))

	# --- the arrow, from the point in the camera's space ---
	var arrow_script: GDScript = load("res://scripts/ui/hud/sound_subtitle_queue.gd")
	_expect(arrow_script.arrow(Vector3(10, 0, 1)) == "→", "Right of the view is the right arrow")
	_expect(arrow_script.arrow(Vector3(-10, 0, 1)) == "←", "Left of the view is the left arrow")
	_expect(arrow_script.arrow(Vector3(1, 0, -10)) == "↑", "Ahead is the up arrow")
	_expect(arrow_script.arrow(Vector3(1, 0, 10)) == "↓", "Behind is the down arrow")
	_expect(arrow_script.arrow(Vector3(1, 5, -1)) == "", "On top of the listener there is no arrow")

	settings.sound_subtitles = original
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: every sound with a game meaning shows its subtitle, queued, capped and expiring")
	quit(_failures)


func bell_one(hud: CanvasLayer) -> String:
	return hud.prompts.tr("HUD_SUB_DOORBELL") % 1


func _text(hud: CanvasLayer) -> String:
	return String(hud.interaction_label.text)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
