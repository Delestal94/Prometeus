# Rediseño del depósito (N-319) — de galpón genérico a lobby de juego comercial

> Pedido del usuario (2026-09-30): "el galpón es muy genérico; darle detalles como un galpón de un juego
> profesional: la distribución de los espacios, las áreas importantes, los modelos genéricos; varias
> iteraciones hasta dejarlo profesional". Este documento es el objetivo de todas las iteraciones: cada
> una lo lee, hace su parte, captura con GPU (`tests/render_depot.gd`) y anota abajo qué cambió.
> Capturas de cada iteración en `D:/tmp/depot_review/iterN/` (fuera del repo).

## Diagnóstico de la línea de base (iter0, capturas con GPU)

Lo que funciona y se mantiene: el recorrido es claro (camión en el eje, zona de carga rayada), las
estanterías de pallet azul/naranja con códigos A-1…, las cajas con marca, el portón con rayas, la
estructura de cerchas y luminarias, cada estación con su color.

Lo que lo hace genérico, por orden de impacto:

1. **Velo lechoso en todo el interior.** La niebla de distancia del nivel (`level_base.tscn`,
   `fog_density 0.008`, color verdoso) y el ambiente parejo lavan el galpón: piso, paredes y techo
   son casi el mismo gris claro. Adentro no hay niebla que tenga sentido a 10 m.
2. **Luz sin intención.** Nada de pozos de luz bajo las campanas, sin sombras de contacto, sin haces
   por los tragaluces, sin zonas oscuras. El camión (el foco) es blanco sobre gris claro.
3. **Una caja vacía con todo contra las paredes.** El centro es un playón de hormigón; las estaciones
   están alineadas en el perímetro como góndolas de un comercio. No hay subdivisiones, alturas ni
   rincones.
4. **Piso de ruido gris repetido**, sin juntas de dilatación marcadas, sin desgaste de tránsito,
   manchas, marcas de ruedas ni sendas peatonales.
5. **Carteles gigantes que se pisan** (5 carteles colgantes saturados + las mismas palabras
   pintadas en flechas en el piso): compiten con el camión y tapan el techo.
6. **Estaciones pobres**: taller = alfombra gris con tres props; mostrador = barra de madera; oficina =
   cubo con ventana vacía; lockers sin uso; pizarra con texto chico y mitad vacía.
7. **Falta la capa de oficio a escala humana**: matafuegos, tableros eléctricos, cañerías, bolardos y
   protecciones de columnas, jaulas rodantes, zunchos, film, cartones apilados, basureros, botiquín,
   reloj fichero, carteles chicos de seguridad.

## Objetivo

Un **centro de distribución chico pero real**, con zonas que se leen por forma, luz y color antes que
por carteles, y un recorrido de 20-30 s del spawn al camión pasando por la pizarra y las estanterías.
Referencias: el barco de Lethal Company (un lugar con alma y oficio), la base de R.E.P.O. (luz que
marca el foco), el campamento de PEAK (estilo cartoon limpio, colores planos), Totally Reliable
Delivery Service (depósito cartoon legible). Estilo del juego: low-poly, colores planos de la paleta,
formas redondeadas y gruesas (`docs/direccion-visual.md`), nada fotorrealista.

## Planta objetivo (espacio del nodo Depot: portón en z = 0, galpón hacia +Z, 30 × 32 m)

```
                         z = 32  (pared del fondo)
 ┌──────────────────────────────────────────────────────────────────┐
 │ INGRESO / STOCK        │   CINTA Y CLASIFICACIÓN   │ OFICINA en   │
 │ pallets, autoelevador, │   mesa de empaque, jaulas │ ENTREPISO    │
 │ transpaleta (x -15..-5)│   rodantes (x -5..6)      │ (x 7..15),   │
 │                        │                           │ escalera,    │
 │                        │                           │ vidrio al    │
 │─────────── pasillo de autoelevador (amarillo) ─────│ galpón       │
 │ ESTANTERÍAS DE         │                           │──────────────│
 │ DESPACHO A y B         │   ISLA DE CONTROL         │ VESTUARIO +  │
 │ (código de estante,    │   pizarra grande + mesa   │ DESCANSO     │
 │ luz propia)            │   del despachante, spawn  │ (tabiques,   │
 │                        │   frente a ella (z≈17)    │ puerta)      │
 │───── senda peatonal (verde) ────────────────────────│──────────────│
 │ PAÑOL / SUMINISTROS    │   BAHÍA DEL CAMIÓN        │ TALLER       │
 │ (jaula de malla con    │   (andén marcado, guías,  │ (box con     │
 │ ventanilla, x -15..-9) │   topes, luz sobre el     │ media pared, │
 │                        │   camión)                 │ elevador,    │
 │                        │                           │ tablero)     │
 └───────────────────────[ PORTÓN ]──────────────────────────────────┘
                         z = 0   (sale a la ruta, -Z)
```

Esto es la intención, no un plano cerrado: la iteración 1 decide las medidas contra lo que el juego
necesita (ver "Restricciones"). Si una estación cambia de lugar, cambia su constante en
`DepotLayout` y todo lo que la usa la sigue.

### Zonas y su lectura

- **Bahía del camión** (foco): andén con topes de goma, guías amarillas en el piso, un semáforo de
  andén (rojo/verde) junto al portón, luz cenital más fuerte sobre el camión. El camión se tiene que
  leer como protagonista: contraste de piso más oscuro alrededor, no blanco sobre blanco.
- **Isla de control** (a donde mira el spawn): la pizarra de pedidos pasa a ser un tablero grande en
  un bastidor con luz propia (tira de luz arriba), una mesa de despachante con monitor, lector de
  código y portapapeles, y el piso con un rectángulo pintado donde se junta la tripulación. Los
  pedidos tienen que leerse desde el spawn.
- **Estanterías de despacho** (se mantienen, mejoran): cajas variadas en tamaño y marca, bastidores
  con numeración grande en las columnas, bandejas no vacías, luz lineal sobre el pasillo.
- **Pañol / suministros**: jaula de malla metálica con ventanilla y mostrador, estantes adentro
  (cinta, espuma, seguros), un timbre, un cartel chico de precios. Se lee como "el lugar donde se
  compra" sin cartel gigante.
- **Taller**: box con media pared y cortina de tiras o persiana, elevador de tijera o gato, tablero
  de herramientas con siluetas llenas, banco con morsa, compresor, cubiertas apiladas, manchas de
  aceite, luz de trabajo cálida. El quiosco de camión/pintura queda adentro.
- **Vestuario + descanso**: tabiques de chapa o bloque que forman un cuarto abierto al galpón, lockers
  con algunas puertas entreabiertas y ropa/cascos, banco, espejo (ya existe `DepotMirror`),
  cocinita con cafetera, microondas, heladera, mesa con tazas, cartelera de corcho legible.
- **Oficina en entrepiso**: estructura elevada con baranda, escalera, ventanal hacia el galpón; es
  la oficina del Jefe (su voz sale por la radio): escritorio, luz cálida encendida, persiana. Un
  punto de referencia alto que se ve desde casi todo el galpón.
- **Cinta y clasificación / stock**: la cinta con cajas corriendo, mesa de empaque con film y cinta,
  jaulas rodantes, pallets con film, autoelevador con su carril.

### Circulación

- **Senda peatonal verde** con bordes blancos desde el spawn a cada estación; **carril de
  autoelevador amarillo** en la parte de atrás; **cruces cebra** donde se tocan.
- Columnas en grilla con **protecciones amarillas** (ya hay en las estanterías) y bolardos en las
  esquinas de la bahía.
- Las flechas de colores del piso se reducen a la senda y a un solo cartel por zona.

### Luz y atmósfera (la mejora más barata y más visible)

- **Sin niebla adentro**: el depósito anula la niebla del nivel mientras la cámara está bajo techo
  (hay un patrón: `AcousticSpace`/`roofed_area` y `DepotMirror.disable_fog`), o baja la densidad a
  algo imperceptible en 30 m. La fachada y el exterior siguen con la niebla del mundo.
- **Ambiente más bajo y más frío**, luces de campana cálidas con alcance y **sombras** en las 3-4
  principales (con presupuesto: `WorldQuality` baja las sombras en Baja), spots cálidos sobre la
  pizarra, el mostrador del pañol y el banco del taller.
- **Haces** por los tragaluces (planos aditivos con gradiente, baratos).
- Piso de **hormigón pulido medio gris** con juntas, desgaste de tránsito en las sendas y manchas;
  paredes con zócalo de bloque pintado y chapa arriba en otro tono.

### Señalética (jerarquía)

- Un cartel por zona, más chico, con **pictograma + palabra** y el color de la zona, colgado sobre la
  zona (no todos juntos frente al spawn). Los códigos de estante siguen grandes.
- Carteles chicos de oficio: "USE CASCO", "VELOCIDAD MÁX. 10 km/h", "SALIDA DE EMERGENCIA", rutas de
  evacuación, matafuegos numerados. Todo por `tr()`.

### Kit de modelos nuevos (Blender, `assets/tools/build_depot_props.py`, mismo estilo)

Bolardo, protección de columna, matafuegos con gabinete, tablero eléctrico con caños, bandeja de
cables, jaula rodante, pila de cartones plegados, rollo de film, zunchadora, basurero de reciclaje,
botiquín, reloj fichero, dispensador de agua, heladera, microondas, mesa de despachante con monitor y
lector, semáforo de andén, topes de goma de andén, malla del pañol con ventanilla, elevador de
tijera, compresor, morsa, cortina de tiras, escalera y baranda del entrepiso, persiana de oficina,
cartel de pictograma genérico. Cada uno low-poly (props chicos de primer plano ~300-800 tris),
paleta del depósito, pivote en la base, nombre `sm_env_depot_*`.

## Restricciones (no se rompen)

- El juego no cambia: spawns de 8 jugadores, `DepotLayout.TRUCK_BAY`, `TRUCK_CLEAR_Z`, el portón,
  los códigos de estante y sus slots (`Depot` reparte los pedidos por slot), las `DepotStation` con
  sus `station_id` (lockers, workshop, supplies, board), el espejo, la radio del Jefe, la pizarra de
  campaña. Si algo se mueve, se mueve su constante y los tests que lo miden.
- Rendimiento: todo lo estático va por `DepotKit` (lotes por material); `bench_depot.gd` no puede
  empeorar más de ~10 %; luces con sombra contadas (Compatibility).
- Tests: `test_depot`, `test_start_yard`, `test_depot_campaign_board`, `test_depot_mirror`,
  `bench_depot` y los que usen `DepotLayout` siguen verdes; si una medida cambia a propósito, el test
  se actualiza y se dice por qué.
- Personajes: los cuerpos de los operarios son de Slatex (S-311): no se modifican sus modelos ni
  clips; se pueden mover, girar y darles un prop.

## Iteraciones

| Iter | Qué | Quién |
|---|---|---|
| 1 | Luz y atmósfera (sin niebla adentro, pozos de luz, sombras, piso y paredes), planta por zonas (mover estaciones, subdivisiones, entrepiso como volumen), sendas y señalética nueva | `constructor-mundo` |
| 2 | Kit de modelos nuevos en Blender y reemplazo de primitivas | `modelador-blender` → `constructor-mundo` |
| 3 | Estaciones a fondo (pañol, taller, vestuario/descanso, isla de control, oficina) y capa de oficio | `constructor-mundo` |
| 4 | Pulido con la crítica de `director-arte`: color, desgaste, detalle, lo que falte | según la crítica |

Cada iteración termina con capturas de `revisor-visual` (GPU) y la crítica de `director-arte`, y
anota abajo qué cambió y qué quedó.

## Registro de iteraciones

### Iteración 1 (2026-09-30, rama `nacho/N-319-depot-redesign`, N-319.1) — luz, planta por zonas, sendas y señalética

Capturas con GPU (`tests/render_depot.gd`, clima `nublado_dia` forzado con `-- --mood=nublado_dia`) en
`D:/tmp/depot_review/iter1/`; la línea de base está en `D:/tmp/depot_review/iter0/` (clima al azar) y las variantes de
clima (sol, noche, niebla al atardecer) en `D:/tmp/depot_review/iter1/moods/`. Vistas nuevas en `SHOTS`:
`control_island`, `supplies_cage`, `office_mezzanine`, `overview_back`, `spawn_view_game` y `spawn_view_left_end` (con el
campo de visión real del juego, 82°: `SHOTS` admite un cuarto elemento con el FOV).

**Luz y atmósfera** (`depot_lighting.gd`, `depot_atmosphere.gd`, `DepotKit.light_pool/stain`)
- Sin velo lechoso adentro: `DepotAtmosphere` mezcla el `Environment` del nivel mientras la cámara está bajo el techo
  (`fog_density` ×0,1, `ambient_light_energy` ×0,85, la parte del ambiente que viene del cielo ×0,3 con un tinte cálido:
  el cielo azul lo dejaba cian) y lo devuelve al salir. Sin tocar `level_base.tscn`. Una prueba de punto por frame y nada
  más cuando la mezcla se asentó.
- Luces reales: 5 (spot sobre el camión, sobre los estantes y sobre el empaque con sombra, spot cálido sobre la pizarra,
  relleno suave del centro) + la lámpara del taller y la del espejo: 7 en total, una más que antes (el renderer
  Compatibility corta las luces por malla y el galpón son lotes grandes). Las sombras de los tres spots grandes las
  reparte `WorldQuality` (clave nueva `shadowed_lights`: Baja 0, Media 1, Alta 3).
- Falsos baratos: un pozo de luz aditivo bajo cada campana y uno por zona cálida (pañol, taller), un haz por cada
  tragaluz con su mancha en el piso (dirección e intensidad del sol del nivel; casi nada de noche), y los tragaluces y
  ventanas en tiras apagados de noche.
- Piso de hormigón gris medio con juntas oscuras, huellas del autoelevador y del camión, rozaduras y manchas de aceite;
  paredes en capas (zócalo oscuro, bloque pintado, chapa clara hasta pasar las ventanas, chapa oscura arriba).

**Planta por zonas** (`depot_zones.gd`, todo con cajas de `DepotKit` por ahora)
- Isla de control frente al spawn: la pizarra ahora mide 4,4 × 2,7 m, con bastidor, tira de luz y texto grande (se lee
  desde el spawn), escritorio del despachante con monitor, lector y portapapeles, y piso pintado; bolardos en las
  esquinas de la bahía.
- Bahía del camión sobre una losa sellada más oscura (el camión ya no es blanco sobre blanco), con guías, bolardos y
  chevrones; rectángulo de la tripulación pintado alrededor de los spawns.
- Pañol (`SHOP_CAGE`, `SHOP_STATION`): jaula de malla al frente a la izquierda con ventanilla y mostrador hacia la bahía,
  estantes con los insumos, pallet de reposición, timbre; el empleado se mudó adentro. La estación `shop` sigue
  siendo la misma, con otra posición.
- Taller: media pared de bloque con tapa roja, postes y dintel, faldón de tiras sobre el hueco por donde se llega al
  kiosco, luz de trabajo cálida.
- Vestuario y descanso: tabiques de chapa con puerta hacia el galpón, en verde azulado; la estación `wardrobe`, el
  espejo, los lockers y la cocinita no se movieron.
- Oficina en entrepiso (`MEZZANINE`): plataforma de acero sobre columnas a 2,9 m con borde amarillo y negro, barandas,
  escalera abierta con rampa de colisión (se puede subir), oficina vidriada con persiana y luz, terraza con banco, y
  pallets en la penumbra de abajo. El despachante trabaja arriba.
- Autoelevador: carril amarillo a lo largo de la izquierda (`FORKLIFT_LANE_*`), con topes de rayas.

**Sendas y señalética**
- Sendas peatonales verdes de 1,3 m con bordes blancos (`depot_circulation.gd`): la columna vertebral detrás de la zona
  de carga, el pasillo entre estantes, el camino al pañol, el del taller y el de la escalera; cuatro cruces cebra (dos
  sobre el carril del camión, dos sobre el del autoelevador).
- Las flechas del piso con su palabra (5 carteles en el piso) se redujeron a una flecha chica por zona, de su color,
  sobre la senda. Los carteles colgantes son un 15 % más chicos (`hanging_sign(..., size)`, `DepotHall.SIGN_SIZE`) y
  cuelgan sobre su zona: pizarra, camión → portón, taller, vestuario, suministros, oficina, estantes A y B. Las
  claves `WORLD_DEPOT_SIGN_SHELVES/LOCKERS/SUPPLIES` (los carteles con flecha frente al spawn) ya no se usan y se
  borraron de `strings_world.csv`.

**Costo**
- `bench_depot` (headless, costo de scripts): sin cambio dentro del ruido (frame 1,28-1,39 ms contra 1,38-1,68 ms
  antes, `packages + HUD` 0,18-0,26 contra 0,18-0,24 ms; nodos 13 037 → 13 107). Lo único nuevo por frame es el
  `_process` de `DepotAtmosphere`.
- GPU real (RTX 4060 Ti, 1280 × 720, clima `nublado_dia`, cuatro vistas del galpón), con sombras apagadas: llamadas de
  dibujo +2 % a +11 % (5 584 → 5 853 desde el spawn, 713 → 734 en el pasillo derecho), tiempo de frame igual dentro
  del ruido. Con las sombras de Alta (tres spots) las vistas de adentro suman entre +40 % y +90 % de llamadas de dibujo:
  cada spot con sombra vuelve a dibujar los ~170 lotes del galpón. Por eso Media tiene 1 y Baja ninguna; si hace
  falta, bajar `shadowed_lights` de Alta a 2.
- Lotes estáticos de `DepotKit`: 137 → 170 (materiales nuevos); meshes directos del depósito 154 → 185.

**Decisiones y cambios a propósito en los tests**
- `test_depot`: carteles legibles desde el spawn 4 → 3 (los de zona cuelgan sobre su zona) y flechas a menos de 11 m del
  spawn en vez de 7 (van en las sendas). Motivo en su encabezado.
- `test_depot_zones` (nuevo): spawns, bahía y estaciones en su lugar, la pizarra mirando al spawn, sendas libres, la
  rampa de la escalera y la terraza, aire (niebla y ambiente adentro y afuera, y al irse el depósito), luces y
  presupuesto de sombras por nivel, carteles chicos, lotes.
- `test_render_budget` (módulo): rango de sombra por nivel.

**Qué queda para la iteración 2** (y siguientes)
- Reemplazar las primitivas por modelos (`assets/tools/build_depot_props.py`): bolardos y protecciones de columna,
  escalera y barandas del entrepiso, malla y ventanilla del pañol, escritorio con monitor, persiana, cortina de tiras,
  topes de andén, matafuegos, tableros eléctricos, jaulas rodantes, cartón plegado, film, zunchadora, basurero,
  botiquín, reloj fichero, dispensador, heladera, microondas, semáforo de andén, elevador de tijera, compresor, morsa.
- Las campanas y los tubos siguen siendo los modelos de antes; la estructura de techo y las cerchas casi no se ven
  (negro verdoso): conductos, bandejas de cable y un poco de luz rasante arriba.
- El centro del galpón (entre el spawn y el empaque) sigue vacío: jaulas rodantes, mesa de clasificación, pallets con
  film.
- El tramo de la pared izquierda entre la jaula y las estanterías (z 9-12) está pelado.
- Las oficinas y el pañol por dentro son cajas: la oficina del Jefe necesita su ventanal cálido y su persiana de verdad.
- Los pozos de luz y las manchas son sutiles; con modelos nuevos hay que revisar el balance.
- Falta la capa de oficio chica: carteles de seguridad (casco, velocidad máxima, salida de emergencia, evacuación),
  matafuegos numerados, botiquín, reloj fichero.
- Lo que no se vio todavía con la crítica de `director-arte`: color y desgaste en general.

### Iteración 2, paso 1 (2026-09-30, rama `nacho/N-319-depot-props`, N-319.2) — kit de modelos en Blender

`modelador-blender` armó el kit en `assets/tools/build_depot_props.py` (sección "N-319.2 kit", grupos `ceiling dispatch
bay logistics office cage safety breakroom workshop`): 40 GLB `sm_env_depot_*` en `models/environment/depot/`, con la
lista corregida por `director-arte` (calzas y tope de rueda en vez de topes de andén, una cocinita en vez de microondas,
cafetera y pava sueltos, sin zunchadora, la cortina de tiras queda como material; se sumaron escalera de ruedas, cono y
valla de piso mojado y el marco de ventana con parteluces). Todavía **no están conectados al juego**: los pone
`constructor-mundo` en el paso siguiente. Renders de revisión en `D:/tmp/depot_review/iter2/blender/`.

**Convenciones del kit** (las necesita `constructor-mundo`)
- Frente hacia −Z, origen en el centro de la base. Las piezas de pared tienen la espalda en z = 0 y salen hacia −Z; su
  origen está en el piso bajo ellas, así que ya vienen a su altura de montaje (matafuegos 0,9, tablero 1,1 con caños a
  3,4, botiquín 1,35, reloj fichero 1,2). Las de techo cuelgan de su origen: campana (gancho, aro a 1,05 m), tubo lineal
  (centro del artefacto), conducto recto de 3 m y codo (sobre el eje; el codo tiene bocas en (−0,9, 0, 0) y (0, 0, 0,9)),
  bandeja de cables de 3 m (fondo de la bandeja).
- Tramos que se repiten cada 1,2 m con una sola pieza de cierre: `railing_segment` + `railing_post`, `window_frame` +
  `window_mullion`, `cage_panel`. La escalera coincide con `_build_stair()` (16 escalones, 2,9 m de alto en 4,6 m hacia
  +Z, 1 m de ancho, origen en el primer contrahuella).
- Nodos con nombre para el juego: `LampDisc` (emisivo) y `LampHalo` (alfa 0,35) en la campana; `DoorLightRed` (X roja) y
  `DoorLightGreen` (flecha verde) en el semáforo del portón, materiales `signal_red`/`signal_green`; `FilmShell`
  (material `film`, alfa 0,35 con brillo) en el pallet filmado; `SignPlate` (material `sign_plate`, para teñir) y
  `Pictogram` en el cartel.
- Cartel de pictograma: `Pictogram` está mapeado a la celda 0 de `textures/depot/tx_depot_pictograms_512.png` (4 × 4
  celdas de 128 px, blanco sobre transparente). Para otro, desplazar la UV `(col, fila) × 0,25`, en este orden: casco,
  chaleco, velocidad, salida, matafuegos, botiquín, punto de reunión, montacargas, manos, no fumar, eléctrico,
  evacuación.
- La malla del pañol y de las jaulas rodantes es una textura alfa de rombos de 25 cm (`tx_depot_cage_mesh_256.png`,
  corte alfa), no barras finas.
- Materiales: nombres de la paleta para que `DepotKit` los agrupe; nuevos solo `film`, `lamp_halo`, `lamp_disc`,
  `cage_mesh`, `sign_pictogram`, `sign_plate`, `signal_red` y `signal_green` (los lotes de `DepotKit` están en 170: no
  pasar de ~190 al conectarlos).

### Iteración 2, paso 2 (2026-10-01, rama `nacho/N-319-depot-finish`, N-319.2) — pasada de luz y pintura, kit conectado

Capturas con GPU (`tests/render_depot.gd`; ahora acepta `-- --out=<carpeta> --only=a,b --mood=... --sun=<energía>`) en
`D:/tmp/depot_review/iter2b/` (21 vistas, clima `nublado_dia`) y `iter2b/moods/<clima>/` (overview, spawn_view_game y la vista
nueva `center_eye_level`, ojos en (0, z 17) mirando +Z, en soleado_dia, nublado_dia, niebla_atardecer y soleado_noche).

**Decisión de luz** (delegada por el usuario, crítica de `director-arte`): el interior tiene su luz casi fija; el clima solo
se nota en tragaluces, ventanas y portón.
- `DepotAtmosphere`: bajo el techo cada valor es `base x (1 - 0,8) + interior x 0,8` (reversible, así que sigue
  recuperando la base si `WorldMood` cambia el `Environment`): ambiente 0,25 de color gris azulado frío, sin aporte del cielo
  (el cielo claro era lo que lavaba el galpón y teñía de cian) y las sombras del sol pasan de 0,85 a 1,0 (el 15 % que se
  colaba por el techo subía el piso de los días claros). Al salir todo vuelve.
- `DepotHall.build_sun_shield()`: cuatro losas gruesas que solo proyectan sombra (techo y paredes laterales y del fondo)
  cierran las fugas del sesgo de sombra del sol del nivel contra un techo de 22 cm.
- Pozos de luz x1,6 (alfa 0,18) y disco de las campanas a 3,6; haces rehechos (`DepotLighting.build_shafts`): cuatro caras
  por tragadero, perfil transversal que muere en los bordes (textura), tenues al salir del techo, máximo a 40 % de la
  caída y nulos al piso; pico por clima 0,25 sol / 0,12 nublado / 0,06 lluvia / 0,09 niebla, nulo de noche, y cada cara
  lleva la mitad (se ven dos una detrás de otra). Vidrio de tragaluces y ventanas celeste grisáceo (`glass_look`),
  atenuado por clima y hora.
- Chapa a media altura #8a938f y la de arriba #5d6669; techo gris neutro #585858; cerchas, columnas y largueros en INK;
  marcos oscuros alrededor de los tragaluces.

**Pintura y carteles** (`depot_circulation.gd`, `depot_labels.gd`)
- Sendas de 1 m en verde apagado #4f8a6a con bordes y cebras en MARKING #d4d9c2 con textura de desgaste; flechas de zona de
  0,6 m al 50 % (material `DepotKit.tint`); sin la flecha grande a la pizarra (el tablero se ve desde el spawn; su entrada
  salió de `FLOOR_GUIDES` y de `test_depot`). Reunión: contorno discontinuo amarillo de 10 cm y tres personas estarcidas,
  sin relleno.
- Carteles colgantes "etiqueta de envío": chapa INK, texto PAPER en Lilita One, lengüeta del color de la zona (25 %) con
  el pictograma del atlas (`DepotLabels.pictogram`: un cuadrado con la UV de su celda y el color por vértice, todos en un
  solo lote `DepotKit.pictograms()`), línea de corte punteada. Sin el "OFICINA" chico de la puerta.

**Kit conectado** (todo por `DepotKit.model()`, los colisionadores quedan como estaban)
- Techo: campanas `bay_lamp_bell` sobre la bahía (con disco y halo propios), `tube_linear` sobre los estantes (el tubo que
  parpadea conserva su artefacto viejo), dos conductos y una bandeja en piezas de 3 m (x −7,6 y 12,6; bandeja en x 0), todo
  entre los cordones de las cerchas.
- Paredes y pisos: marcos de ventana (tres de 1,2 m por ventana), protecciones de columna, bolardos de la bahía, topes de
  rueda y calzas, persianas de la oficina, escalera y barandas del entrepiso (tramos de 1,25 m estirados), mesa del
  despachante.
- Pañol: paneles de malla de rombos y ventanilla del kit (`CAGE_WINDOW` 4,25-6,55 para su ancho); sin la franja violeta.
- Taller: compresor, banco con morsa contra el portón, elevador de tijera en el centro del piso, cono y cartel de piso mojado.
- Descanso: cocinita, heladera, dispensador y reciclaje en fila sobre la pared este.
- Portón: semáforo del kit adentro y afuera (`DepotRollerDoor._build_signal_lights`): X roja con el portón cerrado o en
  movimiento, flecha verde solo del todo abierto.
- `depot_props.gd` (nuevo): el centro del galpón (dos jaulas rodantes con carga, mesa de clasificación, pallet filmado,
  flat-packs y escalera de ruedas, a más de 10 m del camión y fuera de la reunión y las sendas), la pared izquierda z 9-13
  (tablero eléctrico con la bandeja, gabinete de matafuegos, botiquín, reloj fichero) y carteles chicos de pictograma
  (salida, eléctrico, botiquín, velocidad, casco).

**Costo**: lotes de `DepotKit` ("Depot" + "Lamps") 170 → 184 (tope ~190), meshes directos del depósito 202 (tope del test
220). `bench_depot` mismo equipo, antes y después: tiempo de frame 6,88-6,90 ms contra 6,88-6,90 ms (limitado por el
vsync), `packages + HUD` 0,27-0,33 contra 0,31-0,37 ms (ruido); nodos 13 162 → 13 588 (las dos luces del portón son
escenas). Los GLB no suman nodos por pieza: se funden en los lotes.

**Tests**: `test_depot` (se quitó la flecha a la pizarra; arreglado el `SCRIPT ERROR` del reloj: los punteros están en
`WallClock`, no en `Depot`), `test_depot_zones` (aire fijo y sombras, haces y vidrio por clima, losas de sombra, medidas
de pintura, carteles, semáforo del portón, centro y pared, atlas en un lote, tope de lotes).

**Qué queda**: el centro y los carteles de seguridad se juzgaron solo en captura; el pozo de la cocina y la oficina del Jefe
(ventanal cálido) son de la iteración 3; sombras de contacto bajo los props nuevos y polvo en los haces, de la 4.

### Iteraciones 3 y 4 (2026-10-01, rama `nacho/N-319-depot-finish`, N-319.3 y N-319.4) — color, estaciones, desgaste y oficio

Lista final de `director-arte` (color y temperatura, oficina, pictogramas, taller, isla, pañol, descanso, carteles, sombras de
contacto, desgaste, polvo, portón del fondo, mural). Capturas con GPU en `D:/tmp/depot_review/iter3/` (las 22 vistas, con
`workshop_bench` nueva, en `nublado_dia`) y `iter3/moods/<clima>/` (overview, spawn_view_game y center_eye_level en
soleado_dia, nublado_dia, niebla_atardecer y soleado_noche). Los modelos y las texturas de esta pasada los hicieron otros
agentes (rama `nacho/N-319-depot-assets`, ya mezclada): acá solo se conectan.

**Color (I1)**: el gris azulado frío se fue. Ambiente interior neutro cálido #9c978f; campanas, spots y pozos en #ffdcb0 (alfa
del pozo 0,22); los haces y sus manchas son lo único frío (#d6e6ef); chapa de pared y bloque menos verdes; sendas #559472;
las lengüetas de los carteles son `unlit` (el color de la zona es el color en pantalla) y los amarillos del kit (`warning`,
`ui_yellow`: bolardos, protecciones, postes, carteles de piso) llevan una emisión de 0,7 para no quedar oliva bajo la luz baja
(`DepotKit._glowing_yellow`).

**Oficina del Jefe (I2)**: ventanal emisivo #ffd9a0 (energía 1,3, un lote) siempre prendido, persianas del kit, escritorio a 0,8
m del vidrio con el monitor de espaldas y la lámpara del kit (silueta desde abajo), pozo cálido de 3 x 2 m en la terraza y
cartel con el teléfono. Es la tercera cosa más brillante después del camión y la pizarra en los cuatro climas.

**Pictogramas (I3b)**: celdas 12-15 del atlas (`ICON_WRENCH`, `ICON_OPEN_BOX`, `ICON_HANGER`, `ICON_PHONE`): taller llave,
suministros caja abierta, vestuario percha, oficina teléfono; la cruz queda para el botiquín. Sin cartel colgante PIZARRA (la
pizarra encendida ya es lo más brillante; `test_depot` pide 2 carteles legibles desde el spawn en vez de 3, por eso).

**Taller (I4)**: media pared opaca de bloque #5f6763 con franja roja de 10 cm (#b8443a) y vidrio hasta 2,3 m; cortina de tiras
ámbar; banco con los dos tableros de herramientas del kit y el tablero de muestras del kit encima (nada flotando); pozo ámbar
(#ffb060, 1,6 m de radio) sobre el banco; mancha de aceite bajo el elevador; las cubiertas son el `tire_stack` del kit.
**Isla (I5)**: lámpara del kit con pozo #ffe2b8, corcho del kit con portapapeles y hojas colgado por brazos del poste, tira de
luz de la pizarra +20 %, items de la pizarra en Nunito Bold (`DepotLayout.body_bold()`, eje `wght` 700).
**Pañol (I6)**: piso de goma #2a2c30 (sin violeta), estantes con cajas entre los insumos, cartel VENTANILLA con la caja abierta
sobre el tablero del kit (clave `WORLD_DEPOT_WINDOW`), timbre del kit.
**Descanso (I7)**: sin la etiqueta CAFÉ flotante (se borraron las claves muertas `WORLD_DEPOT_COFFEE`, `WORLD_DEPOT_BOARD` y los
cuatro `..._BODY` de los carteles), pozo cálido sobre la cocinita, tazas, imanes y foto del kit en la heladera, dos lockers
entreabiertos con chaleco y casco del kit; el corcho de "NUESTRAS ENTREGAS" usa `tx_depot_cork_photos.png` de fondo (las fotos
del equipo se pinchan encima; con el fondo puesto no se muestra la nota de "vacío"); "EQUIPO DEL MES" con la foto
`tx_depot_employee_month.png` (el texto queda como estaba, más angosto, a la izquierda de la foto).
**Carteles chicos (I8)**: pictograma grande y título, sin cuerpo (los cuatro carteles de pared comparten un solo `DepotKit`).

**Sombras de contacto (I9)**: UN lote multiplicativo (`DepotKit.contact_material()`, `GradientTexture2D` radial de 64 px al 45 %
que muere en el borde; la mezcla multiplicativa ignora el alfa, así que el sombreado va en el color) bajo bolardos,
protecciones, estantes, jaulas, mesas, pallets, escritorio, pie de la escalera, elevador, compresor, banco, cocinita, heladera,
dispensador, reciclaje y lockers.
**Desgaste (I11)**: UN lote de alfa con color por vértice (`DepotKit.wear_material()`): manchas suaves por losa (unos pocos
puntos de valor, no son cuadrados parejos), suciedad de 40 cm al pie de las tres paredes (#2b2f33 al 35 %), bordes de senda
comidos en los cruces, óxido y raspones al pie de bolardos y protecciones; mancha de aceite bajo el camión.
**Polvo (I12)**: diez motas de 2,5 cm por haz (`DepotLighting.build_dust`), con la intensidad atada al pico del haz y ninguna de
noche ni en Calidad Baja; salieron las 90 motas sueltas.
**Flechas (O15)**: solo en las bifurcaciones (cuatro, cada una donde su rama sale de su camino); `test_depot` apunta la de los
estantes por el pasillo.
**Portón del fondo (O14)**: portón de recepción cerrado detrás de la cinta (x −11): las lamas del kit al ras de la pared, jambas
con rayas y dintel (sin marco hondo, que cortaría la cinta). **Mural (I10)**: `tx_depot_mural_brand.png` de 8 x 1,6 m a 5,3 m de
altura, centrado (`DepotProps.MURAL`; no se dibuja si falta el archivo); el reloj se mudó a x 5,9 para dejarle lugar.
**Afuera (O16)**: la mancha gris verdosa del cielo de `door_closed` era la sombra de las nubes (se mezclaba con el verde de la
niebla del nivel): ahora es el color de la nube oscurecido (`RouteSky._neutral_cloud_shade`); la línea de salida de la ruta
pasó de cian a pintura gastada (`route.gd START_LINE`).
**Accesibilidad**: el tubo que parpadea no pasa de 3 destellos por segundo (antes hasta 16); los reciclajes del kit tienen las
bocas distintas (lo dijo el modelador; no lo verifiqué en cámara).

**Costo**: lotes de `DepotKit` ("Depot" + "Lamps") 182 (tope 190; hubo que unificar la malla de rombos de las tres piezas que la
usan y reusar materiales ya existentes), luces reales 7. `bench_depot` en este equipo (muy cargado durante la medición):
frame 7,2 ms contra 6,9 ms (+4 %, vsync y ruido); no hay script nuevo por frame.

**Retoques finales (pedidos tras la crítica de `director-arte`)**
- El corcho "NUESTRAS ENTREGAS" muestra `tx_depot_cork_photos.png` entera (su propio quad de 1,8 x 1,2 m con la proporción 3:2 de la
  textura, no un `BoxMesh`, cuyas UV recortaban la imagen); las fotos del equipo la reemplazan cuando existen. Captura de cerca:
  `final/depot_photo_wall.png`.
- "EQUIPO DEL MES": se borró el párrafo de estadísticas (y sus claves `WORLD_DEPOT_TEAM_STATS`, `_NEXT` y `_ALL_UNLOCKED`); la placa
  tiene el título, la foto `tx_depot_employee_month.png` de 0,9 x 1,125 m (casi el doble de lo que era, 1,8 veces: el alto de la
  placa, 1,9 m con el frente de la heladera debajo, no deja más); el nombre lo trae la foto (un rótulo aparte la contradecía y se sacó, con su clave).
- Tablero de muestras: "COLORES" (`WORLD_DEPOT_SWATCHES`) en Lilita One, INK, 4 cm, centrado en la franja y a 0,5 mm de la cara.
- `render_depot.gd`: `overview` desde x 10,6 mirando 8 grados más a la derecha (la campana ya no tapa la T del mural; quedan el
  ventanal de OFICINA y el camión); `center_eye_level` 7 grados hacia arriba; `lockers_and_break` 1,5 m más cerca de la cocinita y 7
  grados hacia arriba; vistas nuevas `workshop_bench` y `photo_wall`; opciones `--out`, `--only`, `--mood`, `--sun`, `--bias`.
  El script esconde las fotos del equipo de `user://` y muestra el corcho de fábrica.
- Capturas finales a 1920 x 1080 en `D:/tmp/depot_review/final/` (las 10 vistas más `photo_wall`) y `final/moods/<clima>/` (spawn_view_game,
  overview y center_eye_level en soleado_dia, nublado_dia, niebla_atardecer y soleado_noche).
- **Medición del bolardo, corregida**: el ~36 % que figuraba antes estaba mal medido (era la banda negra). `director-arte` midió el
  cuerpo amarillo en 47 grados, 61 % de saturación y 80 % de valor (79 % de noche): cumple.
- **Para quien capture**: una toma de `lockers_and_break` hecha en los primeros segundos de la escena (la primera o la segunda de una
  corrida) sale con paredes y piso del vestuario en gris liso: es el espejo (`DepotMirror`) activándose recién empezada la escena en
  el driver de GL Compatibility (escondiéndolo, el cuadro sale bien; la misma toma sale bien más adelante en una corrida larga). Es de
  las capturas, no del contenido; si se ve en el juego hay que abrir tarea.

**Qué no quedó** (la reja en X de la campana ya la resolvió el modelo, con su aro de 3 radios): el encabezado del tablero de muestras
y los carteles chicos de seguridad con más palabras; las bocas distintas de los reciclajes no se verificaron en cámara.

### Cierre (2026-10-01, rama `nacho/N-319-depot-finish`) — crítica final y textos que faltaban

Capturas con GPU sobre `main` (con el #145 ya mezclado) en `D:/tmp/depot_review/iter5/` (las 29 vistas) y las retocadas en
`iter5b/`. **Crítica (estilo `director-arte`, contra el "hecho cuando")**: ya no es un galpón genérico. Desde el spawn se lee la
jerarquía camión → pizarra → zonas; cada zona tiene su forma (jaula del pañol con su ventanilla, box del taller con media pared
roja, vestuario con lockers y descanso con cocinita, oficina en entrepiso con ventanal cálido y escalera), su luz (pozos cálidos,
penumbra entre zonas, haces fríos) y un cartel chico; el piso cuenta el recorrido (sendas, carril amarillo, cebras, flechas solo
en las bifurcaciones) y hay capa de oficio en todos lados (bolardos, protecciones, tableros, matafuegos, cinta, autoelevador,
operarios). Lo que todavía se veía "sin terminar" eran textos que el arte había dejado en blanco, y se arreglaron:
- **Tablero de muestras**: la franja de arriba es `sign_ink` (oscura) y la palabra iba en INK, así que no se veía. Ahora dice
  "COLORES DEL CAMIÓN" (`WORLD_DEPOT_SWATCHES`) en PAPER, 4,6 cm.
- **Carteles de seguridad con palabra**: los cinco pictogramas de pared (salida, alta tensión, botiquín, 10 km/h, casco) llevan
  debajo una tira del mismo color (en el mismo lote) con su palabra (`WORLD_DEPOT_SAFETY_*`, un `Label3D` cada uno, grupo
  `depot_safety_caption`).
- **"NUESTRAS ENTREGAS"**: el título iba en INK directo sobre la chapa oscura y casi no se leía; ahora va en PAPER sobre su propia
  franja INK, del ancho del corcho.
`test_depot_zones` lo comprueba. `bench_depot`: 2,08 ms de frame contra 2,41 ms de `main` en la misma máquina (ruido; paquetes y
HUD 0,216 contra 0,219 ms). Lotes de `DepotKit` sin cambio (las tiras usan el material de su placa).

**Queda (menor, sin tarea)**: los conductos del tablero eléctrico pasan por delante de la tira "ALTA TENSIÓN"; las bocas distintas
de los reciclajes siguen sin verificarse en cámara; la toma de `lockers_and_break` al principio de una corrida sale gris por el
espejo (es de la captura).
