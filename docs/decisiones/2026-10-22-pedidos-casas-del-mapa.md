# Los pedidos nombran casas del mapa fijo (D-2016.2)

**Decisión:** `OrderGenerator.generate_day()` recibe el `HouseMap` (el host le pasa
`HouseMap.load_default()` en `CompanyOrdersNet.plan_day()`) y cada pedido de una zona con casas en el
mapa (hoy Centro y Campo) nombra una de ellas. Una zona sin casas en el mapa, o sin mapa, sigue con
`<zona>_house_<n>`.

**Por qué:** el bot del día (`bot_company_day`, etapa `deliver`) no podía entregar: los pedidos pedían
`centro_house_9`, que no existe en `data/world/houses.tres` (`centro_01`…), así que ningún viaje
tenía una parada real a la que llegar. La elección usa una sola tirada del generador, como antes,
así que el resto del día (ids, zonas, productos, minutos, requisitos) sale igual con y sin mapa
(`test_order_generator`). `CompanyOrdersNet._house_ok` y `OrderLabel` ya aceptaban las dos formas.

**Pendiente:** D-0312.1 (borrar el camino viejo de `OrderLabel` cuando todas las zonas tengan casas).
`HouseMap.pick_for_day()` (las casas que piden hoy) sigue sin uso: se elige entre todas las de la zona.
