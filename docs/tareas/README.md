# Tareas de Nacho: un archivo por tarea

Cada tarea `N-xxx` (y las heredadas `S-xxx`) es un archivo `docs/tareas/<ID>.md`. Hasta el 2026-10-04 eran
bloques de [`../tareas-nacho.md`](../tareas-nacho.md), y casi todos los PRs editaban ese archivo: las
rutinas en paralelo chocaban ahí (181 de 233 commits en 5 días lo tocaron). Ahora un PR que trabaja una tarea
solo toca su archivo.

`tareas-nacho.md` sigue siendo la portada: cómo leer la lista, el **"Orden de ataque"** (qué hito va
primero y en qué orden) y la intro de cada sección. Las secciones son sus títulos `##`.

## Formato

```markdown
# N-925 · Título corto en castellano — A|B|C · `Opus 5.5 · <esfuerzo>` · Aviso: sí (archivos) | no

Sección: QA — bugs abiertos

Origen: <rutina> AAAA-MM-DD. Contexto en 2-4 líneas con la evidencia. Hecho cuando <criterio verificable>.
- [ ] **N-925.1** Paso concreto. Con `<agente>`; tests `<filtro>`.
```

- La **primera línea** es el título de siempre con un solo `#`; el estado va ahí como antes (`~~…~~` o
  `**[x] …**` hecha, `⏸` en pausa, `⏸ decide el usuario`, `⚠ Bloqueada`).
- **`Sección:`** es un título `##` de `tareas-nacho.md` tal cual (sin `**` ni backticks). Las heredadas:
  `Heredadas de Slatex (S-xxx, 2026-09-29) › <subsección ###>`. Una sección nueva se agrega allá como `##`.
- El nombre del archivo es el ID: `N-224.4.md` para una tarea partida en otra.
- Al cerrarla: `[x]` y el hash o la rama en el archivo, como siempre. Nada en `tareas-nacho.md`.
- Una tarea nueva que va en un hito: además, su ID en la fila del hito de "Orden de ataque" (eso sí es
  `tareas-nacho.md`, pero lo editan solo los planificadores, pocas veces por día).

## Herramientas

```bash
python tools/tareas.py lista --abiertas            # tomables, por sección en el orden de tareas-nacho.md
python tools/tareas.py lista --seccion "QA"        # una sección (todas sus tareas, cualquier estado)
python tools/tareas.py lista --estado decide       # las que esperan al usuario
python tools/tareas.py libre N-9                   # siguiente ID libre de las N-9xx
python tools/tareas.py revisar                     # lo que corre CI (lint) y el pre-push
python tools/archivar-tareas.py                    # mantenimiento: hechas -> docs/tareas/hechas/
```

`revisar` falla si `tareas-nacho.md` vuelve a tener una tarea adentro (por ejemplo, un PR viejo que la editó
como antes): el mensaje dice a qué archivo mover el bloque.

## Hechas

`docs/tareas/hechas/` guarda las terminadas (sin `[ ]`, ⏸ ni ⚠); las de antes del 2026-10-04 están en
[`../tareas-nacho-archivo.md`](../tareas-nacho-archivo.md). Para saber si algo ya se hizo:
`grep -rl "N-224" docs/tareas docs/tareas-nacho-archivo.md`.
