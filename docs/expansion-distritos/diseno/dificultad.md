# Dificultad y modificadores del modo Empresa (D-0127)

> Fase F0 · Carril 1. Lo construye D-1919 (opciones visibles) con las reglas de abajo. Decisión:
> [2026-10-22-dificultad.md](../../decisiones/2026-10-22-dificultad.md).

## 1. Regla: una sola dificultad

El modo Empresa tiene **una** dificultad. No hay "empresa chica / mediana / grande" ni niveles fácil / normal /
difícil. Lo que en otros juegos hace la dificultad acá ya lo hacen tres cosas que existen:

| Qué ajusta el esfuerzo | Cómo | Dónde |
|---|---|---|
| **La tripulación** | Pedidos por día (`ORDERS_BASE_PER_DAY` + `ORDERS_PER_PLAYER`, tope 16), ayudas del modo solo, parámetros de los eventos por tramo 1 / 2 / 3-4 / 5-8 | [roles-tripulacion.md](roles-tripulacion.md) §6, [eventos-del-dia.md](eventos-del-dia.md) §2.5 |
| **El día de campaña** | Pedidos de 1-2 productos los primeros 3 días, 0 eventos los días 1-3, distritos que se abren con hitos | [economia.md](economia.md), [hitos.md](hitos.md), [distritos.md](distritos.md) |
| **La empresa en rojo** | 60 % de los pedidos y solo eventos positivos hasta salir del pozo; sin reinicio | D-0510, [eventos-del-dia.md](eventos-del-dia.md) §2.1 |

Por qué una sola (detalle en la decisión):
- **Balance de una sola curva.** `sim_economy` (D-0540) y los bots de D-2016 / D-2024 miden una economía. Tres
  tamaños de empresa son tres curvas de 20 días, tres juegos de hitos y tres tablas de precios para un equipo de 2
  (crítica de alcance, [critica-alcance.md](critica-alcance.md) §4.5).
- **Coop que entra y sale.** El esfuerzo ya sigue a la cantidad de gente conectada. Un nivel elegido al crear la
  empresa no sabe si mañana juegan 1 u 8.
- **El castigo ya es suave.** No hay game over (quiebra = 60 % de pedidos), las multas de eventos no dejan la caja
  en negativo y el alquiler a 1 jugador deja +100 el día 1. Un modo "fácil" no tendría qué sacar.

## 2. Los modificadores

Dos interruptores de la empresa, **los dos apagados al crearla**. No son niveles: cada uno saca **una** fuente de
fricción concreta que a cierta gente le arruina el juego. No cambian precios ni constantes de la economía;
`sim_economy` (D-0540) y los bots de D-2016 / D-2024 corren con los dos apagados.

| Clave | Nombre en pantalla | Qué hace | Qué no toca |
|---|---|---|---|
| `assisted_packing` | **Armado asistido** | Al poner la cinta (`PackingStation.seal`), la mesa rellena **sola** los huecos libres de la caja y la cierra. Cobra cada celda como siempre (`FILL_COST_PER_CELL`) y gasta el relleno de la mesa. La caja queda marcada `assisted` | La caja, los productos, la etiqueta y los sellos los sigue poniendo el jugador; producto equivocado y sello faltante bajan `Q` igual. Es la única excepción a "no se automatiza armar" de [roles-tripulacion.md](roles-tripulacion.md) §6.5, y es opcional |
| `calm_days` | **Días tranquilos** | Sin eventos del día ([eventos-del-dia.md](eventos-del-dia.md)): el sorteo del host no saca ninguno, tampoco el aviso de la víspera | Los eventos de ruta del juego base (`RouteEventManager`), el proveedor, los pedidos y su ritmo. Se pierde también la ayuda de "empresa en rojo: solo eventos positivos" (no hay eventos) |

### 2.1 Armado asistido: orden de la cinta y qué vale la caja

`PackagingSupplies.pad` cobra todo o nada, y la cinta también se paga: el orden en `seal` es fijo, para que la
plata del relleno nunca deje la caja sin cerrar:
1. ¿Hay cinta en la mesa y alcanza para `TAPE_COST`? Si no, `seal` devuelve `false` sin cambiar nada (como hoy).
2. `n = min(celdas libres, relleno en la mesa, (plata − TAPE_COST) / FILL_COST_PER_CELL)`.
3. `pad(n)`; después, la cinta.
4. Si `n` fue menor que las celdas libres (faltó relleno o plata), la caja sale igual, con un aviso en la mesa
   ("Relleno insuficiente: N huecos") para que nadie la crea completa.

**Lo armado a mano sigue valiendo más en la ruta.** Rellenar todo deja `f = 0`, protección 1 y la absorción más
fuerte (0,6), y la caja nunca cuenta como floja (`free_ratio()` cuenta el relleno como ocupado). Eso le quitaría
el sentido al relleno a mano y contradice [armado-y-trampas.md](armado-y-trampas.md) ("el armado manual tiene que
valer más que el relleno automático de la partida rápida", 0,75). Por eso:
- `PackedBox` guarda `assisted: bool` (en `to_dict` / `from_dict`, porque `CompanySnapshot` compara la vuelta
  completa), y `BoxToPackage.absorption` usa como mínimo **0,75** (el relleno de la partida rápida) para esas cajas;
- `Q`, la paga y las estrellas quedan igual: el asistido no castiga el pedido, solo amortigua menos en la ruta.

**La plata:** el relleno cuesta 1 por celda y la caja de 2 a 8, así que una XL "por las dudas" sale casi gratis
con la opción. El freno real es el stock de relleno de la mesa (`SUPPLY_CAPACITY`, 30): una XL con poco producto
la vacía y el que se queda tiene que reponer. Es aceptable: la opción es para quien no quiere el encastre fino.

Por qué estos dos y no otros:
- **Armado asistido** es lo que [referencias-logistica.md](referencias-logistica.md) §7 marcó como "Adaptamos"
  (opción para el que no disfruta el encastre fino, como en *Unpacking*). Es también una ayuda de accesibilidad
  motriz: rellenar celda por celda con mando es lo más repetitivo del armado.
- **Días tranquilos** responde la pregunta abierta de [eventos-del-dia.md](eventos-del-dia.md) §7 ("si hace falta una
  opción sin eventos"): para el que quiere el bucle de negocio sin sorpresas.
- **Descartados**, cada uno porque ya está cubierto o porque rompe el balance de la única curva:
  - ventanas de entrega más largas o reloj más lento: el galpón congelado ya frena el reloj en la ruta y
    [roles-tripulacion.md](roles-tripulacion.md) §6.5 dice que no se alargan;
  - más plata inicial o alquiler más bajo: es otra curva de economía (justo lo que §1 evita);
  - trampas más suaves: las trampas ya tienen sus ayudas en el juego base (asistente de estante, `solo_assist`);
  - modo "difícil" (pedidos que vencen antes, quiebra con reinicio): sin pedido de nadie, se mira con playtesting
    (ver "Decidir al final" en `revisar/D-0127.md`).

## 3. Quién, cuándo y cómo se guarda

- **Quién:** el host. Son de la empresa, no de cada jugador (como las licencias, `2026-10-22-licencias.md`).
- **Cuándo: solo fuera de la partida.**
  - al crear la empresa, en la pantalla de empresa nueva (slots, D-0235), debajo del nombre, apagados;
  - después, desde la lista de empresas guardadas, antes de abrirla ("Opciones" en el slot).

  Nunca con la empresa abierta: así no cambia la regla de una caja a medio armar, no hace falta avisar a los
  clientes conectados y no choca con el sorteo de eventos, que se hace al cerrar el día anterior.
- **Al cargar una empresa con `calm_days` prendido** se descarta el evento ya planeado para el día que abre (y su
  línea "Mañana:"). **Al cargarla con la opción recién apagada**, ese día se sortea en `OPENING` sin los eventos
  de víspera, por el mismo camino que un guardado viejo sin plan ([eventos-del-dia.md](eventos-del-dia.md) §2.3).
- **Guardado:** `CompanyState.options: Dictionary` (`{"assisted_packing": false, "calm_days": false}`), en
  `to_dict()` / `from_dict()`. `from_dict` acepta solo esas dos claves y solo valores `bool` (lo demás se ignora,
  como `_interrupted` en `CompanySave`). Un save sin `options` carga con los dos apagados: **no hace falta subir
  la versión** de `CompanySave`. `CompanySave.list_slots()` suma `"options"` a cada slot (para los íconos de §4).
- **Red:** ningún RPC ni hecho nuevo. Las dos reglas corren en el host (armado y sorteo de eventos ya son suyos,
  [red-autoridad.md](red-autoridad.md)), y como no cambian en la sesión, al cliente le alcanza el `CompanyState`
  del snapshot de entrada (`CompanyNet`) para mostrarlas.

## 4. Dónde se ve

- En la lista de empresas guardadas: un ícono chico por modificador prendido (texto al pasar el foco).
- En el resumen del día y en la pausa: "Armado asistido" / "Días tranquilos" debajo del nombre de la empresa.
- En la mesa, una caja sellada a medias por falta de relleno: "Relleno insuficiente: N huecos" (§2.1).
- En la mesa de armado con `assisted_packing`: la ayuda de la cinta dice "Cerrar (rellena solo)".
- Textos con clave en `strings_ui.csv` (`UI_COMPANY_OPT_ASSISTED_PACKING`, `UI_COMPANY_OPT_CALM_DAYS` y su
  descripción `_DESC`).

## 5. Hitos, logros y récords

Los modificadores **no bloquean nada**: hitos ([hitos.md](hitos.md)), logros de Steam (D-0138) y récords cuentan
igual. Es un coop de amigos sin tabla de posiciones; marcar o separar partidas "asistidas" castiga al que lo
necesita y suma código. Si el lanzamiento suma una tabla de posiciones (hoy no está en el plan), se revisa.

## 6. Qué construye D-1919

| # | Qué | Test |
|---|---|---|
| 1 | `CompanyState.options` con defaults y validación en `from_dict`; `list_slots()` con `"options"` | `test_company_state` (save viejo sin la clave → apagados; clave desconocida o no bool → ignorada) y el de slots |
| 2 | `PackingStation.seal` con `assisted_packing`, en el orden de §2.1, y el aviso de relleno insuficiente | test de la mesa: caja con 3 huecos → sellada, `fill_ratio() == 1.0`, 3 celdas cobradas; plata justa para la cinta → sella sin relleno; sin cinta → `false` sin cambiar nada |
| 3 | `PackedBox.assisted` (ida y vuelta de `to_dict`) y absorción mínima 0,75 en `BoxToPackage` | test del puente: la misma caja rellena, asistida y a mano, da 0,75 y 0,6 |
| 4 | Sorteo de eventos (D-0123 / su constructor): con `calm_days` no sale ninguno; al cargar, se descarta o se sortea el día como §3 | test del sorteo con la semilla de un día que sí saca evento |
| 5 | Pantalla de empresa nueva y "Opciones" del slot (host), íconos, textos y foco con mando | captura con `revisor-visual` |

El orden es libre: 1 primero; 2-3 y 4 son independientes. Si el sorteo de eventos todavía no existe cuando se
construye D-1919, el punto 4 se agrega a la tarea que lo construya.
