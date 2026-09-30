# Rutina: lanzamiento (mensual)

Mantiene vivo el plan de Steam para que el juego no llegue "terminado" sin página, sin cápsulas ni
features de plataforma. Reglas comunes y sesión: `.claude/rutinas/README.md` (leelo primero).

## 1. Estado

**`estratega-steam`** con este pedido: actualizá `docs/marketing/estado-steam.md` (crealo si no existe)
con

1. features de Steam que un coop necesita y su estado real en el código (Remote Play Together, lobby e
   invitaciones, logros, nube, mando, Steam Deck, declaración de IA desde `art/ai-registro.md`);
2. calendario hacia atrás desde la fecha objetivo de `docs/plan-desarrollo.md` (si no hay fecha,
   proponé una y marcala como decisión pendiente);
3. qué cápsulas y capturas existen y cuáles faltan;
4. qué cambió desde el mes pasado (lo mezclado en el mes, `git log --since="1 month ago"`);
5. **versiones de las dependencias del juego**: la de Godot que usan CI (`.github/workflows/tests.yml`),
   el hook de arranque de la nube y la PC, contra el último parche estable 4.7.x; la de `addons/godotsteam`
   contra su último release compatible (WebFetch de las páginas de releases oficiales). Un parche de
   Godot con arreglos que nos tocan → tarea normal (cambiar la versión fijada en CI, hook, `run-tests.sh`
   y la PC, y correr la batería). GodotSteam nuevo → tarea ⏸ "decide el usuario" (el hook bloquea editar
   el addon a mano: lo actualiza una persona).

## 2. Registrar

Rama `rutina/lanzamiento-AAAA-MM`.

- `docs/marketing/estado-steam.md` actualizado (y los archivos de `docs/marketing/` que el agente toque).
- **`planificador-tareas`** con lo que implica trabajo en el juego: **máximo 5 tareas** por mes, con
  `Origen: lanzamiento AAAA-MM` y sujetas al freno de tareas (regla 11 del README). Cápsulas
  e imágenes → "necesita PC" (las hace la sesión de arte con `artista-conceptual`); capturas y planos del
  tráiler → "necesita PC" (sesión de arte, con `revisor-visual`); features de plataforma (lobby,
  invitaciones, logros, nube, Remote Play) → `constructor-red`; mando y Steam Deck → `constructor-ui`.
  Mientras M5 siga ⏸, estas tareas nacen en M5 con ⏸ y no las toma la construcción. Precio, fecha y
  alcance de idiomas → ⏸
  "decide el usuario".
- PR `docs: launch status AAAA-MM` con auto-merge; sección "Para el usuario" con las decisiones pendientes.

## 3. Etapas que se encienden solas

Dormidas hasta que se cumpla su condición; mientras tanto, esta sección no hace nada.

- **Página pública o demo** (hay un `appid` real en `steam_appid.txt` distinto de 480, o
  `docs/marketing/estado-steam.md` dice "página publicada"): sumá al pedido de `estratega-steam` el
  punto 5, **devlog del mes** — un post corto en `docs/marketing/devlog/AAAA-MM.md` con lo mezclado en el
  mes contado para jugadores y los GIFs que pida (pedido "necesita PC" para `revisor-visual` con
  `trailer_shot.tscn --frames`).
- **Después de la salida** (existe un tag `v1.*`: `git tag -l 'v1.*'`): sumá el punto 6, **post-lanzamiento**
  — reseñas y foros de la página de Steam (WebFetch), agrupados en bugs / pedidos / confusiones. Los
  bugs van como tareas en "QA — bugs abiertos" (con `cazador-bugs` para reproducirlos si se puede), las
  confusiones como tareas de `pulidor-jugabilidad`, los pedidos como propuestas para `critico-diseno`
  en la próxima revisión. Un parche = build con `empaquetador-release` en vivo; nunca se sube solo.
