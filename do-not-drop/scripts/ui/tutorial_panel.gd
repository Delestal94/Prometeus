extends Control
class_name TutorialPanel

signal closed
var _back_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(620, 0), 28)
	UiTheme.title(column, "Cómo jugar", 38)
	UiTheme.tag(column, "COOPEREN O SE CAE TODO", UiTheme.YELLOW, -1.0, 14)
	var text := UiTheme.label(column, "1. Carguen paquetes en los anaqueles o llévenlos en mano.\n2. Un jugador conduce; los demás vigilan la carga incluso durante la marcha.\n3. Frágil: evitá golpes. Ruidoso: calmalo. Equilibrio: mantenelo derecho. Peso creciente: movelo pronto. Líquido: no lo inclines y secá el charco. Explosivo: seguí la secuencia antes de que llegue a cero. Hostil: obedecé CALMÁ o NO TOCAR.\n4. Las buenas acciones dan mérito individual; las entregas dan dinero al equipo.\n5. Entre entregas voten mejoras. Una carta de prioridad puede cambiar el resultado.", 17, UiTheme.INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_back_button = UiTheme.button(column, "Entendido", true)
	_back_button.pressed.connect(close)

func open() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	show()
	_back_button.grab_focus.call_deferred()

func close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
