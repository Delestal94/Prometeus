# Modo Empresa al lado de Entrega y Endless (D-0102) — 2026-11-04

Decidió: Claude, por delegación del usuario (2026-11-04). No se abrió issue `decide-usuario` para esta tarea.

## Contexto
D-0102 (`docs/expansion-distritos/detalle/F0-01-diseno.md`) preguntaba si el modo Empresa va aparte o
reemplaza lo que ya existe. Desde el 2026-10-04 se trabaja con el supuesto S1 (modo nuevo al lado) y con la
fila 1 de [decisiones delegadas](2026-10-04-expansion-decisiones-delegadas.md) (Empresa como juego principal;
Entrega y Endless como "Partida rápida"). D-0112 le fundió D-0128 (encaje del Endless). Sobre eso ya se
construyó: `company_root.tscn` (D-0214), su página de slots en el menú (D-1904), `--autostart-company`
(D-0119), y los filtros `company` / `district` / `fleet` de `run-tests.sh` (D-2014). Entrega y Endless no se
tocaron y sus tests siguen.

## Alternativas
- **(a) Modo Empresa nuevo al lado de Entrega y Endless** (la que recomienda el detalle, S1).
- (b) Empresa reemplaza Entrega y deja Endless: hay que reescribir o borrar los tests de la entrega
  (`level_base.gd`, `--autostart`, bots de la corrida) y la demo actual deja de existir hasta que la Empresa
  esté completa.
- (c) Empresa reemplaza todo: lo mismo que (b) más Endless, que la fila 1 manda dejar "sin cambios" (por eso
  ya se recortó D-1739, el Volcán en Endless).

## Decisión
**(a), con el orden de la fila 1.**
- El modo Empresa es el juego principal: cuando cierre el corte vertical (el bot de D-2016 da `BOT_OK` con 1 y
  2 jugadores), pasa a ser el **primer botón** de la página Jugar.
- Entrega y Endless quedan como **"Partida rápida"**, sin cambios de comportamiento: mismos niveles, mismos
  flags de arranque, mismos tests. Endless no se adapta a la empresa (D-0128 queda contestada así).
- Hasta que cierre el corte, el menú queda como está (Empresa como tercer botón, "en prueba"): poner primero
  un modo que todavía no cierra un día completo sería la peor primera impresión.

## Por qué
- La empresa es la promesa nueva del juego; las partidas rápidas sirven para jugar 10 minutos y sostienen la
  demo y los tests que ya existen.
- (b) y (c) tiran trabajo jugable y tests verdes a cambio de nada: la expansión se puede cortar en cualquier
  fase sin perder el juego base.
- Todo lo construido desde octubre ya supone (a): elegir otra opción rompería D-0214, D-1904 y D-2014.

## Qué cambia
- `supuestos.md` S1 pasa a decidido.
- Trabajo nuevo: el reorden del menú y el rótulo "Partida rápida" no existen todavía. Quedan anotados en
  [`revisar/D-0102.md`](../expansion-distritos/revisar/D-0102.md).
