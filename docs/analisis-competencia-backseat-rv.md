# Análisis de competencia: Backseat Drivers y RV There Yet?

> 2026-09-28. Investigación web sobre dos cooperativos de vehículo que salieron en
> octubre de 2025, contrastada con el diseño actual de Take My Package
> (`definicion-proyecto.md`, `jugabilidad-paquetes-rescate.md`,
> `cartas-y-eventos-de-ruta.md`, `economia-y-contramedidas.md`). Las cifras de ventas y
> reseñas son las publicadas a la fecha y cambian con el tiempo. Lo marcado como
> **(sin verificar)** sale de reseñas y guías, no de una fuente oficial.

## 1. Resumen ejecutivo

- **RV There Yet?** es el éxito de referencia del género: nació de una game jam,
  cuesta ~8 USD, vendió 1,3 M de copias en su primera semana y superó los 4,5 M.
  Su fórmula: un vehículo torpe, un terreno hostil, herramientas físicas (el
  cabrestante) y **chat de voz por proximidad**. El que maneja depende de los demás
  para avanzar.
- **Backseat Drivers** es más chico (≈78 % positivas sobre ~700 reseñas), pero su idea
  central choca con la nuestra: **roles asimétricos dentro del auto**. El conductor no
  ve y el pasajero ve pero no maneja. Nuestra definición de proyecto dice que no
  encontramos juegos con roles asimétricos: **esa afirmación ya no es cierta** y hay
  que corregir cómo nos diferenciamos (ver §5).
- Nuestra diferencia real sigue en pie: en ninguno de los dos **la carga es la
  protagonista**. Ellos tratan de *llegar* y nosotros de *llegar con algo en buen
  estado*, con trampas por paquete, reparación improvisada y un cliente que revisa la
  entrega en la puerta.
- **La brecha más grande:** no tenemos chat de voz. En los dos juegos, y en todo el
  "friendslop" (Lethal Company, PEAK), la comedia sale de la voz. Es la mejora de
  mayor impacto que surge de este análisis (§6, M-01).
- Hay otras 13 mecánicas adaptables, ordenadas por impacto y costo en §7. La mayoría
  refuerzan sistemas que ya diseñamos (kit de reparación, eventos de ruta, mérito y
  cosméticos) en lugar de agregar sistemas nuevos.

## 2. Fichas

### 2.1 RV There Yet?

| Dato | Valor |
| --- | --- |
| Estudio | Nuggets Entertainment (Skövde, Suecia). Fundadores que salieron de Coffee Stain. |
| Origen | Proyecto de game jam que se convirtió en juego comercial. |
| Motor | Unreal Engine |
| Lanzamiento | PC, 21-oct-2025. Xbox y Game Pass, 30-jun-2026. PS5 con crossplay anunciado para sep/oct 2026. |
| Precio | ~8 USD |
| Jugadores | 1–4, cooperativo online |
| Ventas | 1,29 M en 5 días; 2,5 M en 2 semanas; más de 4,5 M en total |
| Pico en Steam | ~35 000 jugadores simultáneos |
| Reseñas | Muy positivas |
| Contenido posterior | Mapa Mt. Yurbuttsk (dic-2025) y mapa final St. Búttin Bay (2026) |

**Premisa:** cuatro amigos tienen que volver a casa en una casa rodante destartalada
atravesando un valle (Mabutts Valley) sin caminos decentes.

### 2.2 Backseat Drivers

| Dato | Valor |
| --- | --- |
| Estudio | GhostJam Games + Deadcat Studios |
| Lanzamiento | PC, 9-oct-2025 |
| Jugadores | Historia para 2; modo Carpool para 4 |
| Modelo comercial | **Friend Pass** (una copia alcanza para invitar a un amigo al modo Historia) y demo separada gratis en Steam ("Free Test Drive") |
| Reseñas | ≈78 % positivas sobre ~690 (Steam); más positivas en los últimos meses |
| Críticas | Bugs de conexión y de lanzamiento. Lo recomiendan para jugar con amigos cercanos y con buena conexión. |

**Premisa:** dos inútiles en el peor auto del mundo recorren "el peor desvío del
mundo" (montañas, túneles de subte, autopistas, instalaciones secretas del gobierno).

## 3. Cómo se juega RV There Yet?

### 3.1 Bucle

Avanzar por un mapa largo y continuo con unos **12 checkpoints**. Entre uno y otro, el
terreno presenta obstáculos que el vehículo solo no puede superar: pendientes, ríos,
barrancos y barro. El equipo combina manejo, herramientas y trabajo fuera del
vehículo. En cada checkpoint se recuperan herramientas y repuestos y aparecen
cosméticos.

### 3.2 Mecánicas clave

| Mecánica | Cómo funciona | Por qué funciona |
| --- | --- | --- |
| **Caja manual con embrague** | Se cambian marchas a mano para ganar fuerza o velocidad. Sirve en curvas y pendientes. | Le da al conductor una habilidad que se aprende. Equivocarse de marcha en una subida es gracioso y queda en el recuerdo. |
| **Cabrestante (winch)** | Se engancha un cable a una superficie y un control remoto lo recoge o lo suelta. Permite llegar a lugares imposibles solo con el manejo. | Es "la estrella" según las reseñas: obliga a coordinar (uno engancha, otro maneja, otro dirige) y cuando falla falla de forma espectacular. |
| **Reparaciones** | El vehículo se rompe y hay herramientas y repuestos físicos para arreglarlo. | Si algo sale mal hay tarea para los demás, no un game over. |
| **Objetos físicos sueltos** | Las herramientas viven dentro del vehículo como objetos. Lo que queda en el piso puede desaparecer o caerse con los golpes. Guardarlas en el techo es "técnica avanzada". | La carga suelta es un riesgo emergente. Es **nuestro tema**, pero en ellos es secundario. |
| **Fauna hostil** | Osos (se ahuyentan con spray), serpientes (no mueren, se distraen tirando objetos), águilas (levantan a un jugador y lo sueltan desde lo alto). | Interrupciones que sacan a los jugadores del vehículo y crean anécdotas. Las reseñas las critican cuando son demasiado agresivas. |
| **Salud y reanimación** | EpiPen reanima a un caído, hamburguesa cura, antídoto contra la serpiente. | Da peso a salir del vehículo. En nuestro juego no aplica (§8). |
| **Voz por proximidad + walkie-talkie** | La voz se atenúa con la distancia; un objeto walkie permite hablar lejos. Pulsar para hablar con V. | La comunicación es el juego. El walkie convierte el "no te escucho" en decisión y en objeto. |
| **Cosméticos encontrables** | Gorros y lentes escondidos en checkpoints y entre ellos. | Invitan a explorar y a desviarse, sin afectar el balance. |
| **Roles emergentes** | Conductor, mecánico, operador del cabrestante, explorador. El juego no los impone: surgen de la situación. | Todos tienen algo que hacer sin tutorial de roles. |

### 3.3 Qué dicen las críticas

- **A favor:** comedia emergente, la física del cabrestante, el precio, la duración
  justa para una noche con amigos.
- **En contra:** física inestable, objetos que aparecen donde no se espera, fauna
  demasiado agresiva ("la frustración divertida pasa a ser frustración real"), casi
  sin historia ni motivación más allá de volver a casa, bugs de voz.
- **Lección:** el caos físico vende, pero el castigo sin aviso cansa. Coincide con
  nuestras reglas de justicia (`jugabilidad-paquetes-rescate.md` §"Reglas de justicia").

## 4. Cómo se juega Backseat Drivers

### 4.1 Bucle

Niveles con recorrido (historia para 2). El **conductor no ve** la ruta y maneja
según lo que le grita el **pasajero, que ve pero no puede manejar**. El auto se
desarma durante el viaje y el mundo "coopera cada vez menos".

### 4.2 Mecánicas clave

| Mecánica | Cómo funciona | Por qué funciona |
| --- | --- | --- |
| **Asimetría de información** | Uno tiene el volante y el otro, los ojos. | Convierte la comunicación en la mecánica central. Es el mismo principio que *Keep Talking and Nobody Explodes*. |
| **Indicaciones con voz de personaje** | Hay indicaciones rápidas (arriba/abajo/izquierda/derecha/parar) que cambian de voz y tono según el personaje. | Funcionan aunque no haya micrófono y cada personaje tiene su identidad. Es barato de producir. |
| **Piezas intercambiables e improvisadas** | Cada componente del auto se puede reemplazar por otro objeto: sin pedal de freno, se encaja un casete; el volante puede ser una caña de pescar. | El arreglo absurdo **es** el chiste y además funciona como mecánica. |
| **Deterioro progresivo** | El auto pierde partes durante el nivel. | La dificultad crece sola, sin crear contenido nuevo. |
| **Modo Carpool (4 jugadores)** | El conductor carga con 3 "chicos" que rompen y tiran cosas y le gritan indicaciones contradictorias. | Transforma un juego de 2 en un party de 4 con roles de **sabotaje leve**. |
| **Radio y bocina** | Se puede interactuar con la radio del auto. | Sirven para actuar y dan material para streams. |
| **Friend Pass + demo gratis** | Con una copia juegan dos. La demo es una app aparte en Steam. | Le quita fricción a un juego que necesita sí o sí a dos personas. |

### 4.3 Qué dicen las críticas

- **A favor:** la premisa se entiende en un segundo; da risa a carcajadas.
- **En contra:** bugs de conexión al lanzar ("un amigo no se puede conectar"), menos
  contenido y menos tracción que RV There Yet?
- **Lección:** una premisa muy clara no alcanza si la conexión falla la primera
  noche. Para nosotros eso refuerza el valor de la batería de red (N-207) y de las
  pruebas con amigos antes de publicar.

## 5. Comparación con Take My Package

| Eje | RV There Yet? | Backseat Drivers | Take My Package |
| --- | --- | --- | --- |
| Jugadores | 1–4 | 2 (4 en Carpool) | 1–5 |
| Protagonista | El vehículo y el terreno | La comunicación conductor↔pasajero | **La carga** (una trampa por paquete) |
| Roles | Emergentes y simétricos | Asimétricos fijos (manos vs. ojos) | Asimétricos: conductor + pasajeros con reglas individuales |
| Estructura | Mapa largo con checkpoints | Niveles de historia | Entregas de 2–5 min, depósito y campaña/endless |
| Fracaso | El vehículo se atasca o se rompe; jugadores caídos | El auto choca o se desarma | El paquete se daña; se repara, se sustituye o se pierde; el cliente reacciona |
| Economía | No (encuentras objetos) | No declarada | Dinero cooperativo, votación, mérito individual, cartas |
| Voz | Proximidad + walkie | Micrófono + indicaciones con voz | **No hay** |
| Generación | Mapas hechos a mano | Niveles hechos a mano | Ruta procedural por semilla |
| Precio | ~8 USD | Friend Pass | Sin definir |

**Qué corregir en el posicionamiento:**

1. `definicion-proyecto.md` dice que no encontramos roles asimétricos replicados.
   Backseat Drivers los tiene desde octubre de 2025. Conviene reescribir el
   diferencial como: *"cada pasajero tiene su propio problema en las manos"*
   (asimetría **entre pasajeros**, no solo entre conductor y pasajero) + *"la carga
   es la protagonista y la entrega se revisa en la puerta"*.
2. El material de tienda (cápsula, tráiler, primeros 5 s) tiene que mostrar **un
   paquete en peligro** antes que el camión. Si mostramos primero el camión en la
   ruta, nos van a leer como "otro RV There Yet?".
3. RV There Yet? demostró que a ~8 USD y con una idea legible en un GIF se puede
   vender millones. Anotarlo como dato para la decisión de precio.

## 6. Qué nos falta que ellos tienen (brechas)

1. **Voz.** Es la diferencia de mayor impacto. En un cooperativo de caos, sin voz la
   comedia depende de Discord y el juego pierde los momentos compartibles.
2. **Salir del vehículo con un propósito.** En RV There Yet? se baja todo el tiempo
   (enganchar, empujar, espantar animales). En nuestro juego bajar solo tiene sentido
   en el depósito y en la puerta del cliente; en la ruta, casi no.
3. **El vehículo como objeto que se rompe y se arregla.** Diseñamos reparación de
   paquetes con mucho detalle, pero el camión solo "recibe daño" como descuento
   económico.
4. **Exploración con premio cosmético.** Nuestro mérito desbloquea cosméticos, pero
   no hay nada para **encontrar** en el mundo.

## 7. Mecánicas propuestas

Formato: **origen → adaptación → por qué encaja → costo → dominio → notas de red**.
Costo: S (días), M (1–2 semanas), L (más). Dominios según
`docs/colaboracion-equipo.md`: paquetes, jugador y UI son de Slatex; ruta, tramos y
peligros, de Nacho; `RunManager`, `EventBus` y nivel son zona compartida.
`vehicle.tscn`/`vehicle.gd` están congelados: todo lo que los toque necesita acuerdo
previo.

### Prioridad A — alto impacto

#### M-01 · Voz por proximidad dentro y fuera del camión
- **Origen:** RV There Yet? (proximidad + walkie), Backseat Drivers (micrófono).
- **Adaptación:** voz posicional por jugador. Dentro de la cabina todos se escuchan
  bien. Fuera se atenúa con la distancia. El bus **Interior/Exterior** que ya existe
  (`SynthAudio`) sirve para ubicar la voz: a quien está afuera se le escucha
  filtrado a través de la chapa. Pulsar para hablar y opción de detección de voz.
- **Por qué encaja:** una trampa como Ruidoso o Equilibrio se vuelve el doble de
  graciosa cuando el pasajero grita "¡FRENÁ!" y el conductor no frena.
- **Implementación posible:** con Steam, la voz de GodotSteam (`startVoiceRecording`
  / `getVoice` / `decompressVoice`) mandando los paquetes por un canal no confiable.
  Con ENet/LAN, `AudioEffectCapture` + compresión propia (o sin voz en LAN al
  principio). Reproducir con `AudioStreamGenerator` en un `AudioStreamPlayer3D`
  pegado a la cabeza del jugador.
- **Costo:** L. **Dominio:** red/jugador (Slatex) + audio. **Red:** la voz no pasa
  por el host autoritativo del juego; es un flujo aparte y no toca la simulación.
  Pedirle al agente `auditor-red` que valide el ancho de banda con 5 jugadores.
- **Riesgo:** los bugs de voz fueron la queja número uno en ambos juegos. Tiene que
  poder desactivarse y tener un volumen por jugador.

#### M-02 · Indicaciones rápidas con voz de personaje
- **Origen:** Backseat Drivers.
- **Adaptación:** menú radial (D-pad o rueda del mouse) con 6–8 frases: "¡Frená!",
  "¡Bache!", "¡Ayuda acá!", "¡Se cae!", "Tengo la cinta", "Esperá", "¡Dale, dale!".
  Cada una se dice con la voz sintetizada del color del jugador (tono distinto), muestra
  un ícono sobre su cabeza y aparece en el HUD mínimo del conductor, que ya está
  diseñado ("pedidos de freno").
- **Por qué encaja:** hace funcional el juego sin micrófono (jugadores tímidos o
  streamers con la voz ya ocupada) y resuelve la comunicación en solitario o con
  bots. Es la versión barata de M-01 y se puede hacer antes.
- **Costo:** S–M. **Dominio:** UI y jugador (Slatex); la voz sintetizada, en
  `SynthAudio`. **Red:** un RPC pequeño y confiable por indicación, con enfriamiento
  para evitar spam.

#### M-03 · El camión como objeto que se rompe y se arregla con lo que haya
- **Origen:** Backseat Drivers (casete como pedal) + RV There Yet? (repuestos).
- **Adaptación:** 4–5 **averías** localizadas y visibles que aparecen por golpes
  fuertes o eventos:

  | Avería | Efecto | Arreglo "oficial" | Arreglo improvisado |
  | --- | --- | --- | --- |
  | Puerta trasera que se abre sola | Los paquetes del estante pueden deslizarse hacia afuera | Pestillo nuevo (tienda) | Cincha o cinta del kit |
  | Espejo retrovisor caído | El conductor pierde la vista trasera | Espejo (tienda) | Un pasajero "hace de espejo" con la cámara del celular (`phone_camera.gd` ya existe) |
  | Limpiaparabrisas roto (con lluvia) | Parabrisas borroso | Repuesto | Un pasajero limpia por la ventana con el trapo del kit |
  | Faro roto (de noche) | Menos visibilidad | Faro | Linterna sostenida por un pasajero |
  | Asiento flojo | El regazo transmite más las sacudidas | Tornillos | Cinta |

- **Por qué encaja:** reutiliza el **kit y los minijuegos de reparación** que ya
  diseñamos para los paquetes (cinta, cincha, trapo), así que no suma herramientas
  nuevas. Además le da al pasajero sin crisis algo que hacer y genera historias para
  la pantalla de resultados ("Espejo reemplazado por un celular").
- **Costo:** M. **Dominio:** **toca el camión congelado.** Proponer que las averías
  vivan en un nodo o componente aparte (`VehicleFaults`) que lea eventos de impacto
  y cambie la presentación desde afuera, sin editar `vehicle.gd`. Acordarlo antes.
  **Red:** el host decide y sincroniza el estado de cada avería.

#### M-04 · Carga que se cae del camión y rescate afuera
- **Origen:** RV There Yet? (objetos que se caen, herramientas en el techo) +
  cabrestante.
- **Adaptación:** ya diseñamos que "si la gallina se escapa afuera" va el juguete
  sustituto. Esto lo generaliza: un paquete que sale despedido queda en la banquina,
  con marcador y ventana de rescate (8–15 s según nuestras reglas de justicia, más
  larga fuera del camión). Opciones:
  1. **Frenar y bajar** a buscarlo (cuesta tiempo de plazo).
  2. **Gancho o caña de rescate** (mejora de tienda, rama Supervivencia): un pasajero
     lo "pesca" desde la puerta trasera sin frenar. Es nuestro cabrestante en chico.
  3. **Abandonarlo** y cerrar el pedido vacío.
- **Por qué encaja:** es la mecánica de RV There Yet? que más cerca está de nuestro
  tema y resuelve la brecha 2 ("salir del camión con propósito"). La caña de rescate
  es un objeto físico gracioso y coordinado, como el cabrestante.
- **Costo:** M (bajar y buscar) + M (caña). **Dominio:** paquetes (Slatex) + zona
  compartida (`RunManager`: que salga del camión ya no significa `RUINED`).
  **Red:** posición del paquete autoritativa en el host; la caña solo manda la
  intención de enganchar.

### Prioridad B — buen impacto, costo contenido

#### M-05 · Tramo "barro/pendiente" con salida cooperativa
- **Origen:** RV There Yet? (terreno que el vehículo no supera solo).
- **Adaptación:** un tipo de tramo nuevo, raro y anunciado, en el que el camión
  puede quedar atascado. Salida: pasajeros empujando desde atrás (mantener un botón
  en la zona correcta) o **eslinga/cabrestante** comprado en la tienda. Mientras
  empujan, **sus paquetes quedan solos**: el dilema es "¿quién baja y qué caja queda
  sin atender?".
- **Por qué encaja:** crea exactamente la tensión de priorizar que buscamos, sin
  convertir el juego en un simulador de terreno.
- **Costo:** M. **Dominio:** Nacho (`constructor-tramos`). **Red:** el host aplica
  la fuerza de empuje según las entradas.
- **Regla:** que nunca bloquee la ruta para siempre. Pasado un tiempo aparece una
  grúa cómica que te saca, con multa.

#### M-06 · Animales que se meten con la carga
- **Origen:** RV There Yet? (osos, serpientes, águilas).
- **Adaptación:** reutilizar `wildlife_crossing.gd` y la bocina con función
  (N-107), pero con animales que **interactúan con los paquetes**, no con los
  jugadores:
  - **Gaviota o carancho** que baja a la caja del estante y trata de llevársela
    (espantarla con la bocina o sujetando la caja).
  - **Perro que se sube** a la caja abierta en una parada (se lo distrae tirándole
    algo, como a la serpiente de RV).
  - **Abejas** atraídas por la torta (Equilibrio) en zona de campo.
- **Por qué encaja:** amplía los peligros sin tráfico de N-106 y conecta la ruta con
  las trampas.
- **Costo:** S–M por animal. **Dominio:** Nacho (peligros) + aviso a Slatex si toca
  estados del paquete. **Red:** determinista por semilla, disparado por el host,
  como el cruce de tren.
- **Lección de las críticas:** nada de ataques sin aviso. Cada animal se anuncia con
  sonido o ícono y se puede contrarrestar.

#### M-07 · Paradas de servicio en la ruta (mini-checkpoints)
- **Origen:** RV There Yet? (checkpoints con herramientas, repuestos y cosméticos).
- **Adaptación:** en rutas largas y en endless, una estación de servicio opcional a
  mitad de camino: reponer consumibles del kit (cuestan dinero cooperativo),
  arreglar averías (M-03) y encontrar un cosmético escondido. **Parar cuesta
  tiempo de plazo**, así que es una decisión.
- **Por qué encaja:** da a endless el ritmo "tensión → respiro" que en campaña hoy
  da el depósito, y conecta con la economía.
- **Costo:** M. **Dominio:** Nacho (ruta y streamer) + UI de compra ya existente.

#### M-08 · Cosméticos para encontrar
- **Origen:** RV There Yet? (gorros y lentes escondidos).
- **Adaptación:** además de desbloquearse con mérito, algunos gorros aparecen en el
  mundo (en el depósito, en paradas, en el jardín de un cliente). Recogerlos
  requiere bajarse o desviarse unos metros.
- **Por qué encaja:** nuestro mérito ya desbloquea cosméticos; esto agrega el placer
  de encontrarlos sin tocar el balance.
- **Costo:** S. **Dominio:** Slatex (jugador y cosméticos) + Nacho (dónde aparecen).

#### M-09 · Radio del camión con función
- **Origen:** Backseat Drivers (radio interactuable).
- **Adaptación:** una perilla en el tablero que cualquiera puede girar. Música
  tranquila **calma la trampa Ruidoso** (gallina) y la música fuerte la altera; el
  noticiero anuncia los eventos de ruta que vienen ("inspección más adelante"). La
  rama Supervivencia ya tiene "radio" como mejora: esto le da un uso concreto.
- **Por qué encaja:** es una interacción chica, visible y compartida, que da
  discusiones ("¡sacá esa música!").
- **Costo:** S–M. **Dominio:** audio (`SynthAudio`) + paquetes (Ruidoso).
  **Red:** el host guarda la estación actual.

### Prioridad C — para más adelante o para probar

#### M-10 · Modo party "Clientes a bordo" (a lo Carpool)
- **Origen:** Backseat Drivers (Carpool: 3 chicos molestos).
- **Adaptación:** modo alternativo en el que uno o dos jugadores son **pasajeros
  caóticos** (un cliente apurado, un chico) que ganan puntos propios por molestar
  dentro de límites: tocar la bocina, cambiar la radio, abrir una caja ajena. Los
  demás siguen haciendo la entrega.
- **Por qué:** agrega rejugabilidad y material para streams con muy poco contenido
  nuevo.
- **Riesgo:** un rol que se dedica a sabotear puede arruinar la partida si no tiene
  límites. Pasárselo primero a `critico-diseno`.
- **Costo:** M–L. **Dominio:** zona compartida (modo de juego nuevo).

#### M-11 · Información asimétrica puntual para el conductor
- **Origen:** Backseat Drivers (el conductor no ve).
- **Adaptación:** **no** copiar la premisa, que es suya, sino usarla como **evento
  de ruta** corto: niebla densa, parabrisas embarrado o una caja grande que tapa la
  vista. Durante 10–20 s, un pasajero en la ventana guía al conductor (con M-01 o
  M-02).
- **Por qué:** es un momento de comunicación intensa y breve que se suma a la tabla
  de eventos de ruta sin volverse nuestra identidad.
- **Costo:** S–M. **Dominio:** Nacho (evento de ruta) + shader para el efecto
  (`artista-shaders`).

#### M-12 · Caja de cambios manual como variante del camión
- **Origen:** RV There Yet? (embrague).
- **Adaptación:** una variante del camión ("clásico viejo") con marchas manuales
  opcionales, a elegir en el depósito, con más mérito o paga como compensación.
- **Por qué:** le da profundidad al conductor. Hoy su rol es el más "normal".
- **Riesgo:** toca el manejo congelado y complica la accesibilidad. Solo como opción.
- **Costo:** M. **Dominio:** camión congelado; necesita acuerdo.

#### M-13 · Friend Pass y demo separada
- **Origen:** Backseat Drivers.
- **Adaptación:** comercial, no de juego. Evaluar un Friend Pass (que el anfitrión
  pueda invitar a alguien sin copia a un modo limitado) y una demo aparte en Steam
  para acumular deseados.
- **Costo:** depende de Steamworks. **Dominio:** release (`empaquetador-release`).

#### M-14 · Mapa largo como modo "Mudanza"
- **Origen:** RV There Yet? (un viaje largo con checkpoints).
- **Adaptación:** un modo de 20–40 min con una sola carga grande (una mudanza) y
  varias paradas de servicio (M-07). Encaja con la generación por semilla del
  endless.
- **Por qué:** es otra forma de sesión además de las entregas cortas, y sirve para
  noches largas con amigos.
- **Costo:** M (reutiliza el streamer). **Dominio:** Nacho + zona compartida.

## 8. Lo que no conviene copiar

| Mecánica | Por qué no |
| --- | --- |
| Salud, muerte y reanimación de jugadores (EpiPen) | Agrega un segundo sistema de fracaso que compite con la carga. Nuestras reglas dicen que un error no deja a un pasajero sin nada que hacer. |
| Conductor que no ve durante toda la partida | Es la identidad de Backseat Drivers. Copiarla nos vuelve un clon. Solo como evento corto (M-11). |
| Fauna que ataca a los jugadores sin aviso | Es la queja principal de RV There Yet? |
| Mapas grandes hechos a mano | No escala con un equipo de 2. Nuestra ventaja es la ruta por semilla. |
| Física "tal cual" sin límites | Las dos reseñas critican la física inestable. Mantener el tope de daño por evento que ya definimos. |

## 9. Orden sugerido

1. **M-02 Indicaciones rápidas** (barato, mejora todo lo demás y sirve en solitario).
2. **M-04 Carga que sale del camión + rescate** (el corazón temático y la brecha 2).
3. **M-03 Averías del camión** (reutiliza el kit; acordar el diseño sin tocar
   `vehicle.gd`).
4. **M-01 Voz por proximidad** (la de mayor impacto, pero cara; empezar por un
   prototipo solo con Steam).
5. **M-06 / M-09** (animales y radio, contenido chico que conecta sistemas).
6. **M-05 / M-07 / M-08** (barro, paradas y cosméticos).
7. **C** según tiempo y playtesting.

Antes de comprometer M-01, M-03 y M-10, pasarlas por `critico-diseno`. Antes de tocar
algo del camión, por `guardian-dominios`.

## 10. Tareas de documentación que surgen

Todo quedó asignado a Nacho en `tareas-nacho.md`, hito **M6** (2026-09-28):
N-704 (diferencial y crítica), N-505 (M-02), N-213 (M-04), N-214 (M-03),
N-212 (M-01), N-109 (M-06), N-406 (M-09), N-108 (M-05), N-110 (M-07),
N-311 (M-08), N-113 (M-11), N-111 (M-14), N-112 (M-10), N-114 (M-12) y
N-907 (M-13).

## Fuentes

- [RV There Yet? — Steam](https://store.steampowered.com/app/3949040/RV_There_Yet/)
- [RV There Yet? — Wikipedia](https://en.wikipedia.org/wiki/RV_There_Yet%3F)
- [PC Gamer — supera 4,5 M de copias](https://www.pcgamer.com/games/adventure/co-op-smash-hit-rv-there-yet-gets-an-unplanned-content-update-for-an-unplanned-game-as-the-comedy-vehicle-sim-surpasses-4-5-million-copies-sold/)
- [WN Hub — 1,3 M en una semana](https://wnhub.io/news/other/item-49140)
- [Skövde — 2,5 M en 2 semanas](https://skovde.com/en/rvthereyet/)
- [Game Rant — explota en Steam](https://gamerant.com/best-new-co-op-physics-games-steam-rv-there-yet/)
- [Game8 — reseña](https://game8.co/articles/reviews/rv-there-yet-review)
- [GAMES.GG — reseña](https://games.gg/rv-there-yet/review/)
- [TheGamer — consejos para empezar](https://www.thegamer.com/rv-there-yet-beginner-tips-tricks-guide/)
- [Twinfinite — guía (enemigos, objetos)](https://twinfinite.net/guides/rv-there-yet-beginners-guide/)
- [Deltia's Gaming — chat por proximidad](https://deltiasgaming.com/rv-there-yet-proximity-chat-guide/)
- [GameGrin — mapa nuevo](https://www.gamegrin.com/news/rv-there-yet-releases-brand-new-map-for-players-to-enjoy/)
- [AllKeyShop — mapa final costero](https://www.allkeyshop.com/blog/rv-there-yet-final-coastal-map-update-news-n/)
- [AllKeyShop — Game Pass y crossplay](https://www.allkeyshop.com/blog/en-us/rv-there-yet-xbox-game-pass-launch-news-n/)
- [Backseat Drivers — Steam](https://store.steampowered.com/app/3558400/Backseat_Drivers/)
- [Backseat Drivers: Free Test Drive — Steam](https://store.steampowered.com/app/3634900)
- [Backseat Drivers — anuncio de lanzamiento](https://store.steampowered.com/news/app/3558400/view/534348484694770230)
- [SteamDB — notas del lanzamiento (9-oct-2025)](https://steamdb.info/patchnotes/20323864/)
- [GhostJam Games — Backseat Drivers](https://ghostjam.com/game/backseat-drivers/)
- [Co-Optimus — info cooperativa](https://www.co-optimus.com/game/17180/pc/backseat-drivers.html)
