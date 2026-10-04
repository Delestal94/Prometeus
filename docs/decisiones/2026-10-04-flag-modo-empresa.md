# Decisión 2026-10-04: el modo Empresa se arranca con `--autostart-company`

Tomada por la rutina `desarrollador` (carril 5) al hacer D-0119 ([reutilizacion.md](../expansion-distritos/diseno/reutilizacion.md) §3).

**Decisión:** el atajo de línea de comandos del modo Empresa es `--autostart-company` (con `--slot=<n>`
opcional), no `--autostart --mode=company` como decían D-0214 y D-2020.

**Por qué:** `scripts/ui/main_menu.gd:159` y `scripts/gameplay/level_common.gd:163` reaccionan a
`--autostart` solo: con `--autostart --mode=company` el menú arrancaría una entrega antes de leer `--mode`,
y habría que cambiar cómo se lee `--autostart` en Entrega (S1 lo prohíbe). `--autostart-endless` ya sigue
este patrón (`main_menu.gd:162`).

**Cambia:** D-0214 (arranque y test `test_company_world_boot`) y D-2020 (smoke de `release.yml`) en
`docs/expansion-distritos/detalle/`, ya corregidas en el mismo PR.
