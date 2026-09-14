extends RefCounted
class_name LifeFamilyGraph
## Explicit genealogy. A parent edge a->b means a is a parent of b.
## relationship(a,b) describes b from a's point of view.

const ROLES: Array[String] = ["none","siblings","parent","child","grandparent","grandchild","ancestor","descendant","parent_sibling","sibling_child","cousin","relative"]
const LABELS: Dictionary = {"none":"Housemate","siblings":"Sibling","parent":"Parent","child":"Child","grandparent":"Grandparent","grandchild":"Grandchild","ancestor":"Ancestor","descendant":"Descendant","parent_sibling":"Parent’s sibling","sibling_child":"Sibling’s child","cousin":"Cousin","relative":"Relative"}

## `departed` remembers ids of Lifelets who passed away. Their parent and
## sibling edges stay in the graph, so a surviving family can still read its own
## genealogy, but they are not household members and are never selectable.
static func fresh() -> Dictionary:
	return {"version":1,"parents":[],"siblings":[],"departed":[]}

static func departed_ids(graph: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in graph.get("departed",[]):
		if entry is String and not result.has(str(entry)): result.append(str(entry))
	return result

static func inverse(role: String) -> String:
	return str({"parent":"child","child":"parent","grandparent":"grandchild","grandchild":"grandparent","ancestor":"descendant","descendant":"ancestor","parent_sibling":"sibling_child","sibling_child":"parent_sibling"}.get(role,role))

static func is_family(role: String) -> bool:
	return role in ROLES and role != "none"

static func label(role: String) -> String:
	return str(LABELS.get(role,"Housemate"))

static func _pair(a: String, b: String) -> String:
	return a+"|"+b if a < b else b+"|"+a

static func _ids(profiles: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in profiles:
		if key is String: result.append(str(key))
	return result

static func create(profiles: Dictionary, links: Array) -> Dictionary:
	if profiles.is_empty() or profiles.size()>8 or _ids(profiles).size()!=profiles.size(): return {"ok":false,"error":"The family needs valid household Lifelets."}
	if links.size()>28: return {"ok":false,"error":"There are too many family connections."}
	var graph: Dictionary = fresh()
	var pairs: Dictionary = {}
	var partners: Array = []
	var housemates: Array = []
	for value: Variant in links:
		if not value is Dictionary or value.size()!=3 or not value.get("a") is String or not value.get("b") is String or not value.get("role") is String:
			return {"ok":false,"error":"A family connection is invalid."}
		var a: String = value.a
		var b: String = value.b
		var role: String = value.role
		if not profiles.has(a) or not profiles.has(b) or a==b or role not in ["housemates","siblings","partners","parent"]:
			return {"ok":false,"error":"Choose two different household Lifelets and a valid connection."}
		var key: String = _pair(a,b)
		if pairs.has(key): return {"ok":false,"error":"Each pair can have only one declared connection."}
		pairs[key] = role
		match role:
			"parent":
				if not profiles[a] is Dictionary or not profiles[b] is Dictionary: return {"ok":false,"error":"A family profile is invalid."}
				var parent_stage: String = LifeLifecycle.stage_for(profiles[a])
				var child_stage: String = LifeLifecycle.stage_for(profiles[b])
				if str(profiles[a].get("life_stage",LifeLifecycle.eligibility(parent_stage)))!="adult" or parent_stage not in ["young_adult","adult","elder"] or child_stage not in LifeLifecycle.STAGES or LifeLifecycle.STAGES.find(parent_stage)<=LifeLifecycle.STAGES.find(child_stage):
					return {"ok":false,"error":"A parent must be an adult in a later age stage than their child. Same-stage parent setup is unavailable."}
				graph.parents.append({"a":a,"b":b})
			"siblings": graph.siblings.append({"a":a,"b":b})
			"partners": partners.append({"a":a,"b":b,"role":"partners"})
			"housemates": housemates.append({"a":a,"b":b})
	var error: String = validate(graph,_ids(profiles))
	if not error.is_empty(): return {"ok":false,"error":error}
	graph = canonical(graph,_ids(profiles))
	for pair: Dictionary in partners+housemates:
		var role: String = relationship(graph,str(pair.a),str(pair.b))
		if role == "siblings": return {"ok":false,"error":"This pair belongs to the same sibling family; revise the sibling links first."}
		if is_family(role): return {"ok":false,"error":"This pair is related through other family links; revise those connections first."}
	return {"ok":true,"graph":graph,"partners":partners}

static func validate(value: Variant, member_ids: Array) -> String:
	if not value is Dictionary or value.size() not in [3,4] or not (value.get("version") is int or value.get("version") is float) or float(value.version)!=1.0 or not value.get("parents") is Array or not value.get("siblings") is Array:
		return "The saved family graph has an invalid format."
	if value.parents.size()>16 or value.siblings.size()>28: return "The saved family graph has too many connections."
	# Departed Lifelets keep their edges so the survivors' genealogy survives,
	# so an edge may name them even though they are no longer household members.
	var known: Dictionary = {}
	for id: String in member_ids: known[str(id)] = true
	var departed: Array = value.get("departed",[])
	if not departed is Array or departed.size()>8: return "The saved family graph has invalid departed memory."
	var buried: Dictionary = {}
	for entry: Variant in departed:
		if not entry is String or entry.is_empty() or known.has(str(entry)) or buried.has(str(entry)):
			return "The saved family graph contains invalid departed memory."
		buried[str(entry)] = true
		known[str(entry)] = true
	var parent_counts: Dictionary = {}
	for category: String in ["parents","siblings"]:
		var seen: Dictionary = {}
		for link: Variant in value[category]:
			if not link is Dictionary or link.size()!=2 or not link.get("a") is String or not link.get("b") is String or not known.has(link.a) or not known.has(link.b) or link.a==link.b:
				return "The saved family graph contains an invalid Lifelet connection."
			var key: String = str(link.a)+"|"+str(link.b) if category=="parents" else _pair(str(link.a),str(link.b))
			if seen.has(key): return "The saved family graph contains a duplicate connection."
			seen[key] = true
			if category=="parents":
				parent_counts[link.b] = int(parent_counts.get(link.b,0))+1
				if int(parent_counts[link.b])>2: return "A Lifelet can have at most two declared parents."
	var cycle_ids: Array = []
	for id: String in member_ids: cycle_ids.append(str(id))
	cycle_ids.append_array(departed_ids(value))
	for id: String in cycle_ids:
		var ancestors: Dictionary = _ancestors(value,id)
		if ancestors.has(id): return "Parent connections cannot contain a cycle."
		for ancestor: String in ancestors:
			if _siblings(value,id,ancestor): return "An ancestor and descendant cannot also be siblings."
	return ""

static func _parents(graph: Dictionary, id: String) -> Array[String]:
	var result: Array[String] = []
	for link: Dictionary in graph.parents:
		if str(link.b)==id: result.append(str(link.a))
	return result

static func _ancestors(graph: Dictionary, id: String) -> Dictionary:
	var result: Dictionary = {}
	var frontier: Array = [{"id":id,"distance":0}]
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_front()
		for parent: String in _parents(graph,str(current.id)):
			var distance: int = int(current.distance)+1
			if not result.has(parent) or distance<int(result[parent]):
				result[parent] = distance
				frontier.append({"id":parent,"distance":distance})
	return result

static func _declared_group(graph: Dictionary, id: String) -> Array[String]:
	var found: Array[String] = [id]
	var index: int = 0
	while index<found.size():
		var current: String = found[index]
		index += 1
		for link: Dictionary in graph.siblings:
			var peer: String = str(link.b) if str(link.a)==current else (str(link.a) if str(link.b)==current else "")
			if not peer.is_empty() and not found.has(peer): found.append(peer)
	return found

static func _siblings(graph: Dictionary, a: String, b: String) -> bool:
	if a==b: return false
	if _declared_group(graph,a).has(b): return true
	var parents: Array[String] = _parents(graph,a)
	for parent: String in _parents(graph,b):
		if parents.has(parent): return true
	return false

static func relationship(graph: Dictionary, a: String, b: String) -> String:
	if a==b or a.is_empty() or b.is_empty(): return "none"
	var a_ancestors: Dictionary = _ancestors(graph,a)
	var b_ancestors: Dictionary = _ancestors(graph,b)
	if a_ancestors.has(b):
		return "parent" if int(a_ancestors[b])==1 else ("grandparent" if int(a_ancestors[b])==2 else "ancestor")
	if b_ancestors.has(a):
		return "child" if int(b_ancestors[a])==1 else ("grandchild" if int(b_ancestors[a])==2 else "descendant")
	if _siblings(graph,a,b): return "siblings"
	var a_parents: Array[String] = _parents(graph,a)
	var b_parents: Array[String] = _parents(graph,b)
	for parent: String in a_parents:
		if _siblings(graph,parent,b): return "parent_sibling"
	for parent: String in b_parents:
		if _siblings(graph,parent,a): return "sibling_child"
	for first: String in a_parents:
		for second: String in b_parents:
			if _siblings(graph,first,second): return "cousin"
	# Preserve known extended kin even when no shorter label fits this small graph.
	for first: String in a_ancestors:
		if b_ancestors.has(first) or _siblings(graph,first,b): return "relative"
		for second: String in b_ancestors:
			if _siblings(graph,first,second): return "relative"
	for second: String in b_ancestors:
		if _siblings(graph,a,second): return "relative"
	return "none"

static func canonical(graph: Dictionary, member_ids: Array) -> Dictionary:
	var result: Dictionary = fresh()
	result.parents = graph.parents.duplicate(true)
	result.parents.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.a)+"|"+str(a.b)<str(b.a)+"|"+str(b.b))
	# Departed memory is household history, not genealogy: carry it through
	# canonicalization so a save/load never forgets who has passed away.
	var buried: Array = []
	for entry: Variant in graph.get("departed",[]):
		if entry is String and not buried.has(str(entry)): buried.append(str(entry))
	buried.sort()
	result.departed = buried
	var seen: Array[String] = []
	for id: String in member_ids:
		if seen.has(id): continue
		var group: Array[String] = _declared_group(graph,id)
		group.sort()
		seen.append_array(group)
		for index: int in range(1,group.size()): result.siblings.append({"a":group[0],"b":group[index]})
	return result

static func links(graph: Dictionary) -> Array:
	var result: Array = []
	for link: Dictionary in graph.parents: result.append({"a":str(link.a),"b":str(link.b),"role":"parent"})
	for link: Dictionary in graph.siblings: result.append({"a":str(link.a),"b":str(link.b),"role":"siblings"})
	return result
