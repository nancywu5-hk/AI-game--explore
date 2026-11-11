class_name ScaleUtils
extends Node

# Utility functions for scaling values based on discrete steps.
# - steps_from_position(position, interval) -> int
# - scaled_value(base_value, change_percent, steps, increase) -> float

static func steps_from_position(position: float, interval: float) -> int:
	if interval <= 0.0:
		return 0
	return int(max(0.0, floor(position / interval)))

static func scaled_value(base_value: float, change_percent: float, steps: int) -> float:
	# change_percent is applied per step multiplicatively. Use negative values to decrease, positive to increase.
	var factor: float = 1.0 + change_percent
	return base_value * pow(factor, steps)
