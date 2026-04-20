# RoomBlueprint.gd
extends Resource
class_name RoomBlueprint

@export var room_scene: PackedScene
@export var possible_tags: Array[String] # Vilka taggar KAN detta rum ha? (Entrance, Dead, Alive, Trapped, Loot, Boss, DeadEnd, Stairs)

# Exempel på parametrar vi kan ställa in via editorn för detta specifika rum
@export var width_param: RoomParameter
@export var length_param: RoomParameter
@export var enemy_density_param: RoomParameter

# TODO: implementera parameter för antal våningar rummet har (en våning bör ha fixed height (kanke per våning (kanske konfigurerbart i generationsfasen))
