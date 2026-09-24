---
name: nuevo-test
description: Cómo escribir un test headless nuevo para Take My Package (do-not-drop/tests/test_*.gd) con las convenciones del proyecto. Usala al agregar o ampliar un test, o cuando una mecánica nueva o un bug arreglado necesita cobertura.
---

# Escribir un test headless

Los tests son scripts `extends SceneTree` que corren con
`godot --headless --path do-not-drop --script res://tests/test_<tema>.gd` y salen
con la cantidad de fallas como código de salida. `tools/run-tests.sh` toma todo
`tests/test_*.gd` automáticamente.

## Antes de escribir

- ¿Ya hay un test del tema? (`ls do-not-drop/tests/test_*`). Si lo hay,
  ampliá ese en vez de crear otro.
- Mirá un test parecido como modelo: `test_depot.gd` (nivel completo),
  `test_traps.gd` o `test_fragile.gd` (una mecánica), `test_settings.gd`
  (datos/guardado).

## Plantilla

```gdscript
extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_<tema>.gd
##
## <Qué comportamiento garantiza este test, en viñetas cortas, nombrando el
## script de juego que lo implementa (archivo.gd).>

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame

	_expect(<condición>, "<qué se esperaba, con el valor real> (got %s)" % <valor>)

	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: <resumen de una línea>")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
```

## Reglas

- Solo `push_error` para las fallas (el runner muestra las líneas `ERROR:`) y un
  único `print("PASS: ...")` al final si no hubo fallas.
- La descripción de cada `_expect` dice lo que **debería** pasar, en inglés, e
  incluye el valor observado: `"Door closes behind the truck (got %s)" % state`.
- Los autoloads se usan por nodo: `root.get_node(^"/root/EventBus")`,
  `root.get_node(^"/root/RunManager")`. Si el test cambia estado global
  (campaña, desbloqueos, run), restauralo al final (`reset_run`,
  `reset_campaign`), como `test_depot.gd`.
- Nada de depender del orden de otros tests ni de lo que haya en `user://`: cada
  test corre con su propio `user://`, pero el perfil arranca vacío.
- Para esperar física, contá `physics_frame`s; no uses timers largos. Un test
  debería durar segundos: el runner corta a los 120 s en CI.
- Si el test necesita pantalla (render, input real), imprimí un mensaje que
  contenga `needs a display` y salí con código distinto de 0 cuando corre
  headless: el runner lo marca como SKIP.
- Los tests de captura (`render_*.gd`) y chequeos visuales (`check_*.gd`) no son
  tests de la batería: los corre el agente `revisor-visual`.

## Después

- Anotá el test en la lista de "Tests" del `README.md`.
- Corrélo con el agente `ejecutor-tests` y el filtro por su nombre.
- Si el hook de chequeo de GDScript marca un error al guardar, arreglalo antes de
  correr la batería.
