# Rendimiento en la PC (build y FPS diarios)

Serie de la rutina `pc-build` (`.claude/rutinas/pc-build.md`): una fila por corrida, sobre el commit de
`origin/main` de ese día. Sirve para ver tendencias: una caída de FPS o una build rota aparecen al día
siguiente.

**PC:** NVIDIA RTX 4060 Ti (driver 610.88, GL Compatibility sobre OpenGL 3.3), AMD Ryzen 5 7600X,
32 GB de RAM, Windows 11. **Resolución:** 1920×1080 en ventana (`--resolution 1920x1080 --windowed`),
vsync apagado (lo apaga el bench).

**Cómo se mide:** `tests/bench_drive.gd` con ventana, semilla 4242, 150 s en reparto y 150 s en Endless
(`--endless`):

```
<godot> --path do-not-drop --resolution 1920x1080 --windowed --script res://tests/bench_drive.gd -- --seconds=150 [--endless]
```

- FPS 1 % bajo = 1000 / p99 ms (el bench no lo imprime).
- Memoria = pico de memoria estática que imprime el bench (no el valor al final).
- Build = export release de "Windows Desktop" a `builds/windows/` y smoke test del `.exe`.
- Una caída de más del 10 % en FPS promedio o 1 % bajo contra el promedio de las últimas 5 filas, o un
  p99 de más de 33 ms, es una tarea en `tareas-nacho.md`. Con "PC ocupada" en Notas no se comparan.

| Fecha | Commit | Build | FPS reparto (prom / 1 % bajo) | FPS Endless (prom / 1 % bajo) | p99 ms (reparto / Endless) | Draw calls (reparto / Endless) | Memoria MiB (reparto / Endless) | Notas |
|---|---|---|---|---|---|---|---|---|
| 2026-09-30 | `390ee37` | OK, 136 MB | 142 / 72 | 333 / 152 | 13,9 / 6,6 | 2.165 / 463 | 388 / 228 | Primera fila. Reparto: `HUD_RUN_STUCK` a los 116 s (progreso 0,99); los últimos 34 s midieron la pantalla final. Endless: 16 tirones de física de 35-86 ms. Editor de Godot abierto en segundo plano. |

## Pico de física al generar un tramo de Endless (N-219)

Headless, sin GPU (`--headless --script res://tests/bench_drive.gd -- --endless --cpu-only --seconds=90 --seed=4242`),
mismo escenario y semilla antes y después. "Pico por tick" es el máximo de `physics per tick` del bench (del
`physics_frame` al siguiente `process_frame`, o sea incluye el `_physics_process` del streamer). Medido en una PC
compartida con otros procesos: los números sueltos oscilan unos ms.

| Qué | Antes | Después |
|---|---|---|
| Pico por tick (3 corridas antes / 5 después) | 102,7 / 103,6 / 125,6 ms | 12,9 / 10,2 / 17,1 / 20,8 ms (y 127 ms en una corrida con la PC ocupada) |
| Tick promedio | 1,01 ms | 0,98-1,24 ms |
| Construir un puente (`add_child`) | 93 ms la primera, 34-44 ms las siguientes | 3-4 ms |
| Construir un túnel | 22-28 ms | 4-5 ms |
| Construir tramo de obras | 18 ms | 2 ms |
| Unir geometría (`DressingBatcher`) en el mismo tick | 6-11 ms (túnel/puente) | 4-9 ms, un tick después |
| Ticks de más de 20 ms en 90 s (mido frame, no solo física) | 23 | 15-35 según carga de la PC (ruido: los frames de 20-30 ms con `physics` < 3 ms no son del streamer) |

Causa: no eran los `StaticBody3D`/shapes ni el terreno. `RouteSegment._model()` hacía `load()` del `.glb` para cada
pieza y el `PackedScene` se liberaba al instanciar, así que un puente leía ~40 veces del disco; el primer puente además
sintetizaba el loop del río (~55 ms), y la unión de geometría corría en el mismo tick que la construcción.

Pendiente de medir con ventana real: la subida de mallas y materiales al renderer del primer tramo de cada tipo
(en GL Compatibility puede costar un frame aparte) y el costo de la unión con el modelo de física de Jolt activo
con el camión lleno (N-220).

