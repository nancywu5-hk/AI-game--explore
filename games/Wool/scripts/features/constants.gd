extends BaseConstants



func _ready() -> void:
	settings = {
		"Grappling": {
			"swing_pump_force": { "value": 1200.0, "min": 0.0, "max": 2000.0, "step": 50.0, "description": "Kraft beim aktiven Schwingen (Knopf halten)" },
			"max_boost_force": { "value": 1400.0, "min": 0.0, "max": 2000.0, "step": 50.0, "description": "Zusätzlicher Schwung beim Loslassen des Seils" },
			"fixed_rope_length": { "value": 200.0, "min": 10.0, "max": 1000.0, "step": 10.0, "description": "Feste Länge des Greifarm-Seils" },
			"max_swing_angle": { "value": 90.0, "min": 0.0, "max": 180.0, "step": 1.0, "description": "Maximaler Schwingwinkel in Grad (0 = nur hängen, 90 = volle Links-Unten-Rechts)" },
				"edge_boost_multiplier": { "value": 1.5, "min": 1.0, "max": 3.0, "step": 0.1, "description": "Multiplikator für den Rückschwung am Seilende (hilft beim Abprallen)" },
				"edge_min_tangential_speed": { "value": 120.0, "min": 0.0, "max": 1000.0, "step": 10.0, "description": "Minimale Tangentialgeschwindigkeit an der Seilkante, bevor ein Boost angewendet wird" },
				"prefer_ccw_on_start": { "value": true, "description": "Wenn true, wird zu Beginn CCW geschwungen, wenn natürlich möglich" },
				"ccw_start_impulse": { "value": 180.0, "min": 0.0, "max": 1000.0, "step": 10.0, "description": "Start-Impuls (Tangentialgeschwindigkeit) für bevorzugten CCW Beginn" }
		}
	}
