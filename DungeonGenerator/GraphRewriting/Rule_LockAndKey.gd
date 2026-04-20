# Rule_LockAndKey.gd
extends GraphRule
class_name Rule_LockAndKey

func can_apply(_graph: LogicalGraph, _target_node: LogicalNode) -> bool:
	# 1. Finns blueprints för lås och nyckel?
	if get_blueprint("Locked") == null or get_blueprint("Key") == null:
		return false
		
	# 2. Pekar denna nod på en Boss?
	for conn in _target_node.connections:
		if conn.assigned_tags.has("Boss"):
			return true
			
	return false

func apply(graph: LogicalGraph, target_node: LogicalNode) -> void:
	# Hitta själva Boss-noden i kopplingarna
	var boss_node: LogicalNode = null
	for conn in target_node.connections:
		if conn.assigned_tags.has("Boss"):
			boss_node = conn
			break
			
	if boss_node == null: return
	
	# 1. Skapa Låst rum
	var lock_node = LogicalNode.new()
	lock_node.id = "lock_" + str(randi() % 1000)
	lock_node.assigned_tags.assign(["Locked"])
	lock_node.blueprint = get_blueprint("Locked")
	
	# Skjut in låset mellan Target och Bossen
	graph.insert_node_between(lock_node, target_node, boss_node)
	
	# 2. Skapa Nyckel-rummet (Detta blir en förgrening / återvändsgränd)
	var key_node = LogicalNode.new()
	key_node.id = "key_" + str(randi() % 1000)
	key_node.assigned_tags.assign(["Key"])
	key_node.blueprint = get_blueprint("Key")
	
	graph.add_node(key_node)
	graph.create_connection(target_node, key_node) # Target grenar nu ut till både Lock och Key
	
	print("Regissör: Lade till Lås framför Boss, och en Nyckel-gren från ", target_node.id)
