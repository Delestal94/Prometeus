extends SceneTree
## Run without --headless. Saves the care card (ui/hud/care_card.gd) under
## user://, in every step CareGuide can ask for -- hold (grabbed), release,
## a tool mid-job, the bomb's sequence, pieces to collect, a box within
## reach -- keyboard and one on a gamepad. Captured at the project's
## 1280x720 base size, on a mid-grey stand-in for the 3D view.

const CareCard = preload("res://scripts/ui/hud/care_card.gd")

const CARDS: Array = [
	["Frágil", 0, 96.0, {"step": &"hold", "title": "SOSTENELA", "detail": "Mantené Clic izq.: la protege de golpes y curvas."},
		{"primary": true, "sway": Vector2(0.6, 0)}, ["Q  soltar"]],
	["Hostil", 1, 51.0, {"step": &"release", "title": "¡SOLTALA!", "detail": "No toques la caja hasta que vuelva a pedir calma."},
		{"primary": true}, ["Q  al regazo"]],
	["Frágil", 1, 40.0, {"step": &"tool", "title": "USÁ: PEGAR PIEZAS", "detail": "Mantené Clic der. hasta llenar el círculo."},
		{"tool_held": true, "work": 0.62}, ["Clic der.  Pegar piezas · quedan 2", "X  otra herramienta", "Q  al estante"]],
	["Explosivo", 1, 38.0, {"step": &"sequence", "title": "TOCÁ EN ORDEN",
		"detail": "Desactivar: una tecla por vez, sin clic. Si le errás, vuelve a empezar."},
		{"sequence": {"steps": [&"up", &"left", &"down"], "index": 1}}, ["Q  soltar"]],
	["Ruidoso", 2, 0.0, {"step": &"collect", "title": "JUNTÁ LAS PIEZAS",
		"detail": "Quedan 2 en el piso: acercate a cada una y apretá E."}, {"missing": 2}, []],
	["Equilibrio", 0, 100.0, {"step": &"hold", "title": "ENDEREZALA", "detail": "Mantené RT: la protege de golpes y curvas."},
		{"pad": true, "primary": false, "sway": Vector2(-0.8, 0)}, ["LT  otra herramienta", "B  soltar"]],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var backdrop := ColorRect.new()
	backdrop.color = Color("6d7a86")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var cards: Array[CareCard] = []
	for i: int in CARDS.size():
		var card: CareCard = CareCard.new()
		card.position = Vector2(20 + (i % 3) * 420, 16 + (i / 3) * 352)
		root.add_child(card)
		cards.append(card)
	for frame: int in 40:
		for i: int in CARDS.size():
			var spec: Array = CARDS[i]
			cards[i].update(spec[0], spec[1], spec[2], spec[3], spec[4], PackedStringArray(spec[5]))
		await process_frame
		if frame in [6, 22, 39]:
			await _shot("render_care_card_%02d.png" % frame)
	backdrop.free()
	for card: CareCard in cards:
		card.free()
	quit(0)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
