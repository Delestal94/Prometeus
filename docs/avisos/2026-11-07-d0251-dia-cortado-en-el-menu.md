# Aviso: chip "Día cortado" en el menú de empresas (D-0251)

- **Archivo:** `do-not-drop/scripts/ui/company_slots_page.gd`, función `_add_row()`. Sin cambios de firma ni señales.
- **Qué cambió:** una fila cuyo save tiene `interrupted` muestra un chip "Día cortado" en su propia línea, entre
  "Jugar" y las acciones, y el tooltip de "Jugar" suma la explicación. Dos claves nuevas en `strings_ui.csv`:
  `UI_COMPANY_SLOTS_INTERRUPTED` y `UI_COMPANY_SLOTS_INTERRUPTED_HINT`.
- **Qué hacer:** nada, salvo tener en cuenta que el chip no entra en la línea de acciones: con los dos modificadores
  encendidos esa línea ya ocupa todo el ancho de la tarjeta.
