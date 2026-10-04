# Tareas de Nacho — Vehículo, Ruta, Ambientación y Depósito

> Reescrita entera con el mismo formato que `docs/tareas-slatex.md`: las tareas 1-127 de la
> versión anterior están cerradas o reubicadas (ver "Qué pasó con la lista anterior" al final).
> Esta lista sigue los 9 pilares de producción y **solo tiene trabajo que Nacho puede terminar
> sin esperar a Slatex y sin playtesting**.
>
> División de dominios y zona compartida: `docs/colaboracion-equipo.md`.
>
> **Cada tarea vive en su archivo**: [`docs/tareas/<ID>.md`](tareas/README.md) (desde el 2026-10-04; antes
> todos los PRs editaban este archivo y chocaban). Acá queda lo compartido: cómo leer la lista, el
> "Orden de ataque" y la intro de cada sección. Para ver las tareas: `python tools/tareas.py lista
> --abiertas` (o `--seccion "QA"`); el panel también las muestra. Un PR que cierra una tarea solo toca su
> archivo; `python tools/tareas.py revisar` (en CI) rechaza una tarea escrita acá adentro.
>
> **Lo terminado se archiva** en `docs/tareas/hechas/` (lo mueve `tools/archivar-tareas.py` en el
> mantenimiento semanal); lo de antes del 2026-10-04, en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).
> Un ID que no está en `docs/tareas/` está hecho: buscalo con `grep -r`, sin leer los archivos enteros.

## Mapa dinámico — pasos solicitados por el equipo

Tareas de esta sección: `python tools/tareas.py lista --seccion "Mapa dinámico — pasos solicitados por el equipo"` (cada una en `docs/tareas/<ID>.md`).

## QA — bugs abiertos

Tareas de esta sección: `python tools/tareas.py lista --seccion "QA — bugs abiertos"` (cada una en `docs/tareas/<ID>.md`).

## Hecho fuera de lista: auditoría de rendimiento (2026-09-29)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: red por Steam y bugs del playtest (2026-09-29)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: túneles del tren y repaso de las cascadas (2026-09-29)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: cascadas en las puntas del río (2026-09-28)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: repaso del depósito tras playtest (2026-09-27)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Cómo leer esta lista

- **ID**: `N-<pilar><número>` (N-101 es pilar 1, tarea 01). Subtareas `N-101.1`, `N-101.2`…
  con `[ ]` / `[x]`.
- **Prio**: **A** hacer ya (cierra algo roto o a medias) · **B** suma valor claro · **C** pulido.
- **Esfuerzo**: el modelo es siempre **Opus 5.5**; lo que cambia por tarea es el esfuerzo de
  razonamiento (ver "Cómo trabajar una tarea").
- **Aviso**: `sí` = toca la zona compartida o un archivo de Slatex. No hay que esperarlo: se deja
  un archivo nuevo en `docs/avisos/` **en el mismo commit**, con un cambio chico y aislado
  (agregar antes que cambiar firmas).
- **Hecho cuando**: el criterio verificable. Sin eso la tarea no se marca.
- **Sin playtesting**: lo que antes era "falta playtesting" se reemplazó por mediciones con código
  (bots, benchmarks, tests, capturas). Lo que necesita gente jugando está en "Para cuando haya
  playtesting" y **no se hace ahora**.

### Cómo trabajar una tarea (Claude Code con Opus 5.5)

Modelo fijo: **Opus 5.5**. Cada tarea trae anotado el esfuerzo recomendado (`/effort` en Claude
Code antes de empezarla):

| Esfuerzo | Cuándo | Ejemplos |
|---|---|---|
| **low** | Cambios mecánicos o de documentación sin decisiones. | N-307, N-701, N-804 |
| **medium** | Decisiones ya tomadas en la tarea, textos, un archivo, assets con script conocido. | N-101, N-202, N-308, N-601 |
| **high** (por defecto) | Una mecánica o sistema en 1-3 archivos con su test. | N-102, N-104, N-302, N-501 |
| **xhigh** | Red (RPC, autoridad, varios procesos), refactors de archivos compartidos, cambios que tocan 4+ archivos. | N-206, N-207, N-208, N-209, N-504 |
| **max** | Nunca de entrada: solo si xhigh no resolvió un bug después de pasarlo por `cazador-bugs`. | — |

Subir un nivel si la tarea falla una vez con el esfuerzo anotado; bajar uno para las subtareas
chicas de una tarea grande ya encaminada.

Además, siguiendo `CLAUDE.md`: los tests se corren con el agente `ejecutor-tests` y un filtro
(`tools/run-tests.sh route`), las capturas y todo lo que necesite pantalla con `revisor-visual`, y
un test que falla sin causa clara con `cazador-bugs`. Al cerrar: `[x]` + hash del commit en el archivo de
la tarea (`docs/tareas/<ID>.md`) y, si hubo aviso, un archivo nuevo en `docs/avisos/`.

---

## Orden de ataque (hitos)

| Hito | Objetivo | Tareas |
|---|---|---|
| **M1 — Cerrar lo que está a medias** | Nada del mundo que se comporte distinto en cada jugador ni que quede sin usar. | N-201, N-202, N-203, N-101, N-102, N-701, N-702 |
| **M2 — Ritmo y guía del jugador** | Una entrega de 2-5 minutos donde siempre se sabe adónde ir. | N-103, N-104, N-105, N-501, N-502, N-503 |
| **M3 — Base técnica** | Rendimiento medido en ventana real, red de 3+ jugadores probada, Endless con curvas. | N-204, N-205, N-206, N-207, N-208, N-209, N-801, N-802 |
| **M4 — Vida y variedad** | IA ambiental, audio del mundo, narrativa ambiental, detalles del camión. | N-106, N-107, N-301 a N-308, N-401 a N-405, N-601 a N-604 |
| **M5 — Preparación de lanzamiento** ⏸ | Builds, tienda, tráiler. N-901 pospuesta a la iteración de lanzamiento. | N-210, N-703, N-901 a N-906, N-911, N-916, N-912 ⏸, N-913 ⏸, N-914 ⏸, N-915 ⏸ (+ S-903 y S-907). Orden: N-916.3 (pago, usuario), N-911, N-901, N-912, N-914, N-913, N-915 |
| **M6 — Mecánicas de la competencia** | Lo que Backseat Drivers y RV There Yet? hacen bien, adaptado a la carga. | N-704, N-505, N-213, N-214, N-212, N-109, N-406, N-108, N-110, N-311, N-113, N-111, N-112, N-114 (N-907 ⏸) |
| **M7 — Pedidos del usuario** | Correr, una meta que sea un lugar, un segundo cuerpo y el diario del día siguiente. | N-115, N-116, N-312, N-606 |
| **M8 — Auditoría 2026-09-29** | Lo que la auditoría encontró roto o flojo: cada pasajero con su propia acción, puntaje y red honestos, textos traducibles, menos trabajo por frame, repo liviano. Va **antes** que lo que quede de M6/M7. | N-919, N-705, N-117, N-805, N-118, N-119, N-222, N-313 ⏸, N-314, N-223, N-315, N-224, N-225, N-316, N-317, N-318, N-319, N-706, N-226, N-227, N-228, N-229, N-238, N-240, N-239, N-321, N-908, N-909, N-910, N-320, N-922, N-920, N-921, N-327, N-328 |
| **M9 — Módulos portables** | Lo genérico del juego en carpetas que se copian a otro proyecto y funcionan, garantizado por CI (`docs/modulos.md`). Pedido del usuario 2026-09-30. Va en paralelo a M8: cada fase es un PR chico. | N-230, N-231, N-232, N-233, N-234 |
| **S — Heredadas de Slatex** | Todo lo que era de Slatex (jugador, paquetes, UI, progresión), con sus hitos S-M1 a S-M5. Va **después de M8**. | Ver "Heredadas de Slatex" más abajo |

Dentro de un hito, el orden de la tabla es el recomendado.

---

## M9 — Módulos portables

Pedido del usuario (2026-09-30): que las piezas genéricas del juego puedan llevarse a otro proyecto con
la seguridad de que funcionan. Análisis, reglas, catálogo y plan de fases en `docs/modulos.md`. Todo es
zona compartida (`modules/`), y las fases 3 y 4 tocan archivos de Slatex: aviso en cada PR.
**Las tareas abiertas las está haciendo Nacho en su sesión local (2026-09-30): no las toma la rutina de
construcción hasta que este párrafo desaparezca.**

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## M8 — Auditoría 2026-09-29

Pedido del usuario: arreglar todo lo que marcó la auditoría (`docs/auditorias/2026-09-29.md`), salvo
revisión humana de PRs ni agente revisor (no se quieren: la puerta son los checks obligatorios). Varias tocan
archivos de Slatex: aviso en `colaboracion-equipo.md` en el mismo PR, como siempre.

Tareas de esta sección: `python tools/tareas.py lista --seccion "M8 — Auditoría 2026-09-29"` (cada una en `docs/tareas/<ID>.md`).

## 1. Game Design

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 2. Programación y arquitectura técnica

Tareas de esta sección: `python tools/tareas.py lista --seccion "2. Programación y arquitectura técnica"` (cada una en `docs/tareas/<ID>.md`).

## 3. Arte y dirección visual

Tareas de esta sección: `python tools/tareas.py lista --seccion "3. Arte y dirección visual"` (cada una en `docs/tareas/<ID>.md`).

## 4. Audio y diseño sonoro

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 5. UI / UX (en el mundo)

La UI de pantalla es de Slatex. Nacho se encarga de la guía **dentro del mundo**, que no necesita
tocar el HUD.

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 6. Narrativa y guion (narrativa ambiental del mundo)

La premisa, los clientes y los textos de las cajas son de Slatex (su S-601 a S-605). Nacho cuenta la
historia **con el entorno**, sin esperar esos textos.

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 7. Producción y gestión de proyecto

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 8. QA (sin playtesting)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 9. Negocio, marketing y distribución

> **⏸ Pospuesto (2026-09-28):** estamos en desarrollo y refinamiento, así que lo de publicar en Steam
> y promocionar el juego queda para una iteración de lanzamiento. Las tareas marcadas ⏸ no se trabajan
> ni cuentan como pendientes hasta que se reabra esta sección.

Tareas de esta sección: `python tools/tareas.py lista --seccion "9. Negocio, marketing y distribución"` (cada una en `docs/tareas/<ID>.md`).

## Mecánicas tomadas de la competencia (2026-09-28)

Salen de `docs/analisis-competencia-backseat-rv.md` (Backseat Drivers y RV There Yet?); la columna
**M-xx** es el id de ese documento, donde está el razonamiento completo. Los IDs siguen el pilar al que
pertenece cada tarea. A diferencia del resto de la lista, varias tocan el dominio de Slatex (paquetes,
jugador, UI): se asignaron a Nacho a pedido del usuario, así que llevan **Aviso: sí** y, antes de
empezarlas, conviene pasar el plan por `guardian-dominios`.

| ID | M-xx | Tarea | Prio |
|---|---|---|---|
| N-704 | — | Corregir el diferencial y pasar las ideas grandes por crítica | A |
| N-505 | M-02 | Indicaciones rápidas con voz de personaje | A |
| N-213 | M-04 | Carga que sale del camión y rescate afuera | A |
| N-214 | M-03 | Averías del camión reparables con el kit | A |
| N-212 | M-01 | Voz por proximidad | A |
| N-109 | M-06 | Animales que se meten con la carga | B |
| N-406 | M-09 | Radio del camión con función | B |
| N-108 | M-05 | Tramo de barro/pendiente con salida cooperativa | B |
| N-110 | M-07 | Paradas de servicio en la ruta | B |
| N-311 | M-08 | Cosméticos para encontrar en el mundo | B |
| N-113 | M-11 | Evento de visibilidad limitada para el conductor | C |
| N-111 | M-14 | Modo "Mudanza" (viaje largo) | C |
| N-112 | M-10 | Modo party "Clientes a bordo" | C |
| N-114 | M-12 | Caja de cambios manual como variante | C |
| N-907 | M-13 | Friend Pass y demo separada (⏸ pospuesta) | C |

Tareas de esta sección: `python tools/tareas.py lista --seccion "Mecánicas tomadas de la competencia (2026-09-28)"` (cada una en `docs/tareas/<ID>.md`).

---
## Pedidos del usuario: correr, meta, personaje flaco y diario (2026-09-29)

Cuatro tareas que pidió el usuario después de ver el juego terminado de punta a punta. Van en el hito
**M7**, en este orden (de la más chica a la más grande). Tres tocan el dominio de Slatex (jugador, UI de
personalización y resultados): llevan **Aviso: sí** y conviene pasar el plan por `guardian-dominios`
antes de empezar.

| ID | Tarea | Prio |
|---|---|---|
| N-115 | Correr | A |
| N-116 | Parada final: estacionamiento de camiones de reparto | A |
| N-312 | Personaje flaco y alto | A |
| N-606 | El diario del día siguiente | A |

Tareas de esta sección: `python tools/tareas.py lista --seccion "Pedidos del usuario: correr, meta, personaje flaco y diario (2026-09-29)"` (cada una en `docs/tareas/<ID>.md`).

---
## Heredadas de Slatex (S-xxx, 2026-09-29)

> Pedido del usuario (2026-09-29): **todas las tareas de Slatex pasan a esta lista** y Slatex queda con una
> sola, S-311 (personaje 2.0 de gelatina, en `docs/tareas-slatex.md`). Conservan su ID `S-xxx` porque
> commits, tests, avisos y auditorías las nombran así.
>
> - **Dominio**: los archivos siguen siendo de Slatex (`docs/colaboracion-equipo.md`), así que casi todas
>   tocan su dominio: **cada PR lleva un aviso en `docs/avisos/`**, aunque el campo diga `Aviso: no` (ese
>   campo se escribió desde el lado de Slatex). Donde una tarea diga "aviso en `colaboracion-equipo.md`",
>   vale `docs/avisos/`.
> - **Esfuerzo**: los modelos de ChatGPT se tradujeron a Opus 5.5 (Sol → mismo esfuerzo, Astra → `xhigh`,
>   Luna → `medium`/`low`).
> - **Orden**: van **después de M8**; entre ellas, el orden S-M1 → S-M5 de su tabla.
> - **Choques con S-311**: lo del cuerpo del jugador que Slatex va a rehacer en gelatina (ragdoll #101,
>   maniquí #102, accesorios #103 / S-305, emotes S-308) queda en pausa mientras S-311 esté abierta; si se
>   hace antes, que use el rig común para que el personaje de gelatina lo herede.

### Orden de las heredadas (hitos S-M1 a S-M5)

| Hito | Objetivo | Tareas |
|---|---|---|
| **S-M1 — Cerrar lo que está a medias** | Que ningún sistema del juego quede anunciado y sin terminar. | S-101, S-102, S-103, S-104, S-105, S-203, S-210, S-804 |
| **S-M2 — Base técnica para lo que sigue** | Partir los archivos gigantes antes de sumarles UI; red robusta. | S-201, S-202, S-204, S-206, S-209 |
| **S-M3 — Onboarding y UX** | Que alguien que nunca jugó entienda qué hacer sin que se lo expliquen. | S-106, S-107, S-501, S-502, S-504, S-505, S-506, S-508, S-510 |
| **S-M4 — Balance medido y juice** | Números justificados por simulación; fallas que den ganas de clipear. | S-108, S-109, S-110, S-111, S-301, S-302, S-310, S-401 a S-404, S-601 a S-604 |
| **S-M5 — Preparación de lanzamiento** | Inglés, logo, telemetría. Tienda, cápsulas, press kit y logros (S-901, S-903, S-904, S-907) ⏸ pospuestos a la iteración de lanzamiento; capturas (S-902) y monetización (S-906) hechas. | S-509, S-306, S-905, S-805 |

Dentro de un hito, el orden de la tabla es el recomendado.

---

### 2. Programación y arquitectura técnica

Tareas de esta sección: `python tools/tareas.py lista --seccion "Heredadas de Slatex (S-xxx, 2026-09-29) › 2. Programación y arquitectura técnica"` (cada una en `docs/tareas/<ID>.md`).

---
### 3. Arte y dirección visual

Tareas de esta sección: `python tools/tareas.py lista --seccion "Heredadas de Slatex (S-xxx, 2026-09-29) › 3. Arte y dirección visual"` (cada una en `docs/tareas/<ID>.md`).

---
### 7. Producción y gestión de proyecto

Tareas de esta sección: `python tools/tareas.py lista --seccion "Heredadas de Slatex (S-xxx, 2026-09-29) › 7. Producción y gestión de proyecto"` (cada una en `docs/tareas/<ID>.md`).

---
### 9. Negocio, marketing y distribución

> **⏸ Pospuesto (2026-09-28):** estamos en desarrollo y refinamiento, así que lo de publicar en Steam
> y promocionar el juego queda para una iteración de lanzamiento. Las tareas marcadas ⏸ no se trabajan
> ni cuentan como pendientes hasta que se reabra esta sección.
> S-905 sigue activa: es investigación de onboarding que alimenta a S-506.

Tareas de esta sección: `python tools/tareas.py lista --seccion "Heredadas de Slatex (S-xxx, 2026-09-29) › 9. Negocio, marketing y distribución"` (cada una en `docs/tareas/<ID>.md`).

---
### Para cuando haya playtesting (no se hace ahora)

Quedan registradas para no perderlas. Cuando se decida hacer playtesting, se usan los datos de
S-805 y los objetivos de S-108.

| Ítem viejo | Qué hay que observar |
|---|---|
| #41, #51, #59, #67 | Si los números de las trampas, ya ajustados por simulación (S-108), se sienten justos. |
| #47 | Tutorial con alguien que nunca vio el juego. |
| #94, #95 | Cada trampa sola y las 7 combinadas en una entrega. |
| #98 | Partida real con 4-5 personas. |

---

### Qué pasó con la lista anterior (1-100)

- **Cerradas** (89): modelado y animación del jugador y de los paquetes, interacción paquete-jugador,
  progresión y desbloqueos, las trampas Líquido/Explosivo/Hostil, cosméticos, opciones, HUD y
  resultados, guía para agregar trampas. El detalle de cada una está en el historial de git de este
  archivo (`git log -p docs/tareas-slatex.md`).
- **Reubicadas** en esta lista:
  #41/#51/#59/#67 (balance) → S-108 · #79 (cosméticos con dos clientes) y #96 (dos jugadores con el mismo
  objeto) → S-204 · #99 (especificaciones visuales) → S-309.
- **Movidas a "Para cuando haya playtesting"**: #47, #94, #95, #98.
- **Encontradas a medias en el relevamiento del 2026-09-24** (nunca estuvieron en la lista vieja):
  eventos de ruta sin resolución (S-101), mérito que nadie otorga (S-102), cartas sin uso (S-103),
  votación que nunca se abre (S-104), campaña que no se guarda (S-105), contenidos repetidos entre
  trampas (S-302), íconos faltantes para 3 trampas (S-301).

## Para cuando haya playtesting (no se hace ahora)

| Ítem viejo | Qué hay que observar |
|---|---|
| #55 | Si la variedad del Endless se siente bien o hace falta más curaduría. |
| #98 | Si los tramos se sienten repetitivos después de varias partidas. |
| #83 (parte) | Mezcla de audio con oído, después de la medida de N-404. |
| — | Si el largo medido en N-102 se siente corto o largo jugando de verdad. |

---

## Qué pasó con la lista anterior (1-127)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Bugs de multijugador del playtest (143-149) — reporte directo del usuario, 2026-09-24

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Segunda tanda de multijugador (151-166) — cacería de `cazador-bugs`, 2026-09-24

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Playtest del 2026-09-25 (172-177) — reporte directo del usuario, jugando solo de noche

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).
