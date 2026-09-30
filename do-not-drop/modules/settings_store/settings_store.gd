class_name SettingsStore
extends Node
## Player-facing settings that survive closing the game. Portable module
## (docs/modulos.md): the game extends it as an autoload, declares its own
## properties (each setter applies itself and calls _save()) and lists them
## in `saved_keys`; this file is the ConfigFile round trip, the generic
## settings every game has (language, fullscreen, audio bus volumes,
## rebindable keys, which input device is in hand) and the hooks a game
## uses to migrate an old file.
##
## Settings apply themselves the moment they change (a volume writes
## straight to its audio bus) so no screen has to remember to push them
## anywhere, and they're saved on change rather than on exit, because the
## way a prototype usually closes is a crash.

signal language_changed(locale: String)
signal input_device_changed(gamepad: bool)

## Configuration the game sets in _init.
var save_path: String = "user://settings.cfg"
var section: String = "player"
## The properties written to and read from the file, in order. Every one
## must exist on the node (get()/set() by name).
var saved_keys: Array[StringName] = []
var default_language: String = "en"
var supported_languages: Array[String] = ["en"]
## Actions the player may rebind, and the keys they ship with.
var rebindable_actions: Array[StringName] = []
var default_key_bindings: Dictionary = {}
## The key that flips fullscreen on any screen; KEY_NONE for none.
var fullscreen_key: Key = KEY_F11

var language: String = "en"
## action -> keycode for every rebindable action.
var key_bindings: Dictionary = {}:
	set(value):
		key_bindings = value.duplicate()
		for action: StringName in rebindable_actions:
			_apply_key_binding(action, int(key_bindings.get(action, default_key_bindings.get(action, KEY_NONE))))
		_save()
var fullscreen: bool = false:
	set(value):
		fullscreen = value
		_apply_fullscreen()
		_save()

## Not a saved setting: which device the player touched last. Every
## on-screen prompt asks this instead of printing "E / A".
var using_gamepad: bool = false

## Guards the setters while loading, so reading the file back doesn't write
## it again once per property.
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Under a test script (--script) the main loop has a script of its own:
	# keep tests away from the player's real save.
	if Engine.get_main_loop().get_script() != null:
		save_path = save_path.get_base_dir().path_join("test_" + save_path.get_file())
	language = default_language
	_load()


func _input(event: InputEvent) -> void:
	var gamepad: bool = using_gamepad
	if event is InputEventJoypadButton:
		gamepad = true
	elif event is InputEventJoypadMotion:
		# Stick drift sits well under this, and shouldn't flip the prompts
		# back while someone is typing on the keyboard.
		gamepad = gamepad or absf((event as InputEventJoypadMotion).axis_value) > 0.5
	elif event is InputEventKey or event is InputEventMouseButton:
		gamepad = false
	if gamepad != using_gamepad:
		using_gamepad = gamepad
		input_device_changed.emit(gamepad)


func _unhandled_input(event: InputEvent) -> void:
	# The shortcut every PC player tries first; it works on any screen.
	if fullscreen_key == KEY_NONE or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == fullscreen_key:
		fullscreen = not fullscreen
		get_viewport().set_input_as_handled()


## Picks the half of a prompt that matches the device in hand.
func prompt(keyboard: String, gamepad: String) -> String:
	return gamepad if using_gamepad else keyboard


func set_language(locale: String) -> void:
	var normalized: String = locale if locale in supported_languages else default_language
	var changed: bool = language != normalized
	language = normalized
	TranslationServer.set_locale(language)
	if changed:
		language_changed.emit(language)
		_save()


## The sign to multiply vertical look motion by, for a game with an
## `invert_look_y` property.
func look_y_sign() -> float:
	return -1.0 if bool(get(&"invert_look_y")) else 1.0


func bind_key(action: StringName, keycode: Key) -> void:
	if action not in rebindable_actions or keycode == KEY_NONE:
		return
	key_bindings[action] = keycode
	_apply_key_binding(action, keycode)
	_save()


func binding_label(action: StringName) -> String:
	return OS.get_keycode_string(int(key_bindings.get(action, default_key_bindings.get(action, KEY_NONE))))


func _apply_key_binding(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action) or keycode == KEY_NONE:
		return
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)


## Sets a bus's volume from a 0..1 value. Silence is -inf dB, which
## linear_to_db already returns for 0.0; setting the bus to that is what
## actually mutes it.
func apply_bus_volume(bus_name: String, volume: float) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


## Reads the file: every saved key back through its own setter (so it
## applies itself), the language, the key bindings merged over the defaults.
func _load() -> void:
	_before_load()
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		_loading = true
		key_bindings = default_key_bindings.duplicate()
		_loading = false
		TranslationServer.set_locale(language)
		_apply_defaults()
		return
	_loading = true
	for key: StringName in saved_keys:
		set(key, config.get_value(section, key, get(key)))
	language = String(config.get_value(section, "language", default_language))
	if language not in supported_languages:
		language = default_language
	TranslationServer.set_locale(language)
	var saved_bindings: Dictionary = Dictionary(config.get_value(section, "key_bindings", default_key_bindings))
	var merged: Dictionary = default_key_bindings.duplicate()
	for action: StringName in rebindable_actions:
		merged[action] = int(saved_bindings.get(action, default_key_bindings.get(action, KEY_NONE)))
	key_bindings = merged
	_after_load(config)
	_loading = false
	if _needs_rewrite(config):
		_save()


func _save() -> void:
	if _loading:
		return
	var config := ConfigFile.new()
	for key: StringName in saved_keys:
		config.set_value(section, key, get(key))
	config.set_value(section, "language", language)
	config.set_value(section, "key_bindings", key_bindings)
	_before_save(config)
	config.save(save_path)


# --- Hooks the game fills in ---------------------------------------------------

## Before the file is read (a one-time carry-over from an older folder).
func _before_load() -> void:
	pass


## No file yet: apply what the defaults mean (volumes to their buses).
func _apply_defaults() -> void:
	pass


## The file was read and every key set; fix up old files here.
func _after_load(_config: ConfigFile) -> void:
	pass


## Whether the file read should be written back at once (a migration).
func _needs_rewrite(_config: ConfigFile) -> bool:
	return false


## Extra keys to write (a migration marker).
func _before_save(_config: ConfigFile) -> void:
	pass
