extends SceneTree
func _initialize() -> void:
	var d:Dictionary={"a":1}
	print("int(null)=", int(d.get("zz")), " ok=", typeof(null))
	var g:Dictionary=LifeFamilyGraph.fresh()
	g.parents.append({"a":"gone","b":"kid"})
	g.parents.append({"a":"dad","b":"kid"})
	var levels:Dictionary={"kid":0}
	for edge:Dictionary in g.parents:
		var next:int=int(levels[str(edge.a)])+1
		print("edge ",edge.a," -> next ",next)
	print(LifeFamilyGraph.relationship(g,"dad","kid")," ",LifeFamilyGraph.relationship(g,"gone","kid"))
	quit(0)
