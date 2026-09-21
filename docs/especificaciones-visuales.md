# 100 especificaciones visuales a mejorar — Do Not Drop

> Última actualización: 2026-09-21
> Complementa `docs/direccion-visual.md` (que define *cómo se ve y por qué*) con una
> lista concreta y numerada de *qué falta*, para poder decir "hagamos el 47" sin
> ambigüedad. Escrito leyendo el estado real del proyecto hoy, no como checklist
> genérica de game dev — cada ítem se refiere a algo que existe (o no existe) en
> `do-not-drop/` a esta fecha.

## Cómo leer esta lista

**Estado de partida (verificado hoy):** toda la geometría del juego está generada en
código con primitivas (cajas, cápsulas, cilindros, un toroide y un casco convexo para
los badenes). No hay ni un solo asset de arte importado. **No hay ninguna animación en
todo el proyecto** — ni `AnimationPlayer`, ni `AnimationTree`, ni un solo `Tween`. El
único sonido que existe es la bocina, y está sintetizada en código. Las ruedas del
vehículo nunca rotan visualmente y el volante tampoco: la física de dirección funciona
(`steering` en `vehicle.gd`), pero ninguna malla la refleja.

Eso no es un defecto del trabajo hecho, es exactamente dónde debería estar un prototipo
que priorizó validar sistemas antes que arte (ver `docs/plan-desarrollo.md`). Esta lista
es el mapa de lo que viene después.

**Prioridades:**

| Marca | Significado |
|---|---|
| **A** | Alto impacto, bajo costo. Se puede hacer hoy, sin pipeline de arte, con código o primitivas. |
| **B** | Alto impacto, costo alto. Necesita assets reales — es trabajo de Fase 6. |
| **C** | Pulido. Vale la pena, pero recién cuando lo de arriba esté resuelto. |

Del total: **35 ítems A**, **47 B** y **18 C**. Los 35 marcados A son los que dan mejor
retorno inmediato y no dependen de tener modelos finales — si hubiera que elegir por
dónde empezar, es por ahí.

---

## 1. Modelado (1-20)

| # | Especificación | Prio |
|---|---|---|
| 1 | ~~Las ruedas no giran.~~ **[x] Hecho (2026-09-21).** El diagnóstico original (vía grep) estaba incompleto: `VehicleWheel3D` sí rota sus mallas hijas nativamente, pero solo en el peer con autoridad física (el host) — un cliente viendo manejar a otro jugador veía las ruedas congeladas porque solo se replicaba la posición del chasis, no la de cada rueda. Se agregó replicación del `transform` de las 4 ruedas (`vehicle.tscn`), así que ahora gira para todos, no solo para quien maneja. Cubierto por `tests/test_vehicle_presentation.gd` y `tests/vehicle_network_probe.gd` (dos procesos reales). | **A** |
| 2 | ~~Las ruedas delanteras no giran al doblar.~~ **[x] Hecho** — mismo fix que el #1: es nativo de `VehicleWheel3D`, solo hacía falta replicar el transform para que se vea en el cliente. | **A** |
| 3 | ~~El volante no se mueve.~~ **[x] Hecho (2026-09-21).** `VehiclePresentation` (`vehicle_presentation.gd`) rota el volante según `vehicle.steering * steering_ratio` (7:1 — una vuelta de volante notoria por un giro real de rueda chico). | **A** |
| 4 | ~~Suspensión sin recorrido visual.~~ **[x] Hecho** — consecuencia directa del #1: al replicarse el transform completo de cada rueda (no solo su rotación), el recorrido de suspensión también viaja. | **A** |
| 5 | Silueta de la furgoneta: hoy es una caja sobre otra caja. Necesita biselado de aristas, trompa levemente inclinada y proporciones de vehículo real. | **B** |
| 6 | Guardabarros / arcos de rueda: las ruedas flotan junto a un panel plano, sin hueco que las contenga. | **B** |
| 7 | Neumático con dibujo y llanta diferenciada. Hoy son dos cilindros concéntricos lisos. | **B** |
| 8 | Líneas de paneles y juntas de puertas en la carrocería — sin ellas la caja se lee como caja, no como chapa. | **B** |
| 9 | **Espejos retrovisores laterales.** Ausentes. Además de correctos, encuadran bien el plano en primera persona y dan sensación de cabina real. | **B** |
| 10 | Puertas traseras reales en la zona de carga (hoy `Tailgate` es una caja fija). | **B** |
| 11 | Mampara entre cabina y zona de carga: hoy son dos volúmenes conceptualmente separados sin nada que los divida visualmente. | **B** |
| 12 | Tablero: hoy es una sola caja oscura. Necesita tablero de instrumentos, rejillas de ventilación, guantera, palanca de cambios. | **B** |
| 13 | ~~Volante con rayos y cubo central.~~ **[x] Hecho (2026-09-21)** — `VehiclePresentation._build_steering_details()` agrega 3 rayos y un cubo central al toroide. | **B** |
| 14 | Pedales: ausentes. Se ven al mirar hacia abajo desde el asiento del conductor. | **C** |
| 15 | Asientos con apoyacabezas y estructura; hoy son dos cajas (almohadón + respaldo). | **B** |
| 16 | Cinturones de seguridad — venden "estoy atado a esto" en un juego que trata de sacudidas. | **C** |
| 17 | **Paquete con identidad por trampa.** Hoy las cuatro trampas son la misma caja con distinto color y texto. Frágil debería leerse frágil (símbolos de copa rota), Ruidoso tener agujeros de ventilación, Equilibrio ser alto y angosto, Peso Creciente ser bajo y macizo. Es la mecánica central: tiene que reconocerse de un vistazo. | **B** |
| 18 | Detalle de cartón en los paquetes: solapas, cinta, etiquetas, abolladuras. | **B** |
| 19 | **Modelo humanoide para el jugador.** Hoy es una cápsula. Sin cabeza, torso, brazos ni piernas, no hay a quién mirar ni a quién animar. | **B** |
| 20 | Manos del viewmodel con dedos y guantes (ver decisión de guantes en `docs/direccion-visual.md` §1). Hoy son dos cápsulas. | **B** |

---

## 2. Animación (21-40)

> Recordatorio: **no existe ninguna animación en el proyecto**. Todo lo de esta sección
> parte de cero, pero varios ítems son código puro (rotar, interpolar, sacudir) y no
> necesitan un animador ni un rig.

| # | Especificación | Prio |
|---|---|---|
| 21 | **Balanceo de carrocería exagerado** en curvas y frenadas, por encima de lo que ya hace la física — vende el peso de la furgoneta. | **A** |
| 22 | **Asentamiento del paquete**: al apoyarlo en su soporte debería acomodarse con un pequeño rebote, no aparecer clavado. | **A** |
| 23 | **Sacudida del paquete proporcional al golpe**, visible en su propia malla, no solo en la cámara. | **A** |
| 24 | ~~Peso Creciente debería verse crecer.~~ **[x] Hecho (2026-09-21)** — `package_feedback.gd` escala la caja hasta 1.35x y la hunde contra el piso según la distancia a fallar (derivada de `package_integrity_changed`, ya relayeado, no hace falta una señal nueva). | **A** |
| 25 | ~~Equilibrio debería verse inclinarse.~~ **[x] Ya lo hacía, sin código nuevo.** El paquete es un `RigidBody3D` real y la trampa ya rota su `global_transform` de verdad (`balance_trap_behavior.gd`) — lo que la física dibuja ya era el ángulo real. No había nada que visualizar aparte. | **A** |
| 26 | ~~Ruidoso debería moverse solo.~~ **[x] Hecho (2026-09-21)** — `package_feedback.gd` sacude Box/correas/etiquetas con una fase distinta por paquete (para que dos Ruidosos juntos no tiemblen al unísono), proporcional a la agitación. Nunca toca el `RigidBody3D` real, así que no puede desincronizar física ni red. | **A** |
| 27 | ~~Parpadeo de faros al recibir un impacto fuerte.~~ **[x] Hecho** — `VehiclePresentation._on_impact()` atenúa los faros un instante (`impact_flicker_seconds`) en golpes fuertes cerca del vehículo, nunca repetido. | **A** |
| 28 | ~~Luces de freno que se encienden al frenar de verdad.~~ **[x] Hecho** — `presentation_braking` (replicado) sube la emisión de las luces traseras cuando `brake > 3.0` de verdad, no un valor fijo. | **A** |
| 29 | Ciclo de caminata del jugador a pie. | **B** |
| 30 | Idle con respiración — sin él, un personaje quieto se lee como muerto. | **B** |
| 31 | Transición de sentarse: hoy abordar un asiento es un corte instantáneo de cámara. | **B** |
| 32 | Manos del conductor siguiendo el volante con IK, en vez de estar fijas en el aire. | **B** |
| 33 | Manos del pasajero agarrando físicamente su paquete mientras lo sostiene. | **B** |
| 34 | Animación de la acción de trampa (mantener/calmar/corregir) — hoy el input no tiene ninguna contraparte visual. | **B** |
| 35 | Gesto de brazo al tocar bocina. | **C** |
| 36 | Reacción de flinch/encogerse del personaje ante un golpe fuerte. | **B** |
| 37 | **Ragdoll físico al fallar**, ya decidido en `docs/requerimientos-tecnicos.md` §2 — es la fuente principal de humor del género. | **B** |
| 38 | Apertura y cierre de puertas al subir o bajar. | **C** |
| 39 | Animación de entrega exitosa: el paquete siendo depositado, no desapareciendo. | **C** |
| 40 | Head bob al caminar (ver también #63, donde toca a la cámara). | **B** |

---

## 3. Ambientación (41-60)

| # | Especificación | Prio |
|---|---|---|
| 41 | ~~Sonido de motor ligado a la velocidad.~~ **[x] Hecho (2026-09-21)** — `SynthAudio.engine_loop()` (armónicos sintetizados, sin asset) + `VehiclePresentation._update_engine()`: el pitch y volumen siguen velocidad y carga del motor en tiempo real. | **A** |
| 42 | **Sonido de impacto** al golpear algo, escalado por fuerza — la señal `vehicle_impact` ya existe y ya lleva la magnitud. | **A** |
| 43 | **Sonidos por trampa**: vidrio tintineando, algo vivo quejándose, peso crujiendo. Refuerza qué paquete está en problemas sin mirar el HUD. | **A** |
| 44 | Chirrido de neumáticos al derrapar o frenar fuerte. | **A** |
| 45 | Ambiente exterior: viento, pájaros, ruido lejano de ruta. | **A** |
| 46 | **Reverb distinta dentro de la furgoneta vs. afuera** — barato en Godot (buses de audio) y vende muchísimo el "estoy adentro de una caja de metal". | **B** |
| 47 | Música: al menos un tema de tensión que suba con el riesgo acumulado de la carga. | **B** |
| 48 | ~~Los faros no iluminan.~~ **[x] Hecho (2026-09-21)** — dos `SpotLight3D` reales por faro, que se apagan/encienden con `presentation_engine_running`. | **A** |
| 49 | Partículas de polvo/tierra bajo las ruedas al acelerar o derrapar. | **A** |
| 50 | Humo de escape en el caño trasero. | **C** |
| 51 | Marcas de neumático en el asfalto al frenar. | **C** |
| 52 | **Props de banquina**: árboles, postes, carteles, cercas, tachos. Hoy solo hay 10 cajas grises como referencia de escala. | **B** |
| 53 | Cableado eléctrico entre postes — barato y da muchísima lectura de profundidad y velocidad. | **B** |
| 54 | Edificios con ventanas, techos y puertas; hoy los "edificios" son cajas grises lisas. | **B** |
| 55 | Vehículos estacionados al costado de la ruta (y, más adelante, tráfico en movimiento). | **B** |
| 56 | Variación de hora del día: el sol está fijo en un solo ángulo (-48°/-28°). | **C** |
| 57 | Clima: lluvia, asfalto mojado con reflejos. Cambia por completo el tono y agrega dificultad natural. | **C** |
| 58 | Nubes en el cielo procedural — hoy es un degradé liso. | **C** |
| 59 | Silueta de horizonte / terreno lejano, para que el mundo no termine en una línea plana. | **B** |
| 60 | Oclusión ambiental (SSAO): sin ella, las cajas apoyadas sobre otras cajas flotan visualmente. **Bloqueado, no es tan "A" como parecía**: probado en 2026-09-21 — el proyecto usa `renderer/rendering_method = "gl_compatibility"` (`project.godot`), y ese renderer **no soporta SSAO en absoluto** en Godot 4 (ni SSIL, SSR, SDFGI ni niebla volumétrica; solo Forward+ los soporta). Activar `ssao_enabled` ahí no rompe nada ni tira error, simplemente no hace nada — se comprobó booteando el juego real y revirtiendo el cambio al no encontrar ninguna diferencia posible de verificar. Para tenerlo de verdad hay que migrar a Forward+, que es un cambio de renderer con impacto más amplio (compatibilidad de hardware, otros efectos), no una línea de configuración suelta. | **B** |

---

## 4. Cámara (61-80)

| # | Especificación | Prio |
|---|---|---|
| 61 | ~~La cámara propia ve su propio cuerpo.~~ **[x] Hecho (2026-09-21)** — `render_layers.gd` separa capa `LOCAL_BODY` (excluida del `cull_mask` de la propia cámara) de `WORLD` (visible para las demás). Cada jugador deja de ver su propia cápsula; sigue viendo la de los demás. | **A** |
| 62 | **Transición al sentarse es un corte seco.** Una interpolación corta de la cámara al asiento se siente mucho mejor y cuesta poco. | **A** |
| 63 | Head bob al caminar a pie — hoy el desplazamiento es perfectamente plano y se siente a patines. | **A** |
| 64 | FOV distinto por contexto: caminando, conduciendo y sosteniendo un paquete no deberían compartir el mismo encuadre. | **A** |
| 65 | **FOV configurable por el jugador.** No hay pantalla de opciones todavía; cuando exista, esto va primero (accesibilidad y mareo). | **B** |
| 66 | **Intensidad de sacudida distinta por asiento**: atrás se siente más que adelante. Hoy todos los asientos comparten los mismos valores. | **A** |
| 67 | Sacudida de cámara también al arruinarse un paquete, no solo al golpear el vehículo. | **A** |
| 68 | Manera de mirar hacia atrás: los espejos (#9) o una tecla dedicada. Hoy el yaw llega a ±160°, que alcanza pero es incómodo. | **B** |
| 69 | Cámara de resultados: un plano cinematográfico de la furgoneta al terminar, en vez del overlay sobre la vista congelada. | **C** |
| 70 | Profundidad de campo sutil sobre el paquete cuando lo estás atendiendo. | **C** |
| 71 | Viñeta que se intensifica cuando la carga está en riesgo — comunica tensión sin texto. | **B** |
| 72 | Aberración cromática breve en impactos muy fuertes. | **C** |
| 73 | Motion blur por velocidad, sutil. | **C** |
| 74 | Modo espectador para quien ya perdió su paquete, en vez de quedarse mirando una caja rota. | **B** |
| 75 | Cámara en tercera persona alternable, solo para desarrollo — hoy es imposible ver la furgoneta desde afuera sin editar la escena. | **A** |
| 76 | Modo foto: aporta directamente al objetivo de "momentos clipeables" (`docs/requerimientos-tecnicos.md` §3.4). | **C** |
| 77 | Fundido a negro al reiniciar la partida, en vez del salto brusco actual. | **A** |
| 78 | Límite de pitch contextual: mirar 80° hacia arriba adentro de la cabina sigue sin aportar nada, aun con el techo ya corregido. | **C** |
| 79 | Retroalimentación de cámara al pingear: un destello o marca en el borde de pantalla apuntando hacia quién pingeó. | **B** |
| 80 | Evitar que la cámara atraviese geometría cercana al mirar en diagonal dentro de la cabina (fade o retroceso). | **B** |

---

## 5. Interacción entre modelos (81-100)

| # | Especificación | Prio |
|---|---|---|
| 81 | ~~Los jugadores sentados son invisibles.~~ **[x] Hecho (2026-09-21).** `board_seat()` ya no hace `visible = false`. En cambio, cada `Player` guarda `seat_node_path` (nueva propiedad replicada) y en `_process()` — en la copia de **cada** peer, no solo la del que se sentó — posiciona su `BodyVisual` en la pose del asiento cada frame. No se reparentó el nodo (habría roto la replicación de posición, que es local al padre actual); en cambio se dejó la posición/rotación real del `Player` sin tocar y solo se reposiciona la malla visual, que no es una propiedad de red. Cubierto por `tests/test_seated_body.gd`. | **A** |
| 82 | El paquete sostenido flota frente a la cámara sin contacto con las manos; debería verse agarrado. | **B** |
| 83 | Abolladuras o deformación progresiva del paquete según el daño acumulado — hoy solo cambia de color. | **B** |
| 84 | Los paquetes deberían chocar entre sí de forma visible y encadenar caos (ya comparten capa de física). | **A** |
| 85 | El cuerpo del jugador debería colisionar con el interior de la furgoneta, no atravesarlo. | **A** |
| 86 | Correas o amarres que sujeten los paquetes al soporte, y que se vean tensarse en las curvas. | **B** |
| 87 | Si la puerta trasera está abierta, la carga suelta debería poder salirse. Excelente fuente de caos. | **B** |
| 88 | Objetos sueltos en la zona de carga que traqueteen con los golpes (herramientas, un termo). | **B** |
| 89 | La furgoneta debería poder voltear props de banquina (#52), no atravesarlos. | **B** |
| 90 | Escombros y partículas al chocar contra algo sólido. | **B** |
| 91 | Rayones y abolladuras acumuladas en la carrocería a lo largo de la entrega. | **C** |
| 92 | Un paquete suelto debería poder golpear a un jugador y empujarlo (con ragdoll, #37, es humor gratis). | **B** |
| 93 | Traspaso de paquete entre jugadores mano a mano, sin pasar por el piso. | **C** |
| 94 | Indicación visual de asiento ocupado vs. libre, más allá del texto del prompt. | **A** |
| 95 | Las manos del conductor deberían ser visibles para los pasajeros — hoy nadie ve a nadie conducir. | **B** |
| 96 | La furgoneta debería hundirse levemente según el peso total de la carga (conecta directo con la trampa de Peso Creciente). | **A** |
| 97 | Sombras de los personajes proyectadas dentro de la cabina, para que se sientan presentes en el espacio. | **B** |
| 98 | Resaltado del objeto interactuable al apuntarlo (outline), en vez de solo el texto del prompt. | **A** |
| 99 | Reacción del paquete al input del jugador: que se vea sostenido, calmado o corregido cuando presionás. | **A** |
| 100 | Marcador sobre el compañero que pingeó, visible a través de la carrocería, para ubicarlo sin tener que girar la cámara. | **B** |

---

## Por dónde empezaría

> Actualizado 2026-09-21: los cinco de la lista original ya están hechos
> (#1/#2/#3, #41, #61+#81). Los siguientes dos candidatos:

1. ~~**#1, #2, #3** — ruedas que giran, ruedas que doblan, volante que se mueve.~~
   **Hecho.**
2. ~~**#41** — sonido de motor.~~ **Hecho.**
3. ~~**#61 + #81** — que cada uno deje de ver su propio cuerpo y los demás sí vean
   el de cada uno mientras viajan sentados.~~ **Hecho.**
4. ~~**#24, #25, #26** — que cada trampa se vea hacer lo que hace.~~ **Hecho** (el
   #25 ya lo hacía solo, sin código nuevo).
5. ~~**#60** — oclusión ambiental.~~ **Resultó no ser tan simple**: el renderer
   actual (`gl_compatibility`) no soporta SSAO en absoluto en Godot 4. No es una
   línea de configuración, es un cambio de renderer — bajado de prioridad a **B**
   y anotado en su fila.

## Próximo paso
Esta lista es el inventario para la Fase 6 (`docs/plan-desarrollo.md`). Los ítems **A**
se pueden ir tomando de a uno sin esperar a nada; los **B** conviene agruparlos por
asset una vez que haya pipeline de arte, para no importar el mismo modelo dos veces.
