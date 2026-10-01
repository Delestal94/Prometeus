# El diario del día siguiente — propuesta

> Estado: **diseño con decisiones tomadas** (2026-09-29). Tarea **N-606** de `tareas-nacho.md`
> (hito M7), partida en las fases de abajo. Dueño de la idea: Nacho.
> **Fase 1 hecha (2026-09-30, N-606.1 y N-606.2)**: apodo, `RunChronicle`, `NewsDesk`, catálogo y la página 2D
> antes de los resultados (`scripts/presentation/newspaper/`, `hud_newspaper.gd`). Las casillas del catálogo
> son `{town}`, `{house}`, `{neighbor}`, `{player}`, `{km}`, `{minutes}` y `{count}`; `test_news_desk` y
> `test_run_chronicle` las cubren. Falta la escena 3D (N-606.3) y el resto.

## La idea en una línea

Al terminar el recorrido, antes de la tarjeta de resultados, una escena corta de cine: a la mañana
siguiente, **el Jefe del depósito lee el diario del pueblo**, y en el diario salen 3 a 5 noticias
cómicas **armadas con lo que de verdad pasó en la partida**: la casa a la que no le llegó la torta, la
gallina que se escapó porque nadie la cinchó, los vecinos que llamaron a la policía al ver a tres tipos
con chaleco arrancándole partes a un camión (eran ustedes arreglando el espejo).

Lo que la hace funcionar no es el chiste suelto sino que **el chiste es sobre tu partida**: el nombre del
pueblo, el número de casa, el nombre del jugador entre comillas y, más adelante, una foto real del
momento.

## Por qué un diario leído en 3D (y no una pantalla 2D)

| Opción | A favor | En contra |
|---|---|---|
| Página de diario 2D sobre la pantalla | Barata, se lee perfecto | Plana; no hay cámara ni actuación, se siente un menú más |
| Noticiero de TV con presentador | Muy graciosa, zócalos | Pide un set, un presentador que habla y, para brillar, repeticiones de video de la partida (caro) |
| **Diario leído por un personaje, escena 3D con planos de cine** | Actuación (reacciones), planos variados, el diario es un objeto que se da vuelta, se hojea, se marca con birome; la página se puede leer en primer plano | Pide animaciones nuevas y un set chico |

Se elige la tercera, **con la página hecha como UI** (un `Control` dentro de un `SubViewport` que se usa
como textura del diario): el texto se escribe con el sistema de UI de siempre, se traduce con `tr()` y en
los primeros planos se lee nítido a 1080p.

## Quién lee y dónde

- **El Jefe del depósito**, en su oficina, a la mañana siguiente, con el mate. Ya existe como personaje
  (`DepotWorker`, modelo redondeado con chaleco) y la oficina ya existe en el depósito. Un personaje fijo
  que se vuelve la "mascota" que juzga cada partida: con los resultados buenos sonríe, con los desastres
  se esconde detrás del diario.
- **Set propio en su propio `World3D`** (un `SubViewport` a pantalla completa), no en el mundo de la
  partida: la escena no depende de dónde quedó el camión, de si es de noche o llueve, y la luz se controla
  como en un set (luz cálida de mañana por la ventana, persiana que corta la luz en franjas).
- **El diario**: *El Eco de {pueblo}* (el pueblo de la ruta, de `TownSign.NAMES`), lema "Todas las
  noticias que llegan (casi) enteras". Fecha del día siguiente, precio ridículo, clima.

## Guion de la secuencia (entrega, ~30 s, se puede saltar)

Gramática de cine: plano general → plano medio → inserto → reacción → contraplano, cortes sobre la
acción (el corte cae cuando la página gira), 1,5 a 4 s por plano, bandas negras 2.35:1 que entran al
empezar y salen al final. Un poco de "cámara en mano" (ruido suave) en los planos de reacción, nada en
los insertos.

| # | Plano | Qué se ve | Cámara | Sonido |
|---|---|---|---|---|
| 0 | Transición | El camión donde terminó, 1 s de la órbita actual → fundido a negro, cartel "A la mañana siguiente…" | Fija | Gallo, pajaritos |
| 1 | General (3 s) | La oficina por la ventana, el Jefe sentado, el mate humeando | Dolly lento hacia adentro | Ambiente de mañana |
| 2 | Medio (2 s) | El Jefe abre el diario; la tapa queda de cara a cámara y le tapa la cara | Fija, leve paneo | Papel |
| 3 | **Diario giratorio** (2,5 s) | La tapa gira hacia la cámara y frena (el clásico del cine de los 30): titular principal + foto | La página ocupa el cuadro | "¡Extra, extra!" + golpe musical |
| 4 | Inserto (3 s) | Recorrido lento sobre la columna del titular; la frase remate se resalta | Travelling lateral sobre el papel | Murmullo de lectura (voz de personaje de N-505) |
| 5 | Reacción (1,5 s) | Baja el diario: cara de espanto, escupe el mate | Primer plano, cámara en mano | Escupida, pausa |
| 6-8 | Por noticia secundaria (≈3,5 s c/u) | Da vuelta la página (corte sobre la acción) → contraplano por encima del hombro → **zoom rápido** a la nota mientras el Jefe la **encierra con birome roja** | Sobre el hombro + zoom de golpe | Hoja, birome |
| 9 | Clasificados (1,5 s) | Aviso chiquito: "SE BUSCA gallina, responde a 'Cacarea'…" | Inserto | Risita contenida |
| 10 | Cierre (fondo de resultados) | El Jefe baja el diario despacio y mira a cámara (a la tripulación). Aparece la tarjeta de resultados de siempre encima | Plano medio fijo, se queda en loop mientras dura la tarjeta | Silencio incómodo → música de resultados |

- **Endless**: versión corta, solo la tapa (planos 1, 3 y 10). "Camión de reparto visto por última vez a
  3,2 km del depósito: 'seguía de largo'".
- **Partida sin incidentes**: igual hay diario, con el chiste invertido: "ESCÁNDALO: repartidores entregan
  todo intacto. Los vecinos sospechan: 'algo traman'".
- **Saltar**: mantener Interactuar/Saltar 0,6 s (anillo que se llena, aviso en la esquina desde el
  segundo 1). Opción en Opciones: *Diario al final: siempre / solo si pasó algo / nunca*.
- **Red**: cada jugador ve la secuencia en su máquina y la salta por su cuenta; lo que tiene que ser
  igual en todos es **el contenido del diario**, que decide el host (ver abajo).

## De dónde salen las noticias

### Hechos de la partida (`RunChronicle`)

Un nodo del nivel que escucha el `EventBus` durante la partida y anota **hechos**, no texto. Casi todo ya
se emite hoy:

| Hecho | Señal que ya existe | Datos |
|---|---|---|
| Casa sin entregar / pedido perdido | `house_delivery_recorded` (`missed`, `lost`) | casa, tipo de trampa del paquete |
| Entregado roto / reclamo | `house_delivery_recorded`, `complaints` de los resultados | casa, tipo |
| Sustituido por un juguete / arreglado con cinta | `rescue_stories()` / `care` del cargo | tipo, arreglos |
| Caja que salió del camión y quedó | `cargo_overboard` + `cargo_overboard_ended(rescued=false)` | tipo |
| Ciervo / ovejas atropellados | `route_event_started` (`deer_hit`, `sheep_hit`) | — |
| Avería del camión y cómo se arregló | `vehicle_fault_started` / `vehicle_fault_repaired` | `rear_door`, `mirror`, método |
| Paquete arruinado y por qué | `package_ruined(cause)` | tipo, causa |
| Foto de entrega aceptada | `delivery_photo_taken` | casa |
| Tiempo, carga sana, puntaje | `run_ended` | — |
| **Nuevos a detectar** | vuelco del camión, perro que persiguió, frenada ante el tren, lluvia | — |

### Redacción (`NewsDesk`, puro y testeable)

- Catálogo en `data/newspaper/stories.json`: por cada hecho, 3+ variantes de titular y bajada, peso
  (qué tan "noticia" es), sección (Policiales, Sociedad, Rurales, Clasificados) y foto (de la partida o
  ilustración).
- Casillas: `{pueblo}`, `{casa}`, `{vecino}` (nombre inventado con la semilla), `{jugador}` (apodo del
  jugador en el juego: "'Fue sin querer', declaró el repartidor Manos de Manteca"), `{km}`, `{minutos}`.
- Elección: tapa = el hecho de mayor peso; 2-3 secundarias **de secciones distintas**; siempre un relleno
  (clasificado, horóscopo del repartidor o pronóstico). Variante elegida con la semilla de la partida, y
  se evita repetir la variante de la partida anterior.
- **Lo decide el host**: arma la lista de `{story_id, variante, casillas}` al terminar y la reparte con
  `EventBus.relay(&"newspaper_ready", [...])`. Viaja el id y los datos, no el texto: cada jugador lo
  traduce en su idioma.

### Catálogo inicial (tono: dibujo animado, nadie sale lastimado de verdad)

**Pedidos que no llegaron (la "tragedia")**, según qué se esperaba:
- Torta: "Cumpleaños en {pueblo} se celebra sin torta: 'soplamos una vela clavada en un pan'".
- Jarrón: "Familia de la casa {casa} esperaba el jarrón de la abuela; ahora la abuela descansa en una lata
  de arvejas".
- Gallina: "Sin la gallina prometida, el gallo del barrio cae en una profunda depresión".
- Explosivo: "Se suspende el Año Nuevo en {pueblo}: 'hicimos ¡pum! con la boca'".
- Criatura: "Nene esperaba su mascota; lo consolaron con una piedra con ojitos pegados".
- Líquido: "Sin el bidón, don {vecino} riega las plantas con mate cocido".
- Pesado: "Vecino que esperaba pesas decide 'hacer cardio persiguiendo al camión'".

**Los repartidores se quedaron con el pedido** (pedido abandonado, N-213.4):
- "Repartidores explican que no entregaron la gallina porque 'se encariñaron': ya le pusieron nombre".
- "Vecinos denuncian un asado a la vera de la ruta 'con lo que se cayó del camión'".
- "El jarrón de la casa {casa} fue visto como maceta en el depósito de Take My Package".

**Averías** (N-214):
- Cualquiera: "Vecinos llaman a la policía: 'tres sujetos con chaleco le arrancaban partes a un camión'.
  Eran los repartidores intentando arreglarlo".
- Espejo: "Camión circula con un celular pegado como espejo. 'Tiene mejor resolución', defiende
  {jugador}".
- Puerta trasera: "Una puerta de camión saludó a todo {pueblo} durante {km} km".

**Fauna** (sin sangre: el animal siempre queda ofendido, no herido):
- Ciervo: "Ciervo radica la denuncia: 'me llevaron puesto y ni tocaron bocina'".
- Ovejas: "Ecologistas acusan a Take My Package de 'atropellar la fauna local'. La empresa: 'la oveja se
  tiró'".

**Carga mal asegurada**:
- Gallina que salió del camión: "Por fin se sabe por qué la gallina cruzó la ruta: 'nadie la había
  cinchado'".
- Sustituida por juguete: "Abuelo asegura que su gallina 'no pone huevos y hace ñiqui cuando la
  apretás'".
- Arreglado con cinta: "Torta de bodas llega unida con cinta de embalar: los novios la declaran
  'rústica'".

**Rellenos** (siempre uno): clasificado de la gallina prófuga, horóscopo ("Frágil: hoy no es día de
baches"), pronóstico ("Mañana: nublado con probabilidad de cajas").

## Cómo se construye (técnica)

- **Carpeta**: `scripts/presentation/newspaper/` (dominio de Nacho: ambientación/presentación).
  `newspaper_director.gd` (la secuencia), `newspaper_page.gd` (la página como `Control`),
  `news_desk.gd` (redacción pura), `run_chronicle.gd` (hechos). Escena del set en
  `scenes/presentation/newspaper_set.tscn` armada por código como el resto.
- **Cámara**: reusar el formato de rieles de `TrailerCamera` (`data/trailer_shots.json`: puntos `at` /
  `look` / `t`) en `data/newspaper/shots.json`, más `fov`, curva de suavizado (entrada-salida cúbica; el
  zoom de golpe con salida exponencial), cortes secos y ruido de cámara en mano por plano. El director
  lleva el reloj y dispara en cada plano los clips del Jefe, los sonidos y el giro de página: todo con
  tiempos en datos, afinable sin tocar código.
- **Página**: `SubViewport` de 1448×2048 con `UPDATE_ONCE` (se dibuja una vez por página, no cada
  cuadro) como textura del diario. Tipografías con licencia OFL: una de cabecera tipo diario antiguo y
  una serif para el cuerpo. Fotos con un shader de trama de puntos (halftone).
- **El diario como objeto**: dos hojas con bisagra, pegadas a las manos con `BoneAttachment3D`; el
  pasar de página con un shader que curva la hoja (compatible con GL Compatibility; sin profundidad de
  campo, que Compatibility no tiene: el foco se sugiere con encuadre y viñeta).
- **Animaciones del Jefe**: clips nuevos en `art/rounded_character/animation_library.py`, igual que
  los que ya existen (`Sit`, `Stroll`…): `SitRead` (loop), `OpenPaper`, `TurnPage`, `LowerPaper`,
  `SpitTake`, `CirclePen`, `SipMate`. Expresiones con `CharacterFace.set_expression()` (ojos
  `worried`, boca abierta) en los golpes.
- **Post**: bandas negras, grano de película suave y viñeta en un `CanvasLayer` propio de la secuencia.
- **Resultados**: la tarjeta de siempre (`hud_results.gd`, Slatex) espera la señal
  `newspaper_finished` antes de mostrarse, y la escena queda de fondo en el plano de cierre en lugar de
  la órbita del camión. Es el único punto que toca archivos de Slatex (aviso en
  `colaboracion-equipo.md`).

## Fases propuestas

1. **Contenido primero (vale solo)**: apodo del jugador, `RunChronicle` + `NewsDesk` + catálogo + la página 2D mostrada
   antes de la tarjeta, sin cinemática. Ya se puede probar si los chistes funcionan. Tests:
   `test_news_desk.gd` (misma semilla → mismo diario, la tapa es el hecho más pesado, secciones
   distintas, todo hecho tiene texto, partida limpia → noticia "escándalo") y `test_run_chronicle.gd`.
2. **La escena**: set, Jefe sentado con los clips que hay, diario 3D con la página de la fase 1, cámara
   por rieles, bandas, saltar, opción en Opciones, relay del host. Test headless del director (llega al
   final, saltar corta y muestra resultados, cliente recibe el mismo diario) y captura con
   `revisor-visual`.
3. **Pulido "de cine"**: clips nuevos del Jefe, giro de tapa, curva de página, birome, expresiones,
   audio (gallo, "¡extra!", papel, escupida), hechos nuevos (vuelco, perro, tren).
4. **Fotos reales ("el paparazzi")**: cuando pasa un hecho con foto (ciervo, gallina que salta, puerta
   que se abre) se saca una captura chica desde un ángulo lindo (como hace la cámara del celular) y va
   al diario con trama de puntos. Es lo que hace que la gente saque captura y la comparta.

Agentes por pieza: `modelador-blender` (set, diario, clips), `artista-shaders` (página, halftone, grano),
`disenador-audio`, `constructor-ui` (página y aviso de saltar), `auditor-red` (relay del diario),
`critico-diseno` antes de empezar (largo de la secuencia y cuánto se salta).

## Decisiones (Nacho, 2026-09-29)

- **Lee siempre el Jefe** del depósito, en su oficina. No hay otros lectores.
- **Dura 30 s y se puede saltar** siempre (mantener el botón 0,6 s). No hay versión corta automática;
  en Endless alcanza con la tapa porque hay menos hechos, pero el tope es el mismo.
- **`{jugador}` es un apodo del juego**, no el nombre de Steam. Hoy el juego no guarda ningún nombre de
  jugador, así que es una pieza nueva (fase 1):
  - Se escribe en el panel de personalización (junto a la cara y los cosméticos), hasta 16 caracteres,
    y se guarda con la apariencia del jugador.
  - Si está vacío, el juego asigna uno gracioso con la semilla del jugador ("el Novato", "Manos de
    Manteca", "Turbo"), así el diario nunca queda sin nombre.
  - Viaja a los demás como el resto de la apariencia (`player_appearance.gd`), para que el host lo meta en
    las casillas del diario.
  - Toca jugador y UI (dominio de Slatex): lleva aviso en `colaboracion-equipo.md`.

## Estudio visual de la escena (2026-10-01)

Prueba de dirección de arte en Godot con assets del juego, **no** la cinemática N-606.3: no toca
`NewspaperPage`, `NewsDesk`, `HudResults`, la red ni el flujo de resultados. Script, shaders y forma
de correrlo: `scripts/tools/newspaper_concept/` y `art/newspaper/LEEME.md`. Capturas en
`art/newspaper/review/`.

### Decisiones

- **Set**: réplica aislada de la oficina del depósito N-319 (escritorio, lámpara, reloj, persianas y
  corcho del kit), fondo con menos contraste que la cara y el diario. Luz cálida, sin post.
- **El Jefe**: el cuerpo redondeado actual con `CharacterFace`, pero con **camisa celeste de oficina y
  bigote** para que no se confunda con la tripulación (mismo cuerpo, en naranja). No se crea otro cuerpo.
- **El diario es papel de diario, no UI**: papel gris cálido y tinta casi negra (no la crema y el azul
  de `UiTheme`), iluminado como el resto del set, con fibra, pliegues, bordes amarillentos y el reverso
  apenas transparentado. Cuatro pliegos con pliegue central en V; sostenido solo por abajo, las puntas
  de afuera se caen.
- **Diagramación de diario**: folio con fecha arriba de cada página, etiqueta de sección, titular,
  bajada, foto con trama de puntos y pie, columnas con filetes, recuadro de clasificados y avisos chicos.
  Las noticias de la partida van grandes; alrededor, columnas de texto chico justificado de relleno que
  dan la textura de un diario de verdad sin competir con ellas. La tapa (el lado que ve la oficina
  mientras el Jefe lee) tiene cabezal, fecha, número y precio.
- **Tipografías**: Lilita One en titulares, Nunito en bajadas y cuerpos grandes. El relleno y los pies
  usan una serif del sistema en el estudio; **producción lleva una serif OFL empaquetada** (como ya
  pedía la sección de arquitectura).
- **Legibilidad**: la doble página orienta; cada bloque tiene su primer plano casi perpendicular al
  papel, del lado opuesto a la cabeza del Jefe, con el texto de la noticia a 24 px o más a 720p. Las
  manos sostienen las esquinas sin tapar noticias. Si un texto real no entra, se pagina; nunca se achica.
- **Ritmo (30 s, salteable)**: general con rótulo → recorrido por el costado hasta la doble página →
  primer plano de cada noticia con pausa de lectura (5–5,5 s) → doble página → el Jefe baja el diario y
  reacciona → resultados con la cara despejada. La cámara se detiene antes de leer; no orbita sobre el
  texto. La reacción va según la partida; escupir el mate queda para desastres excepcionales.
- **Formato**: 16:9 sin bandas (revisa la propuesta de 2,35:1), para no perder superficie de lectura.

### Pendiente para producción

Integrarlo con `NewsDesk` (3–5 noticias y sus textos reales, con traducciones), audio, paso de
página, birome, saltar y resultados reales, contacto fino de los dedos y los clips del Jefe. Las
noticias, el pueblo y "3 de 5" del estudio son de ejemplo.
