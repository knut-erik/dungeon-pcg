# RoomParameter.gd
extends Resource
class_name RoomParameter

@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var probability_curve: Curve

# Funktion för att generera ett värde baserat på fördelningen
func sample(rng: RandomNumberGenerator) -> float:
	# Dra ett jämnt fördelat tal mellan 0 och 1
	var t = rng.randf()
	
	# Om vi har en kurva, låt den förvränga sannolikheten (annars linjärt)
	var weight = probability_curve.sample(t) if probability_curve else t
	
	# Returnera värdet mellan min och max
	return lerp(min_value, max_value, weight)
