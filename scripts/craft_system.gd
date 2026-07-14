## Система крафта — один рецепт для примера.
## Рецепт: 2 дерева → 1 стена

extends Node

# Рецепты: название → {входы: {ресурс: количество}, выходы: {ресурс: количество}}
var recipes: Dictionary = {
	"wall": {
		"inputs": {"wood": 2},
		"outputs": {"wall": 1},
	}
}


## Попытаться скрафтить по названию рецепта.
func craft(recipe_name: String) -> bool:
	if recipe_name not in recipes:
		return false

	var recipe = recipes[recipe_name]

	# Проверяем есть ли ресурсы
	for resource_type in recipe["inputs"]:
		var amount = recipe["inputs"][resource_type]
		if InventorySystem.get_total_resource(resource_type) < amount:
			return false

	# Используем входные ресурсы
	for resource_type in recipe["inputs"]:
		var amount = recipe["inputs"][resource_type]
		InventorySystem.use_resource(resource_type, amount)

	# Даём выходные ресурсы
	for resource_type in recipe["outputs"]:
		var amount = recipe["outputs"][resource_type]
		InventorySystem.add_resource(resource_type, amount)

	return true
