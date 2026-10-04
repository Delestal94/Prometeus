# Rutina: desarrollador de la expansión → una tarea `D-`, un PR

Construye la expansión de `docs/expansion-distritos/` (distritos en un mapa continuo, flota, galpón,
armado de paquetes, empleados, automatización). Cinco triggers usan este archivo con un parámetro
`Carril: N`. Reglas comunes, freno de mano y sesión: `.claude/rutinas/README.md` (leelo primero). Lo que
dice acá manda sobre el README para las tareas `D-`.

Pedido del usuario (2026-10-04): **a toda marcha, sin paradas**. Las decisiones de "cómo se hace" las
toma la rutina y las documenta. Las pruebas manuales y lo que haya que revisar quedan anotados para el
final. **Nunca** se frena una tarea esperando a una persona.

Una corrida = **una** tarea `D-` (o una subtarea si es grande), en lo posible en menos de 45 min. Si no
alcanza, PR "(partial)" con lo hecho y las subtareas abiertas.

## Carriles

| Carril | Modelo del trigger | Grupos (en orden) | Agentes principales |
|---|---|---|---|
| 1 · Arquitectura y diseño | Opus 5.5 | 02, 01 | `Plan`, `constructor-progresion`, `critico-diseno`, `documentador` |
| 2 · Galpón y stock | Sonnet 5.5 | 09, 06 (después 10, 11) | `constructor-mundo`, `constructor-jugador`, `constructor-camion` (autoelevador) |
| 3 · Armado y pedidos | Sonnet 5.5 | 07, 08 | `constructor-trampas`, `constructor-jugador`, `constructor-progresion`, `constructor-ui` |
| 4 · Mapa, salidas y economía | Sonnet 5.5 | 03, 05 (después 15, 04) | `constructor-tramos`, `constructor-mundo`, `constructor-progresion`, `constructor-ui` |
| 5 · Red, CI y calidad | Opus 5.5 | 20 (después 12-14 lo de red) | `constructor-red`, `auditor-red`, `escritor-tests`, `perfilador-rendimiento` |

Los agentes ya traen modelo y esfuerzo fijos en `.claude/agents/`. Esta rutina coordina y les pasa el
contexto completo de la tarea (no ven el tuyo).

## 1. Primero lo que está roto

1. **`main` rojo** (el run del SHA de HEAD, regla 16 del README). Si lo rompió un PR `exp/` mezclado, arreglarlo es la
   tarea del **carril 5**. Los otros carriles lo arreglan solo si el commit rojo tiene más de 1 h. Rama
   `exp/fix-main-<tema>`, con `cazador-bugs`.
2. **Tus PRs `exp/` abiertos** (los de los grupos de tu carril):
   - con conflicto: rebase sobre `origin/main`. En los archivos de detalle casi siempre se conservan las
     dos versiones;
   - rojos: como `construccion.md` §1, con máximo 3 intentos. Al tercero, cerralo con el diagnóstico,
     marcá la tarea `⚠ Bloqueada` con el motivo en su archivo de detalle y seguí con otra.
   El carril 5 además arregla los PRs `exp/` rojos de **cualquier** carril que tengan más de 2 h.
3. **Bugs de la expansión** (`docs/expansion-distritos/bugs/*.md`, menos el README): el más viejo con
   gravedad `bloquea`, después los `molesta`. Se reclama como una tarea (`exp/bug-<tema>`). Los toma
   cualquier carril; el carril 5, primero. El PR que lo arregla borra el archivo del bug.
4. **Más de 10 PRs `exp/` abiertos en total**: no abras otro. Ayudá a ponerlos verdes y terminá.

## 2. Elegir la tarea

Fuente: `docs/expansion-distritos/detalle/*.md` (tareas con detalle) y las tablas de grupo
`docs/expansion-distritos/NN-*.md`.

1. En los grupos de tu carril, en orden, la **primera** tarea que cumple todo esto:
   - no está `[x]` ni `⚠ Bloqueada` ni tachada;
   - no tiene PR abierto ni rama `origin/exp/<ID>-*`;
   - todas sus `Depende de` están `[x]`. Las decididas cuentan como hechas, y una dependencia de otro
     carril sin hacer **no** se espera: se elige otra;
   - es de la fase en curso. F0 y F1 hasta que D-0111 esté `[x]`; después F2, F3, F4 y F5 en orden
     (README de la expansión). Los bloques Núcleo van antes que Ampliación y Pulido.
2. **Tu carril no tiene nada tomable** → tomá la primera tomable de cualquier carril, siguiendo
   "Orden recomendado" de `detalle/README.md`.
3. **No hay nada tomable en ningún carril** → detallá. Tomá las 5 tareas siguientes de tu carril que
   todavía no tienen detalle y escribilas en `detalle/` con el formato de los archivos que ya existen
   (encabezado, depende, qué, subtareas, test, hecho cuando). Es un PR de docs.
4. **Tarea sin detalle** (está solo en la tabla del grupo): primero escribí su detalle en el archivo
   `detalle/` de su fase y grupo (crealo si no existe, como `F1-06-stock.md`), en el mismo PR, y después
   construila.
5. **Ya está hecha** en el código: marcala `[x]` con el hash y elegí otra.

Saltá lo que necesita la PC (Blender, ComfyUI, GPU real, FPS con ventana). Para lo visual, usá un
**placeholder gris** hecho por código (mallas primitivas, `CSGBox3D` horneado o
`assets/models/cargo/sm_cargo_box_cube.glb` escalado). El asset de verdad se pide en
`docs/expansion-distritos/arte-pendiente/<ID>.md`: qué modelo, medidas, pivote, dónde se usa y qué
placeholder reemplaza. Lo toma la sesión de arte de la PC.

**Reclamala enseguida** (el `push` falla si otra corrida ya la tomó, y entonces elegís otra):
```bash
git switch -c exp/<ID>-<tema-corto> origin/main
git commit --allow-empty -m "chore: claim <ID>"
SKIP_TESTS=1 git push -u origin HEAD
```
Una reserva `exp/` abandonada se retoma con la regla 15 del README; nunca se borra.

## 3. Hacer la tarea

1. **Leé** su detalle, [supuestos](../../docs/expansion-distritos/detalle/supuestos.md) y las
   decisiones de `docs/decisiones/2026-10-04-*.md`.
2. **Decidí sin frenar.** Toda elección de cómo se hace (nombres, números, estructura, qué opción de
   varias) la tomás vos, con lo más simple que encaje con `docs/` y el juego actual:
   - si es chica, va como "Decisión:" en el cuerpo del PR;
   - si cambia diseño, números de `company_tuning.gd` o una tarea, va además en
     `docs/decisiones/AAAA-MM-DD-<tema>.md` (archivo nuevo por decisión, para no chocar) y en el
     detalle de la tarea, en el mismo PR.
   Límites (esto sigue siendo del usuario, con issue `decide-usuario`, regla 12): no recortar nada de lo
   que el usuario nombró (fila 5 de `2026-10-04-expansion-decisiones-delegadas.md`), no gastar plata
   real, no tocar precio, fecha ni página de Steam.
3. **Construí** como `construccion.md` §3, con la tabla de agentes de allá. La carpeta
   `scripts/gameplay/business/` es de `constructor-negocio` cuando exista (D-0141); hasta entonces,
   `constructor-mundo` para el galpón y `constructor-progresion` para stock, pedidos y plata.
4. **Test** nuevo o ampliado (skill `nuevo-test`) que compruebe lo que dice "Hecho cuando". Correlo con
   `ejecutor-tests` y el filtro `company` (o el del área). Nunca la batería entera.
5. **Red:** `auditor-red` antes del PR. **Zona compartida o archivos de Slatex:** `revisor-gdscript` y
   aviso en `docs/avisos/`.
6. **Pruebas manuales y cosas a revisar:** nunca se hacen ni se esperan. Anotalas en un archivo nuevo
   `docs/expansion-distritos/revisar/<ID>.md` con dos listas: "Probar a mano" (qué hacer y qué debería
   verse) y "Decidir al final" (lo que el usuario podría querer cambiar, con la opción que elegiste).
   Un archivo por tarea, así los PRs no chocan.

No se toca `docs/tareas-nacho.md` (es de la rutina de construcción). Los bugs que encuentres fuera de tu
tarea van a `docs/expansion-distritos/revisar/<ID>.md` si son de la expansión. Si son del juego actual,
van al cuerpo del PR, para la auditoría.

## 4. Cerrar y subir

1. Skill `cerrar-cambio`, pero el "marcar la tarea" se hace así:
   - en su archivo `detalle/` agregás debajo del título
     `**[x] Hecho (AAAA-MM-DD, PR #n)** — <una línea de qué quedó>`;
   - en la tabla del grupo agregás `✅` al principio de la columna "Tarea".
2. Subida como el README (regla 6): `SKIP_TESTS=1`, título en inglés con prefijo y el ID
   (`feat: D-0202 company state autoload`), `--auto --squash`. Cuerpo del PR:
   - qué se hizo y cómo se verificó;
   - agentes usados;
   - las decisiones tomadas;
   - el link a `revisar/<ID>.md` si existe.
3. Si un PR de otro carril cambió algo que tu tarea usa, rebase antes de pedir el merge.
