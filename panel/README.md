# Sala de control

Página para que Nacho y Slatex vean el desarrollo de un vistazo y decidan rápido:
https://delestal94.github.io/Prometeus/

- **Pilares** (home): diez áreas del desarrollo (diseño, sistemas, mundo, arte, audio, interfaz, red,
  calidad, producción, lanzamiento) con su avance en el juego actual y en la expansión, qué agentes
  las están trabajando y qué está trabado. Arriba, **Para decidir** (issues `decide-usuario` y tareas
  ⏸) y **Atención** (main rojo, PRs rojos o viejos, rutinas caídas o sin rastro, bugs de la expansión).
- **Flujo**: cómo se pasan el trabajo las rutinas (archivos y PRs), con lo activo en verde.
- **Rutinas**: el día en una línea por rutina; qué corrió, qué no dejó rastro y qué viene.
- **Agentes**: los de `.claude/agents/` por pilar, con modelo, esfuerzo y si están en uso.
- **Actividad**: eventos del repo atribuidos a cada rutina, PRs abiertos, CI y avisos.

## Cómo funciona

- `tools/panel/build_data.py` arma `panel/data.json` (no se versiona) desde los agentes, la tabla
  "Ciclo completo" de `CLAUDE.md`, la tabla de rutinas de `.claude/rutinas/README.md`, los carriles de
  `desarrollador.md`, `docs/tareas/` (con `tools/tareas.py`), `docs/expansion-distritos/` y `docs/avisos/`.
- `.github/workflows/panel.yml` lo genera con `--strict` (falla si una tabla cambió de forma) y publica
  `panel/` en Pages en cada push a main que toque esos archivos.
- Lo en vivo lo pide el navegador a la API pública de GitHub (el repo es público): eventos, PRs,
  corridas de CI e issues. Sin token son 60 consultas por hora y refresca cada 4 min; con un token
  *fine-grained* de solo lectura (botón "token", queda solo en ese navegador), cada 20 s.
- "Trabajando" es una deducción: la rutina arrancó hace menos de 75 min y su rama tuvo actividad desde
  entonces. Las ramas `exp/` se atribuyen al carril que arrancó justo antes de crearlas. Una sesión a
  mano en una rama `nacho/` se ve como Construcción A.

## Mantenerlo

- Un horario de rutina nuevo o cambiado: `ROUTINES` en `tools/panel/build_data.py` (cron en UTC).
- Un agente nuevo: su pilar en `PILLARS` (si no, cae en Producción).
- Probar local: `python tools/panel/build_data.py && python -m http.server -d panel 8765` y abrir
  http://localhost:8765/.
