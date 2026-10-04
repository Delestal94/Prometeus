# Decisión 2026-10-04: un solo mapa continuo que se desbloquea

Responde D-0104 de `docs/expansion-distritos/`. **La decidió el usuario**: el mundo es **un solo mapa
continuo**. Las zonas se abren a medida que se avanza, y no hay un nivel por distrito.

## Qué impide pasar a una zona

| Bloqueo | Cómo se ve en el mundo | Se abre con |
|---|---|---|
| **Barrera** | Portón, tranquera o control con guardia | Un hito (D-04xx) |
| **Calle cortada** | Obra, derrumbe o vallas | Un hito, o pagar la obra |
| **Agua** | Costa sin puente (Puerto → Islas) | Tener la **lancha** |
| **Equipo** | Cartel y guardaparque en la entrada de Nieve y Volcán: no te dejan pasar sin el equipo | **Equipo**: cadenas + abrigo (Nieve), traje térmico + cajas térmicas (Volcán) |
| **Altura** | Montañas sin camino transitable desde el llano | Tener la **avioneta** (se aterriza en pistas de montaña) |

Cambia la tabla del README de la expansión: **Montaña se alcanza con la avioneta** (antes decía 4x4).
Nieve y Volcán piden equipo. Dentro de cada zona se sigue entregando con lo que corresponda (4x4 en la
montaña si se lleva en la avioneta grande o ya está allá, bici, carrito).

## Lo que decide la conversación principal (con delegación del usuario: "avanzá")

Si una rutina encuentra una razón fuerte para cambiar alguno de estos puntos, la anota como hallazgo y no
lo cambia por su cuenta.

1. **Trazado fijo, decorado por semilla.** El mapa (dónde está cada distrito, las calles, las costas y las
   montañas) es el mismo en todas las partidas y para todos los jugadores. Cambian por semilla las casas
   que piden, el decorado chico, los eventos y el clima. Un mapa fijo se puede aprender, señalizar y
   bloquear con sentido; uno generado no.
2. **Tamaño ≤ 6 × 6 km** con el galpón (Parque Industrial) cerca del centro. A esa distancia la
   precisión de `float` de Godot alcanza (milímetros) y **no hace falta origen flotante**, que en red
   sería caro. El tope está en `world_tuning.gd`.
3. **Mundo por celdas de 256 m** que se cargan y descargan alrededor de cada jugador y vehículo
   (`modules/world_cells/`, nuevo y portable). El galpón y la red de calles principal quedan siempre
   cargados en versión liviana (impostores lejanos).
4. **Las calles son un grafo** (nodos y tramos con curva) guardado en un recurso del mapa. Los tipos de
   tramo actuales (badén, chicana, puente, ripio, barro, obras…) se colocan **sobre aristas del grafo**:
   el Campo actual pasa a ser una zona de calles con esos tramos, y no se genera infinito.
   `RouteStreamer` se conserva para Endless.
5. **No hay pantallas de carga** después de la inicial: salir del galpón es manejar por el portón.
6. **En red, todos están en el mismo mundo.** El host simula todos los vehículos. Para acotar el costo,
   como máximo **2 vehículos lejos del galpón a la vez** en F1-F3; se revisa con medición (D-2002).
7. **Los bloqueos son objetos del mundo** con un `GateRequirement` (hito, vehículo, equipo). El estado
   abierto o cerrado vive en `CompanyState` y se replica. Un bloqueo abierto no se vuelve a cerrar.

## Qué cambia en el backlog

- **Grupo 03 (mapa y distritos)**: se reescribe el núcleo para mundo continuo, celdas, grafo de calles y
  bloqueos (ver `detalle/F1-03-distritos.md`).
- **Grupo 02**: D-0214 deja de ser "escena que carga distritos" y pasa a ser la escena del mundo.
- **D-0313 y D-0307**: ya no hay carga entre galpón y distrito; se miden el streaming y el tiempo de
  manejo de vuelta.
- **D-0317 y D-0318**: varios vehículos en zonas distintas pasa a ser lo normal, con el tope del punto 6.
- **Grupo 14**: la avioneta es la llave de Montaña, no solo de Volcán.
- **Grupo 16**: Montaña se alcanza en avioneta. Nieve pide equipo.
