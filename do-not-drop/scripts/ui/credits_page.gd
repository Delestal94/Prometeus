class_name CreditsPage
extends VBoxContainer
## The credits (expansion D-1940): who made the game and with what, as the repository says it, in sections that
## scroll. A page of the main menu (Garaje > Créditos). Every line is a translation key, names included, so the
## English page reads right; SECTIONS is the whole content.
##   the team; the engine and the Steam layer (Godot Engine and GodotSteam, MIT); the fonts (Lilita One, Nunito and
##   PT Serif, SIL Open Font License 1.1, assets/fonts/*-OFL.txt); music and sound, composed and synthesized in code
##   (tools/audio/compose_music.py, SynthAudio), no recorded voice; the low-poly models, built by Blender scripts
##   (tools/build_lowpoly_glb_assets*.py); and thanks.

const SECTIONS: Array = [
	["UI_CREDITS_TEAM", ["UI_CREDITS_TEAM_NACHO", "UI_CREDITS_TEAM_SLATEX"]],
	["UI_CREDITS_ENGINE", ["UI_CREDITS_ENGINE_GODOT", "UI_CREDITS_ENGINE_STEAM"]],
	["UI_CREDITS_FONTS", ["UI_CREDITS_FONTS_LIST", "UI_CREDITS_FONTS_LICENSE"]],
	["UI_CREDITS_SOUND", ["UI_CREDITS_SOUND_MUSIC", "UI_CREDITS_SOUND_SFX"]],
	["UI_CREDITS_ART", ["UI_CREDITS_ART_MODELS"]],
	["UI_CREDITS_THANKS", ["UI_CREDITS_THANKS_TESTERS"]],
]
const BODY_HEIGHT: float = 330.0
const SCROLL_STEP: int = 48

var _scroll: ScrollContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.custom_minimum_size = Vector2(0, BODY_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	_scroll.add_child(body)
	for section: Array in SECTIONS:
		UiTheme.tag(body, tr(String(section[0])), UiTheme.YELLOW, -1.0, 15)
		for key: String in section[1]:
			var line: Label = UiTheme.label(body, tr(key), 15, UiTheme.INK)
			line.name = key
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Scrolls the body by `pixels`.
func scroll_by(pixels: int) -> void:
	_scroll.scroll_vertical += pixels


## The lines take no focus, so up and down (pad or keys) scroll them while the page shows.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_up"):
		scroll_by(SCROLL_STEP if event.is_action_pressed(&"ui_down") else -SCROLL_STEP)
		get_viewport().set_input_as_handled()


## Every line shown, in order.
func lines() -> Array[String]:
	var out: Array[String] = []
	for section: Array in SECTIONS:
		out.append(tr(String(section[0])))
		for key: String in section[1]:
			out.append(tr(key))
	return out
