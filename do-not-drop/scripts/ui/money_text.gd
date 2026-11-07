class_name MoneyText
extends RefCounted
## Money as text with the thousands separator of the current language (D-0546): "$1,234" in English,
## "$1.234" in Spanish. One place, so the shop, the day summary and the HUD agree.


## "$1,234", or "-$1,234" for a loss. `locale` empty: the current one.
static func format(amount: int, locale: String = "") -> String:
	var language: String = (locale if locale != "" else TranslationServer.get_locale()).substr(0, 2)
	var separator: String = "." if language == "es" else ","
	var digits: String = str(absi(amount))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = separator + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return "$" + grouped if amount >= 0 else "-$" + grouped
