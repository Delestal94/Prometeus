class_name CompanyShopScreen
extends Node
## The company's shop screen in the Company world (expansion D-0511.2): the adapter between the closing
## screen (DaySummaryPanel, whose Shop button opens it), the shop panel (CompanyShopPanel) and CompanyNet.
##
## The panel never spends. Its Buy becomes CompanyNet.request(CompanyShopNet.BUY, {item}) (D-0518: only the
## host buys; a client's ask comes back host_only and the panel says so). What the panel shows follows the
## company's own state, which the events carry to every peer: shop_bought and wallet_moved redraw the rows
## and the cash, a snapshot (company_state_restored) too, so the host and the clients see the same shop.
## The shop goes away with the closing screen (the next day opened).

var panel: CompanyShopPanel
var layer: CanvasLayer

var _net: CompanyNet
var _summary: DaySummaryPanel
## The ask in flight is rejected before request() returns on the host (the same call), hence the flag.
var _asking: bool = false
var _asked_rid: int = 0


## Builds the screen under `parent`, above `summary`, and turns the summary's Shop button on.
static func attach(parent: Node, net: CompanyNet, summary: DaySummaryPanel) -> CompanyShopScreen:
	var screen := CompanyShopScreen.new()
	screen.name = "CompanyShopScreen"
	parent.add_child(screen)
	screen.setup(net, summary)
	return screen


func setup(net: CompanyNet, summary: DaySummaryPanel) -> void:
	_net = net
	_summary = summary
	layer = CanvasLayer.new()
	layer.name = "CompanyShopLayer"
	layer.layer = 2
	add_child(layer)
	panel = CompanyShopPanel.new()
	panel.name = "CompanyShopPanel"
	layer.add_child(panel)
	panel.buy_requested.connect(_on_buy_requested)
	panel.closed.connect(_on_closed)
	summary.shop_requested.connect(open)
	summary.visibility_changed.connect(_on_summary_visibility)
	summary.set_shop_available(true)
	net.event_applied.connect(_on_event_applied)
	net.request_rejected.connect(_on_request_rejected)
	net.company_state_restored.connect(_on_state_restored)


## Opens the shop over the closing screen (the Shop button), which stops listening to ui_cancel meanwhile.
func open() -> void:
	if panel == null or panel.visible:
		return
	_summary.set_process_unhandled_input(false)
	panel.open(_context())


## What the panel draws: this peer's company (the host's, replicated) and whether it is the host.
func _context() -> Dictionary:
	return {"company": _net.company, "can_act": _net.is_host()}


func _on_buy_requested(item_id: StringName) -> void:
	_asking = true
	_asked_rid = _net.request(CompanyShopNet.BUY, {"item": item_id})
	_asking = false
	if _asked_rid == 0 and panel.visible:
		panel.reject(CompanyShopPanel.NO_LINK)


func _on_closed() -> void:
	_summary.set_process_unhandled_input(true)
	_summary.focus_default()


## The closing screen went away (the next day opened): so does the shop.
func _on_summary_visibility() -> void:
	if not _summary.visible and panel.visible:
		panel.hide()
		_summary.set_process_unhandled_input(true)


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if not panel.visible:
		return
	if kind == CompanyShopNet.BOUGHT:
		panel.note_bought(StringName(str(data.get("item", ""))))
		panel.refresh(_context())
	elif kind == CompanyNet.WALLET:
		panel.refresh(_context())


func _on_state_restored(_snapshot_seq: int) -> void:
	if panel.visible:
		panel.refresh(_context())


func _on_request_rejected(rid: int, reason: StringName) -> void:
	if panel.visible and (_asking or (rid != 0 and rid == _asked_rid)):
		panel.reject(reason)
		panel.refresh(_context())
