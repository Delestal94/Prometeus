class_name ShedEventFeed
extends Control
## The shed's event feed (expansion D-1935): a short column of lines on the right of the screen saying who
## did what in the company ("Ana puso 3 Gallina en una caja", "Llegó el pedido d1_o04"). It reads the
## business events every peer applies (CompanyNet.event_applied), so the host and every client show the same
## lines, and draws nothing else: no RPC, no state.
##
## - Who: the peer the event names (`peer`, as supplier_ordered has it) or whose hands the units left
##   (`from: hands:<peer>`); the name is that player's nickname (PlayerNickname), "Alguien" when unknown.
##   Events that do not name anybody (a box labeled or sealed) say what happened without a who.
## - The same thing done again by the same player right after (units into the same box, one by one) adds up
##   on its line instead of filling the feed.
## - At most MAX_LINES lines, newest at the bottom; each one fades out after LINE_SECONDS.

## Lines shown at once; the oldest goes first.
const MAX_LINES: int = 5
## How long a line stays, and the last part of it, in which it fades out.
const LINE_SECONDS: float = 12.0
const FADE_SECONDS: float = 2.0
const FEED_WIDTH: float = 360.0

const KEY_ORDER_ADDED: String = "UI_FEED_ORDER_ADDED"
const KEY_ORDER_EXPIRED: String = "UI_FEED_ORDER_EXPIRED"
const KEY_BOX_PLACED: String = "UI_FEED_BOX_PLACED"
const KEY_BOX_LABELED: String = "UI_FEED_BOX_LABELED"
const KEY_BOX_SEALED: String = "UI_FEED_BOX_SEALED"
const KEY_BOX_SEALED_BLANK: String = "UI_FEED_BOX_SEALED_BLANK"
const KEY_SUPPLIER: String = "UI_FEED_SUPPLIER_ORDERED"
const KEY_SPOILED: String = "UI_FEED_SPOILED"
const KEY_TRUCK_LEFT: String = "UI_FEED_TRUCK_LEFT"
const KEY_SOMEONE: String = "UI_FEED_SOMEONE"

## The player's nickname for a peer id ("" when unknown). Set by add_to(); a test sets its own.
var name_of: Callable = func(_peer: int) -> String: return ""

## Each shown line: {kind, actor, subject, qty, text, age}.
var _lines: Array[Dictionary] = []
var _column: VBoxContainer


## The feed on its own layer under `root` (CompanyRoot), following root.net's events, the players' names read
## from root's World/Player_<peer>.
static func add_to(root: Node) -> ShedEventFeed:
	var layer := CanvasLayer.new()
	layer.name = "ShedEventFeedLayer"
	root.add_child(layer)
	var feed := ShedEventFeed.new()
	feed.name = "ShedEventFeed"
	layer.add_child(feed)
	feed.name_of = func(peer: int) -> String:
		return PlayerNickname.of(root.get_node_or_null(NodePath("World/%s%d" % [CompanyRoot.PLAYER_PREFIX, peer])))
	var net: Object = root.get(&"net")
	if net != null and net.has_signal(&"event_applied"):
		net.connect(&"event_applied", feed.on_event)
	return feed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -FEED_WIDTH - 24.0
	offset_right = -24.0
	offset_top = 140.0
	_column = VBoxContainer.new()
	_column.name = "Lines"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.custom_minimum_size = Vector2(FEED_WIDTH, 0)
	_column.add_theme_constant_override("separation", 4)
	add_child(_column)
	_redraw()


func _process(delta: float) -> void:
	if not _lines.is_empty():
		advance(delta)


## A business event applied on this peer (CompanyNet.event_applied): a line when it is one the feed tells.
func on_event(_seq: int, kind: StringName, data: Dictionary) -> void:
	var line: Dictionary = line_for(kind, data)
	if line.is_empty():
		return
	var last: Dictionary = _lines.back() if not _lines.is_empty() else {}
	if not last.is_empty() and kind == CompanyTableNet.PLACED and last["kind"] == kind \
			and last["actor"] == line["actor"] and last["subject"] == line["subject"]:
		last["qty"] = int(last["qty"]) + int(line["qty"])
		last["age"] = 0.0
	else:
		_lines.append(line)
		while _lines.size() > MAX_LINES:
			_lines.pop_front()
	_redraw()


## Ages the lines by `seconds`: the ones past LINE_SECONDS go. Public so a test can run it without frames.
func advance(seconds: float) -> void:
	for line: Dictionary in _lines:
		line["age"] = float(line["age"]) + seconds
	var before: int = _lines.size()
	var kept: Array[Dictionary] = []
	for line: Dictionary in _lines:
		if float(line["age"]) < LINE_SECONDS:
			kept.append(line)
	_lines = kept
	if _lines.size() != before:
		_redraw()
	else:
		_fade()


## The text of every line shown, oldest first.
func texts() -> Array[String]:
	var result: Array[String] = []
	for line: Dictionary in _lines:
		result.append(text_of(line))
	return result


## {kind, actor, subject, qty, age} for an event the feed tells, {} for any other or a malformed one.
## `actor` is a peer id (0: nobody named).
func line_for(kind: StringName, data: Dictionary) -> Dictionary:
	var subject: String = ""
	var qty: int = 0
	match kind:
		CompanyOrdersNet.ADDED:
			var order: Variant = data.get("order")
			subject = str((order as Dictionary).get("id", "")) if order is Dictionary else ""
		CompanyOrdersNet.EXPIRED, CompanyTableNet.LABELED, CompanyTableNet.SEALED:
			subject = str(data.get("order", ""))
		CompanyTableNet.PLACED:
			subject = str(data.get("product", ""))
			qty = 1
		CompanyColdNet.SPOILED:
			subject = str(data.get("product", ""))
			qty = int(data.get("qty", 0))
		CompanySupplierNet.ORDERED:
			for entry: Variant in data.get("lines", []):
				qty += int((entry as Dictionary).get("qty", 0)) if entry is Dictionary else 0
		CompanyPallets.DEPARTED:
			pass
		_:
			return {}
	var needs_subject: bool = kind in [CompanyOrdersNet.ADDED, CompanyOrdersNet.EXPIRED, CompanyTableNet.LABELED,
		CompanyTableNet.PLACED, CompanyColdNet.SPOILED]
	if (needs_subject and subject == "") or ((kind == CompanyColdNet.SPOILED or kind == CompanySupplierNet.ORDERED)
			and qty <= 0):
		return {}
	return {"kind": kind, "actor": actor_of(data), "subject": subject, "qty": qty, "age": 0.0}


## The peer an event names: its `peer`, else the hands its units came `from`; 0 when none.
static func actor_of(data: Dictionary) -> int:
	var peer: Variant = data.get("peer")
	if typeof(peer) == TYPE_INT and int(peer) > 0:
		return int(peer)
	var from: String = str(data.get("from", ""))
	if from.begins_with(CompanyNet.HANDS_PREFIX):
		var id: String = from.trim_prefix(CompanyNet.HANDS_PREFIX)
		return int(id) if id.is_valid_int() and int(id) > 0 else 0
	return 0


## The line as read in the current language.
func text_of(line: Dictionary) -> String:
	var subject: String = str(line.get("subject", ""))
	var qty: int = int(line.get("qty", 0))
	var product: String = PickingCartPoint.product_name(StringName(subject)) if subject != "" else ""
	var text: String = ""
	match StringName(line.get("kind", &"")):
		CompanyOrdersNet.ADDED:
			text = tr(KEY_ORDER_ADDED) % subject
		CompanyOrdersNet.EXPIRED:
			text = tr(KEY_ORDER_EXPIRED) % subject
		CompanyTableNet.PLACED:
			text = tr(KEY_BOX_PLACED) % [_who(line), qty, product]
		CompanyTableNet.LABELED:
			text = tr(KEY_BOX_LABELED) % subject
		CompanyTableNet.SEALED:
			text = tr(KEY_BOX_SEALED) % subject if subject != "" else tr(KEY_BOX_SEALED_BLANK)
		CompanyColdNet.SPOILED:
			text = tr(KEY_SPOILED) % [qty, product]
		CompanySupplierNet.ORDERED:
			text = tr(KEY_SUPPLIER) % [_who(line), qty]
		CompanyPallets.DEPARTED:
			text = tr(KEY_TRUCK_LEFT)
	return text


func _who(line: Dictionary) -> String:
	var peer: int = int(line.get("actor", 0))
	var shown: String = name_of.call(peer) if peer > 0 and name_of.is_valid() else ""
	return shown if shown != "" else tr(KEY_SOMEONE)


func _redraw() -> void:
	if _column == null:
		return
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	for i: int in _lines.size():
		var label: Label = UiTheme.label(_column, text_of(_lines[i]), 16, UiTheme.INK)
		label.name = "Line_%d" % i
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override(&"font_outline_color", UiTheme.BACKDROP)
		label.add_theme_constant_override(&"outline_size", 6)
	_fade()


func _fade() -> void:
	if _column == null:
		return
	for i: int in mini(_lines.size(), _column.get_child_count()):
		var left: float = LINE_SECONDS - float(_lines[i]["age"])
		(_column.get_child(i) as CanvasItem).modulate.a = clampf(left / FADE_SECONDS, 0.0, 1.0)
