# Rutina: build y rendimiento (PC, diaria)

Lo que la nube no puede: exportar el `.exe` de Windows y probarlo, medir FPS con la GPU de verdad y
mirar la luz y las sombras reales. Así una build rota o una caída de FPS se ven al día siguiente y no
el día que se quiere jugar con amigos. La lanza el Programador de tareas
(`tools/pc/rutina-pc.ps1 -Rutina build`). Reglas comunes, freno de mano, sesión y freno de tareas:
`.claude/rutinas/README.md` (leelo primero).

## 1. Qué se prueba

1. `git switch --detach origin/main` y anotá el commit. Si ese commit ya tiene fila en
   `docs/rendimiento-pc.md` (no entró nada desde ayer), terminá sin hacer nada.
2. **CI de main**: `gh run list --branch main --workflow tests.yml --limit 1`. Si está rojo, la build no
   se hace: terminá (la construcción arregla main primero). La batería de tests no se corre acá: ya la
   corrió CI sobre ese commit.

## 2. Tres pasadas, en este orden (una GPU, de a una)

1. **`empaquetador-release`**, pedido explícito de build de prueba (el hito M5 sigue en pausa, pero
   esta build no se publica): pasos 3 a 6 de su checklist (export release de "Windows Desktop" a
   `builds/windows/`, dependencias de Steam, smoke test del `.exe`, tamaño y archivos que no deberían
   estar). Sin notas de versión, sin tags, sin subir nada. Conservá solo las 3 builds más nuevas en
   `builds/` (está ignorada por git).
2. **`perfilador-rendimiento`**, solo medir (no cambia código): `tests/bench_drive.gd` **con ventana**
   (sin `--headless`, ver README → Rendimiento), 150 s en reparto y 150 s en Endless, con la misma
   semilla que la última fila de `docs/rendimiento-pc.md`. Tomá ms por frame (promedio, p95, p99), FPS
   promedio y 1 % más bajo, draw calls, costo de física por tick y memoria al final. Una vez por
   semana (lunes) sumá la pasada con el preset bajo de N-205.
3. **`revisor-visual`**, con GPU real: `render_depot.gd`, `render_route_dressing.gd`,
   `render_rail_tunnel.gd` y `render_main_menu.gd` (o sus equivalentes si cambiaron de nombre). Solo
   lo que en la nube no se ve: sombras que faltan o parpadean, luces quemadas, niebla o noche ilegibles,
   brillos que tapan.

Cerrá Godot y el `.exe` después de cada pasada.

## 3. Registrar

- **`docs/rendimiento-pc.md`** (crealo si no existe, con la PC anotada arriba: GPU, CPU, resolución):
  una fila por corrida en la tabla — fecha, commit, build OK/falla y tamaño, FPS reparto y Endless
  (promedio / 1 % bajo), p99 ms, draw calls, memoria. Es la serie que muestra tendencias.
- **Hallazgos** → **`planificador-tareas`** en `tareas-nacho.md`, con `Origen: PC build AAAA-MM-DD`:
  - la build no exporta o el smoke test falla → sección "QA — bugs abiertos", gravedad "bloquea";
  - FPS promedio o 1 % bajo que cae más de 10 % respecto del promedio de las últimas 5 filas, o p99 que
    pasa de 33 ms → tarea con los números y los commits entre la fila buena y esta;
  - problemas de luz o sombra de `revisor-visual` → tarea "necesita PC" (la toma la sesión de arte).
- Rama `rutina/pc-AAAA-MM-DD`, PR `docs: PC build and performance AAAA-MM-DD` con auto-merge. Cuerpo:
  la fila de hoy, la comparación con la anterior y las tareas creadas. La fila se sube todos los días
  aunque no haya hallazgos: esta rutina es la excepción a la regla 7 del README, porque la serie sirve.

## 4. Límites

- No arregla código ni assets: mide y deja tareas.
- No publica nada (ni Steam, ni tags, ni releases de GitHub).
- Si mientras corre la PC se usa para otra cosa (FPS muy por debajo de lo normal en todas las pasadas
  por igual), anotá "PC ocupada" en la fila y no crees tareas de rendimiento ese día.
