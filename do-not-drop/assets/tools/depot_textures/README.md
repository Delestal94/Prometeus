# Depot textures (N-319)

Pillow + numpy scripts that draw the depot's painted textures into `assets/textures/depot/`.
The PNGs are committed; run these only to change them.

    python build_mural_brand.py ../../fonts/LilitaOne-Regular.ttf ../../textures/depot/tx_depot_mural_brand.png
    python build_cork_photos.py ../../textures/depot/tx_depot_cork_photos.png
    python build_employee_month.py ../../fonts/LilitaOne-Regular.ttf ../../textures/depot/tx_depot_employee_month.png

`build_cork_photos.py` crops real game captures from the Godot user folder (`SHOTS` at the top:
`store_shots/*.png`, `packages_review.png`, `player_character_standing_crew.png`); regenerate those
with `tests/render_store_shots.gd` and friends first. The pictogram atlas lives in
`../build_depot_props.py` (`_pictogram_atlas()`).
