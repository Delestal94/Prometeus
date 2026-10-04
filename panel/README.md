# Sala de control

Página para que Nacho y Slatex vean el desarrollo de un vistazo y decidan rápido:
https://delestal94.github.io/Prometeus/

- **Inicio**: un saludo con el resumen en una frase y cuatro números (rutinas trabajando, decisiones
  para ustedes, cambios que entraron hoy, cosas para mirar). Después, **Esperan su decisión** (issues
  `decide-usuario` y tareas ⏸ como tarjetas con su botón), **La cinta** (cada cambio en camino es un
  paquete que avanza: tomada → probándose → lista → en el juego), **Para mirar** y los **diez pilares**
  (diseño, sistemas, mundo, arte, audio, interfaz, red, calidad, producción, lanzamiento) con un círculo de
  avance del juego actual, una barra de la expansión, quién trabaja ahí ahora y un cajón con el detalle.
- **Cómo trabajan**: el diagrama de cómo se pasan el trabajo las rutinas, con lo activo en verde, y los
  pasos adentro de una tarea.
- **Horarios**: la agenda del día de cada rutina, agrupada (expansión, juego actual, control, PC).
- **El equipo**: los agentes con nombre en criollo (Mecánico del camión, Economista…), qué hacen y si
  están en uso.
- **Actividad**: qué pasó, contado en palabras, más las pruebas automáticas y los avisos.
- **¿Qué significa?**: glosario (PR, CI, rutina, carril, ⏸…); los `?` al lado de cada título abren la
  palabra que corresponde. La primera visita muestra una tarjeta de "así se lee esta página".

Los nombres en criollo de los agentes y las descripciones de las rutinas están en `AG` y `RT` de
`panel/index.html`: un agente nuevo sin entrada ahí se muestra con su nombre técnico.

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
- Un agente nuevo: su pilar en `PILLARS` (si no, cae en Producción) y su nombre en criollo en `AG`.
- Probar local: `python tools/panel/build_data.py && python -m http.server -d panel 8765` y abrir
  http://localhost:8765/.
