# Aviso: `package_feedback.gd` partido por responsabilidad (N-225.5)

Archivos de Slatex: `scripts/gameplay/package/package_feedback.gd` (1000 → 444 líneas) y tres nuevos en la misma
carpeta. Refactor puro: sin cambio de comportamiento, de RPC ni de `PROTOCOL_VERSION`. Presentación solamente.

- `package_trap_visuals.gd` (`PackageTrapVisuals`): lo propio de cada trampa (ojos y siseo de Hostil, anillo de
  Frágil, cuenta y tictac de Explosivo, charco de Líquido, hinchazón y crujido de Peso Creciente, quejido de
  Ruidoso), las correas del estante y el disfraz de evento.
- `package_box_dressing.gd` (`PackageBoxDressing`): cartón, contorno de resaltado, material por paquete,
  abolladuras y etiqueta del courier.
- `package_box_motion.gd` (`PackageBoxMotion`): rebote al apoyar, temblor, abolladuras por daño, etiqueta que se
  desprende y confeti.
- `PackageFeedback` (ahora con `class_name`) conserva todas las variables (los tests las leen por nombre), las
  constantes que leen otros archivos, las conexiones a señales, `_process` con el mismo orden y los métodos que
  usan otros archivos (`highlight`, `set_local_grip`, `grip_glow`, `_update_box_scale`…): nada de afuera cambia
  de firma. Los nodos se crean con los mismos nombres y en el mismo orden.
- Si agregás lógica nueva de presentación a la caja, va en el helper de su responsabilidad;
  `tests/test_package_feedback_split.gd` falla si `package_feedback.gd` pasa de 700 líneas.

Qué hacer: `git pull` antes de tocar el feedback de la caja.
