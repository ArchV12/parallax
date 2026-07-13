class_name DepositInfo
extends RefCounted

# One derived (never hand-authored) mining target — always exactly one per
# material a Resource Survey has already detected at a body, rebuilt fresh
# each time by Deposits.deposits_for/deposit_for from that same
# ResourceSurveyData/ResourceMaterialFinding rather than a second parallel
# data set (see the Mining design conversation — two systems tracking
# "what's on this body" independently would drift out of sync). deposit_size
# and extraction_difficulty are just relabeled survey facts (see
# Deposits.DEPOSIT_SIZE_BY_ABUNDANCE/DIFFICULTY_BY_NOTE_VALUE);
# remaining_fraction is the one genuinely new piece of state, owned and
# persisted by Deposits itself, not derivable from the survey.

var body_id: String = ""
var material_name: String = ""
var deposit_size: String = ""           # "Trace" / "Small" / "Moderate" / "Large" / "Massive"
var extraction_difficulty: String = ""  # "Easy" / "Moderate" / "Hard" — flavor only, drives energy usage, not yield/time
var remaining_fraction: float = 1.0     # 1.0 = untouched, 0.0 = fully depleted
