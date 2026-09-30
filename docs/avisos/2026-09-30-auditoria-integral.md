# Aviso: auditoría integral 2026-09-30, tareas que tocan archivos de Slatex

Informe: `docs/auditorias/2026-09-30-integral.md`. Este PR solo agrega tareas en `docs/tareas-nacho.md`, sin código.

- **N-226, color estable del jugador (A-4.3).**
  - Hoy el color sale de `peer_id % 5`. Se cambia por un índice que asigna el anfitrión.
  - Cuando se implemente toca `player.gd`, `hud_results.gd` y `depot_panel.gd`, que son de Slatex.
- **N-313, N-312, N-312.4 y N-606.4 quedan ⏸ "personajes en pausa (S-311)" (A-102).**
  - Es el mismo terreno que S-311.
  - Ninguna rutina las toma hasta que se resuelva S-311.
