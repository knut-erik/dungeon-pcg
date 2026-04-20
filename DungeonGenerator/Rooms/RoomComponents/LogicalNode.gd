# LogicalNode.gd
class_name LogicalNode
extends RefCounted

var id: String
var assigned_tags: Array[String] = []
var connections: Array[LogicalNode] = []
var blueprint: RoomBlueprint # Referens till vilken typ av rum som ska byggas
var custom_data: Dictionary = {} # Används för att skicka unika parametrar, t.ex. delta_y för gateways
