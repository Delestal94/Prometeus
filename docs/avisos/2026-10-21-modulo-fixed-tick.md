# Aviso 2026-10-21 · módulo `fixed_tick` (D-0232)

Zona compartida tocada (`modules/`, `docs/modulos.md`), solo cosas nuevas; no cambia ninguna firma existente.

- `do-not-drop/modules/fixed_tick/` (nuevo): `FixedTick`, pasos con nombre a ritmo fijo a partir del delta del
  frame, con tope de ticks tras un tirón. `module.cfg` y `tests/test_fixed_tick.gd` propios.
- `docs/modulos.md`: una fila en "Cómo se conecta el juego" y otra en el catálogo.
- Lo usa solo el modo Empresa (`scripts/core/company/business_tick.gd`, dominio de Nacho).

Para Slatex: nada que hacer. Si algo del juego actual mira el mundo "cada tantos segundos" con un acumulador
a mano, `FixedTick` lo hace igual.
