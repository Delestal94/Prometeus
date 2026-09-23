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

La autoridad de una trampa sigue siendo el anfitrión: un cliente puede pedir
interactuar, pero no confirmar que se desactivó. Nunca guardar progreso o
otorgar dinero desde el comportamiento de la trampa; eso pasa por
`RunManager`, `CrewProgression` y `UnlockManager` al terminar la entrega.
