# Controles y flujo de UI/lobby — Take My Package

> Última actualización: 2026-09-23
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

### Pasajero (interacción con su paquete)
Diseño unificado para que los 4 tipos de trampa usen el mismo lenguaje de controles
(consistencia = menos fricción para nuevos jugadores en una sesión de fiesta):

| Acción genérica | Teclado | Gamepad | Uso según trampa |
|---|---|---|---|
| Acción primaria (mantener) | Click izquierdo (mantener) | Gatillo derecho (mantener) | Equilibrio: sostener: Ruidoso: calmar |
| Acción secundaria (tap) | Click derecho / E | Botón A/X | Confirmar paso de secuencia (Peso creciente) |
| Movimiento/dirección | WASD o mouse | Stick izquierdo | Input de secuencia (Peso creciente), dirección de corrección (Equilibrio) |
| Abrir/cerrar la caja | T | D-pad abajo | Cualquier trampa: mirar el contenido. La del asiento, la que tenés en la mano o la que mirás. Abierta se puede derramar, y entregada abierta cuenta "con reparos" |

### General (todos los jugadores)
| Acción | Input |
|---|---|
| Ping/emote rápido | Rueda del mouse click / D-pad | Sistema de comunicación no verbal para MVP (ver nota abajo) |
| Pausa/menú | Esc / Start | — |
| Reiniciar | **Mantener** R / Y (en pausa o resultados, instantáneo) | Solo solo o anfitrión |
| Pantalla completa | F11 | — |

### Nota sobre comunicación entre jugadores
Para el MVP **no se implementa voice chat propio** (agrega complejidad de red y de
librerías externas no justificada para una v1) — se asume que los grupos usan Discord/
voice chat externo, como la mayoría de los juegos coop chicos de este tipo. El juego sí
incluye un **sistema simple de pings/emotes** (ej. "¡ayuda!", "¡cuidado!") para
jugadores que jueguen sin voice chat externo. Voice chat propio queda como posible
mejora post-launch, no bloqueante para el MVP.

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
  directo a la furgoneta, sin esperar a nadie) y **Unirse por IP**.
- El host nunca espera en un lobby: `level_base.gd` ya spawnea jugadores dinámicamente
  a medida que se suman (`_sync_players`), así que entrar directo y dejar que los demás
  se sumen después ya funciona sin necesitar una pantalla de espera.
- **Opciones** (menú y pausa): volumen, sensibilidad, invertir Y, pantalla completa,
  restablecer, y la lista de controles del dispositivo en uso. **Salir** cierra el juego.
- Hay pantallas de **Cómo jugar** (tutorial estático) y **Progreso**, accesibles desde
  el menú principal. El perfil local muestra entregas, puntaje, desbloqueos y elecciones.
- Las ayudas en pantalla muestran solo la tecla del dispositivo que se tocó último
  (teclado o gamepad, `GameSettings.using_gamepad`) y cambian según el rol: a pie,
  conductor o pasajero.
- Online, Esc abre el menú **sin pausar** (pausar el árbol congelaba al anfitrión para
  todos); solo el anfitrión puede reiniciar (un cliente que recarga su nivel se queda
  sin jugadores); si se cae el anfitrión, el cliente ve una pantalla "Sin conexión".
  **Pendiente**: el reinicio del anfitrión todavía no recarga el mundo de los clientes.
- El HUD muestra arriba a la izquierda el modo y la sesión; hosteando por LAN, la IP
  para pasarle a los amigos.
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
  rotación automática todavía) y tomar cualquier paquete disponible.
- `UnlockManager` registra metas de progreso para Líquido, Explosivo y Hostil,
  pero `level_base.tscn` ya instancia los siete paquetes y hoy no filtra esas
  tres trampas por desbloqueo. La selección semi-aleatoria y sus reglas de
  balance siguen pendientes.

### HUD durante la partida
- **Conductor**: velocímetro simple, indicador de distancia/tiempo restante a destino.
  **[x] Implementado** (`prototype_hud.gd`: `speed_label`, `distance_label`).
- **Pasajero**: su propio paquete en pantalla con el medidor de integridad/agitación
  visible (barra de color: verde=OK, amarillo=EnRiesgo, rojo=Arruinado), y el prompt de
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
  **[x] Implementado** (overlay de resultados de `prototype_hud.gd`).
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
