## Static data for SPC risk categories.
class_name RiskData

enum Category { TSTM, MRGL, SLGT, ENH, MDT, HIGH }

## Official SPC convective outlook colors
const COLORS: Dictionary = {
	Category.TSTM: Color(0.76, 0.91, 0.76),    # Light green
	Category.MRGL: Color(0.40, 0.64, 0.40),     # Dark green
	Category.SLGT: Color(1.00, 0.88, 0.40),     # Yellow
	Category.ENH:  Color(1.00, 0.65, 0.00),     # Orange
	Category.MDT:  Color(1.00, 0.00, 0.00),     # Red
	Category.HIGH: Color(1.00, 0.00, 1.00),     # Magenta
}

## Short labels (as shown on SPC graphics)
const LABELS: Dictionary = {
	Category.TSTM: "TSTM",
	Category.MRGL: "MRGL",
	Category.SLGT: "SLGT",
	Category.ENH:  "ENH",
	Category.MDT:  "MDT",
	Category.HIGH: "HIGH",
}

## Full descriptive names
const FULL_NAMES: Dictionary = {
	Category.TSTM: "General Thunder",
	Category.MRGL: "Marginal",
	Category.SLGT: "Slight",
	Category.ENH:  "Enhanced",
	Category.MDT:  "Moderate",
	Category.HIGH: "High",
}

## Number key → category mapping
const HOTKEYS: Dictionary = {
	KEY_1: Category.TSTM,
	KEY_2: Category.MRGL,
	KEY_3: Category.SLGT,
	KEY_4: Category.ENH,
	KEY_5: Category.MDT,
	KEY_6: Category.HIGH,
}
