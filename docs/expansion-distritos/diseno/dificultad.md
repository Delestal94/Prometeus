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
fricción concreta que a cierta gente le arruina el juego, y no cambian ningún número de la economía.

| Clave | Nombre en pantalla | Qué hace | Qué no toca |
|---|---|---|---|
| `assisted_packing` | **Armado asistido** | Al poner la cinta (`PackingStation.seal`), la mesa rellena **sola** todos los huecos libres de la caja antes de cerrarla, con el relleno que haya en la mesa y cobrando cada celda como siempre (`PackingStation.pad`, `FILL_COST_PER_CELL`). Si falta relleno o plata, rellena lo que alcanza y cierra igual | La caja, los productos, la etiqueta y los sellos los sigue poniendo el jugador. Producto equivocado, sello faltante y caja muy grande siguen bajando `Q`. La trampa sale igual de [armado-y-trampas.md](armado-y-trampas.md); solo pesa menos el término de huecos |
| `calm_days` | **Días tranquilos** | Sin eventos del día ([eventos-del-dia.md](eventos-del-dia.md)): el sorteo del host no saca ninguno, tampoco el aviso de la víspera | Los eventos de ruta del juego base (`RouteEventManager`), el proveedor, los pedidos y su ritmo. Un evento ya anunciado para mañana se cumple: apagar la opción vale desde el sorteo siguiente |

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
  - trampas más suaves: las trampas ya tienen sus ayudas en el juego base (asistente de estante, `solo_assist`) y
    el armado asistido ya baja la intensidad por huecos;
  - modo "difícil" (pedidos que vencen antes, quiebra con reinicio): sin pedido de nadie, se mira con playtesting
    (ver "Decidir al final" en `revisar/D-0127.md`).

## 3. Quién, cuándo y cómo se guarda

- **Quién:** el host. Son de la empresa, no de cada jugador (como las licencias, `2026-10-22-licencias.md`).
- **Cuándo:**
  - al crear la empresa, en la pantalla de empresa nueva (slots, D-0235), debajo del nombre, apagados;
  - después, desde el resumen del día (D-0508), en una fila "Opciones de la empresa" que solo el host puede
    cambiar. Valen desde el día siguiente. No hay cambio a mitad del día: el armado de una mesa no cambia de
    regla con la caja abierta.
- **Guardado:** `CompanyState.options: Dictionary` (`{"assisted_packing": false, "calm_days": false}`), en
  `to_dict()` / `from_dict()`. Una clave nueva con valor por defecto: un save sin `options` carga con los dos en
  `false` y **no hace falta subir la versión** de `CompanySave` (una versión vieja del juego ignora la clave).
- **Red:** ningún RPC nuevo. Las dos reglas corren en el host (el armado y el sorteo de eventos ya son del host,
  [red-autoridad.md](red-autoridad.md)): el cliente solo necesita saberlas para mostrarlas, y le llegan con
  `CompanyState` en el snapshot de entrada (`CompanySnapshot`) y en el resumen del día.

## 4. Dónde se ve

- En la lista de empresas guardadas: un ícono chico por modificador prendido (texto al pasar el foco).
- En el resumen del día y en la pausa: "Armado asistido" / "Días tranquilos" debajo del nombre de la empresa.
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
| 1 | `CompanyState.options` con defaults, `to_dict` / `from_dict`; save viejo sin la clave carga con los dos apagados | `test_company_state` |
| 2 | `PackingStation.seal`: con `assisted_packing`, `pad()` de todas las celdas libres (`total_cells()` menos las ocupadas) antes de la cinta | test de la mesa: caja con 3 huecos y relleno → sellada con `fill_ratio() == 1.0` y 3 celdas cobradas; sin relleno, sella igual |
| 3 | Sorteo de eventos (D-0123 / su constructor): con `calm_days` devuelve "sin evento" | test del sorteo con la semilla de un día que sí saca evento |
| 4 | Pantalla de empresa nueva y fila del resumen (host), textos y foco con mando | captura con `revisor-visual` |

El orden es libre: 1 primero; 2 y 3 son independientes. Si el sorteo de eventos todavía no existe cuando se
construye D-1919, el punto 3 se agrega a la tarea que lo construya.
