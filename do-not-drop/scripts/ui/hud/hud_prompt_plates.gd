extends RefCounted
## The two plates over the controls bar (N-983): the interaction prompt (a
## keycap and what it does) and, apart under it, the sound subtitles in cream.
## They used to be one label, so "[ E ] Agarrar paquete" and "[vidrio que
## cruje]" read as a list of equal things. Built here so hud.gd only calls it;
## HudPrompts fills them, GameSettings.subtitle_scale sizes the subtitle one.
## Knows nothing of Hud: it gets the dashboard and the rich-label factory.

## Air between the prompt plate and the subtitle plate, in HUD units.
const STACK_GAP: int = 4
## Ink outline around the text; one more with a faint plate (N-983.4), where the
## outline is what keeps white text readable over snow and sky.
const OUTLINE: int = 4
const OUTLINE_FAINT_PLATE: int = 5
const FAINT_PLATE_BELOW: float = 0.5


## Adds the stack to `dashboard` and returns {stack, prompt, subtitle}.
## `make_rich` is Hud.make_rich(parent, font_size) -> RichTextLabel.
static func build(dashboard: Control, make_rich: Callable, font_size: int) -> Dictionary:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", STACK_GAP)
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(stack)
	var prompt: RichTextLabel = _plate_text(stack, make_rich, font_size, UiTheme.PAPER)
	var subtitle: RichTextLabel = _plate_text(stack, make_rich, font_size, UiTheme.CREAM)
	apply_subtitle_scale(subtitle, font_size)
	return {"stack": stack, "prompt": prompt, "subtitle": subtitle}


static func _plate_text(parent: Node, make_rich: Callable, font_size: int, color: Color) -> RichTextLabel:
	var label: RichTextLabel = make_rich.call(parent, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("default_color", color)
	label.add_theme_color_override("font_outline_color", UiTheme.INK)
	return label


## The subtitle plate alone follows the size option; the prompt keeps its size.
static func apply_subtitle_scale(subtitle: RichTextLabel, base_font_size: int) -> void:
	if subtitle == null:
		return
	subtitle.add_theme_font_size_override("normal_font_size",
		roundi(float(base_font_size) * GameSettings.subtitle_scale))


## Plate opacity and outline for both plates (Hud.apply_text_backdrop).
static func apply_backdrop(labels: Array[RichTextLabel], opacity: float) -> void:
	for label: RichTextLabel in labels:
		var plate := label.get_theme_stylebox("normal") as StyleBoxFlat
		if plate == null:
			continue
		plate.bg_color = Color(UiTheme.INK, opacity)
		plate.border_color = Color(UiTheme.INK, opacity)
		plate.shadow_color = Color(UiTheme.INK, opacity * 0.5)
		label.add_theme_constant_override("outline_size",
			OUTLINE_FAINT_PLATE if opacity < FAINT_PLATE_BELOW else OUTLINE)
