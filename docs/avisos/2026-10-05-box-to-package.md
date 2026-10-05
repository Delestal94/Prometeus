# Aviso: cajas armadas que salen como `DeliveryPackage` (D-0213)

- **Quién:** Nacho (rutina desarrollador, carril 1).
- **Qué:** `scripts/gameplay/business/box_to_package.gd` instancia `scenes/gameplay/package/package.tscn`
  y le pone `trap_definition`, `content`, `impact_absorption`, `package_id` (`box_<pedido>`) y tres
  metadatos nuevos: `packed_box` (el `to_dict()` de la caja), `order_id` y `loose_box`.
- **Qué no cambió:** ningún archivo de Slatex (`package.gd`, `package_content.gd`) ni ninguna firma.
  Entrega y Endless no pasan por acá.
- **Para Slatex:** si algún día se renombran esos campos exportados del paquete, `test_box_to_package` falla.
