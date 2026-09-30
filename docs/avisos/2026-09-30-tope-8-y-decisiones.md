# Aviso: tope de 8 jugadores, pago del equipo y rutinas sin borrado de ramas

- **Tope de 8 jugadores** (decisión del usuario): ya era `NetworkManager.MAX_PLAYERS = 8`; se corrigieron
  `definicion-proyecto.md`, `requerimientos-tecnicos.md` y los prompts de los agentes. N-228 barre el resto
  y verifica que jugador, asientos y HUD aguanten 8.
- **Pago del equipo**: la billetera es compartida y cobra puntos de puerta + carga a bordo; el bono de
  tiempo se va. Lo implementa N-227.2 (toca `run_manager.gd` y el desglose de resultados del HUD).
- Las 9 respuestas están en `docs/decisiones/2026-09-30-preguntas-auditoria.md`.
- Las rutinas ya no borran ramas: una reserva abandonada se retoma sobre la misma rama (regla 15 de
  `.claude/rutinas/README.md`). QA corre dos veces por día.
