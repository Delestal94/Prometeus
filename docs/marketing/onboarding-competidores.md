# Cómo enseñan los competidores (primeros 5 minutos)

> 2026-09-30 · S-905. Investigación web sobre cómo cinco cooperativos enseñan controles y reglas al
> arrancar, contrastada con lo que ya tiene Take My Package tras S-506 y el playtest del 2026-09-28.
> Las wikis de fans y las guías no son fuentes oficiales: lo que sale solo de ahí va marcado
> **(wiki)** o **(sin verificar)**. Números de las notas al pie: sección "Fuentes".

## Tabla comparativa

| Juego (salida) | Controles | Reglas (qué hay que lograr) | Dónde se aprende | Lo que falla |
|---|---|---|---|---|
| **PEAK** (Landfall + Aggro Crab, 16-06-2025 [1]) | Sin tutorial formal: se aprende probando. Controles en el menú de pausa [2]. | La **Guía** (8 páginas: estamina, cocinar) es un objeto que está en el lugar del accidente al empezar cada partida [2][3]. Las páginas del diario del Scoutmaster enseñan de a poco [2]. | El aeropuerto es el lobby: tiene un **muro de escalada para practicar** y ningún estado malo se aplica ahí [4]. Desde la 1.1.a (17-06-2025), la Guía **se sincroniza entre clientes: "tus amigos pueden leer por encima de tu hombro"** [3]. | La Guía es opcional y se puede perder (si se cocina abierta, se quema) [3]. |
| **Lethal Company** (Zeekerss, acceso anticipado 2023 [18]) | Carteles y la terminal con "TYPE HELP" en grande [6]. | **Voz de la Company por altavoz**, una vez por partida guardada nueva: "Bienvenido a tu primer día… revisá el manual e iniciá sesión en la terminal" [5]. **Manual de entrenamiento** (clipboard de 4 páginas: escáner, terminal y lunas, cuota) que vuelve a aparecer junto a la palanca aunque se pierda [7]. | Primera luna fija (Experimentation), con **cielo despejado el primer día** **(wiki)** [8]. | Hilo de 01-2024 "necesitamos el tutorial": los nuevos mueren sin entender por qué. La comunidad lo defiende ("morís y aprendés"), pero es terror: el desconcierto es parte del juego [6]. |
| **Totally Reliable Delivery Service** (We're Five Games / tinyBuild, 04-2020) | Pocos: gatillos para agarrar y bumpers para levantar cada brazo [9]. | **La primera entrega es el tutorial**: tirás de la palanca del dispensador, sale un paquete y lo llevás al punto marcado [9][10]. Desde esa entrega se puntúa **por tiempo o por estado del paquete** [10]. | Una capa nueva por entrega: la siguiente trae un vehículo, después paquetes frágiles, después alcantarillas, montacargas y helicóptero [9][10]. | El control es torpe a propósito. Las reseñas destacan que te lo recuerda todo el tiempo abajo en la pantalla, y así se puede entrar y salir sin perderse (resumen de la reseña de Nintendo Life, sin acceso directo) [11]. |
| **Backseat Drivers** (GhostJam + Deadcat, 09-10-2025 [12]) | No encontramos material sobre un tutorial. | **La premisa es la regla**: "El conductor no ve adónde va. El pasajero ve, pero no maneja" [12]. La tienda lo presenta como "un examen de manejo de tus relaciones" [12]. | 8 niveles de campaña [13]. El cambio de asiento se aprende en la ruta: el motor se ahoga y, para cambiar de conductor, se toca la llave [14]. | Los jugadores piden desactivar el cambio forzado: aprender el rol a la fuerza molesta si el grupo ya los repartió [14]. |
| **RV There Yet?** (Nuggets Ent., 10-2025) | Indicaciones contextuales "[E] Interactuar" **(wiki)** [15]. Al sentarse al volante aparecería una lista de controles, y al agarrar cada objeto, sus teclas **(sin verificar)** [16]. | Hay un **Manual de usuario** en el juego, pero no explica todo: por ejemplo, cómo curarse [17]. | Manejar el RV "se aprende practicando" [17]. El embrague manual (mantener Q, mover la palanca, soltar) no se explica con ninguna secuencia guiada [16]. | Las guías de terceros cubren lo que no explica el manual [17]. |

**Patrón común.** Ninguno de los cinco tiene un nivel de tutorial separado. Los cinco enseñan con **un
objeto o una voz dentro del mundo** (Guía, clipboard, altavoz, manual) más **indicaciones de teclas
según el contexto**. Los dos más exitosos, PEAK y Lethal Company, suman además **un espacio seguro para
probar** (muro del aeropuerto) o **un primer día más amable** (cielo despejado).

## Lo que ya tenemos (S-506 y el playtest del 28-09)

| Idea del mercado | En Take My Package | Estado |
|---|---|---|
| Espacio seguro para practicar (muro de PEAK) | `ui/hud/care_practice.gd`: 5 pasos en el depósito con una caja real, una sola vez por perfil | Hecho |
| Indicaciones según el rol (RV, TRDS) | `ui/hud/hud_prompts.gd`: barra de atajos por rol y dispositivo. En "al principio" dura 3 partidas o 60 s | Hecho |
| Tarjeta de una sola vez (manual de Lethal) | `TutorialCatalog.tip_text` + `UnlockManager.mark_tip_seen`: ficha de 6 s la primera vez que ves cada trampa | Hecho |
| Manual completo | `ui/tutorial_panel.gd` en fichas, resaltado en el menú en la primera partida (`main_menu.gd`) | Hecho, **solo desde el menú principal** |
| Dificultad escalonada (TRDS) | `OrderBalancer.build_order`: el presupuesto crece con `completed_runs`, y las trampas avanzadas esperan a desbloquearse | Hecho |
| Premisa sin palabras (Backseat Drivers) | `route/roadside_story.gd`: la camioneta de la competencia en la zanja, la gallina escapada, el cartel | Hecho |
| "Qué hago ahora" | `ui/hud/care_guide.gd`: un solo paso, el más urgente | Hecho |

## Qué tomamos

1. **Primera ruta amable: de día, despejado y sin evento de ruta.** Es lo que hace Lethal Company con
   su primer día [8]. Hoy la primera partida puede tocar noche, niebla o lluvia (`WorldMood.pick`
   sortea con `WEATHER_ODDS`) y `RunManager.start_run` siempre sortea un evento con
   `RouteEventManager.begin_random()`. La propuesta: si `completed_runs == 0` (online, el valor del
   anfitrión, `NetworkManager.world_completed_runs`), forzar clima `CLEAR` + `DAY` y no sortear
   evento. Archivos: `gameplay/route/world_mood.gd`, `core/run_manager.gd`. `--mood=` sigue mandando.
2. **Bienvenida con voz, una vez por perfil.** Es el altavoz de Lethal [5]. El despachante del
   depósito (`depot_dressing.gd`, nodo `Dispatcher`) dice una línea con `SynthAudio.callout_voice`
   (N-505), acompañada de subtítulo en la zona de contexto (`hud_notices.gd`): "Cada caja va a la casa
   de la pizarra. Si no sabés algo, mirá el tablero de Cómo jugar". Se marca con
   `mark_tip_seen(&"welcome")`, igual que `care_practice`. Cuesta poco porque la voz y el registro de
   "ya visto" ya existen.
3. **"Cómo jugar" también dentro de la partida.** PEAK muestra los controles en la pausa [2], y en
   Lethal el manual reaparece junto a la palanca [7]. Hoy `tutorial_panel.gd` solo se abre desde el
   menú principal, así que quien se sumó a una sala no tiene cómo consultarlo sin salir. Hay que sumar
   un botón en `ui/hud/hud_pause.gd` (la pausa online no congela, así que no molesta a nadie) y,
   como versión dentro del mundo, una estación "Manual" en el depósito (`depot_station.gd` →
   `depot_panel.gd`) que abra el mismo panel.
4. **Que lo que aprendió uno lo vea el equipo.** Es la Guía sincronizada de PEAK [3]. Hoy la ficha de
   primera vez es local: cuando a un novato le toca un Líquido, el veterano que va al lado no se
   entera de por qué el otro no sabe qué hacer. La propuesta: mandar un aviso corto a los demás
   pasajeros ("Juan ve el Líquido por primera vez") por el canal de pings que ya existe
   (`EventBus.request_ping`), sin RPC nueva. Primero hay que pasarlo por `critico-diseno`, porque
   puede ser ruido.
5. **Qué no tomar.**
   - **El "morís y aprendés" de Lethal** [6]: el desconcierto sirve en el terror. En nuestro juego,
     una caja rota sin saber por qué se siente injusta, y ese fue justo el problema del playtest del
     28-09.
   - **El cambio de rol forzado de Backseat Drivers** [14]: ya hay quejas de sus jugadores, y nuestro
     asiento es libre, "el primero que llega".
   - **Un mini-nivel como el de TRDS**: S-506 descartó la idea, y el depósito con `care_practice` ya
     cumple el papel de "primera entrega guiada".

## Propuestas de tarea (no agregadas a la lista)

- **Primera ruta amable** (recomendación 1): `constructor-mundo` para `world_mood.gd` y
  `constructor-progresion` o `constructor-red` para el evento de ruta y el valor del anfitrión, más
  `escritor-tests` (el test: con `completed_runs == 0`, el clima es CLEAR/DAY y no hay evento).
  Esfuerzo B.
- **Bienvenida del despachante** (2): `constructor-ui` + `disenador-audio` para la línea. Esfuerzo B.
  Textos en `strings_world.csv` (es, en).
- **Cómo jugar en la pausa y en el depósito** (3): `constructor-ui`, y la estación con
  `constructor-mundo`. Esfuerzo B. Aviso a Slatex (UI).
- **Aviso de primera vez al equipo** (4): antes `critico-diseno`. Si pasa, `constructor-ui` +
  `auditor-red`. Esfuerzo A.

## Fuentes

1. Wikipedia, "Peak (video game)": salida el 16-06-2025, Aggro Crab + Landfall. https://en.wikipedia.org/wiki/Peak_(video_game)
2. PEAK Wiki (wiki), "How to play": Guía en el lugar del accidente, diario de Myres, controles en la pausa, "mostly learned through experimentation". https://peak.wiki.gg/wiki/How_to_play
3. PEAK Wiki (wiki), "Guidebook": 8 páginas, notas de la 1.1.a (17-06-2025) sobre la sincronización. https://peak.wiki.gg/wiki/Guidebook
4. PEAK Wiki (wiki), "Airport": muro de escalada, sin efectos de estado. https://peak.wiki.gg/wiki/Airport
5. Steam Community, Lethal Company, hilo del 18-02-2024 con el texto del altavoz. https://steamcommunity.com/app/1966720/discussions/0/6292161380817308286/ También en Lethal Company Wiki, "Intercom": https://lethal-company.fandom.com/wiki/Intercom
6. Steam Community, Lethal Company, "To Zeekerss. We need the Tutorial.", 15-01-2024. https://steamcommunity.com/app/1966720/discussions/0/6852856640099508443/
7. Lethal Company Wiki, Miraheze (wiki), "Clipboard": manual de entrenamiento de 4 páginas, reaparece junto a la palanca. https://lethal.miraheze.org/wiki/Clipboard
8. Lethal Company Wiki, Fandom (wiki), "Experimentation": primera luna de toda partida nueva, despejado el primer día. https://lethal-company.fandom.com/wiki/Experimentation
9. GameGrin, reseña de Totally Reliable Delivery Service, Mogtones, 08-04-2020. https://www.gamegrin.com/reviews/totally-reliable-delivery-service-review/
10. Touch, Tap, Play, recorrido de la demo, 03-04-2020: la entrega "First Timer" y la puntuación por tiempo o por estado. https://www.touchtapplay.com/totally-reliable-delivery-service-walkthrough-completing-all-demo-deliveries/
11. Nintendo Life, reseña de TRDS (Switch). La leímos en el resumen del buscador porque la página directa devolvió 403. https://www.nintendolife.com/reviews/switch-eshop/totally_reliable_delivery_service
12. Steam, página de Backseat Drivers (app 3558400): salida el 09-10-2025, premisa. https://store.steampowered.com/app/3558400/Backseat_Drivers/
13. SteamDB, notas de "BACKSEAT DRIVERS OUT NOW", 09-10-2025 (8 niveles, según el resumen del buscador). https://steamdb.info/patchnotes/20323864/
14. Steam Community, Backseat Drivers, "Disable swapping?", 11 y 12-10-2025. https://steamcommunity.com/app/3558400/discussions/0/599665891568096440/
15. rvthereyet.space (sitio de fans), guía de controles. https://rvthereyet.space/guides/controls-guide
16. Resumen del buscador de varias guías de RV There Yet? (sin verificar: la lista de controles al sentarse no apareció en ninguna página que pudiéramos abrir). Por ejemplo: https://deltiasgaming.com/rv-there-yet-keybinds-and-controls-guide/
17. TheGamer, "Things To Know Before Starting RV There Yet?", Emily Serwadczak, 30-10-2025. https://www.thegamer.com/rv-there-yet-beginner-tips-tricks-guide/
18. Wikipedia, "Lethal Company". https://en.wikipedia.org/wiki/Lethal_Company
