extends "res://scripts/meal_flow.gd"
var deny_setdown:bool=true
var denied:int=0
func _settle_food(value:Dictionary,from:Vector3)->bool:
	if deny_setdown:denied+=1;return false
	return super._settle_food(value,from)
