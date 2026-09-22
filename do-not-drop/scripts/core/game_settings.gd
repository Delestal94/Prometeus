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
const SECTION: String = "player"

## 0.0 mutes, 1.0 is the unmodified mix the game was balanced at.
var master_volume: float = 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		_apply_volume()
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

## Guards the setters while loading, so reading the file back doesn't write
## it again four times.
var _loading: bool = false


func _ready() -> void:
	_load()


## The sign to multiply vertical look motion by. Both look implementations
## ask for this rather than each deciding what "inverted" means.
func look_y_sign() -> float:
	return -1.0 if invert_look_y else 1.0


func _apply_volume() -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	# Silence is -inf dB, which linear_to_db already returns for 0.0; setting
	# the bus to that is what actually mutes it.
	AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		_apply_volume()
		return
	_loading = true
	master_volume = float(config.get_value(SECTION, "master_volume", 1.0))
	look_sensitivity = float(config.get_value(SECTION, "look_sensitivity", 1.0))
	invert_look_y = bool(config.get_value(SECTION, "invert_look_y", false))
	fullscreen = bool(config.get_value(SECTION, "fullscreen", false))
	_loading = false


func _save() -> void:
	if _loading:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "look_sensitivity", look_sensitivity)
	config.set_value(SECTION, "invert_look_y", invert_look_y)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.save(SAVE_PATH)
