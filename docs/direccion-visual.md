# Dirección visual — Do Not Drop

> Última actualización: 2026-09-21
> Complementa `docs/requerimientos-tecnicos.md` sección 2 (pipeline de arte, low-poly
> estilo PEAK) y la sección "Decisión de cámara" de ese mismo doc. Ese documento dice
> *qué estilo* usar en términos generales; este detalla *cómo se ve y se siente* en
> cada sistema concreto — punto de vista, paleta, luz, qué existe visualmente y qué no.
>
> Marca `[x]` lo que ya está implementado y verificable en el código hoy, `[ ]` lo que
> es propuesta/pendiente de decisión. La idea es que este documento se vaya
> actualizando a medida que se toman decisiones, no que sea un plan cerrado de una vez.

## 0. Filosofía visual (por qué se ve como se ve)

- **Low-poly estilizado, no realista.** Coherente con la investigación de mercado:
  el arte nunca es el cuello de botella para un dev solo, el diseño de sistemas sí.
  Colores saturados y planos en vez de texturas fotorealistas — permite usar packs
  ya hechos (Kenney.nl) y mantener consistencia visual sin pipeline de texturizado.
- **Todo lo que existe hoy es geometría generada en código** (`BoxMesh`, cápsulas,
  `SurfaceTool` para el badén), sin un solo asset de arte importado todavía. Esto
  no es el estilo final — es el estado real del prototipo (Fase 1-2 del plan), y
  hay que leerlo como tal: los colores y proporciones de abajo son los que ya están
  ajustados y probados, la geometría específica (formas reales de props/personajes)
  es lo que la Fase 6 va a reemplazar.
- **La cámara vende el caos físico** (ver sección 2): sin suavizado, sin cámara
  lenta artificial, todo lo que se ve es la física real reaccionando en vivo. Esto
  es una decisión de diseño, no solo estética — el paquete se rompe por los mismos
  golpes que sacude al jugador, así que ocultar esa sacudida con una cámara suave
  rompería la lectura de la mecánica central.

## 1. Punto de vista del jugador

**[x] Primera persona, por asiento, siempre.** Nunca hay cámara en tercera persona
ni una vista aérea. Cada jugador ve el mundo desde los ojos de su propio personaje —
ver `docs/requerimientos-tecnicos.md` "Decisión de cámara" para el porqué (PEAK es en
realidad primera persona, no tercera como parece a simple vista).

| Parámetro | Valor actual | Archivo |
|---|---|---|
| FOV | 78° | `first_person_camera.gd` |
| Near clip | 0.03 m | `first_person_camera.gd` |
| Far clip | por defecto del motor (no fijado explícitamente) | — |
| Límite de giro horizontal (yaw) | ±160° desde el frente del asiento | `first_person_camera.gd` |
| Límite de giro vertical (pitch) | ±80° | `first_person_camera.gd` |
| Sensibilidad mouse | 0.0028 rad/px | `first_person_camera.gd` |
| Sensibilidad stick | 2.4 rad/s a fondo | `first_person_camera.gd` |

- **[x] Sin suavizado de cámara.** El transform de la cámara sigue al asiento
  frame a frame, sin lerp. El único movimiento "extra" es el shake de impacto
  (sección 5), que es deliberadamente brusco, no un filtro suave.
- **[x] Rígida al asiento, no al mundo.** La cámara es hija del `Marker3D` del
  asiento — hereda su transform por jerarquía de escena. Girar la camioneta gira
  al jugador con ella (correcto: estás sentado adentro), pero mirar alrededor
  (mouse/stick derecho) es relativo al asiento, no cambia la dirección del vehículo.
- **[x] `C`/clic del stick derecho recentra la vista** al frente del asiento —
  necesario porque sin él, en un yaw de ±160°, sería fácil perderse mirando hacia
  atrás sin saber cómo volver al frente rápido.
- **[ ] Far clip / distancia de dibujo**: no está fijado explícitamente (usa el
  default del motor). Con el streaming de tramos de la Fase 3 (`RouteStreamer`,
  ver `docs/plan-desarrollo.md`) esto va a importar de verdad — un tramo
  apareciendo de la nada a poca distancia se nota mucho más que uno curado a mano.
  **Pendiente de decidir**: ¿niebla de distancia para disimular el borde de lo
  generado (ver sección 4), o simplemente generar con suficiente anticipación
  (`lookahead_distance` ya es ajustable en `RouteStreamer`) para que nunca se vea
  el borde?

### Manos / viewmodel
- **[x] El jugador ve sus propias manos** — del conductor en el volante, del
  pasajero cerca de su paquete (ver `docs/requerimientos-tecnicos.md`, "Flujo
  físico de carga y abordaje"). Son cápsulas placeholder hoy, ancladas a la
  cámara y alineadas con el volante/paquete.
- **[ ] Arte final de manos**: pendiente de Fase 6. Deciding factor: ¿manos con
  guantes/mangas (más fácil de hacer low-poly genérico, cubre más error de
  proporción) o manos "desnudas" con variación de piel/skins (más personalizable,
  pero es contenido de meta-progresión que todavía no existe, ver
  `docs/plan-desarrollo.md` Fase 5)?

## 2. El mundo: escala y proporción

- **1 unidad de Godot = 1 metro**, confirmado desde Fase 0.
- Camioneta: cabina + hasta 4 asientos de pasajero en los laterales de la zona de
  carga (ver `vehicle.tscn`). Altura de ojos del conductor sentado: ver
  `DriverEyePoint` en `vehicle.tscn` (~1.15-1.35 m sobre el piso del vehículo,
  verificado por `check_driver_sightline.gd`).
- Ruta actual (`route.gd`, curada a mano): 220 m, ancho de calzada 12 m en tramo
  normal, se angosta a 5.8 m en el puente (fuerza precisión de manejo), badenes de
  0.17-0.22 m de alto.
- **[ ] Escala de personajes/props**: sin definir formalmente todavía (no hay
  personaje con arte final). Referencia implícita por los `Marker3D` de asiento y
  la altura de cámara: un adulto promedio, ~1.7-1.8 m de alto de ojos parado.

## 3. Paleta de colores

Ya hay **tres paletas coherentes entre sí** en uso real, no elegidas al azar — nacen
de la misma lógica (tonos fríos apagados para el mundo, acentos cálidos/saturados
para lo que importa mirar). Vale la pena declararlas como una paleta única de marca
en vez de mantenerlas duplicadas por archivo.

### Mundo (ruta, terreno — `route.gd`)
| Nombre | Hex | Uso |
|---|---|---|
| ROAD | `#394a50` | Asfalto |
| SHOULDER | `#63736f` | Banquina / suelo |
| MARKING | `#d4d9c2` | Líneas de carril |
| WARNING | `#e7be51` | Badenes, avisos, franjas de precaución |
| TEAL | `#65b5a1` | Zona de entrega, líneas de salida |
| CONCRETE | `#8c9791` | Barreras, postes, chicana |

### Cielo / luz ambiente (`level_base.tscn`)
| Elemento | Valor |
|---|---|
| Cielo (tope) | `#48757a` |
| Cielo (horizonte) | `#b8ccc9` |
| Suelo (bajo) | `#3d5248` |
| Luz ambiente | `#c2dbe6`, energía 0.65 |
| Sol (`DirectionalLight3D`) | `#ffedcc` aprox. (1, 0.93, 0.8), energía 1.2, rotación -48°/-28°, sombras activas hasta 100 m |

### UI (compartida entre `main_menu.gd` y `prototype_hud.gd`)
| Nombre | Hex | Uso |
|---|---|---|
| INK | `#132a31` | Fondo de paneles, texto sobre superficies claras |
| PAPER | `#edf2e8` | Texto principal sobre fondo oscuro |
| MUTED | `#acc1bd` | Texto secundario |
| MINT | `#83e2ba` | Acento primario, botones activos, récords |
| YELLOW | `#f4c562` | Alertas suaves (pings) |
| RED | `#f47e6d` | Alertas fuertes, errores, "en riesgo" |

### Estado de los paquetes (`package_feedback.gd`)
| Estado | Color | Hex |
|---|---|---|
| OK (frágil, base) | ámbar | `#e8be77` |
| EN RIESGO | naranja | `#ff883d` |
| ARRUINADO | bordó apagado | `#9a4547` |

**[ ] Pendiente**: consolidar estas tres tablas en constantes compartidas (hoy cada
script redefine INK/PAPER/etc. por separado — `main_menu.gd` y `prototype_hud.gd`
tienen la misma paleta duplicada) — más una cuestión de mantenibilidad de código que
visual, pero vale la pena resolverlo antes de que se sumen más pantallas con la
misma paleta.

## 4. Iluminación, cielo y niebla

- **[x] Luz direccional única** ("Sol"), ángulo bajo (-48° de altura) — sombras
  largas, más dramatismo que un mediodía cenital plano.
- **[x] Ambient light** desde el cielo (`ambient_light_source = 3`, es decir, del
  `Sky`), energía moderada (0.65) — evita sombras completamente negras sin
  necesitar luces de relleno adicionales.
- **[x] Cielo procedural** (`ProceduralSkyMaterial`), no un skybox de imagen —
  gratis en rendimiento, sin asset que mantener, y combina bien con el estilo
  low-poly de colores planos.
- **[ ] Tonemap**: actualmente `tonemap_mode = 0` (Linear, sin ajuste). Godot trae
  Filmic/ACES listos para usar con un solo campo. **Recomendación**: probar Filmic
  o ACES cuando haya más contraste de escenas (interiores oscuros de furgoneta vs.
  exteriores soleados) — Linear tiende a "quemar" los blancos en esa transición.
  No urge mientras todo sea geometría de colores planos sin mucho rango dinámico.
- **[ ] Niebla de distancia**: no implementada. Relevante por dos razones
  distintas, que pueden pedir soluciones distintas:
  1. **Estética**: refuerza profundidad/escala en una ruta larga (220 m+, más con
     streaming).
  2. **Oculta el "borde del mundo"** del streaming de tramos (`RouteStreamer`) —
     tapar con niebla el punto exacto donde un tramo nuevo aparece es más barato
     que generar con muchísima anticipación, y es el truco estándar de juegos con
     mundo generado en tiempo real.
  **Pendiente de decisión**: ¿niebla sutil todo el tiempo (más atmosférico) o
  activarla recién si el modo endless (Fase 3.5+) la necesita para disimular el
  streaming? Dado que hoy la ruta curada no tiene ese problema, no hay apuro.

## 5. Qué ve el jugador y qué no (oclusión, interior/exterior)

Esta sección es, literalmente, "qué hay y qué no hay que tapar" — el pedido
específico de "campo de visión, qué ve y qué no".

- **[x] Interior de la camioneta es real geometría, no un truco.** Cabina con
  tablero y volante, asientos de pasajero con su paquete enfrente — el jugador
  está físicamente adentro de un volumen 3D real, no una imagen pegada.
- **[x] El parabrisas es transparente de verdad** (`transparency = 1`,
  `albedo_color` con alpha 0.18, ligeramente tintado, `metallic = 0.35`,
  `roughness = 0.28` — vidrio, no un agujero en la carrocería). Verificado por
  `check_driver_sightline.gd`: nada bloquea la vista del conductor hacia la ruta —
  ni el tablero, ni el volante, ni un "vidrio" que en realidad fuera opaco.
- **[x] La carrocería vista desde adentro no bloquea** — las caras traseras se
  cullean (`cull_mode` en los materiales relevantes) para que estar sentado
  adentro del volumen del vehículo no muestre el interior de las paredes exteriores
  como si fueran una caja cerrada encima de la cabeza.
- **[x] Los pasajeros ven su paquete de cerca, ocupando buena parte del campo
  visual** — es la superficie principal de esa mecánica, tiene que ser lo primero
  que se lee al mirar al frente desde ese asiento.
- **[ ] Oclusión entre pasajeros**: no evaluado todavía. Con hasta 4 pasajeros +
  conductor en una furgoneta chica, ¿un pasajero puede ver a otro pasajero
  gestionando su propio paquete (refuerza la lectura social de "todos estamos en
  esto juntos"), o el diseño del interior los separa visualmente (cada uno
  concentrado en lo suyo, menos distracción)? Depende del layout final de asientos,
  que hoy son placeholders (`Marker3D` sin geometría propia de asiento).
- **[ ] LOD / culling de distancia**: no implementado — a la escala actual (una
  ruta de 220 m con unas pocas docenas de objetos) no hace falta. Se vuelve
  relevante recién si el modo endless genera muchos tramos activos a la vez
  (`RouteStreamer.lookahead_distance` + `behind_keep_distance` ya limitan cuántos
  hay vivos, pero cada uno todavía se dibuja entero mientras existe).
- **[ ] Niebla/oclusión intencional del streaming**: ver sección 4.

## 6. Efectos y feedback visual

- **[x] Shake de cámara** en impactos fuertes del vehículo (`vehicle_impact`,
  ver sección 1) — corto, sin suavizado, proporcional a la fuerza del golpe.
- **[x] Confeti al arruinarse un paquete** (`package_feedback.gd`): burst de
  `GPUParticles3D` con cubitos de colores (paleta de la sección 3), sin asset de
  partícula — refuerza el momento "clipeable" (`docs/requerimientos-tecnicos.md`
  3.4) en vez de solo cambiar un color.
- **[x] Color + texto del paquete según estado** (sección 3, tabla de estados) —
  feedback legible a distancia, no depende de leer una barra de progreso.
- **[ ] Slow-mo breve en golpes fuertes**: en el plan original (3.4) pero no
  implementado — tocar `Engine.time_scale` globalmente afectaría la física
  host-autoritativa en multijugador, así que necesita diseñarse como un efecto
  puramente cosmético del lado del cliente (interpolación visual, no del timestep
  real) antes de construirse. Ver `docs/requerimientos-tecnicos.md` 3.4.
- **[ ] Post-processing adicional** (viñeta, chromatic aberration en impactos,
  motion blur): no evaluado. Encaja con la filosofía "cámara vende el caos", pero
  cada uno tiene costo de rendimiento y de "ruido visual" — mejor evaluarlos
  después de tener personajes/props con arte final, cuando haya más base visual
  sobre la que juzgar si suman o distraen.

## 7. Vehículo — exterior e interior

- **[x] Exterior**: furgoneta simple, geometría de cajas (placeholder). Colores
  actuales: carrocería teal oscuro (`#06828f` aprox.), detalles en amarillo verdoso
  y crema.
- **[x] Interior**: tablero oscuro casi negro (`#0e1820` aprox.), volante visible,
  parabrisas de vidrio tintado (sección 5).
- **[ ] Arte final del vehículo**: Fase 6. Pendiente de decidir si el estilo va
  más hacia "van de reparto genérica" (funcional, PEAK-like) o algo con más
  personalidad/marca propia (relevante si en algún momento hay más de un vehículo
  desbloqueable, `docs/plan-desarrollo.md` Fase 5).

## 8. Personajes

- **[x] Placeholder actual**: cápsulas simples (`CharacterBody3D` sin malla
  distintiva más allá de la forma de colisión).
- **[ ] Plan (Fase 6)**: low-poly, 1.000-5.000 triángulos, **ragdoll físico** en
  vez de animación a mano (barato de producir, y el ragdoll cayéndose es
  intrínsecamente gracioso — refuerza los "momentos clipeables"). Ver
  `docs/requerimientos-tecnicos.md` sección 2.
- **[ ] Variación visual entre jugadores**: sin definir. En una sesión de hasta 5
  jugadores en primera persona, la única forma de identificar quién es quién es
  viendo a los demás desde afuera (o por el ping, que ya dice "Jugador N" — ver
  `docs/controles-y-ui.md`). ¿Colores de personaje por jugador (simple, barato) o
  esperar a que haya cosméticos reales (Fase 5) para diferenciarlos?

## 9. Pipeline de arte (para cuando llegue la Fase 6)

- **Fuente principal**: Kenney.nl (low-poly, CC0, glTF) — ya elegido en
  `docs/requerimientos-tecnicos.md`. Packs tipo Synty como alternativa puntual si
  hace falta algo más específico que no esté en Kenney.
- **Presupuesto de triángulos**: 1.000-5.000 por asset (personajes/props),
  consistente con el low-poly estándar en tiempo real.
- **Texturas**: colores planos/paleta simple, no fotorealista — coherente con no
  tener que producir/mantener un set de texturas complejo.
- **[ ] Nombrado y organización de assets importados**: no definido todavía (no hay
  ningún asset importado aún). Cuando empiece la Fase 6, conviene fijar esto acá
  antes de importar el primer pack, para no reorganizar después.

## Preguntas abiertas para decidir en conjunto

Estas son las decisiones reales que quedan, no ejecución técnica pura — vale la pena
resolverlas habladas, no que yo las decida solo:

1. **Niebla de distancia**: ¿sí/no, y con qué prioridad (estética vs. tapar el
   streaming del modo endless)?
2. **Tonemap** (Linear actual vs. Filmic/ACES): ¿probarlo ya con una escena de
   referencia, o esperar a tener más contraste de escenas real?
3. **Identificación visual entre jugadores**: ¿colores simples por jugador ahora,
   o esperar a cosméticos reales de la Fase 5?
4. **Estilo del vehículo/manos**: ¿"utilitario genérico" o con más personalidad
   propia desde ya, aunque sea placeholder?

## Próximo paso
Con esto documentado, el trabajo de Fase 6 (pase de arte) tiene una base concreta
para arrancar sin tener que redescubrir estos valores leyendo el código — y un lugar
único donde actualizar la paleta/iluminación si cambian antes de llegar a esa fase.
