# Sesión de arte (a mano, en la PC)

No es un trigger: se corre en una sesión en vivo con Blender y ComfyUI abiertos, diciendo "corré la
sesión de arte". Hace lo que la nube no puede: las tareas marcadas "necesita PC". Reglas comunes:
`.claude/rutinas/README.md` (la del freno de mano no aplica: hay alguien mirando).

## 1. Preparar

1. `git fetch origin && git switch main && git pull`.
2. Blender con el addon MCP (`get_addon_status`) y ComfyUI (`server_info`, o `launch_comfyui`). Comparten
   la GPU de 8 GB: entre un agente de Blender y uno de ComfyUI, `free_memory`.
3. Juntá el trabajo: tareas abiertas con "necesita PC" en las dos listas + la última
   `docs/auditorias/*-revision.md` (tabla de `director-arte`).

## 2. Por cada tarea (una rama y un PR cada una, como en `construccion.md`)

| Qué | Agente |
|---|---|
| Modelo 3D nuevo o refinado | `modelador-blender` |
| Imagen, textura, ícono, cápsula de Steam | `artista-conceptual` |
| Material o shader con texturas nuevas | `artista-shaders` |
| Sprite de partícula | `artista-vfx` |
| Clip de animación en Blender | `animador` |

Después de cada asset: **`revisor-visual`** con la escena donde aparece (acá con GPU real: sombras y
luz también cuentan) y, si es modelo, `check_pivots.gd`. Si un asset no pasa, se itera antes del PR.

Cada imagen conservada, anotada en `art/ai-registro.md`; cada asset, en `docs/inventario-assets.md`.

## 3. Cerrar

Skill `cerrar-cambio` por tarea. Push normal (en la PC corre el hook `pre-push`), PR con auto-merge.
Al final, cuántas tareas "necesita PC" quedan y cuál conviene la próxima vez.
