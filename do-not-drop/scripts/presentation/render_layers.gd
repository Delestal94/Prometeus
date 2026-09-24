extends RefCounted
## These are visual layers, independent of physics collision layers.
const WORLD: int = 1
## Your own body: others see it, your own first-person cameras don't (the
## head would fill the lens). There are no stand-in first-person hands --
## the only hands on screen are a character's.
const LOCAL_BODY: int = 2


static func configure_first_person(camera: Camera3D) -> void:
	camera.cull_mask &= ~LOCAL_BODY
