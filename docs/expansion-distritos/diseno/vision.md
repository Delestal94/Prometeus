# Visión de la expansión: una empresa de reparto que crece (D-0101)

> Qué juego queremos que sea Take My Package con la expansión de distritos. Es el norte para las tareas
> `D-` de `docs/expansion-distritos/`: si una tarea empuja hacia algo que este documento dice que **no**
> es, la tarea está mal planteada. Fuentes: el [README de la expansión](../README.md),
> [supuestos.md](../detalle/supuestos.md), `docs/decisiones/2026-10-04-*.md` y
> `docs/definicion-proyecto.md`. Los números viven en `company_tuning.gd` y en los `.tres`, no acá.

## 1. En una frase

**Hoy** el juego es una entrega: uno maneja, los demás cuidan cada uno su caja con su trampa, y la
puerta del cliente revisa lo que llegó. **Con la expansión** es una empresa de reparto: la tripulación
recibe la mercadería, **arma** los paquetes, los lleva por un mapa que se va abriendo con vehículos
nuevos y, día tras día, convierte un galpón vacío en una operación que funciona casi sola mientras
ellos salen a las entregas difíciles.

La promesa para el jugador: *"lo que armaste en el galpón es lo que vas a sufrir en la ruta"*.

## 2. El bucle del día (5 pasos)

Un día de juego va de 08:00 a 20:00; una hora de juego son 90 s reales (día de 18 min,
`docs/decisiones/2026-10-04-expansion-decisiones-delegadas.md`, fila 3). A las 20:00 no se corta una
salida: el cierre espera que vuelva.

| # | Paso | Qué hace la tripulación | Dónde pasa |
|---|---|---|---|
| 1 | **Llega mercadería** | Un camión del proveedor entra a la dársena; se descargan palets y se guardan los productos en estanterías | Galpón (Parque Industrial) |
| 2 | **Entran pedidos** | Clientes de las zonas abiertas piden 1 a 3 productos con requisitos (frágil, frío, regalo, urgente, pesado) y una ventana de entrega | Tablero del galpón, celular |
| 3 | **Se arman los paquetes** | Caja del tamaño justo, productos correctos, relleno, cinta, etiqueta y sellos, en una grilla de celdas | Estación de armado |
| 4 | **Se despacha y se entrega** | Se carga el vehículo que pide la zona y se hace la ruta con sus peligros; cada pasajero cuida su caja; la puerta del cliente la revisa | Mapa continuo |
| 5 | **Cierre del día** | Cobros, alquiler y sueldos, reputación, hitos; con la plata se amplía el galpón, se contrata, se compran máquinas, vehículos y equipo | Pantalla de cierre |

El paso 3 es el puente: **lo que se arma define la trampa del viaje** y su intensidad
([armado-y-trampas.md](armado-y-trampas.md)). Vidrio sin relleno pega más fuerte; una caja grande con
huecos suma Equilibrio. La trampa sigue saliendo del producto; el armado mueve cuánto pega.

## 3. Cómo crece la empresa

Inspirado en *Schedule I*: el jugador pasa de **hacer cada caja** a **diseñar el galpón**.

1. **A mano (F1).** La tripulación hace todo: descarga, guarda, arma, carga y sale. Si todos salen y no
   hay empleados, el galpón se congela (decisión delegada, fila 4): nadie es castigado por ir a entregar.
2. **Empleados (F2).** Se contratan y se les asigna una estación (descarga, picking, armado, control,
   despacho) con un portapapeles que se lleva en la mano, no con un menú. Con empleados el galpón sigue
   andando aunque la tripulación esté afuera.
3. **Máquinas (F2 en adelante).** Cintas, encintadoras, etiquetadoras, clasificadores y robots.
4. **Mapa (F2-F4).** Las zonas se abren por hitos, vehículos y equipo; cada una trae su forma de llegar
   y sus peligros.

Lo que mide el progreso: **plata** (de la empresa, en `CompanyState`; supuesto S8),
**reputación** (0-100, arranca en 50) y **hitos** (D-0118) que abren zonas y licencias.

## 4. Qué se conserva del juego actual

Esto no se toca: es el corazón que ya funciona y lo que nos diferencia (`docs/definicion-proyecto.md`).

| Qué | Cómo sigue en la expansión |
|---|---|
| **Las 7 trampas** (Frágil, Peso Creciente, Equilibrio, Ruidoso, Explosiva, Hostil, Líquido) | Cada producto trae la suya por su `PackageContent` (S9); los 10 contenidos actuales son los primeros 10 productos |
| **Cuidado en el asiento** | Cada pasajero lleva su caja en las manos durante el viaje, igual que hoy (`PackageCare`) |
| **Asimetría** | Uno maneja, los demás cuidan; ahora además alguien puede quedarse en el galpón |
| **La puerta del cliente** | `DeliveryHouse` revisa el paquete como hoy; el resultado se cobra al cierre del día |
| **Mérito y cartas** | Se siguen ganando en las salidas (`CrewProgression`); la plata de la empresa es otro número (S8) |
| **Tipos de tramo** | Badén, chicana, puente, ripio, barro, obras… pasan a ser aristas del grafo de calles del Campo |
| **Entrega y Endless** | Quedan como **"Partida rápida"**, sin cambios de comportamiento; el modo Empresa es el juego principal (fila 1) |
| **Red** | Host autoritativo, hasta 8 jugadores, todos en el mismo mundo |

## 5. Qué es nuevo

- **Galpón construible**: dársena, estanterías, estación de armado, despacho; se amplía con plata.
- **Mercadería y stock**: proveedores, palets, inventario, compras para el día siguiente.
- **Armado de paquetes** en grilla (celdas de 0,2 m) con calidad `Q` de 0 a 100.
- **Pedidos de clientes** con requisitos, ventanas de entrega y penalidades por tardanza o error.
- **Un mapa continuo** (≤ 6 × 6 km, galpón cerca del centro) con zonas que se desbloquean, sin
  pantallas de carga después de la inicial (`docs/decisiones/2026-10-04-mapa-continuo.md`).
- **Flota**: vehículos nuevos con su forma de manejar y su trampa amplificada.
- **Empleados y automatización**: estaciones, sueldos, máquinas.
- **Día con reloj, cierre y guardado de empresa** con slots.

## 6. Las 9 zonas del mapa

Un solo mapa continuo con trazado fijo; cambian por semilla las casas que piden, el decorado chico, los
eventos y el clima. Misma tabla que el [README](../README.md#distritos-un-solo-mapa-continuo); la
definitiva la escribe D-0114 (`diseno/distritos.md`).

| # | Zona | Para moverse adentro | Peligros propios | Se abre con |
|---|---|---|---|---|
| 0 | Parque Industrial (galpón) | zorra, autoelevador | — | abierta |
| 1 | Barrio Centro | bici, camioneta | tránsito, calles angostas, peatones, semáforos | abierta |
| 2 | Suburbio | camioneta, carrito | perros, barrios cerrados, rociadores | barrera: hito de 25 entregas |
| 3 | Campo | camioneta | lo que ya existe (ripio, barro, animales) | calle cortada: hito de reputación |
| 4 | Puerto y Costa | camioneta | grúas, contenedores, marea | barrera portuaria: hito + licencia náutica |
| 5 | Islas | lancha; carrito en tierra | oleaje, marea, muelles, gaviotas | agua: tener la lancha |
| 6 | Montaña | avioneta para llegar; a pie/4x4 arriba | cornisas, desprendimientos, pendientes, niebla | altura: tener la avioneta |
| 7 | Nieve | 4x4 con cadenas, avioneta con esquís | hielo, frío en la carga, avalanchas, ventisca | equipo: cadenas + abrigo |
| 8 | Volcán | 4x4 hasta la base; avioneta (paracaídas) a la cumbre | calor, lava, ceniza, temblores | equipo: traje térmico + cajas térmicas, y hito final |

Cada zona tiene que **cambiar cómo se cuida la caja**, no solo el paisaje: frío en la carga, oleaje,
lanzamientos en paracaídas, calor. Una zona que solo es "otro decorado" no entra.

## 7. La flota

La tabla definitiva (asientos, carga, velocidad, qué trampa amplifica) la escribe D-0115
(`diseno/flota.md`). La idea de cada uno:

| Vehículo | Rol | Dónde brilla |
|---|---|---|
| **Camioneta** (la de hoy) | El caballo de batalla: varios pasajeros, carga media | Barrio Centro, Suburbio, Campo, Puerto |
| **Bici** | Una persona, una caja, rápida en calles angostas | Barrio Centro |
| **Carrito** eléctrico tipo golf (fila 2) | 2-4 asientos, caja abierta, batería | Suburbio, Islas en tierra |
| **Lancha** | Cruza el agua; el oleaje sacude todo | Puerto → Islas |
| **Avioneta** | Llega a la altura; aterriza en pistas de montaña, con esquís en la nieve, lanza en paracaídas en el volcán | Montaña, Nieve, Volcán |
| **4x4** | Pendientes, cadenas, base del volcán | Montaña (arriba), Nieve, Volcán |
| Zorra y autoelevador | **Herramientas del galpón**, no de reparto | Parque Industrial |

En red el host simula todos los vehículos; como máximo **2 vehículos lejos del galpón a la vez** en
F1-F3 (mapa continuo, punto 6).

## 8. La tripulación de 1 a 8

El reparto exacto lo define D-0110 (`diseno/roles-tripulacion.md`). La regla de diseño:

- **Solo o en dupla**: todo se puede hacer; el galpón se congela mientras nadie está, y los empleados
  (F2) son la forma de crecer sin más gente.
- **De 3 a 8**: aparece la decisión "¿quién se queda armando y quién sale?". Los pedidos por día
  escalan con la cantidad de jugadores (6 + 2 por jugador, tope 16; supuestos).
- Nadie mira: siempre hay una caja que alguien tiene que llevar, armar o cuidar.

## 9. Qué NO es

- **No es un simulador de tráfico.** Hay tránsito y peatones como peligro de Barrio Centro, no como
  sistema que se gestiona. No hay semáforos que programar ni rutas óptimas que calcular.
- **No es un tycoon de planillas.** Siempre hay una caja en las manos de alguien. La gestión se hace
  en el mundo (portapapeles, tableros, estaciones), no en menús con tablas. Si una decisión solo se
  puede tomar en una pantalla de números, se rediseña.
- **No es un juego de conducción.** Manejar importa por lo que le hace a la carga, como hoy.
- **No es un mundo abierto infinito.** El trazado es fijo y ≤ 6 × 6 km; se aprende y se señaliza.
- **No es un juego de supervivencia ni de combustible.** Sin nafta como costo (fila 6): el costo
  operativo es el mantenimiento.
- **No reemplaza lo que ya anda.** Entrega y Endless siguen como partida rápida, con sus tests.
- **No depende de playtesting para avanzar.** Se mide con bots y benchmarks; la gente juega al final.

## 10. Cómo sabemos que va bien

- **Corte vertical F1** (D-0111, `diseno/corte-vertical.md`): un día completo proveedor → stock →
  pedido → armado → camioneta → Barrio Centro → cierre, en gris, que el bot `bot_company_day` completa
  sin errores y dentro del presupuesto de `bench_company` (D-2011).
- **No se arranca F2** sin ese corte cerrado y medido.
- **Alcance**: D-0112 critica la expansión contra la capacidad del equipo; puede recortar o posponer lo
  que el usuario no nombró (rival, prestigio, mercado negro, kayak, helicóptero…) pero **nunca** las
  zonas, la bici, el carrito, la lancha, la avioneta, el armado, los camiones de mercadería, los
  empleados, la automatización, los desbloqueos por hitos ni los modelos nuevos (fila 5).

## 11. Fases

| Fase | Qué queda jugable |
|---|---|
| F0 — Base | Nada visible: decisiones, arquitectura, guardado de empresa, multi-vehículo |
| F1 — Corte vertical | Un día completo en gris con la camioneta y Barrio Centro |
| F2 — Crecer | Hitos, empleados, primeras máquinas, Suburbio y Campo, bici y carrito |
| F3 — Agua y altura | Lancha, Puerto, Islas; Montaña y Nieve |
| F4 — Aire y fuego | Avioneta, aeródromos, Volcán |
| F5 — Contenido y lanzamiento | Modelos finales, UI, audio, VFX, rendimiento, Steam |
