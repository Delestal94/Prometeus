# S-311.78 — contrato de clips de juego del personaje gel

El export del personaje gel añade `Drive`, `EnterTruck` y `ExitTruck` sin
modificar `vehicle.tscn` ni la presentación de pedales del camión. `Drive`
incluye una pose base sentada, manos alcanzables para el IK existente del
volante y pies separados para acelerador/freno.

Para S-311.80, la integración debe consumir los marcadores del camión y su
estado real de volante/pedales; no debe fijar posiciones propias dentro del
clip ni duplicar `ReferenceTruckCab.animate_pedals()`. Si Nacho cambia la
geometría o los nombres de esos puntos antes de esa integración, hay que
actualizar juntos el adaptador de pose y `test_driver_ik.gd`.
