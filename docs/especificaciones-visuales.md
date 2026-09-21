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
| 1 | **Las ruedas no giran.** `VehicleWheel3D` no rota las mallas hijas por su cuenta; hay que rotar `Tire`/`Hub` según `get_rpm()`. Hoy la camioneta se desplaza con las ruedas congeladas — es lo primero que delata que algo no está vivo. | **A** |
| 2 | **Las ruedas delanteras no giran al doblar.** La física dirige (`steering`), pero la malla apunta siempre al frente. Rotar el nodo de la rueda en Y según el ángulo de dirección. | **A** |
| 3 | **El volante no se mueve.** El toroide de `SteeringWheel` es estático. Rotarlo en su eje proporcional a `steering`, con un multiplicador (una vuelta de volante ≈ mucho más que el ángulo real de rueda). | **A** |
| 4 | **Suspensión sin recorrido visual.** Las ruedas están en posición fija; deberían subir y bajar con el recorrido real de la suspensión al pasar un badén. | **A** |
| 5 | Silueta de la furgoneta: hoy es una caja sobre otra caja. Necesita biselado de aristas, trompa levemente inclinada y proporciones de vehículo real. | **B** |
| 6 | Guardabarros / arcos de rueda: las ruedas flotan junto a un panel plano, sin hueco que las contenga. | **B** |
| 7 | Neumático con dibujo y llanta diferenciada. Hoy son dos cilindros concéntricos lisos. | **B** |
| 8 | Líneas de paneles y juntas de puertas en la carrocería — sin ellas la caja se lee como caja, no como chapa. | **B** |
| 9 | **Espejos retrovisores laterales.** Ausentes. Además de correctos, encuadran bien el plano en primera persona y dan sensación de cabina real. | **B** |
| 10 | Puertas traseras reales en la zona de carga (hoy `Tailgate` es una caja fija). | **B** |
| 11 | Mampara entre cabina y zona de carga: hoy son dos volúmenes conceptualmente separados sin nada que los divida visualmente. | **B** |
| 12 | Tablero: hoy es una sola caja oscura. Necesita tablero de instrumentos, rejillas de ventilación, guantera, palanca de cambios. | **B** |
| 13 | Volante con rayos y cubo central — el toroide de 8 anillos se lee como un anillo flotante. | **B** |
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
| 24 | **Peso Creciente debería verse crecer**: escalar la caja progresivamente y hundirla contra el piso a medida que el temporizador avanza. Hoy el peso cambia solo como número. | **A** |
| 25 | **Equilibrio debería verse inclinarse**: la caja tendría que ladearse visiblemente según el ángulo acumulado, antes de fallar. | **A** |
| 26 | **Ruidoso debería moverse solo**: sacudidas cortas y aleatorias desde adentro, más frecuentes cuanto más agitado. | **A** |
| 27 | Parpadeo de faros al recibir un impacto fuerte. | **A** |
| 28 | Luces de freno que se encienden al frenar de verdad (hoy las traseras son emisivas fijas). | **A** |
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
| 41 | **Sonido de motor ligado a la velocidad.** Hoy el único audio del juego es la bocina. Es probablemente el agujero sensorial más grande que queda. | **A** |
| 42 | **Sonido de impacto** al golpear algo, escalado por fuerza — la señal `vehicle_impact` ya existe y ya lleva la magnitud. | **A** |
| 43 | **Sonidos por trampa**: vidrio tintineando, algo vivo quejándose, peso crujiendo. Refuerza qué paquete está en problemas sin mirar el HUD. | **A** |
| 44 | Chirrido de neumáticos al derrapar o frenar fuerte. | **A** |
| 45 | Ambiente exterior: viento, pájaros, ruido lejano de ruta. | **A** |
| 46 | **Reverb distinta dentro de la furgoneta vs. afuera** — barato en Godot (buses de audio) y vende muchísimo el "estoy adentro de una caja de metal". | **B** |
| 47 | Música: al menos un tema de tensión que suba con el riesgo acumulado de la carga. | **B** |
| 48 | **Los faros no iluminan.** Son cajas emisivas sin `SpotLight3D` detrás. Hoy no aportan nada funcional. | **A** |
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
| 60 | Oclusión ambiental (SSAO): sin ella, las cajas apoyadas sobre otras cajas flotan visualmente. | **A** |

---

## 4. Cámara (61-80)

| # | Especificación | Prio |
|---|---|---|
| 61 | **La cámara propia ve su propio cuerpo.** Documentado como rough edge conocido en `docs/direccion-visual.md` §8: hace falta separar por capas de render (`VisualInstance3D.layers` + `Camera3D.cull_mask`) para ocultar el cuerpo propio sin ocultar el de los demás. | **A** |
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
| 81 | **Los jugadores sentados son invisibles.** `board_seat()` hace `visible = false` al abordar: nadie ve a nadie durante el viaje entero, que es justo cuando la tensión compartida importa. Debería ocultarse solo el cuerpo propio (ver #61), no el de todos. | **A** |
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

Si hubiera que elegir cinco de los 100 para hacer mañana, serían estos — todos **A**,
todos sin pipeline de arte, y los cinco atacan la sensación de "esto no está vivo":

1. **#1, #2, #3** — ruedas que giran, ruedas que doblan, volante que se mueve. Son
   tres rotaciones de malla. Es la diferencia más grande por menos código que hay en
   toda la lista.
2. **#41** — sonido de motor. El juego hoy es mudo salvo la bocina.
3. **#61 + #81** — separar capas de render para que cada uno deje de ver su propio
   cuerpo y empiece a ver el de los demás. Un juego cooperativo donde nadie ve a
   nadie durante el viaje entero está desperdiciando su mecánica central.
4. **#24, #25, #26** — que cada trampa se vea hacer lo que hace. Hoy tres de las
   cuatro solo existen como números.
5. **#60** — oclusión ambiental. Una línea de configuración que hace que todo deje
   de flotar.

## Próximo paso
Esta lista es el inventario para la Fase 6 (`docs/plan-desarrollo.md`). Los ítems **A**
se pueden ir tomando de a uno sin esperar a nada; los **B** conviene agruparlos por
asset una vez que haya pipeline de arte, para no importar el mismo modelo dos veces.
