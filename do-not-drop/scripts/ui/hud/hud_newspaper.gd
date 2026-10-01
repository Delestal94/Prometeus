class_name HudNewspaper
extends Node
## The next-day newspaper between the end of the run and the results card
## (N-606.2). The host relays newspaper_ready just before run_ended, so by the
## time the results come up the paper is already here; HudResults asks
## present() first and shows the card when the player closes the page. Without
## a paper (a joiner who arrived late, a host that sent none, one that can't
## be read) present() says no and the card comes up as always.
##
## It listens and draws; what the paper says is the host's call.

const PAGE = preload("res://scripts/presentation/newspaper/newspaper_page.gd")

## Set by Hud before this is added as its child.
var hud: Hud
var page: Control
var _paper: Dictionary = {}
var _then: Callable = Callable()


func _ready() -> void:
	EventBus.newspaper_ready.connect(func(paper: Dictionary) -> void: _paper = paper)
	EventBus.run_started.connect(func(_route: StringName, _players: Array) -> void: _paper = {})


func is_open() -> bool:
	return page != null and is_instance_valid(page)


## Shows the page waiting for this run, if any. `then` runs once the player
## closes it. False when there is nothing to show (the caller goes on).
func present(then: Callable) -> bool:
	if _paper.is_empty() or is_open():
		return false
	var candidate: Control = PAGE.new()
	hud.root.add_child(candidate)
	var readable: bool = candidate.call(&"show_paper", _paper)
	_paper = {}
	if not readable:
		candidate.queue_free()
		return false
	page = candidate
	_then = then
	hud.overlay_mode = "newspaper"
	hud.hud_layer.hide()
	candidate.connect(&"finished", _on_finished)
	return true


## Closes the page as if the player had (the connection was lost under it).
func dismiss() -> void:
	if is_open():
		page.call(&"close")


func _on_finished() -> void:
	if is_open():
		page.queue_free()
	page = null
	var then: Callable = _then
	_then = Callable()
	if then.is_valid():
		then.call()
