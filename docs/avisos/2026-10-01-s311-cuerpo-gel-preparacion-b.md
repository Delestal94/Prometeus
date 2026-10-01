# S-311 — preparación aislada del cuerpo de gel

Se agregan el generador y las validaciones en `art/gel_character/`, tres modelos
en `do-not-drop/assets/models/characters/gel/` y un test/capturador aislados en
`do-not-drop/tests/`. El validador genérico mantiene su firma; el nuevo modo
`--gel-body` comprueba el contrato específico. El rig nuevo tiene veinte huesos,
incluidos `grip.L/R` y `thumb.L/R`, y conserva los nueve clips actuales mediante
retarget hacia reposos nuevos; no reutiliza sus posiciones anteriores literalmente.
Incluye `Run` tras sincronizar el cambio N-115 del otro desarrollador.

No se modifica el jugador activo, la personalización, IK del camión, red ni
colisiones. El master `personaje_redondeado.blend` queda intacto. Estos modelos
no están aprobados como reemplazo por defecto: falta la integración C y material
D/comparación E. Núcleo, corrección de grosor y distorsión UV permanecen pendientes;
el núcleo experimental no cumple el presupuesto y no se activa.

Hacer pull antes de continuar cualquier bloque o tocar el PR. No iniciar trabajo
automático sobre la lista de Slatex; S-311 sigue siendo su tarea reservada.
