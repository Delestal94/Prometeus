extends Node
## Player-facing settings that survive closing the game.
##
## docs/critica-diseno-abogado-del-diablo.md section 4: a party game aimed at
## people who don't play much had no way to turn the volume down, no way to
## change look sensitivity, and no way to leave without Alt+F4. None of that
## is a feature anybody asks for by name -- it's the floor a game has to
## clear before it can be handed to someone else.
##
## Settings apply themselves the moment they change (volume writes straight
## to the audio bus) so no screen has to remember to push them anywhere, and
## they're saved on change rather than on exit, because the way a prototype
## usually closes is a crash.

const SAVE_PATH: String = "user://settings.cfg"
## Headless `--script` tests do not build Godot's editor-managed global class
## cache before autoloads are parsed. Keep this dependency explicit so the
## settings autoload compiles in both the editor/game and the isolated runner.
const WORLD_QUALITY = preload("res://scripts/presentation/world_quality.gd")
var save_path: String = SAVE_PATH
const SECTION: String = "player"

## 0.0 mutes, 1.0 is the unmodified mix the game was balanced at.
var master_volume: float = 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		_apply_volume()
		_save()

## Background music on its own bus, under the master volume.
var music_volume: float = MUSIC_VOLUME_DEFAULT:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		_apply_music_volume()
		_save()
const MUSIC_VOLUME_DEFAULT: float = 0.7
var effects_volume: float = 1.0:
	set(value):
		effects_volume = clampf(value, 0.0, 1.0)
		_apply_bus("SFX", effects_volume)
		_save()
var voice_volume: float = 1.0:
	set(value):
		voice_volume = clampf(value, 0.0, 1.0)
		_apply_bus("Voice", voice_volume)
		_save()
var preferred_fov: float = 82.0:
	set(value):
		preferred_fov = clampf(value, 65.0, 100.0)
		_save()
var camera_shake_scale: float = 1.0:
	set(value):
		camera_shake_scale = clampf(value, 0.0, 1.0)
		_save()

const REBINDABLE_ACTIONS := [&"interact", &"ui_ping", &"drive_horn", &"look_back"]
const DEFAULT_KEY_BINDINGS := {&"interact": KEY_E, &"ui_ping": KEY_V, &"drive_horn": KEY_H, &"look_back": KEY_B}
var key_bindings: Dictionary = DEFAULT_KEY_BINDINGS.duplicate():
	set(value):
		key_bindings = value.duplicate()
		for action: StringName in REBINDABLE_ACTIONS:
			_apply_key_binding(action, int(key_bindings.get(action, DEFAULT_KEY_BINDINGS[action])))
		_save()

## Multiplies whatever each look implementation already uses, so 1.0 is
## exactly today's feel and nobody has to re-tune the defaults.
var look_sensitivity: float = 1.0:
	set(value):
		look_sensitivity = clampf(value, 0.2, 3.0)
		_save()

var invert_look_y: bool = false:
	set(value):
		invert_look_y = value
		_save()

var fullscreen: bool = false:
	set(value):
		fullscreen = value
		_apply_fullscreen()
		_save()

## Graphics quality preset, WorldQuality.Level (tareas de Nacho N-205):
## applies at once to whatever is on screen, and to what loads later.
var graphics_quality: int = WORLD_QUALITY.Level.HIGH:
	set(value):
		graphics_quality = clampi(value, WORLD_QUALITY.Level.LOW, WORLD_QUALITY.Level.HIGH)
		if is_inside_tree():
			WORLD_QUALITY.apply(get_tree(), graphics_quality)
		_save()

## Size of the in-game HUD (panels, banners, prompts) relative to how it
## was laid out. Menus and the pause/results card keep their size: they're
## centred and already sized to fit, it's the corners that crowd a small
## screen or vanish on a TV across the room.
const HUD_SCALE_MIN: float = 0.35
## A large HUD obscures the package, particularly at 1280×720. Keep the
## readable range compact; the interface is already deliberately high contrast.
const HUD_SCALE_MAX: float = 0.85
const HUD_SCALE_DEFAULT: float = 0.48
const HUD_DEFAULT_MARKER: String = "hud_scale_default_48"
var hud_scale: float = HUD_SCALE_DEFAULT:
	set(value):
		hud_scale = clampf(value, HUD_SCALE_MIN, HUD_SCALE_MAX)
		hud_scale_changed.emit(hud_scale)
		_save()
signal hud_scale_changed(scale: float)

## The last address typed into "Unirse", so rejoining the same friend's LAN
## game doesn't mean typing their IP again every session.
var last_join_address: String = "":
	set(value):
		last_join_address = value.strip_edges()
		_save()

## Not a saved setting: which device the player touched last. Every on-screen
## prompt asks this instead of printing "E / A" and making the player work
## out which half applies to them.
var using_gamepad: bool = false
signal input_device_changed(gamepad: bool)

## Guards the setters while loading, so reading the file back doesn't write
## it again four times.
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Under a test script (--script) the main loop has a script of its own:
	# keep tests away from the player's real save, which they used to fill
	# with dozens of scripted runs and unlocks.
	if Engine.get_main_loop().get_script() != null:
		save_path = "user://test_settings.cfg"
	_load()
	WORLD_QUALITY.watch(get_tree())
	WORLD_QUALITY.apply(get_tree(), graphics_quality)


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
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F11:
		fullscreen = not fullscreen
		get_viewport().set_input_as_handled()


## Picks the half of a prompt that matches the device in hand.
func prompt(keyboard: String, gamepad: String) -> String:
	return gamepad if using_gamepad else keyboard


## Back to how the game ships, for anyone who dragged a slider somewhere
## they can't get back from.
func reset_to_defaults() -> void:
	_loading = true
	master_volume = 1.0
	music_volume = MUSIC_VOLUME_DEFAULT
	effects_volume = 1.0
	voice_volume = 1.0
	preferred_fov = 82.0
	camera_shake_scale = 1.0
	look_sensitivity = 1.0
	invert_look_y = false
	fullscreen = false
	graphics_quality = WORLD_QUALITY.Level.HIGH
	hud_scale = HUD_SCALE_DEFAULT
	key_bindings = DEFAULT_KEY_BINDINGS.duplicate()
	_loading = false
	_save()


## The sign to multiply vertical look motion by. Both look implementations
## ask for this rather than each deciding what "inverted" means.
func look_y_sign() -> float:
	return -1.0 if invert_look_y else 1.0


func bind_key(action: StringName, keycode: Key) -> void:
	if action not in REBINDABLE_ACTIONS or keycode == KEY_NONE:
		return
	key_bindings[action] = keycode
	_apply_key_binding(action, keycode)
	_save()


func binding_label(action: StringName) -> String:
	return OS.get_keycode_string(int(key_bindings.get(action, DEFAULT_KEY_BINDINGS.get(action, KEY_NONE))))


func _apply_key_binding(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)


func _apply_volume() -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	# Silence is -inf dB, which linear_to_db already returns for 0.0; setting
	# the bus to that is what actually mutes it.
	AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))


func _apply_music_volume() -> void:
	var bus: int = AudioServer.get_bus_index("Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(music_volume))

func _apply_bus(name: String, volume: float) -> void:
	var bus := AudioServer.get_bus_index(name)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _load() -> void:
	LegacyUserData.migrate()
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		_apply_volume()
		_apply_music_volume()
		_apply_bus("SFX", effects_volume)
		_apply_bus("Voice", voice_volume)
		return
	_loading = true
	master_volume = float(config.get_value(SECTION, "master_volume", 1.0))
	music_volume = float(config.get_value(SECTION, "music_volume", MUSIC_VOLUME_DEFAULT))
	effects_volume = float(config.get_value(SECTION, "effects_volume", 1.0))
	voice_volume = float(config.get_value(SECTION, "voice_volume", 1.0))
	preferred_fov = float(config.get_value(SECTION, "preferred_fov", 82.0))
	camera_shake_scale = float(config.get_value(SECTION, "camera_shake_scale", 1.0))
	look_sensitivity = float(config.get_value(SECTION, "look_sensitivity", 1.0))
	invert_look_y = bool(config.get_value(SECTION, "invert_look_y", false))
	fullscreen = bool(config.get_value(SECTION, "fullscreen", false))
	graphics_quality = int(config.get_value(SECTION, "graphics_quality", WORLD_QUALITY.Level.HIGH))
	hud_scale = minf(float(config.get_value(SECTION, "hud_scale", HUD_SCALE_DEFAULT)), HUD_SCALE_MAX)
	# Files saved before the HUD default dropped to 60 % hold the old 100 %
	# default, not a choice anyone made: move them to the new one, once.
	if not config.has_section_key(SECTION, HUD_DEFAULT_MARKER):
		hud_scale = HUD_SCALE_DEFAULT
	last_join_address = String(config.get_value(SECTION, "last_join_address", ""))
	var saved_bindings: Dictionary = Dictionary(config.get_value(SECTION, "key_bindings", DEFAULT_KEY_BINDINGS))
	key_bindings = DEFAULT_KEY_BINDINGS.duplicate()
	for action: StringName in REBINDABLE_ACTIONS:
		key_bindings[action] = int(saved_bindings.get(action, DEFAULT_KEY_BINDINGS[action]))
		_apply_key_binding(action, int(key_bindings[action]))
	_loading = false
	if not config.has_section_key(SECTION, HUD_DEFAULT_MARKER):
		_save()
	_apply_bus("SFX", effects_volume)
	_apply_bus("Voice", voice_volume)


func _save() -> void:
	if _loading:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "effects_volume", effects_volume)
	config.set_value(SECTION, "voice_volume", voice_volume)
	config.set_value(SECTION, "preferred_fov", preferred_fov)
	config.set_value(SECTION, "camera_shake_scale", camera_shake_scale)
	config.set_value(SECTION, "look_sensitivity", look_sensitivity)
	config.set_value(SECTION, "invert_look_y", invert_look_y)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "graphics_quality", graphics_quality)
	config.set_value(SECTION, "hud_scale", hud_scale)
	config.set_value(SECTION, HUD_DEFAULT_MARKER, true)
	config.set_value(SECTION, "last_join_address", last_join_address)
	config.set_value(SECTION, "key_bindings", key_bindings)
	config.save(save_path)
