extends SceneTree
## Lo usa check-gdscript.sh: carga el script que se le pasa después de "--"
## con el proyecto completo (autoloads incluidos, así EventBus, NetworkManager…
## resuelven) y sale con 1 si no compila. Los errores los imprime Godot.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var script: Script = load(args[0]) if args.size() > 0 else null
	quit(0 if script != null and script.can_instantiate() else 1)
