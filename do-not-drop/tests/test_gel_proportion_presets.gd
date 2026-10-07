extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_proportion_presets.gd
##
## S-311.21 ships six editable .tres presets and a reusable random button. This
## test checks their semantic extremes, caller-owned loading and 500 seeded
## random clicks against the conservative cross-parameter constraints.

const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const RandomButton := preload("res://scripts/gameplay/player/gel/gel_proportion_random_button.gd")
const EXPECTED_IDS: Array[StringName] = [
	&"delgada", &"flaca", &"rellena", &"petisa", &"cabezona", &"larguirucha",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_presets()
	_check_safe_randomizer()
	await _check_random_button()
	if _failures == 0:
		print("PASS: six gel presets and 500 safe random combinations")
	quit(_failures)


func _check_presets() -> void:
	_expect(Presets.preset_ids() == EXPECTED_IDS, "the six preset ids have stable display order")
	var fingerprints: Dictionary = {}
	for preset_id: StringName in EXPECTED_IDS:
		var preset: Resource = Presets.load_preset(preset_id)
		_expect(preset != null, "%s loads as GelBodyProportions" % preset_id)
		_expect(Presets.label_key(preset_id).begins_with("UI_GEL_PRESET_"), "%s has a label key" % preset_id)
		if preset == null:
			continue
		_check_contract_ranges(preset, preset_id)
		fingerprints[JSON.stringify(preset.as_dictionary())] = true
	_expect(fingerprints.size() == EXPECTED_IDS.size(), "all six presets have distinct values")
	_expect(Presets.load_preset(&"unknown") == null, "unknown presets do not fall back silently")

	var delgada: Resource = Presets.load_preset(&"delgada")
	for definition: Dictionary in Proportions.parameter_definitions():
		_expect(
			is_equal_approx(float(delgada.get(definition[&"name"])), float(definition[&"default"])),
			"Delgada keeps the measured default for %s" % definition[&"name"]
		)
	var flaca: Resource = Presets.load_preset(&"flaca")
	_expect(flaca.total_height == 1.2 and flaca.head_size == 0.75, "Flaca uses the tall, small-head extremes")
	_expect(flaca.general_thickness == -1.0, "Flaca uses the authored 30 percent thinner morph extreme")
	_expect(flaca.neck_length == 1.25 and flaca.neck_thickness < 0.0, "Flaca keeps a long visible neck")
	_expect(Presets.load_preset(&"rellena").general_thickness > 0.5, "Rellena demonstrates positive volume")
	_expect(Presets.load_preset(&"petisa").total_height == 0.85, "Petisa demonstrates minimum height")
	_expect(Presets.load_preset(&"cabezona").head_size == 1.25, "Cabezona demonstrates maximum head size")
	var tall: Resource = Presets.load_preset(&"larguirucha")
	_expect(tall.leg_length == 1.25 and tall.arm_length == 1.25, "Larguirucha demonstrates long limbs")

	flaca.general_thickness = 0.0
	_expect(Presets.load_preset(&"flaca").general_thickness == -1.0, "loaded presets are caller-owned copies")
	var target: Resource = Proportions.new()
	var changed_events: Array[bool] = []
	target.changed.connect(func() -> void: changed_events.append(true))
	_expect(Presets.apply_preset(&"cabezona", target), "a known preset copies into an existing resource")
	_expect(target.head_size == 1.25 and changed_events.size() == 1, "preset application changes the resource once")
	_expect(not Presets.apply_preset(&"unknown", target), "an unknown preset leaves the target alone")


func _check_contract_ranges(preset: Resource, preset_id: StringName) -> void:
	for definition: Dictionary in Proportions.parameter_definitions():
		var parameter_name: StringName = definition[&"name"]
		var value: float = float(preset.get(parameter_name))
		_expect(
			value >= float(definition[&"minimum"]) and value <= float(definition[&"maximum"]),
			"%s.%s stays inside the editable contract" % [preset_id, parameter_name]
		)


func _check_safe_randomizer() -> void:
	var rng := RandomNumberGenerator.new()
	var fingerprints: Dictionary = {}
	for sample: int in 500:
		rng.seed = 31_121 + sample
		var proportions: Resource = Proportions.new()
		Presets.randomize_safe(proportions, rng)
		var values: Dictionary = proportions.as_dictionary()
		_expect(Presets.is_safe(values), "random sample %d respects all pair constraints" % sample)
		fingerprints[JSON.stringify(values)] = true
	_expect(fingerprints.size() > 490, "seeded randomization produces varied bodies")


func _check_random_button() -> void:
	var target: Resource = Proportions.new()
	var changed_events: Array[bool] = []
	var button_events: Array[Resource] = []
	target.changed.connect(func() -> void: changed_events.append(true))
	var button: Button = RandomButton.new()
	button.proportions = target
	button.set_random_seed(31_121)
	button.proportions_randomized.connect(
		func(value: Resource) -> void: button_events.append(value)
	)
	root.add_child(button)
	await process_frame
	button.emit_signal(&"pressed")
	_expect(changed_events.size() == 1, "one click emits one Resource change")
	_expect(button_events == [target], "one click reports the randomized resource")
	_expect(Presets.is_safe(target.as_dictionary()), "the button uses the safe randomizer")
	_expect(button.text != "UI_GEL_PROPORTION_RANDOM", "the button label is translated")
	button.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
