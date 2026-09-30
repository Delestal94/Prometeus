extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/settings_store/tests/test_settings_store.gd
##
## The settings_store module on its own (docs/modulos.md), with a game-like
## subclass defined here: a property listed in saved_keys is written when
## it changes and read back through its setter (so it applies itself); an
## unknown language falls back to the default; key bindings merge over the
## defaults and reach the InputMap; the migration hooks run on an old file;
## a test run never touches the real save; the input device follows the
## last event; prompt() picks the half for the device in hand.

var _failures: int = 0


class GameSettingsLike extends SettingsStore:
	var volume: float = 1.0:
		set(value):
			volume = clampf(value, 0.0, 1.0)
			applied.append(volume)
			_save()
	var subtitles: bool = false:
		set(value):
			subtitles = value
			_save()
	var applied: Array = []
	var migrated: bool = false

	func _init() -> void:
		save_path = "user://settings_store_module.cfg"
		section = "player"
		saved_keys = [&"volume", &"subtitles"]
		default_language = "es"
		supported_languages = ["es", "en"]
		rebindable_actions = [&"jump"]
		default_key_bindings = {&"jump": KEY_SPACE}

	func _after_load(config: ConfigFile) -> void:
		if not config.has_section_key(section, "v2"):
			migrated = true

	func _needs_rewrite(config: ConfigFile) -> bool:
		return not config.has_section_key(section, "v2")

	func _before_save(config: ConfigFile) -> void:
		config.set_value(section, "v2", true)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not InputMap.has_action(&"jump"):
		InputMap.add_action(&"jump")
	var path: String = "user://test_settings_store_module.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var settings := GameSettingsLike.new()
	root.add_child(settings)
	await process_frame
	_expect(settings.save_path == path, "Under a test script the store uses a test file (got %s)" % settings.save_path)
	_expect(settings.language == "es" and TranslationServer.get_locale().begins_with("es"),
		"The default language applies with no file")
	_expect(settings.key_bindings == {&"jump": KEY_SPACE},
		"Bindings start at their defaults (got %s)" % [settings.key_bindings])
	settings.volume = 0.4
	settings.subtitles = true
	settings.bind_key(&"jump", KEY_J)
	settings.set_language("en")
	_expect(settings.binding_label(&"jump") == "J",
		"A rebound key is labelled (got %s)" % settings.binding_label(&"jump"))
	var bound_j: bool = false
	for event: InputEvent in InputMap.action_get_events(&"jump"):
		bound_j = bound_j or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_J)
	_expect(bound_j, "The binding reaches the InputMap")
	var config := ConfigFile.new()
	_expect(config.load(path) == OK, "Changes are saved at once")
	_expect(is_equal_approx(float(config.get_value("player",
		"volume", 0.0)), 0.4) and bool(config.get_value("player", "subtitles", false)),
		"Every saved key is in the file")
	_expect(String(config.get_value("player", "language", "")) == "en", "The language is in the file")
	_expect(bool(config.get_value("player", "v2", false)), "The game's extra keys are written")
	settings.free()

	# An old file (no marker, an unknown language, a stale binding) read back.
	config.set_value("player", "language", "fr")
	config.set_value("player", "key_bindings", {&"jump": KEY_K, &"gone": KEY_X})
	config.erase_section_key("player", "v2")
	config.save(path)
	var again := GameSettingsLike.new()
	root.add_child(again)
	await process_frame
	_expect(is_equal_approx(again.volume, 0.4) and again.subtitles, "Saved values come back through their setters")
	_expect(again.applied == [0.4], "A setter applied itself once on load (got %s)" % [again.applied])
	_expect(again.language == "es", "An unsupported language falls back to the default (got %s)" % again.language)
	_expect(again.key_bindings == {&"jump": KEY_K},
		"Bindings merge over the defaults and drop unknown actions (got %s)" % [again.key_bindings])
	_expect(again.migrated, "The migration hook saw the old file")
	var rewritten := ConfigFile.new()
	rewritten.load(path)
	_expect(bool(rewritten.get_value("player", "v2", false)), "An old file is rewritten with the marker")
	again.set_language("de")
	_expect(again.language == "es", "set_language() refuses an unsupported locale")

	var joy := InputEventJoypadButton.new()
	joy.pressed = true
	again._input(joy)
	_expect(again.using_gamepad and again.prompt("E", "A") == "A", "A gamepad press switches the prompts")
	var key := InputEventKey.new()
	key.pressed = true
	again._input(key)
	_expect(not again.using_gamepad and again.prompt("E", "A") == "E", "A key press switches them back")
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("PASS: settings save on change, load through their setters, migrate and follow the device")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
