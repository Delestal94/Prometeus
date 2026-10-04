# N-950 — arte existente en el barrio procedural

Nacho agrega `scripts/gameplay/town/town_art.gd`, adaptador que reutiliza
viviendas, forest GLB, bancos/farolas y piezas del depósito con `DepotKit` y
`DressingBatcher`. No modifica, elimina ni regenera assets existentes.

`town_prototype.gd` usa esos modelos en lugar de los edificios/árboles/muebles
de bloque. `town_delivery.gd` elige tres casas de cliente distintas, conserva
su orientación de frente y carga desde estantes con las piezas originales.
El depósito/taller son construcciones compactas para el lote; el depósito
original del juego no cambia. El monumento y pavimentos siguen siendo provisionales.

El plano portable, semilla, versión de generador y API del GPS no cambian.
Sin RPC/replicación nueva ni cambio de protocolo. Tests ampliados y capturas
de inspección/juego para comprobar colisiones, escala, apoyo y accesos.
Hacer pull antes de continuar con la ambientación de este adaptador.
