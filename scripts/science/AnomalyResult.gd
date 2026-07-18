class_name AnomalyResult
extends RefCounted

# A single detected anomaly at a body, for one specific Knowledge category —
# NativeRate.anomaly_for()'s return type. In-memory only, same "no save
# system yet" pattern as every other runtime-computed data class (see
# ActiveOperation.gd).

var name: String = ""
var description: String = ""
var magnitude: String = ""  # "Minor" or "Major"
var rate: float = 0.0
