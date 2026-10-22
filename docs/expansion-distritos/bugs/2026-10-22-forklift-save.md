# D-BUG · Con el autoelevador movido, el save pierde todo el libro de palets

**Gravedad:** bloquea (rompe el guardado de la empresa).

**Escenario:** modo Empresa. Alguien sube al autoelevador y lo mueve. Después el día se cierra (o se sale al menú)
y se carga la empresa. Hallado leyendo el código en D-0134. No se probó, y no hay ningún test que guarde
después de mover el autoelevador.

**Causa:**
- `CompanyPallets.to_save()` (`do-not-drop/scripts/core/company/company_pallets.gd:453-458`) pasa `jack_at` a
  `[x, z]`, pero deja `forklift` tal como lo da `CompanyForklift.to_dict()` (`company_forklift.gd:169-171`), con
  `at` como `Vector2`. `SafeJson.write` usa `JSON.stringify` (`modules/persistence/safe_json.gd:13`), que guarda un
  `Vector2` como el texto `"(x, y)"`.
- Al cargar, `load_save` → `put_snapshot` → `forklift.put_snapshot` rechaza ese texto, porque
  `CompanyPallets.point_ok` pide un `Vector2` (`company_forklift.gd:184`). `load_save` devuelve false y
  `CompanyState.pallets` queda en `{}`. Se pierden los palets, el remito y `departed_day`, que es el que evita que
  el camión del proveedor vuelva a entregar los mismos palets (`company_pallets.gd:146-148`).
- Además se guarda `driver`: si el save se hizo con alguien manejando, al cargar el autoelevador queda tomado por
  un peer que ya no existe.

**PR que lo trajo:** #655 (D-0606.b, el autoelevador en el galpón).

**Hecho cuando:** `to_save()` guarda el `at` del autoelevador como `[x, z]` y `driver` en 0, y `load_save` lee ese
formato. Un test en `test_company_save` o en el de palets guarda con el autoelevador movido y con conductor,
pasa por JSON, carga, y verifica que el libro, `departed_day` y la posición sigan iguales y que no haya
conductor.
