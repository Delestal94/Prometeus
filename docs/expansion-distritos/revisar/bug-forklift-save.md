# Revisar · bug forklift-save

## Probar a mano
- Modo Empresa: subir al autoelevador, moverlo, cerrar el día (o salir al menú) y cargar la empresa. Debería verse el libro de palets, el autoelevador donde quedó y nadie manejándolo.
- Guardar con alguien manejando: al cargar el autoelevador queda libre.

## Decidir al final
- Decisión: el conductor no se guarda (se guarda 0), porque el peer ya no existe al cargar.
- Sugerencia de tooling: `tools/run-tests.sh` no reimporta si `.godot/` ya existe pero tiene el caché de `class_name` viejo.
