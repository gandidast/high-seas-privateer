class_name ProceduralShipBaker
extends RefCounted
## Static facade & texture cache for crisp 2D pixel-art sprite-stack ship layers,
## Giant Kraken body & tentacle sprites, 48x48 coastal fort bastions,
## deck module sprites, floating loot crates, and Dredge-Grid item icons.
## Implementations are modularized under res://visual/baker/*.

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")
const ShipHullBaker = preload("res://visual/baker/ship_hull_baker.gd")
const ItemIconBaker = preload("res://visual/baker/item_icon_baker.gd")
const EntitySpriteBaker = preload("res://visual/baker/entity_sprite_baker.gd")

const OUTLINE_COLOR := Draw.OUTLINE_COLOR
const SUNLIGHT_HIGHLIGHT := Draw.SUNLIGHT_HIGHLIGHT
const SHIP_TEX_WIDTH: int = ShipHullBaker.SHIP_TEX_WIDTH
const SHIP_TEX_HEIGHT: int = ShipHullBaker.SHIP_TEX_HEIGHT
const GRID_CELL_PX: int = ItemIconBaker.GRID_CELL_PX

static var _ship_layer_cache: Dictionary = {}
static var _sail_range_cache: Dictionary = {}
static var _module_cache: Dictionary = {}
static var _loot_cache: Dictionary = {}
static var _item_icon_cache: Dictionary = {}
static var _kraken_body_cache: Dictionary = {}
static var _kraken_tentacle_cache: Dictionary = {}
static var _fort_cache: Dictionary = {}


static func get_sail_layer_range(layer_count: int = 24) -> Vector2i:
	var safe_layers: int = maxi(12, layer_count)
	if not _sail_range_cache.has(safe_layers):
		_sail_range_cache[safe_layers] = ShipHullBaker.get_sail_layer_range(safe_layers)
	return _sail_range_cache[safe_layers]


static func bake_ship_layers(faction: int = 0, layer_count: int = 20, hull_tier: int = 0) -> Array[ImageTexture]:
	var safe_layers: int = maxi(12, layer_count)
	var safe_tier: int = clampi(hull_tier, 0, 5)
	var safe_faction: int = ShipHullBaker.normalize_faction(faction)
	var cache_key: String = "%d_%d_%d" % [safe_faction, safe_layers, safe_tier]
	if _ship_layer_cache.has(cache_key):
		return _ship_layer_cache[cache_key]

	var layers: Array[ImageTexture] = ShipHullBaker.bake_ship_layers(safe_faction, safe_layers, safe_tier)
	_ship_layer_cache[cache_key] = layers
	return layers


static func bake_item_grid_icon(
	item_id: String,
	category: int = 0,
	width_cells: int = 1,
	height_cells: int = 1,
	rarity: int = 0,
	affix: int = 0
) -> ImageTexture:
	var cw: int = maxi(1, width_cells)
	var ch: int = maxi(1, height_cells)
	var cache_key: String = "%s_%d_%dx%d_%d_%d" % [item_id, category, cw, ch, rarity, affix]
	if _item_icon_cache.has(cache_key):
		return _item_icon_cache[cache_key]

	var tex: ImageTexture = ItemIconBaker.bake_item_grid_icon(item_id, category, cw, ch, rarity, affix)
	_item_icon_cache[cache_key] = tex
	return tex


static func bake_module_texture(category: int, rarity: int = 0, affix: int = 0) -> ImageTexture:
	var cache_key: String = "%d_%d_%d" % [category, rarity, affix]
	if _module_cache.has(cache_key):
		return _module_cache[cache_key]

	var tex: ImageTexture = ItemIconBaker.bake_module_texture(category, rarity, affix)
	_module_cache[cache_key] = tex
	return tex


static func bake_loot_crate_texture(is_salvage: bool = false) -> ImageTexture:
	var cache_key: int = 1 if is_salvage else 0
	if _loot_cache.has(cache_key):
		return _loot_cache[cache_key]

	var tex: ImageTexture = EntitySpriteBaker.bake_loot_crate_texture(is_salvage)
	_loot_cache[cache_key] = tex
	return tex


static func bake_kraken_body_texture(hit_flash: bool = false) -> ImageTexture:
	var cache_key: int = 1 if hit_flash else 0
	if _kraken_body_cache.has(cache_key):
		return _kraken_body_cache[cache_key]

	var tex: ImageTexture = EntitySpriteBaker.bake_kraken_body_texture(hit_flash)
	_kraken_body_cache[cache_key] = tex
	return tex


static func bake_kraken_tentacle_texture(frame: int = 0, hit_flash: bool = false) -> ImageTexture:
	var safe_frame: int = clampi(frame, 0, 2)
	var cache_key: String = "%d_%d" % [safe_frame, 1 if hit_flash else 0]
	if _kraken_tentacle_cache.has(cache_key):
		return _kraken_tentacle_cache[cache_key]

	var tex: ImageTexture = EntitySpriteBaker.bake_kraken_tentacle_texture(safe_frame, hit_flash)
	_kraken_tentacle_cache[cache_key] = tex
	return tex


static func bake_fort_texture(hit_flash: bool = false) -> ImageTexture:
	var cache_key: int = 1 if hit_flash else 0
	if _fort_cache.has(cache_key):
		return _fort_cache[cache_key]

	var tex: ImageTexture = EntitySpriteBaker.bake_fort_texture(hit_flash)
	_fort_cache[cache_key] = tex
	return tex


static func clear_caches() -> void:
	_ship_layer_cache.clear()
	_sail_range_cache.clear()
	_module_cache.clear()
	_loot_cache.clear()
	_item_icon_cache.clear()
	_kraken_body_cache.clear()
	_kraken_tentacle_cache.clear()
	_fort_cache.clear()
