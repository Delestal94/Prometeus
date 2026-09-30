# Frágil: el toque amortigua un poco menos (N-229)

`do-not-drop/data/traps/fragile.tres` (dominio de Slatex):

- `cushion_leak` 0,1 → 0,15: un toque bueno ahora deja pasar el 15 % del golpe (un bache pesado de 35 quita
  5,25 en vez de 3,5). El código (`fragile_trap_behavior.gd`) no cambió; su valor por defecto sigue en 0,1.

Por qué: la decisión del 2026-09-30 (pregunta 9 de `docs/decisiones/2026-09-30-preguntas-auditoria.md`) mantiene
el objetivo de al menos una casi pérdida por viaje del jugador torpe, y el informe de `tests/sim_trap_balance.gd`
daba 0,73. En Frágil el torpe que falla dos de los tres baches y amortigua el tercero quedaba en 26,5 de
integridad, a 1,5 del borde de casi pérdida (25): su casi pérdida era 0,8 %. Con 0,15 queda en 24,75 y pasa a
37,2 %; el viaje torpe llega a 1,10 y el informe dice CUMPLE. Ningún perfil pierde más cajas en ninguna trampa
(solo cambió Frágil, y un toque bueno sigue salvando el 85 % del golpe).

Tests: `test_fragile_cushion.gd` espera 5,25 por golpe amortiguado (antes 3,5) y `test_fragile.gd` fija el borde
con los datos del `.tres` (dos fallos y un toque terminan entre 5 y 25; tres toques dejan la caja bien).
