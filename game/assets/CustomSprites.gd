class_name CustomSprites
extends RefCounted

## Sprite original dibujada a mano, pixel a pixel, en memoria.
## No usa archivos de imagen: se genera una vez y se convierte en ImageTexture.
## El superviviente se dibuja desde arriba: coronilla, hombros, pañuelo, mochila
## y una única pose estática con la pistola a dos manos apuntando al frente (-Y).
## Las cuatro regiones de survivor_sheet() alternan brazos/hombros: hay balanceo sutil.

const OUTLINE := Color(0.03, 0.045, 0.03, 1.0)
const SKIN := Color(0.72, 0.55, 0.40, 1.0)
const JACKET := Color(0.20, 0.28, 0.16, 1.0)
const JACKET_LIGHT := Color(0.28, 0.36, 0.20, 1.0)
const PANTS := Color(0.12, 0.14, 0.11, 1.0)
const SCARF := Color(1.0, 0.78, 0.28, 1.0)
const PACK := Color(0.16, 0.13, 0.09, 1.0)
const GUN := Color(0.08, 0.08, 0.07, 1.0)
const FRAME: int = 48

static func survivor_sheet() -> ImageTexture:
	var img := Image.create(FRAME * 4, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Cuatro regiones con balance alterno de brazos/hombros (_draw_survivor).
	for f in range(4):
		_draw_survivor(img, f * FRAME, f)
	return ImageTexture.create_from_image(img)

static func vehicle() -> ImageTexture:
	var img := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Neumáticos a los lados, vistos desde arriba.
	for p in [Vector2i(8, 26), Vector2i(80, 26), Vector2i(8, 86), Vector2i(80, 86)]:
		_rect_outline(img, p.x, p.y, p.x + 8, p.y + 24, Color(0.05, 0.05, 0.05, 1), OUTLINE)

	# Carrocería, capó y cabina.
	_rect_outline(img, 16, 10, 80, 118, Color(0.18, 0.24, 0.15, 1), OUTLINE)
	_rect(img, 28, 14, 68, 22, Color(0.22, 0.29, 0.18, 1))
	_rect_outline(img, 24, 24, 72, 62, Color(0.12, 0.16, 0.11, 1), OUTLINE)
	_rect(img, 28, 28, 68, 42, Color(0.16, 0.24, 0.26, 1))
	_rect(img, 46, 28, 50, 42, Color(0.10, 0.15, 0.16, 1))
	_rect(img, 30, 45, 66, 47, Color(0.28, 0.34, 0.22, 1))

	# Espejos laterales.
	_rect_outline(img, 11, 52, 17, 60, JACKET, OUTLINE)
	_rect_outline(img, 79, 52, 85, 60, JACKET, OUTLINE)

	# Caja trasera con listones.
	_rect_outline(img, 22, 66, 74, 108, Color(0.15, 0.11, 0.07, 1), OUTLINE)
	for y in range(72, 107, 8):
		_rect(img, 24, y, 72, y + 2, Color(0.24, 0.18, 0.10, 1))

	# Faros delanteros arriba y pilotos traseros abajo.
	_rect(img, 24, 8, 34, 14, SCARF)
	_rect(img, 62, 8, 72, 14, SCARF)
	_rect(img, 22, 113, 32, 118, Color(0.62, 0.12, 0.10, 1))
	_rect(img, 64, 113, 74, 118, Color(0.62, 0.12, 0.10, 1))
	return ImageTexture.create_from_image(img)

static func _draw_survivor(img: Image, ox: int, frame: int) -> void:
	var swings: Array[int] = [-2, 0, 2, 0]
	var shoulders: Array[int] = [-1, 0, 1, 0]
	var swing: int = swings[frame % 4]
	var shoulder: int = shoulders[frame % 4]

	# Silueta horizontal de hombros y brazos: no hay piernas ni perfil frontal.
	_round_rect_outline(img, ox + 11, 19 + shoulder, ox + 37, 27 + shoulder,
			4, JACKET, OUTLINE)

	# Torso ovalado, visto desde arriba.
	_round_rect_outline(img, ox + 16, 18, ox + 32, 29, 4, JACKET, OUTLINE)
	_rect(img, ox + 18, 19 + shoulder, ox + 22, 21 + shoulder, JACKET_LIGHT)
	_rect(img, ox + 26, 19 + shoulder, ox + 30, 21 + shoulder, JACKET_LIGHT)
	_rect(img, ox + 23, 22, ox + 25, 27, Color(0.10, 0.12, 0.09, 1))

	# Mochila en la espalda (abajo en la imagen) con sus tirantes.
	_round_rect_outline(img, ox + 18, 26, ox + 30, 33, 2, PACK, OUTLINE)
	_rect(img, ox + 20, 28, ox + 28, 31, Color(0.24, 0.19, 0.12, 1))
	_rect(img, ox + 19, 23, ox + 21, 27, PACK)
	_rect(img, ox + 27, 23, ox + 29, 27, PACK)

	# Pañuelo ámbar: franja ancha entre la coronilla y los hombros.
	_rect_outline(img, ox + 16, 17, ox + 32, 20, SCARF, OUTLINE)
	_rect(img, ox + 23, 20, ox + 26, 23, SCARF)

	# Coronilla y gorra, sin ojos ni cara: solo se ve la parte superior.
	_disc(img, ox + 24, 11, 7, OUTLINE)
	_disc(img, ox + 24, 11, 6, SKIN)
	_disc(img, ox + 17, 12, 2, SKIN)
	_disc(img, ox + 31, 12, 2, SKIN)
	_disc(img, ox + 24, 10, 5, GUN)
	_rect(img, ox + 21, 4, ox + 27, 7, GUN)
	_rect(img, ox + 22, 5, ox + 26, 6, JACKET_LIGHT)

	# Brazos extendidos a izquierda y derecha, con balance alterno.
	_round_rect_outline(img, ox + 7, 20 + swing, ox + 16, 26 + swing, 3, JACKET, OUTLINE)
	_rect(img, ox + 8, 21 + swing, ox + 11, 25 + swing, SKIN)
	_round_rect_outline(img, ox + 32, 20 - swing, ox + 41, 26 - swing, 3, JACKET, OUTLINE)
	_rect(img, ox + 37, 21 - swing, ox + 40, 25 - swing, SKIN)

	# Pistola corta apuntando hacia delante desde la mano derecha.
	var gun_y: int = 11 - swing
	_rect_outline(img, ox + 37, gun_y, ox + 40, 21 - swing, GUN, OUTLINE)
	_rect_outline(img, ox + 35, 20 - swing, ox + 40, 24 - swing, GUN, OUTLINE)
	_rect(img, ox + 38, gun_y + 1, ox + 39, gun_y + 3, JACKET_LIGHT)

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			_px(img, x, y, c)

static func _rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int,
		fill: Color, outline: Color) -> void:
	_rect(img, x0, y0, x1, y1, fill)
	for x in range(x0, x1):
		_px(img, x, y0, outline)
		_px(img, x, y1 - 1, outline)
	for y in range(y0, y1):
		_px(img, x0, y, outline)
		_px(img, x1 - 1, y, outline)

static func _disc(img: Image, cx: int, cy: int, radius: int, c: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= radius * radius:
				_px(img, x, y, c)

static func _round_rect(img: Image, x0: int, y0: int, x1: int, y1: int,
		r: int, c: Color) -> void:
	_rect(img, x0 + r, y0, x1 - r, y1, c)
	_rect(img, x0, y0 + r, x1, y1 - r, c)
	_disc(img, x0 + r, y0 + r, r, c)
	_disc(img, x1 - r - 1, y0 + r, r, c)
	_disc(img, x0 + r, y1 - r - 1, r, c)
	_disc(img, x1 - r - 1, y1 - r - 1, r, c)

static func _round_rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int,
		r: int, fill: Color, outline: Color) -> void:
	_round_rect(img, x0 - 1, y0 - 1, x1 + 1, y1 + 1, r + 1, outline)
	_round_rect(img, x0, y0, x1, y1, r, fill)
