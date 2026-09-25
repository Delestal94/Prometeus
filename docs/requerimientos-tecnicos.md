# Requerimientos técnicos y funcionales — Take My Package

> Basado en: `docs/definicion-proyecto.md` (idea base: delivery cooperativo, 1 conductor +
> hasta 4 pasajeros con paquetes-trampa) y `docs/mecanicas-candidatas.md`.
> Última actualización: 2026-09-20
> Objetivo de este documento: dejar sentada la base funcional y técnica necesaria para
> que el juego sea adictivo y altamente rejugable desde el día del release, con arte
> estilo PEAK (low-poly, estilizado, simple).

## 0. Resumen del concepto (para referencia rápida)

Hasta 5 jugadores en una camioneta: 1 conduce, hasta 4 llevan un paquete cada uno. Cada
paquete tiene una "trampa" — una regla individual que el pasajero debe manejar mientras
el vehículo se mueve (ej: no moverlo mucho, resolver un puzzle antes de que su peso
aumente, mantenerlo en cierta posición, etc.). El caos surge del cruce entre la
conducción (afecta físicamente a todos los paquetes a la vez) y las reglas individuales
de cada pasajero.

---

## 1. Motor y stack técnico

### Motor definitivo: **Godot** (4.x)
> Actualizado 2026-09-20: se confirmó Godot como motor definitivo (reemplaza la
> recomendación inicial de Unity). Se actualiza toda la sección de networking/física
> en consecuencia.

- Godot 4 tiene físicas 3D sólidas (motor **Jolt** integrado desde 4.3, recomendado
  por sobre el GodotPhysics3D por defecto para simulaciones de vehículo/objetos más
  estables) y buen soporte de VehicleBody3D nativo para arrancar rápido.
- Es liviano, gratis, open source, con buena cantidad de documentación y ejemplos
  públicos — sigue cumpliendo el criterio de "motor bien cubierto para que la IA te
  asista" que habíamos marcado en `checklist-exito.md` (menos volumen que Unity, pero
  la comunidad y documentación oficial crecieron mucho en los últimos años).
- Ya tenemos precedente de éxito de un solo dev con Godot en la propia investigación:
  **Brotato** (10M+ copias) se hizo en Godot.

### Renderer: **GL Compatibility** para el MVP (decidido 2026-09-24)

`project.godot` usa `renderer/rendering_method = "gl_compatibility"` y se queda así hasta
Early Access (docs/tareas-nacho.md N-308, antes #34).

- **Por qué:** el público de un cooperativo de amigos a precio bajo tiene hardware
  modesto (notebooks, gráficos integrados); Compatibility corre en OpenGL 3.3 / GLES3 y
  la meta es 60 FPS estables. El estilo low-poly de colores planos no depende de los
  efectos que se pierden.
- **Qué se pierde:** SSAO, SSIL, SSR, SDFGI, niebla volumétrica y motion blur, que solo
  existen en Forward+. Activarlos en Compatibility no da error: simplemente no hace nada.
- **Cómo se compensa la oclusión ambiental:** oclusión horneada en los colores de vértice
  de los modelos (script de Blender, al exportar) y sombras de contacto falsas bajo autos
  estacionados, casas y cajas apiladas. Las dos son baratas en cualquier GPU. Las sombras
  de contacto ya están (N-308.2, `scripts/presentation/contact_shadow.gd`): Compatibility
  tampoco tiene nodos `Decal`, así que son una malla plana sin luz, con una franja que se
  esfuma en metros alrededor de la base; en la ruta cada vértice se apoya en el terreno.
- **Cuándo revisarlo:** solo si, con el juego ya en Early Access, las mediciones de
  N-204 muestran margen de sobra en el hardware objetivo y hay un efecto de Forward+ que
  se note en capturas. Cambiar de renderer obliga a volver a revisar shaders
  (`.gdshader`), iluminación y capturas.

### Networking
- API de multiplayer de alto nivel de Godot (`MultiplayerAPI`, `ENetMultiplayerPeer`,
  nodos `MultiplayerSynchronizer`/`MultiplayerSpawner` en Godot 4), modelo
  **host-cliente** (uno de los 5 jugadores hostea la partida) — mismo criterio que
  antes: es el modelo más simple de implementar solo, sin servidores dedicados para
  el MVP.
- Sincronizar: posición/física del vehículo (autoridad del host), estado de cada
  paquete (posición, "salud"/integridad, progreso de su puzzle), y estado del puzzle
  individual (puede resolverse localmente y sincronizar solo el resultado para reducir
  tráfico de red).

### Física
- Física de vehículo: usar el nodo **VehicleBody3D** de Godot (con motor Jolt activado)
  como base, para no reinventar la rueda en la parte más compleja.
- Física de paquetes: RigidBody3D simples con Joints/constraints según el tipo de
  paquete (ej: un paquete "frágil" tiene un umbral de fuerza de impacto que dispara
  falla; uno "pesado creciente" cambia su masa en tiempo real según el timer del
  puzzle).

### Decisión de arquitectura de movimiento: camioneta fija vs. entorno moviéndose

Te recomendaron mantener la camioneta siempre en el centro del mundo (origen) y mover
el entorno alrededor — es una técnica real y usada (a veces llamada "floating origin"
o "treadmill"), pero **no la recomiendo tal cual para este juego específico**. Motivo:

- **Rompe la física natural que es el corazón del juego**: la gracia de los
  paquetes-trampa es que reaccionen físicamente a la aceleración, frenada y giros
  reales del vehículo (inercia). Si la camioneta está fija y es el *entorno* el que se
  mueve, el motor de física no "sabe" que hay aceleración — la camioneta nunca acelera
  desde su propio marco de referencia, así que los paquetes/rigidbodies no sentirían
  inercia real a menos que la simules manualmente aplicando fuerzas ficticias
  (marco de referencia no inercial). Eso agrega complejidad justo donde no conviene.
- **Complica el networking**: sincronizar "el entorno moviéndose" en vez de "el
  vehículo moviéndose" es un patrón mucho menos estándar en multiplayer — la mayoría
  de las soluciones de netcode (incluida la de Godot) asumen que sincronizás la
  posición/transform de objetos que se mueven en el mundo, no un desplazamiento global
  de todo el escenario para cada cliente.
- **El problema que esta técnica resuelve (precisión de punto flotante en distancias
  gigantescas) no aplica a nuestro caso**: nuestras rutas son tramos curados y
  finitos (sección 3.3), no un mundo infinito tipo simulador espacial. Los problemas
  de precisión de float32 aparecen recién en distancias de decenas/cientos de miles de
  unidades — muy por encima de lo que va a recorrer una entrega o incluso una sesión
  larga del modo endless.

**Recomendación**: usar el enfoque estándar — la camioneta se mueve de verdad por el
mundo con física real (VehicleBody3D), y el "mundo infinito" del modo endless se logra
con **streaming de tramos** (generás/instanciás el tramo siguiente antes de que el
jugador llegue, y eliminás los tramos que quedaron muy atrás) — esto te da la misma
sensación de "mundo interminable" sin sacrificar la física ni complicar el networking.
Si en el futuro el modo endless genera sesiones extremadamente largas y aparecen
problemas de precisión (poco probable a las distancias de este juego), la solución más
simple es un "rebase" ocasional del origen (mover todo el set de objetos activos de
vuelta cerca de (0,0,0) cuando la camioneta se aleja mucho, no en cada frame) — mucho
más simple que invertir el modelo de movimiento del juego entero.

### Decisión de cámara: primera persona por asiento (confirmado 2026-09-20)

**PEAK es en realidad un juego en primera persona**, no en tercera persona con cámara
externa (verificado — es un malentendido común). Esto encaja directamente con el
pedido de que "el conductor debe ver dentro de la cabina": cada jugador ve el mundo
desde los ojos de su personaje, sentado en su lugar dentro de la furgoneta.

- **La furgoneta tiene interior real**: cabina del conductor con tablero y volante
  visibles, y hasta 4 asientos de pasajero en los laterales de la zona de carga, cada
  uno con su propio paquete-trampa enfrente (ver `Vehicle` en
  `docs/arquitectura.md` sección 3 — los asientos son `Marker3D` hijos del vehículo,
  no entidades separadas por ahora).
- **Cámara rígida, sin suavizado**: la cámara sigue el transform del asiento
  directamente, frame a frame, sin interpolar. Es deliberado — PEAK vende su caos
  físico dejando que la cámara "sienta" cada golpe sin filtrar, y acá el golpe es
  literalmente la mecánica central (el paquete se rompe por los mismos impactos que
  sacuden al jugador). Se suma un shake corto sobre la señal `vehicle_impact` ya
  existente en el `EventBus`, para reforzar ese feedback sin inventar un sistema
  nuevo.
- **Manos visibles (viewmodel)**: como en PEAK, el jugador ve sus propias manos —
  del conductor sosteniendo el volante, del pasajero cerca de su paquete. Por ahora
  son cápsulas placeholder (arte final en la Fase 6), pero ya están ancladas a la
  cámara y alineadas con el volante.
- **Por asiento, no por jugador único**: la cámara es un componente reutilizable
  (`FirstPersonCamera`, `scenes/presentation/first_person_camera.tscn`) que vive como
  hija directa del `Marker3D` del asiento (hereda su transform gratis por jerarquía de
  escena) y arranca inactiva — una interacción de "sentarse" la activa
  (`activate()`). El mismo componente sirve para el conductor hoy y para cada
  pasajero cuando se sume el multiplayer (Fase 4), sin duplicar código.

### Flujo físico de carga y abordaje (agregado 2026-09-20)

El loop no arranca con el jugador ya manejando — hay una fase previa a pie, a pedido
explícito del usuario ("debería haber un lobby donde uno cargue los paquetes... deciden
quién carga los paquetes y quién se sube a conducir"):

1. El jugador aparece **a pie, en primera persona** (mismo estilo PEAK), cerca de la
   furgoneta y de un paquete apoyado en un punto de carga.
2. Camina hasta el paquete y presiona **interact** (`E`) para agarrarlo — lo lleva
   frente a la cámara (viewmodel), igual que las manos del volante.
3. Camina hasta la furgoneta y presiona interact junto a un asiento vacío para dejarlo.
4. Presiona interact junto al asiento del conductor para subirse: ahí recién la cámara
   cambia a primera persona *dentro* de la cabina y se habilita el manejo.
5. La entrega **arranca sola** apenas hay conductor sentado y el paquete está a bordo
   — sin pantalla de "empezar" de por medio (ver `docs/plan-desarrollo.md`).
6. **En multiplayer (Fase 4) no hay asignación de roles**: cualquier jugador puede
   caminar a cualquier asiento — el primero que se sienta en el volante conduce, el
   resto carga paquetes. El rol lo decide la acción física, no un menú.

Técnicamente esto se resuelve con un patrón `Interactable` genérico (`Area3D` con
`interact(player)`), reutilizable para paquetes, puntos de montaje y asientos — ver
`docs/arquitectura.md`.

---

## 2. Arte — pipeline estilo PEAK

- **Low-poly estilizado**: personajes y objetos con **1.000-5.000 triángulos** por
  asset (rango estándar de low-poly para tiempo real), paleta de colores simple y
  saturada, sin texturas fotorealistas.
- **Ventaja para vos como solo dev**: este estilo permite usar **asset packs low-poly
  ya existentes** para acelerar el arte base (vehículos, props, entorno) y enfocar tu
  tiempo en los personajes/paquetes que sí necesitan ser distintivos. Con Godot, la
  fuente más práctica es **Kenney.nl** (modelos low-poly gratuitos, licencia CC0, en
  formato glTF listo para importar) — muy usada en la comunidad Godot; los packs tipo
  Synty también son importables (vienen en FBX/glTF, no están atados a Unity) si
  necesitás algo más específico. Es coherente con el patrón de toda la investigación:
  minimizar carga de arte para maximizar foco en el diseño de sistemas.
- **Personajes**: ragdoll físico (como TRDS/PEAK) — barato de animar porque gran parte
  del "movimiento" es física, no animación a mano. Esto también genera humor gratis
  (el ragdoll cayéndose es intrínsecamente gracioso, refuerza el objetivo de "momentos
  clipeables").

---

## 3. Diseño del loop para maximizar adicción/rejugabilidad

Basado en principios de diseño de roguelites/juegos "one more run" (investigación de
mercado 2026):

### 3.1 Loop base (~2-5 minutos por entrega, sesión total 15-30 min)
1. Se genera una ruta (combinación de tramos de camino + obstáculos, ver punto 4).
2. Cada jugador recibe un paquete con una trampa asignada (aleatoria dentro de rangos
   de dificultad).
3. El conductor maneja hacia el destino mientras los demás gestionan sus paquetes.
4. Al llegar: puntaje según cuántos paquetes llegaron intactos/a tiempo.
5. Con el puntaje se desbloquea progreso meta (ver 3.2) y se vuelve al paso 1.

**Regla de oro (según investigación)**: el loop repetible tiene que "sentirse bien" en
30 segundos — la conducción + el manejo de paquetes debe ser divertido aunque no pase
nada extra, para que la repetición no canse.

### 3.2 Meta-progresión (entre partidas)
- Desbloqueo de **nuevos tipos de trampa de paquete** (contenido barato de agregar:
  cada trampa es un mini-sistema independiente, no arte nuevo pesado).
- Desbloqueo de **vehículos nuevos** con distinto manejo (afecta directamente el
  desafío del conductor).
- **Cosméticos** (skins de personajes/vehículos) como recompensa de progreso sin
  afectar balance — barato de producir dado el low-poly.
- Sistema tipo "no podés ganar todo desde el principio" (como Rogue Legacy): las
  primeras partidas son más difíciles/limitadas y mejoran con el progreso, generando
  motivo concreto para volver.

### 3.3 Generación de variedad barata (procgen liviano — mecánica #5 del banco)
- Rutas armadas por **combinación de tramos curados a mano** (rectas, curvas, puentes
  angostos, badenes) en vez de generación 100% procedural — más control de calidad,
  variedad casi infinita con bajo costo de producción.
- Asignación de trampas de paquete semi-aleatoria, con reglas de balance (no más de
  X trampas de alta dificultad simultáneas para partidas iniciales).

### 3.4 Momentos "clipeables" (diseño explícito, no accidental)
- Paquetes con **fallas visualmente exageradas** (explosión de confeti/objetos si se
  arruinan, en vez de solo un mensaje de "perdiste") — refuerza que sea "divertido de
  mirar" en streams, patrón confirmado en Lethal Company/Megabonk.
  **[x] Implementado (2026-09-21)**: `package_feedback.gd` dispara un burst de
  `GPUParticles3D` (cubitos de colores) al recibir `package_ruined`, en la posición
  real del paquete; se limpia solo. Ver `tests/test_ruin_feedback.gd`.
- Cámara que reaccione a los golpes fuertes del vehículo (shake, slow-mo breve) para
  amplificar los momentos de caos.
  **[x] El shake ya estaba implementado** (`first_person_camera.gd`, reacciona a
  `vehicle_impact`). **[ ] El slow-mo breve queda pendiente** — tocar
  `Engine.time_scale` globalmente afectaría la física host-autoritativa en
  multijugador, así que necesita diseñarse con cuidado (¿solo cosmético del lado
  del cliente, sin tocar el timestep real?) antes de implementarlo.

### 3.5 Rejugabilidad a largo plazo
- **Modo "endless"/contrarreloj** una vez agotado el contenido curado inicial,
  combinando tramos y trampas ya desbloqueadas.
- Tabla de puntajes (leaderboard) local o global simple — el patrón de "superar tu
  propio récord" es un enganche barato de implementar y efectivo.
- Considerar un **desafío diario/semanal** (ruta fija para todos) más adelante, después
  del MVP — genera razón de volver sin necesitar contenido nuevo cada vez.

---

## 4. Sistema modular de "paquetes-trampa"

Diseñar esto como un **framework de plugins internos**, no como casos hardcodeados,
para que agregar un tipo de trampa nuevo sea rápido (clave para el contenido post-launch
barato):

- Cada tipo de trampa define: (a) qué input del jugador espera, (b) qué condición de
  falla tiene, (c) cómo reacciona a la física del vehículo (sacudidas, frenadas,
  curvas), (d) feedback visual/sonoro de estado (ok / en riesgo / arruinado).
- Catálogo inicial sugerido para el MVP (3-4 tipos, ampliable después):
  1. **Frágil**: falla si recibe un impacto/sacudida por encima de un umbral.
  2. **Peso creciente**: un puzzle simple (ej. secuencia, memoria, coordinación motriz)
     debe resolverse antes de que un timer haga crecer el peso hasta ser inmanejable.
  3. **Equilibrio**: hay que mantenerlo en cierta orientación/ángulo mientras el
     vehículo se mueve (se cae o se derrama si se inclina de más).
  4. **Ruidoso/vivo**: reacciona con sonido/movimiento propio a las sacudidas (ej. un
     animal o algo "vivo" en la caja) y hay que calmarlo con una acción del jugador.

---

## 5. Alcance del MVP (para no repetir el error de scope creep)

- **Jugadores**: soportar de 1 a 5 (single-player opcional con bots o penalización de
  puntaje, pero diseñado principalmente para coop).
- **1 vehículo** inicial, **1 entorno** (set de tramos combinables), **3-4 tipos de
  trampa** — todo lo demás (vehículos/entornos/trampas extra) es contenido post-MVP.
- **Sin dedicated servers** para el lanzamiento — host-cliente alcanza para validar en
  Early Access.

## 6. Precio y lanzamiento
- Precio sugerido: **$8-15 USD**, consistente con el patrón de toda la investigación.
- **Early Access recomendado**: el balance de dificultad/diversión de un juego
  multiplayer de caos depende mucho de feedback real de grupos jugando — encaja
  directamente con el patrón de validación temprana que vimos en Lethal Company,
  RimWorld, Dwarf Fortress, etc.

## Próximo paso
Con esta base técnica, el siguiente documento debería ser un **plan de desarrollo por
fases** (`docs/plan-desarrollo.md`): qué construir primero (ej. física de vehículo +
1 trampa funcionando end-to-end antes de sumar multiplayer), para validar el loop
central cuanto antes.
