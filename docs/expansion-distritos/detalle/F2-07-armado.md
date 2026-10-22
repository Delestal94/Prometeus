# F2 · Grupo 07 — Armado de paquetes (detalle)

> Carril 3 de la rutina `desarrollador`. Ampliación del grupo 07 que se construye de a una; el resto sigue en
> la tabla de [07-armado-de-paquetes.md](../07-armado-de-paquetes.md). Números de [supuestos.md](supuestos.md).

### D-0721 · Conservadora con hielo para productos fríos — B · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `ColdPack` (`scripts/gameplay/business/cold_pack.gd`) + `PackedBox.ice_packs`; `test_cold_pack`. Meter el hielo desde la mesa visible, cobrar `ICE_PACK_COST` y leer la duración en la puerta quedan para D-0721.b (ver `revisar/D-0721.md`).
**Depende de:** D-0703 (`PackedBox`), D-0708 (`BoxSeals`, sello de frío)
**Qué:** `class_name ColdPack`, estático. Una caja con un producto frío (`temperature == &"cold"`) aguanta `COLD_BASE_MINUTES` (15) sola y `COLD_PER_ICE_MINUTES` (25) más por cada paquete de hielo (`PackedBox.ice_packs`, máximo `ICE_PACKS_MAX` = 2). `add_ice`, `cold_minutes`, `holds(box, minutos_de_viaje)` y `ice_needed(minutos)`. El hielo viaja en `to_dict`/`from_dict` de la caja.
Decisión: el hielo es un contador de la caja, no un insumo de la mesa: `SUPPLY_CAPACITY` viaja en el snapshot de red y tocarlo cambiaría el protocolo por algo que todavía no se dibuja. Decisión: `ICE_PACK_COST` (2) lo cobra quien llama, como el resto de `PackagingSupplies`.
**Test** `test_cold_pack`: solo una caja con producto frío cuenta; el hielo se detiene en el máximo; el mismo viaje arruina la caja sin hielo y la salva con hielo; una caja sin frío siempre aguanta; `ice_needed`; ida y vuelta por JSON con el conteo limitado.
**Hecho cuando:** el frío dura N min en la ruta (el test pasa).
