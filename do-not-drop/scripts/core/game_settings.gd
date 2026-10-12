extends SettingsStore
## Take My Package's settings on the settings_store module's SettingsStore
## (docs/modulos.md): the module does the file, the language, fullscreen,
## the audio buses and the rebindable keys; this file is what this game
## lets the player change and what each setting does when it does.
##
## docs/critica-diseno-abogado-del-diablo.md section 4: a party game aimed at
## people who don't play much had no way to turn the volume down, no way to
## change look sensitivity, and no way to leave without Alt+F4. None of that
## is a feature anybody asks for by name -- it's the floor a game has to
## clear before it can be handed to someone else.

const SAVE_PATH: String = "user://settings.cfg"
## Kept explicit so the settings autoload compiles the same in the
## editor/game and the isolated test runner.
const WORLD_QUALITY = preload("res://modules/render_budget/world_quality.gd")
const SECTION: String = "player"
const LANGUAGE_DEFAULT: String = "es"
const SUPPORTED_LANGUAGES: Array[String] = ["es", "en"]
const SAVED_KEYS: Array[StringName] = [
	&"master_volume", &"music_volume", &"effects_volume", &"voice_volume", &"preferred_fov",
	&"camera_shake_scale", &"impact_effects", &"look_sensitivity", &"invert_look_y", &"fullscreen",
	&"graphics_quality", &"hud_scale", &"control_help_mode", &"colorblind_palette", &"menu_text_scale",
	&"opaque_gel", &"sound_subtitles", &"voice_chat_enabled", &"voice_push_to_talk", &"save_run_log", &"last_join_address",
	&"newspaper_mode",
]

## 0.0 mutes, 1.0 is the unmodified mix the game was balanced at.
var master_volume: float = 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		apply_bus_volume("Master", master_volume)
		_save()

## Background music on its own bus, under the master volume.
var music_volume: float = MUSIC_VOLUME_DEFAULT:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		apply_bus_volume("Music", music_volume)
		_save()
const MUSIC_VOLUME_DEFAULT: float = 0.7
var effects_volume: float = 1.0:
	set(value):
		effects_volume = clampf(value, 0.0, 1.0)
		apply_bus_volume("SFX", effects_volume)
		_save()
var voice_volume: float = 1.0:
	set(value):
		voice_volume = clampf(value, 0.0, 1.0)
		apply_bus_volume("Voice", voice_volume)
		_save()
var preferred_fov: float = 82.0:
	set(value):
		preferred_fov = clampf(value, 65.0, 100.0)
		_save()
var camera_shake_scale: float = 1.0:
	set(value):
		camera_shake_scale = clampf(value, 0.0, 1.0)
		_save()

## Local-only ruin punctuation (brief slowed confetti, white vignette and low thud).
## Accessibility switch: it never changes simulation or Engine.time_scale.
var impact_effects: bool = true:
	set(value):
		impact_effects = value
		_save()

## Proximity voice (N-212, proximity_voice.gd). The general switch: while it
## is off the microphone is never opened, whatever key is held. Off by
## default until it is tested with a real Steam session; it is switched on
## in Options (options_voice_section.gd, N-212.3).
var voice_chat_enabled: bool = false:
	set(value):
		voice_chat_enabled = value
		_save()
## Push-to-talk is the default (critico-diseno, N-704.3); off means open mic.
var voice_push_to_talk: bool = true:
	set(value):
		voice_push_to_talk = value
		_save()

## Local run log (S-805, run_telemetry.gd): at the end of each run the game
## writes one JSON file to user://telemetry/ for the playtest summary script.
## Off by default; nothing ever leaves this machine.
var save_run_log: bool = false:
	set(value):
		save_run_log = value
		_save()

const REBINDABLE_ACTIONS := [
	&"interact", &"ui_ping", &"drive_horn", &"look_back", &"use_card", &"voice_talk", &"sprint",
	&"drive_shift_up", &"drive_shift_down",
	# N-966: everything else the player presses. drive_left / drive_right are
	# also the strafe keys on foot (player_movement.gd).
	&"walk_forward", &"walk_backward", &"drive_left", &"drive_right", &"jump",
	&"drive_accelerate", &"drive_brake", &"drive_handbrake",
	&"package_drop", &"package_open", &"care_work", &"care_tool_next", &"phone_toggle", &"crew_panel",
	&"spectate_toggle",
]
## Actions that carry a key in the Input Map but are not offered in Options: no
## action may be moved onto their key (a notice says it is reserved, like Esc / F11).
const RESERVED_KEY_ACTIONS: Array[StringName] = [
	&"ui_pause", &"run_restart", &"look_center", &"dev_camera_toggle", &"toggle_net_stats",
]
## The shipped keys are the project.godot ones. KEY_NONE means "no keyboard key
## by default": care_work is the right mouse button until a key is added.
const DEFAULT_KEY_BINDINGS := {
	&"interact": KEY_E, &"ui_ping": KEY_V, &"drive_horn": KEY_H, &"look_back": KEY_B, &"use_card": KEY_G,
	&"voice_talk": KEY_Z, &"sprint": KEY_SHIFT,
	# The old van's manual gearbox (N-114); the gamepad uses the bumpers.
	&"drive_shift_up": KEY_UP, &"drive_shift_down": KEY_DOWN,
	&"walk_forward": KEY_W, &"walk_backward": KEY_S, &"drive_left": KEY_A, &"drive_right": KEY_D,
	&"jump": KEY_SPACE, &"drive_accelerate": KEY_W, &"drive_brake": KEY_S, &"drive_handbrake": KEY_SPACE,
	&"package_drop": KEY_Q, &"package_open": KEY_T, &"care_work": KEY_NONE, &"care_tool_next": KEY_X,
	&"phone_toggle": KEY_F,
	&"crew_panel": KEY_TAB, &"spectate_toggle": KEY_TAB,
}

## Where each action is read. Two actions only clash over a key when they share
## a context: W is both "walk forward" and "accelerate" by default, because you
## are never walking and driving at once. An action missing here counts as ALL.
const CONTEXT_FOOT: int = 1
const CONTEXT_DRIVE: int = 2
const CONTEXT_DEPOT: int = 4
const CONTEXT_SPECTATE: int = 8
const CONTEXT_ALL: int = 15
const BINDING_CONTEXTS := {
	&"walk_forward": CONTEXT_FOOT, &"walk_backward": CONTEXT_FOOT, &"jump": CONTEXT_FOOT,
	&"drive_left": CONTEXT_FOOT | CONTEXT_DRIVE, &"drive_right": CONTEXT_FOOT | CONTEXT_DRIVE,
	&"drive_accelerate": CONTEXT_DRIVE, &"drive_brake": CONTEXT_DRIVE, &"drive_handbrake": CONTEXT_DRIVE,
	&"drive_horn": CONTEXT_DRIVE, &"drive_shift_up": CONTEXT_DRIVE, &"drive_shift_down": CONTEXT_DRIVE,
	&"look_back": CONTEXT_FOOT | CONTEXT_DRIVE,
	&"sprint": CONTEXT_FOOT | CONTEXT_DRIVE, &"package_drop": CONTEXT_FOOT | CONTEXT_DRIVE,
	&"package_open": CONTEXT_FOOT | CONTEXT_DRIVE, &"care_work": CONTEXT_FOOT | CONTEXT_DRIVE,
		&"care_tool_next": CONTEXT_FOOT | CONTEXT_DRIVE,
	&"phone_toggle": CONTEXT_FOOT | CONTEXT_DRIVE,
	&"crew_panel": CONTEXT_FOOT | CONTEXT_DRIVE | CONTEXT_DEPOT, &"spectate_toggle": CONTEXT_SPECTATE,
}

## What rebind_key() / reset_binding() report in result["status"].
const BIND_OK: StringName = &"ok"
const BIND_SWAPPED: StringName = &"swapped"
const BIND_BLOCKED: StringName = &"blocked"
const BIND_RESERVED: StringName = &"reserved"
const BIND_INVALID: StringName = &"invalid"

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

## Graphics quality preset, WorldQuality.Level (tareas de Nacho N-205):
## applies at once to whatever is on screen, and to what loads later.
var graphics_quality: int = WORLD_QUALITY.Level.HIGH:
	set(value):
		graphics_quality = clampi(value, WORLD_QUALITY.Level.LOW, WORLD_QUALITY.Level.HIGH)
		if is_inside_tree():
			WORLD_QUALITY.apply(get_tree(), graphics_quality)
		gel_material_mode_changed.emit(uses_opaque_gel())
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

## How long the compact shortcut strip stays on screen. BEGINNING teaches
## new players, then gets out of the way; the other two modes are explicit
## accessibility preferences.
enum ControlHelp { ALWAYS, BEGINNING, NEVER }
var control_help_mode: int = ControlHelp.BEGINNING:
	set(value):
		control_help_mode = clampi(value, ControlHelp.ALWAYS, ControlHelp.NEVER)
		control_help_mode_changed.emit(control_help_mode)
		_save()
signal control_help_mode_changed(mode: int)

## Accessibility choices are independent: someone may need the colour-safe
## palette without larger menu text, or captions without either visual aid.
var colorblind_palette: bool = false:
	set(value):
		colorblind_palette = value
		colorblind_palette_changed.emit(colorblind_palette)
		_save()
signal colorblind_palette_changed(enabled: bool)

## Removes transparent sorting and screen reads from gel bodies. Low graphics
## quality enables the same opaque material automatically; this switch lets a
## player choose it independently as an accessibility preference.
var opaque_gel: bool = false:
	set(value):
		opaque_gel = value
		gel_material_mode_changed.emit(uses_opaque_gel())
		_save()
signal gel_material_mode_changed(use_opaque: bool)


func uses_opaque_gel() -> bool:
	return opaque_gel or graphics_quality == WORLD_QUALITY.Level.LOW

const MENU_TEXT_SCALES: Array[float] = [1.0, 1.25, 1.5]
var menu_text_scale: float = 1.0:
	set(value):
		var closest: float = MENU_TEXT_SCALES[0]
		for candidate: float in MENU_TEXT_SCALES:
			if absf(candidate - value) < absf(closest - value):
				closest = candidate
		menu_text_scale = closest
		menu_text_scale_changed.emit(menu_text_scale)
		_save()
signal menu_text_scale_changed(scale: float)

var sound_subtitles: bool = false:
	set(value):
		sound_subtitles = value
		sound_subtitles_changed.emit(sound_subtitles)
		_save()
signal sound_subtitles_changed(enabled: bool)

## The next-day newspaper at the end of a delivery (N-606.3): always, only
## when the run gave news (not the "everything arrived" scandal), or never.
enum NewspaperMode { ALWAYS, NEWS_ONLY, NEVER }
var newspaper_mode: int = NewspaperMode.ALWAYS:
	set(value):
		newspaper_mode = clampi(value, NewspaperMode.ALWAYS, NewspaperMode.NEVER)
		_save()

## The last address typed into "Unirse", so rejoining the same friend's LAN
## game doesn't mean typing their IP again every session.
var last_join_address: String = "":
	set(value):
		last_join_address = value.strip_edges()
		_save()


## The arrow keys read as arrows, not as the English "Up"/"Down" the engine
## names them (N-114: the gear keys), here and wherever a prompt shows a key.
const KEY_GLYPHS := {KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→"}


func binding_label(action: StringName) -> String:
	var keycode: int = bound_key(action)
	if keycode == KEY_NONE:
		return tr("UI_OPT_BIND_RIGHT_CLICK")
	return String(KEY_GLYPHS.get(keycode, super(action)))


## The key an action has now (its default until the player changes it).
func bound_key(action: StringName) -> int:
	return int(key_bindings.get(action, default_key_bindings.get(action, KEY_NONE)))


func is_binding_default(action: StringName) -> bool:
	return bound_key(action) == int(DEFAULT_KEY_BINDINGS.get(action, KEY_NONE))


## The other rebindable actions that already use this key in a context that
## `action` is also read in (empty when the key is free for it).
func binding_conflicts(action: StringName, keycode: int) -> Array[StringName]:
	var found: Array[StringName] = []
	if keycode == KEY_NONE:
		return found
	var mine: int = int(BINDING_CONTEXTS.get(action, CONTEXT_ALL))
	for other: StringName in rebindable_actions:
		if other != action and bound_key(other) == keycode \
				and (mine & int(BINDING_CONTEXTS.get(other, CONTEXT_ALL))) != 0:
			found.append(other)
	return found


## True when the key belongs to an action Options does not offer (restart,
## look center, dev camera, net stats, pause), whatever the Input Map says now.
func is_reserved_key(keycode: int) -> bool:
	for action: StringName in RESERVED_KEY_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				if keycode in [int(key.physical_keycode), int(key.keycode)] and keycode != KEY_NONE:
					return true
	return false


## Binds a key the way Options does (N-966). A key another action already
## uses (in a shared context) is swapped: that action gets this one's old key.
## When a swap can't be clean (several owners, nothing to hand back, or the
## handed-back key collides too) nothing changes and the status is BLOCKED.
## Returns {"status": BIND_*, "other": the action involved, or &""}.
func rebind_key(action: StringName, keycode: int) -> Dictionary:
	if action not in rebindable_actions or keycode == KEY_NONE:
		return {"status": BIND_INVALID, "other": &""}
	if keycode == KEY_ESCAPE or (fullscreen_key != KEY_NONE and keycode == fullscreen_key):
		return {"status": BIND_RESERVED, "other": &""}
	if is_reserved_key(keycode):
		return {"status": BIND_RESERVED, "other": &""}
	var old: int = bound_key(action)
	if keycode == old:
		return {"status": BIND_OK, "other": &""}
	var owners: Array[StringName] = binding_conflicts(action, keycode)
	if owners.is_empty():
		_assign_key(action, keycode)
		_save()
		return {"status": BIND_OK, "other": &""}
	var other: StringName = owners[0]
	if owners.size() > 1 or old == KEY_NONE:
		return {"status": BIND_BLOCKED, "other": other}
	var collisions: Array[StringName] = binding_conflicts(other, old)
	collisions.erase(action)
	if not collisions.is_empty():
		return {"status": BIND_BLOCKED, "other": other}
	_assign_key(other, old)
	_assign_key(action, keycode)
	_save()
	return {"status": BIND_SWAPPED, "other": other}


## Puts one action back on its shipped key (same swap rule as rebind_key).
func reset_binding(action: StringName) -> Dictionary:
	if action not in rebindable_actions:
		return {"status": BIND_INVALID, "other": &""}
	var default_key: int = int(DEFAULT_KEY_BINDINGS.get(action, KEY_NONE))
	if default_key == KEY_NONE:
		_assign_key(action, KEY_NONE)
		_save()
		return {"status": BIND_OK, "other": &""}
	return rebind_key(action, default_key)


func _assign_key(action: StringName, keycode: int) -> void:
	key_bindings[action] = keycode
	_apply_key_binding(action, keycode as Key)


## KEY_NONE here means "take the keyboard key away" (care_work back to the
## mouse); the module skips it.
func _apply_key_binding(action: StringName, keycode: Key) -> void:
	if keycode == KEY_NONE:
		if InputMap.has_action(action):
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey:
					InputMap.action_erase_event(action, event)
		return
	super(action, keycode)


func _init() -> void:
	save_path = SAVE_PATH
	section = SECTION
	saved_keys = SAVED_KEYS.duplicate()
	default_language = LANGUAGE_DEFAULT
	supported_languages = SUPPORTED_LANGUAGES.duplicate()
	rebindable_actions.assign(REBINDABLE_ACTIONS)
	default_key_bindings = DEFAULT_KEY_BINDINGS.duplicate()


func _ready() -> void:
	super()
	# The palette reaches the render_budget module before the first model is
	# dressed (the route_gen and world_mood modules go to DetailMaterials directly).
	LowpolyMaterials.configure()
	WORLD_QUALITY.watch(get_tree())
	WORLD_QUALITY.apply(get_tree(), graphics_quality)


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
	impact_effects = true
	look_sensitivity = 1.0
	invert_look_y = false
	fullscreen = false
	graphics_quality = WORLD_QUALITY.Level.HIGH
	hud_scale = HUD_SCALE_DEFAULT
	control_help_mode = ControlHelp.BEGINNING
	colorblind_palette = false
	opaque_gel = false
	menu_text_scale = 1.0
	sound_subtitles = false
	voice_chat_enabled = false
	voice_push_to_talk = true
	save_run_log = false
	key_bindings = DEFAULT_KEY_BINDINGS.duplicate()
	set_language(LANGUAGE_DEFAULT)
	_loading = false
	_save()


## The working-title save folder comes over once (LegacyUserData).
func _before_load() -> void:
	LegacyUserData.migrate()


## No file yet: the defaults still have to reach their buses.
func _apply_defaults() -> void:
	apply_bus_volume("Master", master_volume)
	apply_bus_volume("Music", music_volume)
	apply_bus_volume("SFX", effects_volume)
	apply_bus_volume("Voice", voice_volume)


func _after_load(config: ConfigFile) -> void:
	# A hand-edited file can't leave an action that ships with a key keyless.
	for action: StringName in rebindable_actions:
		var shipped: int = int(DEFAULT_KEY_BINDINGS.get(action, KEY_NONE))
		if shipped != KEY_NONE and bound_key(action) == KEY_NONE:
			_assign_key(action, shipped)
	# Files saved before the HUD default dropped hold the old 100 % default,
	# not a choice anyone made: move them to the new one, once.
	if not config.has_section_key(SECTION, HUD_DEFAULT_MARKER):
		hud_scale = HUD_SCALE_DEFAULT
	else:
		hud_scale = minf(hud_scale, HUD_SCALE_MAX)


func _needs_rewrite(config: ConfigFile) -> bool:
	return not config.has_section_key(SECTION, HUD_DEFAULT_MARKER)


func _before_save(config: ConfigFile) -> void:
	config.set_value(SECTION, HUD_DEFAULT_MARKER, true)
