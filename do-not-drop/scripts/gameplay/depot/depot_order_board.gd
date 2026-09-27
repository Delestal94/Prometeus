class_name DepotOrderBoard
extends Node3D
## The order board: a whiteboard on a stand beside the truck, angled toward
## where the crew appears. Depot writes today's orders on it (write()) and
## ticks each house off as the run reports it (mark()).
##
## Children keep fixed names -- Title, Rule, Row0..3, Mark0..3 -- that tests
## and the HUD's depot panel look up.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const TITLE: String = "WORLD_DEPOT_BOARD_TITLE"
const RULE: String = "WORLD_DEPOT_BOARD_RULE"
const ROWS: int = 4
const BLUE_INK := Color("2a4d9b")
const RED_INK := Color("c0392b")
## What each delivery outcome writes beside its row, and in which colour.
const MARKS: Dictionary = {
	&"delivered_ok": ["WORLD_DEPOT_MARK_OK", Color("1f8a5b")],
	&"delivered_at_risk": ["WORLD_DEPOT_MARK_OK", Color("d9822b")],
	&"delivered_ruined": ["WORLD_DEPOT_MARK_RUINED", Color("c0392b")],
}
const MARK_MISSED: Array = ["WORLD_DEPOT_MARK_MISSED", Color("857a6e")]

var _title: Label3D
var _rule: Label3D
var _rows: Array[Label3D] = []
var _marks: Array[Label3D] = []


func _ready() -> void:
	position = Layout.BOARD_AT + Vector3.UP * Layout.FLOOR_TOP
	basis = Layout.board_basis()
	_build_stand()
	_build_labels()


## Writes one row per order: {"house", "code", "trap", "content"}. With no
## orders (endless, tareas de Nacho N-101: no houses) the depot stays the lobby
## it is, and the board sets the goal and the bar instead: `endless_best`.
func write(orders: Array[Dictionary], endless_best: int) -> void:
	for row: int in range(_rows.size()):
		_marks[row].text = ""
		_rows[row].text = ""
		if row < orders.size():
			var order: Dictionary = orders[row]
			_rows[row].text = tr("WORLD_DEPOT_BOARD_ORDER") % [
				int(order.house) + 1, order.code, order.trap, String(order.content).to_lower()]
	_title.text = tr(TITLE)
	_rule.text = tr(RULE)
	if orders.is_empty():
		_title.text = tr("WORLD_DEPOT_ENDLESS_TITLE")
		_rule.text = tr("WORLD_DEPOT_ENDLESS_RULE")
		_rows[0].text = tr("WORLD_DEPOT_ENDLESS_ROW")
		_rows[1].text = (tr("WORLD_DEPOT_ENDLESS_BEST") % endless_best) if endless_best > 0 \
				else tr("WORLD_DEPOT_ENDLESS_NO_BEST")


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
	kit.box(Vector3(3.3, 1.95, 0.05), Vector3(0.0, 1.85, 0.0), DepotKit.flat(Color("f4f6f2"), 0.25))
	kit.box(Vector3(3.42, 0.06, 0.08), Vector3(0.0, 2.85, 0.0), frame)
	kit.box(Vector3(3.42, 0.06, 0.08), Vector3(0.0, 0.85, 0.0), frame)
	kit.box(Vector3(3.3, 0.05, 0.12), Vector3(0.0, 0.84, 0.07), frame)  # marker tray
	for x: float in [-1.74, 1.74]:
		kit.box(Vector3(0.06, 2.05, 0.08), Vector3(x, 1.85, 0.0), frame)
		kit.box(Vector3(0.06, 0.85, 0.06), Vector3(x, 0.42, 0.0), frame)
		kit.box(Vector3(0.08, 0.04, 0.7), Vector3(x, 0.03, 0.0), frame)
	var markers: Array[Color] = [BLUE_INK, RED_INK, Color("1f8a5b")]
	for index: int in range(markers.size()):
		kit.box(Vector3(0.12, 0.02, 0.02), Vector3(-1.2 + index * 0.2, 0.88, 0.09), DepotKit.flat(markers[index], 0.5))
	kit.collider(Vector3(3.5, 2.1, 0.2), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.85, 0.0)))
	kit.commit("Board")


func _build_labels() -> void:
	_title = DepotLabels.text(self, tr(TITLE), Vector3(0.0, 2.6, 0.035), 0.0, 64, BLUE_INK,
			Layout.DISPLAY_FONT, 0.0052, 0)
	_title.name = "Title"
	var date: Dictionary = Time.get_date_dict_from_system()
	DepotLabels.text(self, "%02d/%02d" % [int(date.day), int(date.month)], Vector3(1.42, 2.72, 0.035), 0.0, 30,
			RED_INK, Layout.DISPLAY_FONT, 0.0045, 0)
	_rule = DepotLabels.text(self, tr(RULE), Vector3(0.0, 2.4, 0.035), 0.0, 26, RED_INK, Layout.BODY_FONT, 0.0045, 0)
	_rule.name = "Rule"
	for row: int in range(ROWS):
		var y: float = 2.1 - row * 0.36
		# Left-aligned from the board's left margin, whatever its length.
		var line := DepotLabels.text(self, "", Vector3(-1.42, y, 0.035), 0.0, 32, BLUE_INK, Layout.BODY_FONT, 0.0045, 0)
		line.name = "Row%d" % row
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rows.append(line)
		var mark_label := DepotLabels.text(self, "", Vector3(1.38, y, 0.035), 0.0, 40, MARK_MISSED[1],
				Layout.DISPLAY_FONT, 0.005, 0)
		mark_label.name = "Mark%d" % row
		_marks.append(mark_label)
