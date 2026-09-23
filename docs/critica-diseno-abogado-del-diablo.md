# Abogado del diablo — crítica de diseño de Take My Package

> Encargado explícitamente por el usuario: "quiero que seas el abogado del diablo
> a nivel de diseño... y seas crítico con absolutamente todo, desde la interfaz,
> jugabilidad y diseño". Este documento no es un plan de acción ni una lista de
> tareas — es una lista de problemas y riesgos, deliberadamente sin filtrar. Cada
> punto cita la fuente (doc o comportamiento observado jugando la build real) para
> que se pueda verificar, no es solo opinión. Fecha: 2026-09-22.
>
> **Nota de honestidad**: yo mismo escribí buena parte del código que estoy
> criticando acá (la ruta procedural, el personaje, la integración de props). Este
> documento no exime nada de eso — al contrario, varios de los puntos más duros son
> sobre decisiones mías de esta misma sesión.

---

## 1. El proyecto no sabe qué juego es

Esto es el problema raíz del que se derivan la mayoría de los demás.

- `docs/definicion-proyecto.md` vende el concepto como una mezcla de **PEAK**
  (caos físico cooperativo, comedia emergente, ragdoll) y **Totally Reliable
  Delivery Service** (delivery físico absurdo). Ninguno de los dos vive
  todavía en el juego real: no hay ragdoll, no hay física de personaje
  cómica, no hay nada que se caiga/rebote/choque de forma graciosa entre
  jugadores. Lo que hay son **medidores de 0 a 100 que bajan con inputs de
  botón mantenido o secuencias de teclas** (`docs/parametros-diseno.md`).
  Eso no es PEAK, es un minijuego de barra de progreso con un vehículo de
  fondo. La comedia física que es la razón de ser de la referencia todavía
  no existe en absoluto.
- Encima de esa base no validada se apiló, en una sola sesión de trabajo
  (`docs/cartas-y-eventos-de-ruta.md`, `docs/economia-y-contramedidas.md`),
  un sistema de **economía cooperativa + votación de compras + cartas tipo
  roguelite + mérito individual + cosméticos + eventos de ruta narrativos**
  (inspección sorpresa, cliente impaciente, caja parásita, tienda confusa).
  Eso es la superestructura de un juego de gestión/roguelite de sesiones
  largas, no de un juego de fiesta de 2-5 minutos por partida
  (`docs/requerimientos-tecnicos.md` sección 3.1, "la regla de oro: el loop
  tiene que sentirse bien en 30 segundos"). Un jugador nuevo hoy tendría que
  entender: trampas, integridad, votaciones de compra, mérito, cartas,
  eventos de ruta con penalidades — todo **antes de la primera partida**,
  porque no hay tutorial (ver sección 4).
- Nadie en los documentos se pregunta explícitamente: ¿el juego es sobre
  reírse de que un paquete se cayó, o sobre optimizar una economía
  cooperativa entre partidas? AhMismamente los dos sistemas compiten por la
  atención del jugador en el mismo HUD (ver sección 3).

**Riesgo concreto**: cuando llegue el playtesting real (que los propios docs
marcan como "pendiente, lo más importante" en cada fase), la pregunta
"¿es divertido?" va a tener una respuesta contaminada — no vas a saber si lo
que no funciona es el loop central (trampas + manejo) o el peso muerto de
sistemas de economía que nadie pidió jugar.

---

## 2. El loop central todavía no está validado, y ya se construyó encima

`docs/plan-desarrollo.md` es explícito y se cita a sí mismo constantemente:
> "Criterio subjetivo (el más importante): jugarlo se siente tenso/divertido...
> Si no, ajustar parámetros... no seguir sumando features sobre una base que no
> genera diversión."

Y sin embargo, el checklist de "pendiente" para ese criterio subjetivo sigue
sin marcar en **Fase 1, Fase 2 y Fase 3.5** al mismo tiempo que Fase 4
(multiplayer), Fase 5 (parte de meta-progresión) y ahora todo el sistema de
cartas/economía/eventos ya están construidos y funcionando. El propio plan
dice, textual, que esto es exactamente lo que no había que hacer
("no tiene sentido pagar ese costo [multiplayer] sobre una mecánica que
todavía no sabemos si es divertida" — y se adelantó igual, con la excusa de
que "en la práctica... quedó más simple integrarlo ya que separarlo").

Esto no es un error de ejecución — cada decisión individual tiene una
justificación razonable en el momento ("ya que estamos"). El problema es el
patrón acumulado: **cero sesiones de playtesting humano documentadas en todo
el proyecto**. Todo lo que existe como "testing" son 40+ scripts GDScript que
verifican que la lógica no rompe (`tests/`), no que el juego sea divertido.
Eso es QA, no diseño. El propio README lo reconoce en el primer test listado
("la validación subjetiva del manejo y la diversión sigue pendiente de
playtesting") y ese texto no cambió en toda la sesión, mientras el scope
seguía creciendo.

---

## 3. La ruta procedural (implementada esta sesión) probablemente rompe el ritmo del juego

Esto es autocrítica directa de mi propio trabajo de hoy, y es uno de los
puntos más serios del documento.

- El pedido original era "tramos mucho más largos entre casa... mini
  aventuras". Lo que se construyó: **400-600 metros por tramo, con 3 casas
  por default → un recorrido de aproximadamente 2000 metros por partida**,
  contra los 220 metros originales.
- `docs/requerimientos-tecnicos.md` sección 3.1 dice explícitamente: **"loop
  base (~2-5 minutos por entrega)"** y que esa regla de oro es la base de
  todo el diseño de adicción/rejugabilidad. A la velocidad de manejo actual
  (`WALK_SPEED`/velocidad del vehículo documentada en otros params), 2000
  metros son varios minutos de más — nadie recalculó el tiempo de entrega
  real contra esa regla de oro antes de multiplicarlo por 9. Es un cambio de
  ritmo mayor que se hizo por sensación ("se siente mejor así") sin volver a
  mirar el propio documento de diseño que fija cuánto debería durar una
  entrega.
- Un viaje 9 veces más largo con las mismas 4 trampas y sin contenido nuevo
  en el medio (mismo bosque, mismos props reciclados, ningún evento nuevo
  además de los ya existentes) tiene un riesgo real de volverse **tedioso
  antes que "mini aventura"** — "mini" y "2000 metros" son términos en
  tensión. Nadie jugó esto de punta a punta como jugador real todavía (yo
  tampoco: lo verifiqué con tests automatizados y una captura de pantalla,
  no manejando la ruta completa).
- Efecto secundario no evaluado: con rutas tan largas, **la ventana de
  "casi se rompe, no se rompió" (near-miss) que el propio documento de
  parámetros identifica como el gancho principal** (`parametros-diseno.md`,
  "principio de diseño para los números") se diluye — más tiempo total
  significa más oportunidades de que un paquete se arruine del todo mucho
  antes de llegar, dejando al jugador pasajero sin nada que hacer el resto
  del viaje (la trampa arruinada no revive, ver sección 6).

---

## 4. No hay onboarding de ningún tipo

- `docs/controles-y-ui.md` lista **"Cómo jugar (tutorial)"** en el diseño
  original del menú y lo marca como **no implementado**, sin plan concreto
  de cuándo. El menú real (`main_menu.gd`) tiene tres botones: Jugar solo,
  Crear sala, Unirse por IP. Nada le explica a un jugador nuevo qué es una
  "trampa", qué significan los cuatro colores de estado de un paquete, ni
  qué botón mantiene/suelta/calma nada.
- El esquema de controles (`docs/controles-y-ui.md` sección 1) usa el mismo
  lenguaje genérico ("acción primaria: mantener", "acción secundaria: tap")
  para las 4 trampas **a propósito**, por consistencia — pero eso significa
  que sin explicación previa, un jugador nuevo sentado con un paquete
  "Equilibrio" no tiene ninguna pista de que mantener el clic izquierdo
  corrige el ángulo, más allá de un prompt de texto en pantalla que compite
  con otros cuatro elementos de HUD (ver sección 5).
- No hay pantalla de opciones. No hay reasignación de teclas. No hay
  control de volumen. Para un juego pensado para jugarse en grupo con gente
  que no necesariamente juega seguido (el público de un party game), la
  barrera de entrada real (¿cómo bajo el volumen del motor si molesta?,
  ¿cómo cambio de WASD si tengo teclado no-QWERTY?) está completamente sin
  resolver, y no está ni siquiera en el plan de fases con fecha.

---

## 5. El HUD es denso y compite consigo mismo

Basado en las capturas reales jugando la build de esta sesión: en pantalla,
simultáneamente, hay:

- Panel de título/sección de ruta (arriba izquierda).
- Velocímetro + tiempo + **"EQUIPO $100"** (arriba derecha) — moneda
  cooperativa mostrada todo el tiempo, sin ninguna explicación en pantalla
  de para qué sirve mientras se maneja.
- Panel de "CARGA" (estado del propio paquete) abajo izquierda.
- Panel de progreso/distancia a la entrega (abajo centro-derecha), que
  además reemplaza su contenido con el prompt de interacción
  ("Cargá el paquete y tomá el volante") en ciertos momentos.
- Prompt de interacción centrado en pantalla ("[E/A] Agarrar paquete").
- Banner de evento de ruta atravesando el centro de la pantalla
  ("[EVENTO] Inspección sorpresa...") **superpuesto en el mismo espacio
  vertical** que el prompt de interacción — en la captura real de esta
  sesión ambos textos casi se pisan.
- Una barra de atajos de teclado fija abajo de todo, permanente, en
  cualquier momento del juego, incluso después de que un jugador ya aprendió
  los controles.

Para un juego cuyo pitch central es "mirá el camino y reaccioná a los
golpes físicos", hay seis-siete elementos de texto compitiendo por atención
en la misma pantalla, todos con jerarquía visual similar (mismo tono de
fondo oscuro semitransparente, tipografía similar). Nada le dice al ojo
"esto es lo urgente ahora mismo" — todo grita al mismo volumen.

`docs/direccion-visual.md` sección 3 ya admite que la paleta de UI está
**duplicada entre `main_menu.gd` y `prototype_hud.gd`** en vez de vivir en un
lugar común — es un síntoma del mismo problema de fondo: nadie está mirando
el HUD como un sistema de jerarquía de información, cada pantalla agrega lo
suyo.

---

## 6. Las trampas, tal como están diseñadas, castigan sin dar nada de vuelta

- Una vez que un paquete llega a `Arruinado`, se marca como estado terminal
  (`parametros-diseno.md`, "reglas que surgieron al implementarlo": "arruinar
  un paquete ya no termina la entrega... la entrega sigue y simplemente se
  puntúa menos"). Eso está bien para no cortarle la partida a los demás, pero
  tiene un costo no resuelto: **el jugador cuyo paquete se arruinó no tiene
  nada que hacer el resto del viaje.** No hay una segunda vida, no hay un
  minijuego de "ayudá a otro", no hay nada — se convierte en pasajero pasivo
  mirando cómo los demás juegan, potencialmente por varios minutos si pasó
  temprano en una ruta de ~2000m (ver sección 3). Para un juego de fiesta
  donde la promesa es que todos estén activos todo el tiempo, esto es un
  agujero real.
- La trampa "Ruidoso" tiene una nota reveladora en su propio documento:
  *"la trampa ruidosa no se calma sola al máximo. El decaimiento pasivo se
  pausa una vez que llega al tope: si nadie la atiende, se escapa. Sin esto
  bajaba del máximo el mismo frame y era literalmente imposible de perder."*
  — es decir, el balance de esta trampa específica se ajustó para que **se
  pudiera perder**, no para que se sintiera bien perderla. Es un parche
  técnico presentado como decisión de diseño.
- Las cuatro trampas (Frágil, Peso creciente, Equilibrio, Ruidoso) son
  mecánicamente cuatro variantes del mismo patrón ("mantené un medidor
  dentro de un rango con un input"). Contra el catálogo mucho más rico que
  el propio `docs/economia-y-contramedidas.md` ya imagina (Explosivo,
  Apestoso/tóxico, Líquido) — ninguno de esos tres, que son los que de
  verdad introducirían mecánicas *distintas* entre sí (desactivar bajo
  presión, ventilar/sellar, mantener nivelado activamente en vez de pasivo),
  está implementado. Lo que hay hoy es menos variado de lo que el propio
  documento de economía ya asume como base.

---

## 7. Multijugador: fricción de conexión real, sin red de seguridad social

- El transporte por defecto usa **Steam con el AppID 480 (Spacewar)**, el
  de ejemplo público de Valve — documentado explícitamente como "no se puede
  publicar con ese id". Es una decisión correcta para prototipar, pero
  significa que **todo el flujo de invitación de amigos de Steam probado
  hasta ahora nunca fue con el juego real** — cuando llegue el appid
  definitivo hay que re-verificar todo ese camino, no asumir que "ya
  funcionaba".
- La alternativa LAN (`--host-lan` / `--join=<ip>`) tiene un gotcha de
  firewall de Windows documentado en el propio README ("las reglas quedan
  atadas a la ruta exacta del ejecutable... con el binario equivocado, el
  anfitrión abre el puerto pero nunca ve llegar a nadie, **en silencio**").
  Para el público real de un party game (grupos de amigos, no
  desarrolladores), depurar por qué nadie se puede conectar sin ningún
  mensaje de error visible en pantalla es una barrera de entrada seria, sin
  ninguna mitigación en UI (no hay "no se pudo conectar, revisá tu
  firewall").
- No hay ningún mecanismo de matchmaking, sala pública, ni código de sala
  corto — la única forma de jugar con gente que no está en tu lista de
  amigos de Steam es compartir una IP manualmente. Eso descarta de plano
  cualquier jugador que quiera sumarse por streaming/Discord de comunidad,
  que es exactamente el público que los juegos de referencia (Lethal
  Company, PEAK) explotaron para crecer virálmente.
- **Griefing en la economía cooperativa no está considerado en ningún
  documento**: el dinero es compartido y las compras se votan
  (`cartas-y-eventos-de-ruta.md`). ¿Qué pasa si un jugador vota
  sistemáticamente mal o abandona la sesión a mitad de una votación? No hay
  ni una línea sobre esto en ningún doc de diseño.

---

## 8. Dirección visual: la referencia (PEAK) no se está usando para lo que la hace funcionar

- `docs/direccion-visual.md` es honesto en su sección 0: **todo lo que existe
  hoy es geometría generada en código** (cajas, cápsulas). Eso es aceptable
  como placeholder de Fase 1-2, pero el documento fecha esto al **Fase 6**
  sin ningún hito intermedio — es "más adelante" sin un cuándo concreto, en
  un proyecto que ya lleva meta-progresión y economía implementadas antes que
  el arte base.
- El personaje que se construyó esta sesión (low-poly redondeado, cuerpo
  tipo "figura de juguete") es una interpretación razonable de "estilo
  PEAK", pero **PEAK no es solo su estética visual — es que los personajes
  son ragdolls físicos reales**, y el documento técnico lo tiene anotado
  como la decisión correcta desde el principio (`requerimientos-tecnicos.md`
  sección 2: "ragdoll físico... barato de animar... genera humor gratis").
  Lo que se construyó en su lugar son **animaciones tradicionales por
  hueso** (Idle/Walk/Jump/Die/PickUpPackage, todas con keyframes a mano) —
  exactamente lo opuesto a la decisión de arquitectura que el propio
  proyecto ya había tomado, y sin que nadie revisara esa contradicción antes
  de construirlo. Las animaciones a mano no son necesariamente un error, pero
  el juego ahora tiene una base de personaje que **no** es la que su propio
  documento técnico especificaba para lograr la comedia física de la
  referencia.
- No existe ninguna decisión sobre clima, hora del día, ni variación de
  ambientación más allá de "bosque siempre igual" (`direccion-visual.md`
  secciones 4 y 5 marcan lluvia/asfalto mojado/nubes procedurales como
  `[ ]`, sin evaluar). Con una ruta ahora de ~2000m por partida, la falta de
  variedad ambiental durante ese recorrido es más notoria que antes, no
  menos.
- SSAO está confirmado bloqueado por el renderer actual (`GL Compatibility`)
  y la nota en `tareas-nacho.md` dice explícitamente "no reabrir sin decidir
  primero migrar a Forward+" — es decir, hay un techo de calidad visual
  conocido y aceptado sin que exista todavía una decisión sobre si el
  proyecto se queda en ese renderer para siempre o no. Esa decisión afecta
  directamente qué tan bien se puede ver el arte final de Fase 6 cuando
  llegue, y no está tomada.

---

## 9. Proceso de equipo: la división de dominios por archivo está generando fricción, no evitándola

`docs/colaboracion-equipo.md` divide el trabajo entre Nacho (vehículo/ruta/
ambientación) y Slatex (jugador/paquetes/interacción/UI/progresión) por
**archivo**, con la regla implícita de "avisar antes de tocar lo del otro".
En la práctica, durante esta sola sesión:

- Se tuvo que tocar `main_menu.gd`, `run_manager.gd`, `level_base.gd`,
  `player.gd` y `prototype_hud.gd` — todos marcados como zona de Slatex —
  para conectar el modo Endless al menú, el puntaje por distancia, y el
  personaje nuevo. Cada vez, la única forma de avanzar fue el usuario
  autorizando explícitamente "tocalo igual", no un proceso real de
  coordinación con la otra persona.
- Un merge real durante la sesión (7 commits de Slatex: progresión de
  tripulación, votación de tienda, eventos de ruta, identidad de paquetes,
  estantes de carga) tocó **exactamente los mismos archivos** que se estaban
  modificando en paralelo del lado de Nacho. El merge automático de git no
  tuvo conflictos de texto esta vez, pero fue suerte de que los cambios no
  se solaparan línea por línea — con dos personas construyendo sistemas
  grandes (economía completa vs. generación de ruta completa) sobre los
  mismos archivos de base al mismo tiempo, un conflicto real es cuestión de
  tiempo, no de si.
- Nadie parece tener la responsabilidad explícita de "¿esto que estamos
  construyendo en paralelo encaja en un mismo juego?" — cada dominio avanza
  su propia lista de 100 tareas (`tareas-nacho.md`, `tareas-slatex.md`) de
  forma independiente. El resultado observable es justamente el problema de
  la sección 1: dos visiones de juego (caos físico simple vs. economía
  cooperativa profunda) creciendo en paralelo sin que ningún documento las
  concilie.

---

## 10. Resumen priorizado — qué mirar primero si esto fuera una auditoría real

1. **Jugar la versión actual con humanos reales, ya**, antes de tocar una
   sola línea de código más. Cero sesiones de playtesting documentadas
   después de meses de desarrollo (por el historial de commits) es la
   alarma más grande de todo este documento.
2. **Decidir el largo real de una entrega** contra la propia regla de oro de
   2-5 minutos (sección 3) — la ruta de esta sesión probablemente la viola,
   y nadie lo midió con un cronómetro todavía.
3. **Decidir si el juego es un party game corto o un roguelite de economía
   cooperativa** (sección 1) — ahora mismo intenta ser los dos en el mismo
   HUD, en la misma sesión, y compite consigo mismo.
4. **Darle algo que hacer al jugador cuyo paquete ya se arruinó** (sección
   6) — con rutas más largas, este agujero se hace más grande, no más
   chico.
5. **Un tutorial mínimo**, aunque sea texto (sección 4) — el juego ya tiene
   más sistemas (trampas + votación + cartas + eventos + mérito) que
   cualquier jugador nuevo puede aprender sin guía.
6. **Simplificar el HUD** a "una sola cosa urgente a la vez" (sección 5)
   antes de sumar más paneles.

Nada de esto es irreversible ni catastrófico — es exactamente el tipo de
cosas que un playtesting real con gente ajena al proyecto destaparía en la
primera sesión. El riesgo real es seguir agregando sistemas antes de tener
esa sesión.
