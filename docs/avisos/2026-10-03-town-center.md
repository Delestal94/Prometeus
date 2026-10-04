# N-950: Centro transitable en el spike offline

`town_prototype.gd` acepta `built_districts` (por defecto `[0]`).
`town_delivery.gd` construye `[0, 1]` con un corredor completo y cruces con
colisión; conserva las barreras hacia Campo e Industrial. Lotes y zonas
verdes adicionales tienen nombres que incluyen su distrito.

`town_art.gd` usa las viviendas originales de dos plantas y bungalow para
el Centro, conserva escala nativa y toldos de comercios. Plaza, parque,
árboles y mobiliario se construyen para las zonas abiertas. F4 elige el
Centro en el GPS, F1–F3 restauran el cliente pendiente. El destino del
Centro está sobre una calle junto a la plaza, sin atravesar el césped.

Los tres pedidos actuales permanecen iguales. No hay guardado/desbloqueo
persistente ni replicación online de esta escena. No cambia el protocolo.
Textos de prueba localizados ES/EN. Ver `docs/mapa-pueblo.md` para controles.
