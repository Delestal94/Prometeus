# Tareas de Slatex — Jugador, Paquetes, Interacción, UI y Progresión

> Última actualización: 2026-09-23 (estado sincronizado con `6f4ec56`)
> Ver `docs/colaboracion-equipo.md` para la división de dominios y la zona
> compartida. Las tareas 1-32 vienen directo de `docs/especificaciones-visuales.md`
> (número original entre paréntesis); 33-100 son backlog nuevo del proyecto,
> descompuesto en pasos concretos.
>
> Prioridad: **A** accionable ya (sin pipeline de arte) · **B** necesita
> arte/assets · **C** pulido para más adelante.
>
> Estado: ✅ hecho · 🟡 parcial · Pendiente. Entre paréntesis, el commit o
> archivo donde quedó hecho.

> Límite actual: `UnlockManager` registra Líquido, Explosivo y Hostil como
> desbloqueos, pero los siete paquetes ya están instanciados en el nivel y
> todavía no se filtran por perfil. El progreso local de clientes de red
> tampoco es fiable hasta retransmitir inicio/fin de partida desde el host.

## Paquetes — modelado (1-2)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 1 | Identidad visual por trampa: Frágil con símbolos de copa rota, Ruidoso con agujeros de ventilación, Equilibrio alto y angosto, Peso Creciente bajo y macizo — hoy las 4 son la misma caja con distinto color y texto. Es la mecánica central: tiene que reconocerse de un vistazo. (#17) | B | ✅ Hecho (`af4856d`, cajas por trampa en `c77194f`) |
| 2 | Detalle de cartón en los paquetes: solapas, cinta, etiquetas, abolladuras. (#18) | B | ✅ Hecho: solapas, cinta, etiquetas y abolladuras (`test_package_identity`) |

## Jugador — modelado (3-4)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 3 | Modelo humanoide para el jugador — hoy es una cápsula, sin cabeza, torso, brazos ni piernas. (#19) | B | ✅ Hecho (`d4a7885`, personaje rigged) |
| 4 | Manos del viewmodel con dedos y guantes (dirección ya fijada en `docs/direccion-visual.md` §1). (#20) | B | 🟡 Parcial: asset de guantes (`c77194f`) |

## Jugador — animación (5-16)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 5 | Ciclo de caminata a pie. (#29) | B | ✅ Hecho (`d4a7885`, anim Walk) |
| 6 | Idle con respiración. (#30) | B | ✅ Hecho (`d4a7885`, anim Idle) |
| 7 | Transición de sentarse: hoy abordar un asiento es un corte instantáneo de cámara (el fundido a negro ya tapa el corte de cámara — esto es la animación del cuerpo en sí, no la cámara). (#31) | B | ✅ Hecho (`da9d75d`, pose interpolada) |
| 8 | Manos del conductor siguiendo el volante con IK. (#32) | B | 🟡 Manos procedurales visibles y siguiendo el volante (`e22452f`); falta IK del esqueleto |
| 9 | Manos del pasajero agarrando físicamente su paquete mientras lo sostiene. (#33) | B | ✅ Hecho (`990987c`, agarre según ancho) |
| 10 | Animación de la acción de trampa (mantener/calmar/corregir) — hoy el input no tiene contraparte visual en el personaje. (#34) | B | ✅ Hecho (2026-09-23): las manos del asiento presionan la caja al mantener y dan un toque por dirección (`player.gd` `_pose_tending_hands`); solo local |
| 11 | Gesto de brazo al tocar bocina. (#35) | C | ✅ Hecho (2026-09-23): la mano derecha va al centro del volante mientras suena (`vehicle_presentation.gd`) |
| 12 | Reacción de flinch/encogerse ante un golpe fuerte. (#36) | B | ✅ Hecho (`da9d75d`) |
| 13 | Ragdoll físico al fallar (ya decidido en `docs/requerimientos-tecnicos.md` §2). (#37) | B | ✅ Hecho (`f86676d`, cuerpo físico temporal) |
| 14 | Apertura y cierre de puertas al subir o bajar. (#38) | C | ✅ Hecho (`reference_truck.gd`) |
| 15 | Animación de entrega exitosa: el paquete siendo depositado, no desapareciendo. (#39) | C | ✅ Hecho (2026-09-23): la caja viaja a la puerta y el vecino la recibe (`package.gd` `consume(hand_over_at)`) |
| 16 | Head bob de la malla del personaje (la cámara ya bobea — esto es sincronizar el cuerpo visible, para cuando exista #3). (#40) | B | ✅ Hecho (`da9d75d`) |

## Cámara y HUD — contexto jugador (17-22)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 17 | FOV configurable por el jugador — depende de la pantalla de opciones (ver sección propia más abajo). (#65) | B | ✅ Hecho (`GameSettings`, `options_panel.gd`) |
| 18 | Profundidad de campo sutil sobre el paquete cuando lo estás atendiendo. (#70) | C | ✅ Hecho (`player.gd`, fondo suavizado al llevar carga) |
| 19 | Viñeta que se intensifica cuando la carga está en riesgo — comunica tensión sin texto. (#71) | B | ✅ Hecho (`674d8b1`) |
| 20 | Modo espectador para quien ya perdió su paquete, en vez de quedarse mirando una caja rota. (#74) | B | ✅ Hecho (2026-09-23): Tab/Back, cámara de persecución para quien ya no tiene caja que salvar (`spectator_camera.gd`, `test_spectator`) |
| 21 | Modo foto. (#76) | C | ✅ Hecho (`phone_camera.gd`) |
| 22 | Retroalimentación de cámara al pingear: destello o marca en el borde de pantalla apuntando hacia quién pingeó. (#79) | B | ✅ Hecho (`ee06b29`) |

## Interacción paquete-jugador (23-30)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 23 | El paquete sostenido flota frente a la cámara sin contacto con las manos — debería verse agarrado. (#82) | B | ✅ Hecho (`990987c`) |
| 24 | Abolladuras o deformación progresiva del paquete según el daño acumulado — hoy solo cambia de color. (#83) | B | ✅ Hecho (`acccb84`) |
| 25 | Los paquetes deberían chocar entre sí de forma visible y encadenar caos (ya comparten capa de física). (#84) | A | ✅ Hecho: rebote, giro, daño encadenado y test físico |
| 26 | El cuerpo del jugador debería colisionar con el interior de la furgoneta, no atravesarlo. (#85) | A | ✅ Hecho (`a834da1`, cabina cerrada y puertas sólidas) |
| 27 | Correas o amarres que sujeten los paquetes al soporte, visiblemente tensas en las curvas. (#86) | B | ✅ Hecho (`c027586`) |
| 28 | Un paquete suelto puede golpear a un jugador y empujarlo (con ragdoll, humor gratis). (#92) | B | ✅ Hecho (`c027586`, `f86676d`) |
| 29 | Traspaso de paquete entre jugadores mano a mano, sin pasar por el piso. (#93) | C | ✅ Hecho (`eea8f5c`) |
| 30 | Las manos del conductor deberían ser visibles para los pasajeros — hoy nadie ve a nadie conducir. (#95) | B | ✅ Hecho (`e22452f`) |

## Presencia social (31-32)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 31 | Sombras de los personajes proyectadas dentro de la cabina, para que se sientan presentes en el espacio. (#97) | B | ✅ Verificado: los personajes proyectan sombra, también el propio cuerpo oculto a tu cámara |
| 32 | Marcador sobre el compañero que pingeó, visible a través de la carrocería, para ubicarlo sin girar la cámara. (#100) | B | ✅ Hecho (2026-09-23): un "!" amarillo sobre quien pingeó, visible a través de la carrocería (`prototype_hud.gd` `_mark_pinger`) |

## Fase 5 — Progresión y desbloqueos (33-47)

> `CrewProgression` administra economía y cartas de campaña; `UnlockManager`
> administra el progreso local persistente. En esta sección quedan el balance
> con playtesting (#41, parcial) y el test externo del tutorial (#47, pendiente).

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 33 | Decidir qué se desbloquea primero (trampas nuevas, vehículos, cosméticos) — decisión de contenido, no solo técnica; no arrancar la implementación sin esto resuelto. | A | ✅ Hecho: Líquido, pintura violeta, Explosivo y Hostil |
| 34 | Diseñar `UnlockManager` (autoload): API mínima de qué está desbloqueado y cómo se marca algo como tal. | A | ✅ Hecho (`unlock_manager.gd`) |
| 35 | Guardado persistente de progreso en `user://`, mismo patrón JSON ya usado por el leaderboard en `run_manager.gd` (zona compartida: avisar si hace falta tocar `run_manager.gd`). | A | ✅ Hecho (`user://unlock_progress.json`) |
| 36 | Definir condiciones de desbloqueo (¿puntaje acumulado? ¿cantidad de entregas exitosas? ¿logros puntuales?). | A | ✅ Hecho: entregas exitosas + puntaje acumulado |
| 37 | Pantalla de "Progreso" (ya estaba en el flujo de UI original, `docs/controles-y-ui.md`, nunca implementada). | B | ✅ Hecho (`progress_panel.gd`) |
| 38 | Agregar el botón "Progreso" al menú principal. | A | ✅ Hecho |
| 39 | Notificación al desbloquear algo, reutilizando el patrón de fundido/toast ya existente (`quick_fade_requested`, `ping_sent`). | A | ✅ Hecho (toast en HUD) |
| 40 | Test automatizado de `UnlockManager`: guardar, cargar, no perder progreso entre sesiones. | A | ✅ Hecho (`test_unlock_manager.gd`) |
| 41 | Balancear la curva de desbloqueos: que las primeras partidas no se sientan vacías ni las últimas triviales. | B | 🟡 Parámetros iniciales documentados; falta playtesting |
| 42 | Documentar el sistema de desbloqueos en `docs/plan-desarrollo.md` Fase 5 una vez armado. | A | ✅ Hecho |
| 43 | Documentar la decisión de perfil local vs. cuenta (fuera de alcance del MVP, pero dejarlo explícito). | A | ✅ Hecho: perfil local para el MVP |
| 44 | Pantalla "Cómo jugar" / tutorial (mencionada en el flujo de UI original, nunca implementada). | B | ✅ Hecho (`tutorial_panel.gd`) |
| 45 | Contenido del tutorial: explicar las 4 trampas y los controles básicos sin asumir que el jugador ya sabe jugar. | A | ✅ Hecho |
| 46 | Decidir si el tutorial es una pantalla estática o un mini-nivel interactivo — documentar la decisión antes de construir. | A | ✅ Hecho: pantalla estática para MVP |
| 47 | Playtesting del tutorial con alguien que nunca vio el juego. | A | Pendiente: requiere una persona externa |

## Contenido nuevo — trampa "Líquido" (48-55)

> Se derrama por charquitos progresivos si se inclina o golpea de más — distinta de
> Equilibrio (que falla por vuelco) y de Ruidoso (que falla por agitación sostenida).

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 48 | Diseñar la mecánica exacta: qué cuenta como "inclinación peligrosa", cómo se acumula el derrame, cómo se corrige. | A | ✅ Hecho: inclinación/golpe derraman; mantener seca el charco |
| 49 | `liquid_trap_behavior.gd`, siguiendo el contrato de `i_trap_behavior.gd` ya establecido. | A | ✅ Hecho |
| 50 | `data/traps/liquid.tres` con sus parámetros iniciales. | A | ✅ Hecho |
| 51 | Balance de parámetros: que no se sienta redundante con Equilibrio. | B | 🟡 Parámetros iniciales: acumula derrame y se seca, no endereza la caja |
| 52 | Identidad visual: charquito/mancha creciendo en la caja, o una etiqueta "LÍQUIDO" con nivel visible. | B | ✅ Hecho: charco azul creciente |
| 53 | Sonido propio: chapoteo, siguiendo el patrón `SynthAudio` ya usado para las otras 4 trampas. | A | ✅ Hecho (`liquid_slosh`) |
| 54 | Test automatizado, siguiendo el patrón de `test_traps.gd`. | A | ✅ Hecho (`test_liquid_trap.gd`, `test_liquid_visual.gd`) |
| 55 | Sumarlo al catálogo jugable (`level_base.tscn` o el sistema de asignación que exista una vez armada la progresión). | A | ✅ Hecho: disponible en entrega y Endless |

## Contenido nuevo — trampa "Explosivo" (56-63)

> Cuenta regresiva visible, falla total e inmediata si no se desactiva a tiempo con
> una secuencia bajo presión real — distinta de Peso Creciente (que falla gradual).

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 56 | Diseñar la mecánica exacta: duración del temporizador, cómo se desactiva, si se puede reiniciar el conteo. | A | ✅ Hecho: 14 s, secuencia de direcciones; error resta tiempo |
| 57 | `explosive_trap_behavior.gd`. | A | ✅ Hecho |
| 58 | `data/traps/explosive.tres`. | A | ✅ Hecho |
| 59 | Balance: que la presión de tiempo real sea justa en multijugador (el pasajero puede estar atendiendo otra cosa). | B | 🟡 Parámetros iniciales; falta playtesting multijugador |
| 60 | Identidad visual: contador numérico o barra de mecha visible en la caja. | B | ✅ Hecho: contador y flecha de secuencia |
| 61 | Sonido propio: tictac que acelera, siguiendo `SynthAudio`. | A | ✅ Hecho (`explosive_tick`) |
| 62 | Test automatizado. | A | ✅ Hecho (`test_explosive_trap.gd`, `test_explosive_visual.gd`) |
| 63 | Sumarlo al catálogo jugable. | A | ✅ Hecho: disponible en entrega y Endless |

## Contenido nuevo — trampa "Hostil" (64-71)

> Algo vivo y agresivo: si el input es incorrecto, "ataca" (feedback negativo activo,
> no solo ausencia de feedback positivo) — distinta de Ruidoso (que solo se agita).

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 64 | Diseñar la mecánica exacta: qué input es "correcto" vs. "incorrecto", y qué penalidad tiene fallarlo. | A | ✅ Hecho: alterna CALMÁ/NO TOCAR; fallar provoca ataque |
| 65 | `hostile_trap_behavior.gd`. | A | ✅ Hecho |
| 66 | `data/traps/hostile.tres`. | A | ✅ Hecho |
| 67 | Balance: que la penalidad por error se sienta justa, no punitiva al azar. | B | 🟡 Parámetros iniciales; falta playtesting |
| 68 | Identidad visual: algo que se asome/reaccione agresivamente desde la caja. | B | ✅ Hecho: ojos y tentáculos rojos |
| 69 | Sonido propio: gruñido/siseo, siguiendo `SynthAudio`. | A | ✅ Hecho (`hostile_hiss`) |
| 70 | Test automatizado. | A | ✅ Hecho (`test_hostile_trap.gd`, `test_hostile_visual.gd`) |
| 71 | Sumarlo al catálogo jugable. | A | ✅ Hecho: disponible en entrega y Endless |

## Personajes y cosméticos (72-79)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 72 | Selección de color/piel de personaje en el menú, más allá del color automático por `peer_id` ya implementado. | B | ✅ Hecho (Uniforme) |
| 73 | Integrar cosméticos con el sistema de desbloqueos (Fase 5). | B | ✅ Hecho (`UnlockManager`) |
| 74 | UI de selección de cosmético. | B | ✅ Hecho (`cosmetics_panel.gd`) |
| 75 | Persistencia de la elección del jugador (mismo guardado JSON del progreso). | A | ✅ Hecho |
| 76 | Decidir si los cosméticos son solo de color o incluyen geometría/accesorios (depende de cuándo llegue el modelo humanoide, #3). | A | ✅ Hecho: color de uniforme para MVP; accesorios requieren arte dedicado |
| 77 | Vista previa del cosmético antes de confirmarlo (un espejo simple o un modelo girando). | C | ✅ Hecho (`cosmetics_panel.gd`, maniquí 3D giratorio) |
| 78 | Sincronizar la elección de cosmético en red, mismo patrón que el color por `peer_id` ya replicado. | B | ✅ Hecho (`cosmetic_id` replicado en Player) |
| 79 | Test automatizado de que la elección persiste y se ve igual en todos los clientes. | A | 🟡 Persistencia cubierta; falta test de dos clientes reales |

## Pantalla de opciones (80-87)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 80 | Armar la pantalla de opciones (no existe todavía, solo el menú principal). | A | ✅ Hecho (`options_panel.gd`) |
| 81 | Slider de FOV (depende del ítem #17 de esta lista). | B | ✅ Hecho |
| 82 | Sliders de volumen: general, música, efectos, voces/pings. | A | ✅ Hecho (buses Music/SFX/Voice) |
| 83 | Reasignación de teclas — al menos las acciones más usadas (interactuar, ping, bocina). | B | ✅ Hecho (`7b036fe`) |
| 84 | Opciones de accesibilidad: reducir sacudida de cámara, reducir el golpe de FOV en impactos. | B | ✅ Hecho (slider Sacudida de cámara) |
| 85 | Persistencia de las opciones elegidas (archivo de configuración separado del progreso). | A | ✅ Hecho (`GameSettings`) |
| 86 | Aplicar las opciones en caliente, sin necesitar reiniciar el juego. | A | ✅ Hecho (sin botón aplicar) |
| 87 | Test automatizado: las opciones se guardan y se aplican correctamente al recargar. | A | ✅ Hecho (`test_settings.gd`) |

## HUD y resultados — pulido (88-93)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 88 | Pantalla de leaderboard dedicada (hoy el récord solo se ve en la pantalla de resultados de la propia partida). | B | ✅ Hecho (`leaderboard_panel.gd`) |
| 89 | Desglose más claro del puntaje en resultados (ya existe la base, pulir legibilidad). | A | ✅ Hecho (2026-09-23): una línea por concepto que suma exacto al total (`RunManager` `breakdown`, `test_score_breakdown`) |
| 90 | Indicador compartido más legible del estado de todos los paquetes (ya existe `cargo_rows_box`, evaluar si hace falta iconografía en vez de solo texto). | B | ✅ Hecho (íconos de trampa en el HUD, `c77194f`) |
| 91 | Feedback visual cuando alguien más resuelve su trampa a tiempo (reforzar la cooperación, no solo el riesgo). | B | ✅ Hecho (`prototype_hud.gd`: toast, chime y destello de fila al volver de riesgo a seguro) |
| 92 | Revisar la consistencia de la paleta de colores del HUD contra `docs/direccion-visual.md` §3 (hoy duplicada entre `main_menu.gd` y `prototype_hud.gd` — considerar unificar en un archivo de constantes compartido). | A | ✅ Hecho (`ui_theme.gd` compartido) |
| 93 | Pantalla de pausa: agregar acceso directo a opciones (depende de que exista la pantalla de opciones). | A | ✅ Hecho (botón Opciones en pausa) |

## QA de su dominio (94-98)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 94 | Playtesting de cada trampa nueva en aislamiento antes de combinarla con las demás. | A | Pendiente |
| 95 | Playtesting de las 7 trampas combinadas (4 actuales + 3 nuevas) en una sola entrega. | A | Pendiente |
| 96 | Bug bash de interacción: soltar un paquete a mitad de traspaso, cambiar de asiento en medio de una acción, dos jugadores interactuando con el mismo objeto a la vez. | A | 🟡 Cubierto por regresiones automatizadas; el caso de dos jugadores requiere playtest de red |
| 97 | Verificar que `test_interaction`, `test_multi_cargo`, `test_trap_visual_feedback`, `test_trap_audio` y `test_interaction_highlight` sigan pasando después de cada trampa nueva. | A | ✅ Hecho: suite verde el 2026-09-23 |
| 98 | Playtesting específico de multijugador real (4-5 personas) una vez sumadas las trampas nuevas y la progresión. | A | Pendiente |

## Documentación de su dominio (99-100)

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 99 | Mantener actualizadas las filas de jugador/paquetes/UI en `docs/especificaciones-visuales.md`. | A | 🟡 Actualizada la lista de entrega; faltan assets/animaciones pendientes |
| 100 | Escribir la guía "cómo agregar una trampa nueva" (`i_trap_behavior.gd` + `.tres` + integración) para no redescubrirla cada vez — usar las 3 trampas nuevas de esta lista como los primeros casos reales. | A | ✅ Hecho (`docs/como-agregar-una-trampa.md`) |
