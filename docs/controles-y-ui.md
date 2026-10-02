# Controles y flujo de UI/lobby — Take My Package

> Última actualización: 2026-09-25
> Cada jugador juega desde su propio dispositivo/cliente (no split-screen local) —
> esto simplifica el esquema de controles: cada uno usa su teclado+mouse o gamepad
> completo, no hay que repartir un solo teclado entre varios jugadores.

## 1. Esquema de controles

### Conductor
| Acción | Teclado | Gamepad |
|---|---|---|
| Acelerar | W | Gatillo derecho (RT) |
| Frenar/retroceder | S | Gatillo izquierdo (LT) |
| Girar izquierda/derecha | A / D | Stick izquierdo |
| Freno de mano | Espacio | Botón X (no A: A es "interactuar", y sentado eso te baja del asiento) |
| Bocina (feedback/comedia) | H | Botón B/círculo |
| Mirar alrededor (asiento, primera persona) | Mouse | Stick derecho |
| Centrar la vista | C | Clic del stick derecho |

### A pie
| Acción | Teclado | Gamepad |
|---|---|---|
| Caminar / mirar | WASD / mouse | Stick izquierdo / stick derecho |
| Correr (mantener) | Shift (reasignable en Opciones) | Clic del stick izquierdo |

Correr sube la velocidad de 3,6 a 6 m/s sin estamina. Con una caja en brazos se corre a 5 m/s y cada paso la sacude
(ver `jugabilidad-paquetes-rescate.md`, "Correr con la caja"). No se corre sentado, manejando ni arriba de un camión
en movimiento. La primera vez que corrés con una caja sale el consejo "Correr con la caja la sacude".

### Pasajero (interacción con su paquete)
Diseño unificado para que los 4 tipos de trampa usen el mismo lenguaje de controles
(consistencia = menos fricción para nuevos jugadores en una sesión de fiesta):

| Acción genérica | Teclado | Gamepad | Uso según trampa |
|---|---|---|---|
| Acción primaria (mantener) | Click izquierdo (mantener) | Gatillo derecho (mantener) | Equilibrio: **mantener y contrapesar**: empujar con WASD (stick izq.) hacia el lado contrario a la inclinación de la caja, como lo ve la pantalla de cada asiento; Ruidoso y Hostil: calmar. Líquido no usa el botón: se **friega** alternando A y D (o el stick de lado a lado). Frágil no usa el mantener: pide un **toque** justo antes del bache (anillo sobre la caja) |
| Acción secundaria (tap) | Click derecho / E | Botón A/X | Confirmar paso de secuencia (Peso creciente) |
| Movimiento/dirección | WASD o mouse | Stick izquierdo | Input de secuencia (Peso creciente), dirección de corrección (Equilibrio) |
| Abrir/cerrar la caja | T | D-pad abajo | Cualquier trampa: mirar el contenido. La del asiento, la que tenés en la mano o la que mirás. Abierta se puede derramar, y entregada abierta cuenta "con reparos" |

### General (todos los jugadores)
| Acción | Input |
|---|---|
| Ping/emote rápido | Rueda del mouse click / D-pad arriba | Tocar: “¡Cuidado!”. Mantener: rueda de seis mensajes; elegir con mouse o stick derecho. |
| Usar carta | G (reasignable) / D-pad izquierda | Rescate en ruta; Descuento y Re-voto desde Suministros |
| Pausa/menú | Esc / Start | — |
| Tripulación (solo en el depósito) | **Mantener** Tab / Back | Lista de quién está, con uniforme, quién maneja y quién tiene caja; el anfitrión LAN ve además el código de sala |
| Reiniciar | **Mantener** R / Y (en pausa o resultados, instantáneo) | Solo solo o anfitrión |
| Hablar (voz por proximidad, solo Steam) | **Mantener** Z (reasignable; sin botón de mando) | Solo con "Chat de voz" prendido en Opciones; con "Pulsar para hablar" apagado el micrófono queda abierto |
| Pantalla completa | F11 | — |

### Nota sobre comunicación entre jugadores
Hay **voz por proximidad solo por Steam** (N-212; en LAN no hay voz): apagada por defecto hasta probarla con
Steam real, se prende en Opciones ("Chat de voz"), con pulsar para hablar por defecto (Z, reasignable) o micrófono
abierto, y en "Voces de la tripulación" un silenciar y un volumen por compañero mientras dure la sesión. El juego
sigue teniendo el **sistema simple de pings/emotes** (ej. "¡ayuda!", "¡cuidado!") para quien juega sin voz.

---

## 2. Flujo de UI

> **Estado real (2026-09-21)**: esto era el plan antes de programar. La implementación
> real (`main_menu.gd`) diverge a propósito en un punto central — no hay pantalla de
> lobby. El diagrama y la sección "Lobby" de abajo quedan como diseño de referencia
> para cuando haya algo que elegir en un lobby (vehículo, modo); por ahora no aplican.

```
Main Menu
  ├── Jugar
  │     ├── Crear partida (host)
  │     │     └── Lobby (esperando jugadores)
  │     └── Unirse a partida (por código/IP)
  │           └── Lobby (esperando al host)
  ├── Cómo jugar (tutorial/explicación de trampas)
  ├── Progreso (desbloqueos, ver docs/requerimientos-tecnicos.md sección 3.2)
  └── Opciones (audio, controles, video)
```

### Lo que hay en cambio
- Tres botones directos: **Jugar solo** (sin sesión), **Crear sala** (hostea y entra
  directo al depósito, sin esperar a nadie) y **Unirse por IP**.
- **El depósito hace de lobby jugable** (2026-09-23): toda partida arranca ahí y sus
  estaciones abren `ui/depot_panel.gd` solo antes de salir: **pizarra de pedidos**,
  **vestuario** (uniforme), **taller** (camión y pintura, los elige el anfitrión),
  **suministros** (acolchado y seguro con la plata del equipo) y **equipo del mes**
  (progreso). Cubre buena parte de lo que iba a hacer el lobby de abajo.
- **Panel de tripulación** (S-507, `scripts/ui/hud/crew_panel.gd`): mientras se mantiene Tab (Back en gamepad) en el
  depósito, antes de salir, aparece una lista con todos los conectados: el color del uniforme y su nombre, un
  ícono con texto para "al volante" y "con caja" (nunca solo color), y quién sos vos y quién es el anfitrión.
  Abajo, solo para el anfitrión de una sala LAN, el código de sala y la IP para pasarlos; en Steam dice que se
  invita desde la lista de amigos, y un cliente ve por qué no hay código. No pausa, no libera el cursor y no toma
  foco: se puede caminar mientras se mira. Lee estado ya replicado (no hay RPC nuevos).
- El host nunca espera en un lobby: `level_base.gd` ya spawnea jugadores dinámicamente
  a medida que se suman (`_sync_players`), así que entrar directo y dejar que los demás
  se sumen después ya funciona sin necesitar una pantalla de espera.
- **Opciones** (menú y pausa): volumen, sensibilidad, invertir Y, pantalla completa,
  escala del HUD, tamaño de texto de menús (100/125/150 %), paleta para daltonismo,
  subtítulos de sonidos, ayudas de controles, restablecer y la lista de controles del
  dispositivo en uso. **Salir** cierra el juego.
- Hay pantallas de **Cómo jugar** (tutorial estático) y **Progreso**, accesibles desde
  el menú principal. El perfil local muestra entregas, puntaje, desbloqueos y elecciones.
- Las ayudas en pantalla muestran solo la tecla del dispositivo que se tocó último
  (teclado o gamepad, `GameSettings.using_gamepad`) y cambian según el rol: a pie,
  conductor o pasajero.
- Online, Esc abre el menú **sin pausar** (pausar el árbol congelaba al anfitrión para
  todos); solo el anfitrión puede reiniciar (un cliente que recarga su nivel se queda
  sin jugadores); si se cae el anfitrión, el cliente ve una pantalla "Sin conexión".
  **Pendiente**: el reinicio del anfitrión todavía no recarga el mundo de los clientes.
- El HUD muestra arriba a la izquierda el modo y la sesión; hosteando por LAN, el código de
  sala (8 letras, `K7QM-4TXA`; ver `scripts/ui/room_code.gd`) para pasarle a los amigos. "Unirse" acepta
  el código o la IP.
- **Conexión real**: Steam (relayeado, sin abrir puertos) o IP directa por LAN (ENet) —
  la elección es automática (Steam si está corriendo) salvo en "Unirse por IP", que
  siempre fuerza LAN. Ver README sección "Multijugador".

### Lobby (diseño de referencia, no implementado)
- Lista de jugadores conectados (nombre + listo/no listo).
- Host elige: vehículo (si hay más de uno desbloqueado) y ruta/modo (normal vs.
  endless, si ya está implementado).
- Botón "Listo" por jugador; el host inicia cuando todos están listos.
- Tendría sentido el día que haya algo real que elegir (vehículo desbloqueado, modo
  endless) — hasta entonces, agregar esta pantalla sería fricción sin función.

### Asignación de roles y paquetes
- Al empezar la partida, un jugador es conductor (rotable entre partidas o elegido en
  el lobby, a definir con playtesting) y el resto recibe un paquete cada uno.
  **[x] Parcial**: cualquier jugador puede sentarse a conducir (primero en llegar, sin
  rotación automática todavía) y tomar cualquier paquete disponible. Qué caja va a
  qué casa lo dice la pizarra del depósito (dos cajas por trampa en las estanterías).
- Líquido, Explosivo y Hostil aparecen en el depósito recién cuando están desbloqueadas
  (`UnlockManager.TRAP_UNLOCKS`, `depot.gd` `withhold_locked`, 2026-09-23); en línea manda
  el perfil del host. `OrderBalancer` arma el pedido con presupuesto de dificultad, sin
  repeticiones prematuras y con al menos una trampa accesible.

### HUD durante la partida

La interfaz tiene tres capas con zonas fijas. Una zona muestra **un solo texto** a la vez;
si llegan varios, `hud_notices.gd` conserva la cola y enseña primero el de mayor prioridad:

| Capa | Zona | Contenido | Movimiento |
|---|---|---|---|
| **Crítico** | Arriba, centro | Tu caja en riesgo (incluida la cuenta del explosivo) o el evento de ruta con su cuenta regresiva | Grande, con pulso suave |
| **Contexto** | Abajo, centro | Acción del objeto que mirás, soltar paquete, abrir/cerrar/ver la tapa y subtítulos opcionales de sonidos de trampas | Un solo bloque estable |
| **Información** | Esquinas | Velocidad, tiempo, distancia, estado de la carga, sesión, dinero cuando corresponde y avisos breves | Chico y quieto |

La barra de atajos respeta **Ayudas de controles: siempre / al principio / nunca**. En
“al principio” desaparece al completar 3 partidas o tras 60 segundos de uso del HUD. El
dinero del equipo se reserva para decisiones: depósito, pausa y resultados; no ocupa la
ruta mientras se maneja.

- **Conductor**: velocímetro simple, indicador de distancia/tiempo restante a destino.
  **[x] Implementado** (`scripts/ui/hud/hud.gd`, antes `prototype_hud.gd`: `speed_label`, `distance_label`).
- **Pasajero**: su propio paquete en pantalla con el medidor de integridad/agitación
  visible (OK ✓, En riesgo ! con pulso, Arruinada ✕; paleta normal u Okabe-Ito), y el prompt de
  la acción correspondiente a su trampa. **[x] Implementado** (`cargo_hint_label`,
  `interaction_label`).
- **Compartido**: mini resumen del estado de todos los paquetes (iconos chicos) para
  que todos vean cuándo un compañero está en problemas — esto refuerza la tensión
  social/cooperativa (mecánica #8 del banco: riesgo compartido). **[x] Implementado**:
  `cargo_rows_box` escucha `cargo_registered`/`package_integrity_changed` para **toda**
  la carga a bordo, no solo la propia — cada cliente ve el estado de los cuatro
  paquetes, con barra de color por integridad.

### Pantalla de resultados
- Desglose de puntaje por paquete (según fórmula de `parametros-diseno.md`).
  **[x] Implementado** (overlay de resultados de `scripts/ui/hud/hud_results.gd`).
- Récord local. **[x] Implementado** (no estaba en el plan original, se sumó después:
  "¡NUEVO RÉCORD!" o el récord actual, ver `RunManager` y README sección Tests /
  `test_leaderboard`).
- Progreso de desbloqueos ganado en esta partida. **[x] Implementado** —
  `UnlockManager` acumula puntaje/entregas en `user://unlock_progress.json` y el HUD
  muestra un toast cuando se habilita contenido.
- Botones: "Jugar de nuevo" (mismo lobby) / "Volver al lobby" / "Salir".
  **[x] Parcial**: "Volver a intentar" reinicia la misma sesión (no hay lobby al que
  volver, ver más arriba) y "Menú" vuelve al menú principal.

## Próximo paso
La mayor parte de esto ya está implementado (ver los `[x]`/`[ ]` de cada sección); lo
que falta reflejado acá es contenido, no diseño: desbloqueos reales (Fase 5, pendiente
de decidir qué se desbloquea) y, si hace falta, un lobby real cuando haya algo que
elegir en él.
