# D-0710.b: las trampas leen la severidad del armado

- **Qué cambió:**
  - `modules/hazards/i_trap_behavior.gd` (zona compartida, solo agrega): `var severity` (1 por defecto), que
    `on_setup` lee de la clave `severity` del config (entre `SEVERITY_MIN` 0,1 y `SEVERITY_MAX` 4). Ninguna firma
    cambia.
  - Los 7 comportamientos de `scripts/gameplay/traps/` (dominio de Slatex) multiplican por `severity` el daño que
    hacen, nunca lo que hace la respuesta correcta: Frágil (golpes, pasos), Equilibrio (daño por segundo, y
    `angle_fail_seconds` ÷ severidad), Peso creciente (crecimiento), Ruidoso (sacudida, paso, y
    `fail_seconds_at_max` ÷ severidad), Hostil (error, enojo pasivo, golpe, paso), Líquido (derrame por
    inclinación, golpe, paso) y Explosivo (mecha ÷ severidad; penalidad por error, golpe, paso). Con severidad 1
    todo es igual que antes: ningún `.tres` ni test de trampa cambia.
  - `package.gd` (Slatex): `initialize_trap()` arma el config con `PackageRescue.trap_config(self)` en vez de
    `trap_definition.params.duplicate(true)` (una línea; el archivo sigue en 700). `package_rescue.gd`: nuevos
    `TRAP_PLAN_META` (`&"trap_plan"`, el mismo `BoxToPackage.META_TRAP_PLAN`) y `trap_config(p)`, que suma la
    severidad del plan si la caja tiene uno; `complete_care_tool` lo usa al reparar.
  - `tests/sim_trap_balance.gd`: `_simulate` toma `severity` (1 por defecto) y el modo `-- --levels` compara los
    niveles (`tests/sim_data/levels_report.md`); el `"\n"` del final del reporte ya no es un salto literal.
- **Qué tiene que hacer Slatex:** nada para lo que hay. Una trampa nueva escala por `severity` su daño (golpe,
  derrame, enojo, tiempo hasta fallar) y no su respuesta; `test_box_trap_levels` la prueba sola con las otras 7
  (la deja quieta 20 s y pide que a severidad alta pierda más que a 1).
- Decisión: [2026-11-04-severidad-de-trampas.md](../decisiones/2026-11-04-severidad-de-trampas.md).
