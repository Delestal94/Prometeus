# S-311.24 — equidad visual e IK del vehículo

Slatex cerró S-311.24 manteniendo las proporciones del cuerpo como una capa exclusivamente visual:
la cápsula de colisión, la cámara y el alcance de interacción no cambian. El rig de gelatina planta el
pie más bajo sobre el piso y reutiliza la IK existente para llevar ambas manos a la caja real.

No se modificaron archivos del vehículo, el volante ni los pedales. Cuando el personaje de gelatina se
conecte al puesto de conductor, el ajuste de manos al volante y pies a los pedales sigue en el dominio de
Nacho y debe conservar la misma regla: mover solamente huesos/objetivos visuales, nunca la física, la
cámara ni el alcance del jugador.

Archivos y prueba de referencia:

- `do-not-drop/scripts/gameplay/player/gel/gel_foot_grounding.gd`
- `do-not-drop/scripts/gameplay/player/carry_pose.gd`
- `do-not-drop/tests/test_gel_fairness.gd`
- `do-not-drop/tests/test_driver_ik.gd`
