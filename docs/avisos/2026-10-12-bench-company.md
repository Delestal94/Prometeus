# Aviso: paso nuevo de CI `bench_company` (D-2011, 2026-10-12)

Lo hizo Nacho (rutina `desarrollador`, carril 5).

- `.github/workflows/tests.yml`, job "Runtime performance and visual captures": paso nuevo "Measure company
  world performance" después de "Measure rendered performance". Corre `tests/bench_company.gd` 30 s con
  `xvfb-run` y deja `bench-company.log` en el artefacto `runtime-audit`. Es informativo: nunca pone el job rojo.
- Suma ~45 s a ese job. Slatex: no hay nada que hacer.
