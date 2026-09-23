class_name LeaderboardPanel
extends Control

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func open() -> void:
	_refresh()
	show()


func _build() -> void:
	UiTheme.apply(self)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.06, 0.08, 0.92)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(520, 0), 26)
	column.add_theme_constant_override("separation", 10)
	UiTheme.title(column, "Récords locales", 36)
	var rank: int = 1
	for entry: Dictionary in RunManager.leaderboard:
		UiTheme.label(column, "%d.  %d pts  ·  %s  ·  %s" % [rank, int(entry.get("score", 0)), String(entry.get("mode", "delivery")), String(entry.get("date", ""))], 18, UiTheme.WHITE)
		rank += 1
	if rank == 1:
		UiTheme.label(column, "Todavía no hay entregas registradas.", 18, UiTheme.MUTED)
	var close_button: Button = UiTheme.button(column, "Volver", false, Vector2(0, 48))
	close_button.pressed.connect(func() -> void: hide(); closed.emit())


func _refresh() -> void:
	for child: Node in get_children():
		child.queue_free()
	call_deferred("_build")
