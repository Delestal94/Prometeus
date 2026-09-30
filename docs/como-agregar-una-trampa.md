# Cómo agregar una trampa

Cada trampa nueva tiene cuatro partes: reglas, datos, lectura visual y una
entrada en los niveles. Mantenerlas separadas permite ajustar dificultad sin
rehacer el paquete ni el HUD.

1. Crear `scripts/gameplay/traps/<id>_trap_behavior.gd`, extender
   `ITrapBehavior` y declarar sus parámetros exportados. La trampa recibe el
   estado físico de la caja y el input del jugador, y solo devuelve/cambia el
   estado de riesgo; no debe crear UI ni decidir puntaje.
2. Crear `data/traps/<id>.tres`, asignar el script anterior y dejar allí los
   valores balanceables. Añadir el recurso al catálogo de `level_base.tscn` y
   `level_endless.tscn` respetando los desbloqueos de `UnlockManager`.
3. Añadir en `package_feedback.gd` una señal visual clara y un sonido en
   `SynthAudio`: deben diferenciarse aun sin leer texto. Los casos existentes
   son Líquido (charco/chapoteo), Explosivo (contador/tictac) y Hostil
   (ojos/siseo).
4. Escribir `tests/test_<id>_trap.gd` para la regla y
   `tests/test_<id>_visual.gd` para la representación. El test debe cubrir un
   input correcto, uno incorrecto y la condición de pérdida.
5. Ejecutar la regresión: `test_interaction`, `test_multi_cargo`,
   `test_trap_visual_feedback`, `test_trap_audio` y
   `test_interaction_highlight`.

El contexto que el paquete le pasa a `on_physics_process` (N-117) trae, además de `input`
(`steady`, `calm`, `direction_pressed` y `tap`, los dos últimos son flancos: valen un solo
tick, el paquete los gasta después de cada uno), `code_reader` (`&"driver"` u `&"owner"`: quién
lee lo que la trampa sortea) e `impact_ahead` (segundos al próximo bache que el camino anuncia,
`INF` si no hay; solo si la trampa dice `wants_road_ahead()`). Una trampa sin protección por
mantener aprieta lo contrario con `hold_protects()` (Frágil: `false`), publica su estado de
toque con `cushion_state()` y convierte un bache tomado rápido en golpe con `road_jolt_strength()`.
Lo que la trampa sortea sale de `config["roll_seed"]` (la semilla de sesión y el id de la caja;
`0` sin sesión: el reloj). Nunca poner en `get_hint()` lo que un solo jugador debe ver.

La autoridad de una trampa sigue siendo el anfitrión: un cliente puede pedir
interactuar, pero no confirmar que se desactivó. Nunca guardar progreso o
otorgar dinero desde el comportamiento de la trampa; eso pasa por
`RunManager`, `CrewProgression` y `UnlockManager` al terminar la entrega.
