extends BaseConstants

const DEFAULT_AIR_RESISTANCE: float = 0.992
const DEFAULT_APPLIES_TO_GRAPPLING: bool = true
const DEFAULT_WATER_SLOWDOWN_FACTOR: float = 0.5
const DEFAULT_WATER_BUOYANCY_FORCE: float = -300.0 # Clearer float effect (was -100.0)
const DEFAULT_WATER_RESISTANCE: float = 0.8

func _ready() -> void:
	settings = {}
