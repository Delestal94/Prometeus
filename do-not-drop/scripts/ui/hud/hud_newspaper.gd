class_name HudNewspaper
extends Node
## The next-day newspaper between the end of the run and the results card
## (N-606.2, N-606.3). The host relays newspaper_ready just before run_ended,
## so by the time the results come up the paper is already here; HudResults
## asks present() first and shows the card on `newspaper_finished` (the
## callable it passes). The paper is a scene (NewspaperDirector: the Boss
## reads it in his office, ~30 s, held button to skip) that each player sees
## and skips on their own. Without a paper (a joiner who arrived late, a host
## that sent none, one that can't be read), or with the option saying not to
## show this one, present() says no and the card comes up as always.
##
## It listens and draws; what the paper says is the host's call.

## The scene is over (watched to the end or skipped): the results come next.
signal newspaper_finished

const DIRECTOR = preload("res://scripts/presentation/newspaper/newspaper_director.gd")

## Set by Hud before this is added as its child.
var hud: Hud
var director: Control
var _paper: Dictionary = {}
var _then: Callable = Callable()
var _world_3d_was_disabled: bool = false


func _ready() -> void:
	EventBus.newspaper_ready.connect(func(paper: Dictionary) -> void: _paper = paper)
	EventBus.run_started.connect(func(_route: StringName, _players: Array) -> void: _paper = {})


## The scene must not outlive the HUD with the 3D world switched off: the root
## viewport is the game's, and the next run (the host restarting under a client
## still reading) would be drawn without a world (N-921.1).
func _exit_tree() -> void:
	if is_open() and hud != null and is_instance_valid(hud) and hud.get_viewport() != null:
		hud.get_viewport().disable_3d = _world_3d_was_disabled


func is_open() -> bool:
	return director != null and is_instance_valid(director)


## Whether the option (Opciones > Diario al final) lets this paper show.
static func wanted(paper: Dictionary, mode: int) -> bool:
	match mode:
		GameSettings.NewspaperMode.NEVER:
			return false
		GameSettings.NewspaperMode.NEWS_ONLY:
			return String((paper.get("front", {}) as Dictionary).get("id", "")) != "clean_run"
	return true


## Plays the paper waiting for this run, if any. `then` runs once the scene
## is over. False when there is nothing to show (the caller goes on).
func present(then: Callable) -> bool:
	if _paper.is_empty() or is_open():
		return false
	var paper: Dictionary = _paper
	_paper = {}
	if not wanted(paper, GameSettings.newspaper_mode):
		return false
	var candidate: Control = DIRECTOR.new()
	hud.root.add_child(candidate)
	if not bool(candidate.call(&"play", paper)):
		candidate.queue_free()
		return false
	director = candidate
	_then = then
	hud.overlay_mode = "newspaper"
	hud.hud_layer.hide()
	# The run's world is behind an opaque scene: don't draw it meanwhile.
	var screen: Viewport = hud.get_viewport()
	_world_3d_was_disabled = screen.disable_3d
	screen.disable_3d = true
	candidate.connect(&"finished", _on_finished)
	return true


## Ends the scene as if the player had skipped it (the connection was lost under it).
func dismiss() -> void:
	if is_open():
		director.call(&"finish")


func _on_finished() -> void:
	if is_open():
		director.queue_free()
		hud.get_viewport().disable_3d = _world_3d_was_disabled
	director = null
	var then: Callable = _then
	_then = Callable()
	newspaper_finished.emit()
	if then.is_valid():
		then.call()
