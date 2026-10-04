# Rutina: sesión de arte (PC, cada 2 h)

Corre en la PC de Nacho, con Blender y ComfyUI: crea los modelos e imágenes que todavía no existen y
refina los que ya hay. Una corrida = **un** asset = un PR. La lanza el Programador de tareas
(`tools/pc/rutina-pc.ps1 -Rutina arte`); también se puede pedir en vivo ("corré la sesión de arte") y
se sigue este mismo archivo. Reglas comunes, freno de mano, sesión y freno de tareas:
`.claude/rutinas/README.md` (leelo primero).

## 0. Antes de elegir

1. **PRs `arte/*` abiertos** (`gh pr list --state open --json number,headRefName,statusCheckRollup,mergeable`):
   - con conflicto: `git rebase origin/main` en su rama; en docs se conservan las dos líneas; en un
     binario (`.glb`, `.png`) quedate con el tuyo y, si cambió la fuente, reexportalo con su script;
     `git push --force-with-lease` (solo en ramas `arte/`);
   - rojo: leé el check que falló (`gh run view <id> --log-failed`), reproducí con `ejecutor-tests` y el
     filtro del test, arreglá. Máximo 3 intentos por PR; al tercero, `gh pr close <n> --comment
     "<diagnóstico>"` y la tarea queda `⚠ Bloqueada (AAAA-MM-DD)` en un PR chico de docs.
   Arreglar uno de estos es la corrida entera.
2. **3 PRs `arte/*` abiertos o más**: terminá sin hacer nada (lo que no se mezcla no se apila).
3. **Herramientas**: Blender con `get_addon_status` (el lanzador ya lo abrió; si no responde, terminá y
   decilo en la salida) y ComfyUI con `server_info` (si no está, `launch_comfyui`). Comparten la GPU de
   8 GB: entre un agente que usa Blender y uno que usa ComfyUI, `free_memory`.

## 1. Elegir el asset

**Modo del turno**: `$(( 10#$(date +%H) / 2 % 2 ))` → `0` **crear**, `1` **refinar**. Si en ese modo no
hay nada tomable, usá el otro.

Primero, en cualquier modo: tareas abiertas de `docs/tareas-nacho.md` que digan **"necesita PC"** y sean
de arte (modelo, imagen, textura, ícono, cápsula, captura de tienda o tráiler, material, sprite, clip, música), en el orden de ataque.

Si no hay ninguna:

- **Crear**: lo ⬜ ("falta crearlo") de `docs/inventario-assets.md` y lo que el §10.1 todavía arma con
  primitivas en código. Primero lo que se ve de cerca y seguido (en la cabina, en la puerta de la casa,
  en la ruta al lado del camión), después lo lejano, después lo de la tienda de Steam.
- **Refinar**: `director-arte` sobre el área del día (`$(( 10#$(date +%j) % 5 ))`: 0 decorado de ruta y
  tramos, 1 casas, jardines y depósito, 2 texturas e imágenes 2D, 3 UI e íconos, 4 materiales y
  efectos), con los assets que ya pasaron por esta rutina en las últimas dos semanas
  (`git log origin/main --since="14 days ago" --format=%s | grep -i "art"`) para que no los repita.
  Tomá el primer REFINAR de su tabla; sumá como fuente el §10.2 del inventario. BORRAR o REHACER algo
  grande no se ejecuta: va como tarea ⏸ "decide el usuario".

Después de las de `tareas-nacho.md`, los pedidos de la expansión: cada archivo de
`docs/expansion-distritos/arte-pendiente/<ID>.md` es un asset que una tarea `D-` dejó con placeholder gris
(qué modelo, medidas, pivote, dónde va). Al terminarlo, se reemplaza el placeholder en la escena, se borra
ese archivo en el mismo PR y se marca la tarea de arte del grupo (D-18xx u otra) con `✅`.

Si lo elegido no tiene tarea, creala con **`planificador-tareas`** en `tareas-nacho.md`, con "necesita
PC" y `Origen: sesión de arte AAAA-MM-DD` (respetando el freno de tareas; si está activo, trabajá solo
sobre tareas existentes).

**Nunca**:
- personajes: cuerpo del jugador, residente, NPC, ragdoll, maniquí, accesorios y cosméticos (pausados
  por el usuario el 2026-09-29; S-311, el personaje de gelatina, es de Slatex);
- lo marcado ⛔ en el inventario;
- el camión (lo modela `constructor-camion` con su propio flujo, no esta rutina);
- lo que ya tenga rama `origin/arte/<ID>-*` o `origin/nacho/<ID>-*` o PR abierto.

**Reclamá** antes de trabajar:
```bash
git switch -c arte/<ID>-<tema-corto> origin/main
git commit --allow-empty -m "chore: claim <ID>"
SKIP_TESTS=1 git push -u origin HEAD
```

## 2. Hacer el asset

Dale al agente el contexto completo: la tarea, `docs/direccion-visual.md`, la fila del inventario, el
asset actual si es un refinado y dónde aparece en el juego.

| Qué | Agente |
|---|---|
| Modelo 3D nuevo o refinado | `modelador-blender` |
| Imagen, textura, ícono, cápsula de Steam | `artista-conceptual` |
| Material o shader con texturas nuevas | `artista-shaders` |
| Sprite de partícula o efecto | `artista-vfx` |
| Clip de animación en Blender (no de personajes) | `animador` |
| Música (regenerar con `tools/audio/compose_music.py`) | `disenador-audio` |
| Capturas de tienda (`render_store_shots.gd`), planos del tráiler y GIFs de devlog (`trailer_shot.tscn`) | `revisor-visual` |

- **Reproducible**: un modelo sale de un script de Blender en `do-not-drop/assets/tools/` (nuevo o
  ampliando el lote que corresponde, con `lowpoly_kit.py`); una textura de detalle, de
  `art/tools/make_detail_textures.py`; una imagen, de `art/tools/comfy_generate.py` con el prompt
  anotado. Nada hecho a mano que no se pueda volver a generar.
- **Presupuesto**: triángulos en el rango del inventario para su tipo; texturas de 2048² como máximo y
  sin duplicar una que ya exista.
- **Integrar**: si reemplaza un archivo existente, mismo camino y mismo nombre. Si es nuevo, conectalo
  con el agente del área (`constructor-tramos` para decorado y tramos, `constructor-ui` para UI,
  `constructor-camion` para la cabina) y un test que lo cargue (skill `nuevo-test`), corrido con
  `ejecutor-tests` y su filtro. Los `.import` y `.uid` que genera Godot se commitean tal como salen.

**Verificar** (acá con GPU real: luz y sombras también cuentan): `revisor-visual` con la escena donde
aparece y, si es un modelo, `check_pivots.gd`. Si no pasa, se itera; máximo 3 vueltas. Si a la tercera
sigue sin pasar, no se sube el asset: descartá los cambios, borrá la rama y anotá en la tarea "Intento
AAAA-MM-DD: <qué no pasó>" en un PR chico de docs.

## 3. Registrar y subir

1. Cada imagen conservada, en `art/ai-registro.md` (declaración de IA de Steam); cada asset, en
   `docs/inventario-assets.md` (estado, triángulos, script que lo genera).
2. Skill `cerrar-cambio`: tarea `[x]` con el hash en `tareas-nacho.md`, aviso en `docs/avisos/` si tocó
   archivos de Slatex o la zona compartida.
3. Subida según el README (`SKIP_TESTS=1`, `--auto --squash`). Título `feat: <ID> <asset> (art)`.
   Cuerpo: qué se creó o refinó, antes/después en triángulos y tamaño, capturas que miró
   `revisor-visual` (la ruta en el repo si las guardó), agentes usados, supuestos.
4. Cerrá lo que abriste: Godot siempre; Blender y ComfyUI quedan abiertos para la próxima corrida,
   pero con la escena de Blender vacía (`File > New`) y `free_memory` en ComfyUI.
