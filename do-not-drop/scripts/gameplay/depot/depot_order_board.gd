class_name DepotOrderBoard
extends Node3D
## The order board: the control island's big whiteboard on a frame with its
## own strip light (N-319), left of the truck and angled toward where the crew
## appears, so the orders read from the spawn. Depot writes today's orders on
## it (write()) and ticks each house off as the run reports it (mark()).
##
## Children keep fixed names -- Title, Rule, Row0..6, Mark0..6, Boss0, Boss1 --
## that tests and the HUD's depot panel look up. Boss0/Boss1 are the Boss's
## note under the orders (S-603): what she said over the radio this morning
## and, when there is one, her reaction to the last run.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const TITLE: String = "WORLD_DEPOT_BOARD_TITLE"
const RULE: String = "WORLD_DEPOT_BOARD_RULE"
## One row per house for the biggest crew (NetworkManager.MAX_PLAYERS - 1).
const ROWS: int = 7
## The panel: its width, its height and the height of its centre.
const PANEL_WIDTH: float = 4.4
const PANEL_HEIGHT: float = 2.7
const PANEL_CENTRE: float = 2.2
## Text sizes: one metre of board in pixels of each kind of writing.
const PIXEL: float = 0.0062
## The writing area under the rule, down to the marker tray, and its width.
const ROWS_TOP: float = 2.8
const ROWS_BOTTOM: float = 1.75
## The Boss's note under the orders: where its two lines start, how far apart
## they are, and their size.
const NOTE_TOP: float = 1.68
const NOTE_PITCH: float = 0.175
const NOTE_FONT: int = 26
const NOTE_INK := Color("1c6b47")
const NOTE_KEY: String = "WORLD_BOSS_NOTE"
const TEXT_WIDTH: float = 3.9
const ROW_FONT: int = 32
## Up to this many orders each takes two lines (house and shelf, then the
## box); more go one line each, smaller, so all of them fit.
const TWO_LINE_ROWS: int = 4
const BLUE_INK := Color("2a4d9b")
const RED_INK := Color("c0392b")
## What each delivery outcome writes beside its row, and in which colour.
const MARKS: Dictionary = {
	&"delivered_ok": ["WORLD_DEPOT_MARK_OK", Color("1f8a5b")],
	&"delivered_at_risk": ["WORLD_DEPOT_MARK_OK", Color("d9822b")],
	&"delivered_ruined": ["WORLD_DEPOT_MARK_RUINED", Color("c0392b")],
	&"lost": ["WORLD_DEPOT_MARK_LOST", Color("c0392b")],
}
const MARK_MISSED: Array = ["WORLD_DEPOT_MARK_MISSED", Color("857a6e")]

var _title: Label3D
var _rule: Label3D
var _rows: Array[Label3D] = []
var _marks: Array[Label3D] = []
var _notes: Array[Label3D] = []


func _ready() -> void:
	position = Layout.BOARD_AT + Vector3.UP * Layout.FLOOR_TOP
	basis = Layout.board_basis()
	_build_stand()
	_build_labels()


## Writes one row per order: {"house", "code", "trap", "content"}. With no
## orders (endless, tareas de Nacho N-101: no houses) the depot stays the lobby
## it is, and the board sets the goal and the bar instead: `endless_best`.
func write(orders: Array[Dictionary], endless_best: int) -> void:
	var count: int = mini(orders.size(), _rows.size())
	var two_lines: bool = count <= TWO_LINE_ROWS
	var pitch: float = (ROWS_TOP - ROWS_BOTTOM) / float(maxi(count, 2 if two_lines else 1))
	for row: int in range(_rows.size()):
		var line: Label3D = _rows[row]
		line.position.y = ROWS_TOP - row * pitch
		_marks[row].position.y = line.position.y
		line.font_size = ROW_FONT
		_marks[row].text = ""
		line.text = ""
		if row < count:
			var order: Dictionary = orders[row]
			var key: String = "WORLD_DEPOT_BOARD_ORDER" if two_lines else "WORLD_DEPOT_BOARD_ORDER_SHORT"
			line.text = tr(key) % [int(order.house) + 1, order.code, order.trap, String(order.content).to_lower()]
			# Never taller than its share of the board, never wider than it.
			var tall: float = Layout.BODY_FONT.get_height(ROW_FONT) * (2 if two_lines else 1) * line.pixel_size
			if tall > pitch * 0.92:
				line.font_size = maxi(int(ROW_FONT * pitch * 0.92 / tall), 10)
			DepotLabels.fit_label(line, TEXT_WIDTH - 0.25)
	_title.text = tr(TITLE)
	_rule.text = tr(RULE)
	if orders.is_empty():
		_title.text = tr("WORLD_DEPOT_ENDLESS_TITLE")
		_rule.text = tr("WORLD_DEPOT_ENDLESS_RULE")
		_rows[0].text = tr("WORLD_DEPOT_ENDLESS_ROW")
		_rows[1].text = (tr("WORLD_DEPOT_ENDLESS_BEST") % endless_best) if endless_best > 0 \
				else tr("WORLD_DEPOT_ENDLESS_NO_BEST")
		DepotLabels.fit_label(_rows[0], TEXT_WIDTH - 0.25)
		DepotLabels.fit_label(_rows[1], TEXT_WIDTH - 0.25)
	DepotLabels.fit_label(_title, TEXT_WIDTH - 1.0)
	DepotLabels.fit_label(_rule, TEXT_WIDTH)


## Writes the Boss's note: up to two already translated lines (the day's
## start line, then her reaction to the last run). Fewer clears the rest.
func say(lines: Array[String]) -> void:
	for index: int in range(_notes.size()):
		var note: Label3D = _notes[index]
		note.font_size = NOTE_FONT
		note.text = ""
		if index < lines.size():
			note.text = (tr(NOTE_KEY) % lines[index]) if index == 0 else lines[index]
			DepotLabels.fit_label(note, TEXT_WIDTH - 0.2)


## Ticks a house's row with how its delivery went.
func mark(house_index: int, outcome: StringName) -> void:
	if house_index < 0 or house_index >= _marks.size():
		return
	var entry: Array = MARKS.get(outcome, MARK_MISSED)
	_marks[house_index].text = tr(entry[0])
	_marks[house_index].modulate = entry[1]


func _build_stand() -> void:
	var kit := DepotKit.new(self, "BoardColliders")
	var frame := DepotKit.flat(Color("59656a"), 0.4, 0.6)
	var dark := DepotKit.flat(Color("263238"), 0.5, 0.3)
	var top: float = PANEL_CENTRE + PANEL_HEIGHT * 0.5
	var bottom: float = PANEL_CENTRE - PANEL_HEIGHT * 0.5
	var posts: float = PANEL_WIDTH * 0.5 + 0.06
	kit.box(Vector3(PANEL_WIDTH, PANEL_HEIGHT, 0.05), Vector3(0.0, PANEL_CENTRE, 0.0), DepotKit.flat(Color("f4f6f2"),
			0.25))
	kit.box(Vector3(PANEL_WIDTH + 0.12, 0.06, 0.08), Vector3(0.0, top + 0.03, 0.0), frame)
	kit.box(Vector3(PANEL_WIDTH + 0.12, 0.06, 0.08), Vector3(0.0, bottom - 0.03, 0.0), frame)
	kit.box(Vector3(PANEL_WIDTH, 0.05, 0.12), Vector3(0.0, bottom - 0.04, 0.07), frame)  # marker tray
	for x: float in [-posts, posts]:
		kit.box(Vector3(0.06, top + 0.12, 0.08), Vector3(x, (top + 0.12) * 0.5, 0.0), frame)
		kit.box(Vector3(0.08, 0.04, 0.9), Vector3(x, 0.03, 0.0), frame)
		kit.box(Vector3(0.05, 0.05, 0.3), Vector3(x * 0.92, top + 0.1, 0.15), frame)  # arm of the light
	# The strip light over the top edge: its housing, and the glowing tube under it.
	kit.box(Vector3(PANEL_WIDTH, 0.1, 0.24), Vector3(0.0, top + 0.16, 0.3), dark)
	kit.box(Vector3(PANEL_WIDTH - 0.2, 0.02, 0.12), Vector3(0.0, top + 0.1, 0.3), DepotKit.glow(Color("fff1d6"), 2.9))
	var markers: Array[Color] = [BLUE_INK, RED_INK, Color("1f8a5b")]
	for index: int in range(markers.size()):
		kit.box(Vector3(0.12, 0.02, 0.02), Vector3(-1.6 + index * 0.2, bottom - 0.01, 0.09),
				DepotKit.flat(markers[index], 0.5))
	# A rule between the orders and the Boss's note.
	kit.box(Vector3(PANEL_WIDTH - 0.5, 0.012, 0.01), Vector3(0.0, ROWS_BOTTOM + 0.02, 0.03), DepotKit.flat(RED_INK,
			0.5))
	kit.collider(Vector3(PANEL_WIDTH + 0.3, top + 0.2, 0.25), Transform3D(Basis.IDENTITY, Vector3(0.0,
			(top + 0.2) * 0.5, 0.0)))
	kit.commit("Board")


func _build_labels() -> void:
	var left: float = -PANEL_WIDTH * 0.5 + 0.2
	var right: float = PANEL_WIDTH * 0.5 - 0.22
	_title = DepotLabels.text(self, tr(TITLE), Vector3(0.0, PANEL_CENTRE + 1.16, 0.035), 0.0, 64, BLUE_INK,
			Layout.DISPLAY_FONT, 0.0075, 0)
	_title.name = "Title"
	var date: Dictionary = Time.get_date_dict_from_system()
	DepotLabels.text(self, "%02d/%02d" % [int(date.day), int(date.month)], Vector3(right - 0.05, PANEL_CENTRE + 1.24,
			0.035),
			0.0, 30, RED_INK, Layout.DISPLAY_FONT, 0.0062, 0)
	_rule = DepotLabels.text(self, tr(RULE), Vector3(0.0, PANEL_CENTRE + 0.84, 0.035), 0.0, 26, RED_INK,
			Layout.BODY_FONT, PIXEL, 0)
	_rule.name = "Rule"
	# write() spaces the rows to fit however many orders there are.
	for row: int in range(ROWS):
		# Left-aligned from the board's left margin, whatever its length.
		var line := DepotLabels.text(self, "", Vector3(left, ROWS_TOP, 0.035), 0.0, ROW_FONT, BLUE_INK,
				Layout.body_bold(), PIXEL, 0)
		line.name = "Row%d" % row
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		line.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_rows.append(line)
		var mark_label := DepotLabels.text(self, "", Vector3(right, ROWS_TOP, 0.035), 0.0, 40, MARK_MISSED[1],
				Layout.DISPLAY_FONT, 0.0068, 0)
		mark_label.name = "Mark%d" % row
		mark_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_marks.append(mark_label)
	# The Boss's note: dark green ink, so it reads as hers and not the crew's.
	for index: int in range(2):
		var note := DepotLabels.text(self, "", Vector3(left, NOTE_TOP - index * NOTE_PITCH, 0.035), 0.0, NOTE_FONT,
				NOTE_INK, Layout.BODY_FONT, PIXEL, 0)
		note.name = "Boss%d" % index
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_notes.append(note)
