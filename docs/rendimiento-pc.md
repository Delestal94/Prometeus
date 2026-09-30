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
