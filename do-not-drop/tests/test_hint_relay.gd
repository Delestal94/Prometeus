extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_hint_relay.gd
## Verifies the bug fixed this pass: a package's hint text now reaches
## EventBus (and so every client's HUD) instead of staying something only
## the package's own local, host-only trap_behavior knows about.
## N-805: the hint travels as a LocText line ([key, args...]), not text the
## host already translated, so each peer reads it in its own language; care
## messages (a tool's progress, with its name inside) too; and the HUD finds
## a prompt's icon from its key, so an English prompt gets one. Runs real
## physics frames rather than faking them, since the relay throttle lives
## inside _integrate_forces.

const PackageCare = preload("res://scripts/gameplay/package/package_care.gd")

var _failures: int = 0
var _received: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _on_hint(id: StringName, hint: Array) -> void:
	_received.append([id, hint])


func _run() -> void:
	await process_frame
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.call(&"start_run")

	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"package_hint_changed", _on_hint)

	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/growing_weight.tres"))
	root.add_child(package)
	await process_frame
	package.call(&"initialize_trap")

	package.call(&"report_to_run")
	_expect(_received.size() == 1, "report_to_run sends an immediate hint (got %d events)" % _received.size())
	if not _received.is_empty():
		var line: Array = _received[0][1]
		_expect(not LocText.render(line).is_empty(), "The initial hint isn't blank")
		_expect(not line.is_empty() and String(line[0]).begins_with("HUD_HINT_"),
			"The hint travels as a key, not translated text (got %s)" % [line])
		_expect_both_languages(line, "The relayed hint")

	# Real physics frames, package unfrozen: this is what actually drives
	# _integrate_forces and, inside it, the hint relay throttle.
	package.freeze = false
	for _i in range(60):  # ~1s at 60Hz -- well past the 0.25s throttle
		await physics_frame
	_expect(_received.size() >= 2, "the throttle fires again after ~1s of real physics (got %d events total)" % _received.size())

	_check_care_messages()
	_check_prompt_icons()

	# Not free(): this resumes inside a physics step, and freeing a rigid
	# body mid-step crashed Jolt on exit about half the time. Same deferred
	# removal the game itself uses for a delivered box.
	package.queue_free()
	await process_frame
	await process_frame
	# Leave the autoloads as they were: a run left going and a listener on a
	# script that's about to go away made shutdown crash about half the time.
	bus.disconnect(&"package_hint_changed", _on_hint)
	run_manager.call(&"reset_run")
	await process_frame
	if _failures == 0:
		print("PASS: package hints report to the run immediately and relay again on a throttle")
	quit(_failures)


## A care message is a key too, and a tool's progress names the tool in the
## reader's language.
func _check_care_messages() -> void:
	var care: RefCounted = PackageCare.new()
	care.call(&"begin_crisis", &"fragile")
	var crisis: Array = care.get(&"message")
	_expect(crisis == ["HUD_CARE_CRISIS_RESCUE"], "A crisis message is a key (got %s)" % [crisis])
	_expect_both_languages(crisis, "The crisis message")
	care.call(&"collect_part")
	_expect(care.get(&"message") == ["HUD_CARE_MSG_PIECES_LEFT", 2],
		"Pieces left carry their count as an argument")
	care.call(&"advance_work", 0.5, &"tape", {"work": true}, &"fragile", 0.0, true)
	var progress: Array = care.get(&"message")
	_expect(progress.size() == 3 and progress[1] == ["HUD_CARE_TOOL_TAPE"],
		"Work progress names the tool by its key (got %s)" % [progress])
	TranslationServer.set_locale("en")
	var english: String = LocText.render(progress)
	_expect(english.begins_with(tr("HUD_CARE_TOOL_TAPE")) and english.ends_with("%"),
		"...and reads in English on an English peer (%s)" % english)
	TranslationServer.set_locale("es")
	var blocker: Array = care.call(&"tool_blocker", &"rag", &"fragile", 0.0)
	_expect(blocker == ["HUD_CARE_BLOCK_NOTHING_TO_ABSORB"], "A tool blocker is a key (got %s)" % [blocker])
	var snapshot: Dictionary = care.call(&"snapshot")
	var copy: RefCounted = PackageCare.new()
	copy.call(&"apply_snapshot", snapshot)
	_expect(copy.get(&"message") == progress, "The message reaches clients as the same key line")
	copy.call(&"apply_snapshot", {"message": "texto viejo"})
	_expect((copy.get(&"message") as Array).is_empty(), "An old build's text message is dropped, not shown raw")


## The prompt icon comes from the prompt's key, in either language (the old
## table looked for Spanish words and English prompts went without one).
func _check_prompt_icons() -> void:
	var prompts: Node = HudPrompts.new()
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		var cases: Dictionary = {"HUD_PROMPT_PICK_UP_PACKAGE": &"grab", "HUD_PROMPT_UNLOAD_PACKAGE": &"grab",
			"HUD_PROMPT_DROP_TO_DRIVE": &"drop", "HUD_PROMPT_PLACE_PACKAGE": &"drop",
			"HUD_PROMPT_STORE_ON_SHELF": &"drop", "HUD_PROMPT_DRIVE": &"sit", "HUD_PROMPT_SIT": &"sit",
			"HUD_PROMPT_SIT_BY_CARGO": &"sit", "WORLD_DOORBELL_PROMPT": &"bell", "HUD_PROMPT_OPEN_BOX": &"open_box"}
		for key: String in cases:
			var got: StringName = prompts.call(&"_action_id_for_prompt", tr(key))
			_expect(got == cases[key], "%s: '%s' shows the %s icon (got '%s')" % [locale, tr(key), cases[key], got])
		_expect(prompts.call(&"_action_id_for_prompt", "") == &"", "%s: no prompt, no icon" % locale)
		# A depot box's prompt carries its bin code and trap name after the action.
		var coded: String = "%s A-1  ·  %s" % [tr("HUD_PROMPT_PICK_UP_PACKAGE"), tr("HUD_TRAP_FRAGILE")]
		_expect(prompts.call(&"_action_id_for_prompt", coded) == &"grab",
			"%s: a coded depot prompt still grabs" % locale)
	TranslationServer.set_locale("es")
	prompts.free()


func _expect_both_languages(line: Array, what: String) -> void:
	TranslationServer.set_locale("en")
	var english: String = LocText.render(line)
	TranslationServer.set_locale("es")
	var spanish: String = LocText.render(line)
	_expect(not english.is_empty() and english != spanish,
		"%s reads in each peer's language (es '%s', en '%s')" % [what, spanish, english])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
