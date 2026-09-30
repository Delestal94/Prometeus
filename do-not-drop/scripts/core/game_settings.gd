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
	&"sound_subtitles", &"voice_chat_enabled", &"voice_push_to_talk", &"save_run_log", &"last_join_address",
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
## default until playback (N-212.2) and its Options toggle (N-212.3) land.
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
]
const DEFAULT_KEY_BINDINGS := {
	&"interact": KEY_E, &"ui_ping": KEY_V, &"drive_horn": KEY_H, &"look_back": KEY_B, &"use_card": KEY_G,
	&"voice_talk": KEY_Z, &"sprint": KEY_SHIFT,
	# The old van's manual gearbox (N-114); the gamepad uses the bumpers.
	&"drive_shift_up": KEY_UP, &"drive_shift_down": KEY_DOWN,
}

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

## The last address typed into "Unirse", so rejoining the same friend's LAN
## game doesn't mean typing their IP again every session.
var last_join_address: String = "":
	set(value):
		last_join_address = value.strip_edges()
		_save()


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
