# N-950: seis pedidos entre Barrio y Centro

`town_delivery.gd` añade `delivery_lots(plan)` y `order_lots`: conserva los
clientes originales y elige tres viviendas residenciales del Centro por
su dirección. Selección estable al invertir la lista de lotes; no modifica
el plano. Las casas conservan el modelo ya ajustado al lote y reciben el
script de timbre, marcador y paquete asignado. Los comercios quedan intactos.

Los seis paquetes A–F salen del mismo depósito. `town_art.loading_rack`
baja la bandeja inferior a 0.25 m: hay tres cajas por nivel. Las inferiores
quedan 0.15 m hacia el frente, dentro de la bandeja, para que el nivel
intermedio no bloquee el rayo de interacción. F1–F3 seleccionan A–C en
Barrio, F4–F6 D–F en Centro; F7 reemplaza el anterior F4 de visita a la plaza.
Los textos ES/EN y `docs/mapa-pueblo.md` explican los nuevos controles.

`test_town_delivery` cubre los seis destinos sobre 100 semillas, carga real,
selección por apuntado y ausencia de interpenetración en el estante, rechazo
de caja equivocada, entregas entre distritos, ausencia de registro duplicado
y regreso prematuro sin terminar. `render_town_delivery` añade estante,
cliente Centro y su GPS. La prueba sigue offline y en memoria, sin RPC nuevos,
recompensas ni guardado de campaña. No cambia el protocolo.
