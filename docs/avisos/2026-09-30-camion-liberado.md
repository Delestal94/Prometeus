# Aviso: `vehicle.tscn` / `vehicle.gd` ya no están congelados (2026-09-30)

Lo decidió Nacho. El congelamiento venía del aviso del 2026-09-21, que existía porque Slatex estaba
reemplazando el modelo del camión. El modelo entró el 2026-09-23 y ahí el motivo se terminó, pero los
avisos de M6 (PR #14 en adelante) siguieron repitiendo "siguen congelados" sin que nadie lo volviera a
decidir.

- `vehicle.tscn` y `vehicle.gd` vuelven a ser archivos normales del dominio de Nacho: se editan sin
  acuerdo previo ni aviso (salvo que el cambio toque la zona compartida o archivos de Slatex).
- Criterio que queda en `constructor-camion`: lo que es del vehículo en sí (manejo, física,
  sincronización de su pose) va en `vehicle.gd`; un sistema con reglas propias (como `VehicleFaults`)
  sigue siendo un componente aparte.
- Se sacó la regla de `CLAUDE.md`, del README de rutinas, de `cerrar-cambio` y de los agentes.
  `guardian-dominios` ya no reporta "⛔ Congelado".
- N-218 (predicción del camión) y N-114 (caja manual) quedan como tareas normales, sin "acuerdo previo".
- Slatex: si querés cambiar algo del camión, es como tocar cualquier archivo de Nacho (con aviso).
