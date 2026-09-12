extends RefCounted
class_name LifeNeighborhood
## Original small-town destinations. Layout IDs remain stable for saved actions.
const PLACES={
	"home":{"name":"Your home","tag":"Make yourself at home","description":"Your household's own space. Rest, cook, build, and make room for the next chapter.","color":"d3987f"},
	"park":{"name":"Juniper Gardens","tag":"Breathe a little deeper","description":"A leafy public garden with benches, flowers, and space to meet the neighbors. Tend the greenery or take an unhurried break.","color":"8bab70"},
	"library":{"name":"The Reading Room","tag":"A quiet kind of adventure","description":"A neighborhood library with reading nooks and shared computers. Discover a book, practice a skill, or get some work done.","color":"7394a9"},
	"maya_home":{"name":"Maya’s garden cottage","resident":"maya","tag":"17 Willow Lane","description":"Maya Chen’s compact sage cottage has a sheltered porch, a bright kitchen and a little painting corner. A home full of plants and things she has made.","color":"80a698"},
	"leo_home":{"name":"Leo’s brick bungalow","resident":"leo","tag":"24 Rowan Close","description":"Leo Morgan’s wide brick bungalow has a reading room, an open kitchen and a sunny side terrace. There is always another book on his table.","color":"b78068"},
	"studio":{"name":"Common Ground Studio","tag":"Make something that is yours","description":"A sunlit community studio. Try your hand at the easels, meet another creative Lifelet, and turn an idea into your next canvas.","color":"c58b74"},
	"priya_home":{"name":"Priya’s lamplit flat","resident":"priya","tag":"9 Rowan Close","description":"Priya Sharma’s upstairs flat is lined with paperbacks and warm lamps, with a wide window seat over the street and tea always within reach.","color":"9a7fa8"},
	"tom_home":{"name":"Tom’s fence-line house","resident":"tom","tag":"31 Willow Lane","description":"Tom Alvarez’s long house leans into its garden: boots by the door, a workbench of half-finished plans and a yard that is mostly one large vegetable bed.","color":"6f8f5e"}
}
## Place keys owned by a resident, mirroring the catalogue homes.
const RESIDENT_HOMES: Array[String] = ["maya_home", "leo_home", "priya_home", "tom_home"]

static func layout(place:String) -> Array:
	var entries:Array=[]
	match place:
		"maya_home":entries=[["bed",-3.3,-2.8,0],["nightstand",-4.2,-.55,90],["sofa",-.9,1.1,0],["table",-.9,2.6,0],["rug",-.9,1.7,0],["plant",-4.1,3.4,0],["easel",2.55,3.15,180],["fridge",3.9,-3.2,0],["stove",2.55,-3.3,0],["sink",1.1,-3.3,0],["dining",3.2,.4,0],["chair",3.2,1.4,180],["toilet",-1,-1.5,0],["shower",-1.15,-3.7,0],["bookshelf",-4.1,2.1,90],["plant",4.1,3.3,0]]
		"leo_home":entries=[["bed",4.5,-2.6,0],["nightstand",5.1,.1,-90],["sofa",-3.4,-2.25,0],["table",-3.4,-.6,0],["rug",-3.4,-1.1,0],["bookshelf",-5,-3.3,0],["bookshelf",-1.7,-3.3,0],["desk",-4.5,2.6,180],["chair",-4.5,1.6,0],["fridge",.2,-3.2,0],["stove",1.6,-3.2,0],["sink",2.55,-3.2,0],["dining",.5,1.5,0],["chair",.5,2.5,180],["chair",.5,.5,0],["toilet",4.1,2.6,180],["shower",5.3,2.8,0],["plant",-5.1,.8,0]]
		"priya_home":entries=[["bed",4.4,-2.7,0],["nightstand",5.0,-1.9,90],["bookshelf",-3.0,-3.2,0],["bookshelf",-4.9,1.0,90],["bookshelf",-4.9,2.8,90],["desk",4.3,1.0,90],["chair",3.6,1.0,0],["sofa",-2.6,2.6,180],["rug",-2.6,1.7,0],["table",-2.6,.6,0],["lamp",-3.8,2.0,0],["fridge",.2,-3.2,0],["stove",1.6,-3.2,0],["sink",2.7,-3.2,0],["dining",.4,1.5,0],["chair",.4,2.5,180],["toilet",4.2,2.5,180],["shower",5.3,2.9,0],["plant",-1.0,3.6,0]]
		"tom_home":entries=[["bed",-4.4,-2.6,0],["nightstand",-5.0,-1.8,90],["desk",4.6,2.6,180],["chair",4.6,1.6,0],["sofa",.9,2.9,180],["rug",.9,1.9,0],["table",.9,.4,0],["fridge",-3.9,-3.2,0],["stove",-2.5,-3.3,0],["sink",-1.1,-3.3,0],["dining",-4.5,.5,0],["chair",-4.5,1.5,180],["toilet",-1.1,-1.5,0],["shower",-1.2,-3.7,0],["plant",4.8,-3.3,0],["plant",5.1,3.6,0]]
		"park":entries=[["bench",-3,1.8,20],["bench",3,1.8,-20],["plant",-3.7,-2.8,0],["plant",-2.4,-3.3,0],["plant",2.4,-3.3,0],["plant",3.7,-2.8,0],["easel",-5,0,60],["dining",4.6,-.6,0],["chair",4.6,.42,180],["chair",4.6,-1.62,0]]
		"library":entries=[["bookshelf",-5.1,-4.2,0],["bookshelf",-3.4,-4.2,0],["bookshelf",-1.7,-4.2,0],["bookshelf",1.4,-4.2,0],["bookshelf",3.1,-4.2,0],["bookshelf",4.8,-4.2,0],["rug",-3,.3,0],["sofa",-3,-1.0,0],["table",-3,1.0,0],["lamp",-5.2,-1,0],["plant",-.5,-1.9,0],["desk",3.8,-.5,0],["chair",3.8,.48,180],["desk",3.8,3.2,180],["chair",3.8,2.22,0],["chair",-4.1,3.5,155],["chair",-2.2,3.5,205],["plant",5.4,4.1,180]]
		"studio":entries=[["easel",-4.9,-3.4,0],["easel",-2.6,-3.4,0],["easel",-.3,-3.4,0],["easel",2,-3.4,0],["easel",4.4,-3.4,0],["desk",-4,3.7,180],["chair",-4,2.77,0],["sofa",3.5,3.4,180],["table",3.5,1.8,0],["rug",3.5,2.5,0],["plant",5.1,.4,0],["bookshelf",-5.2,-.4,90],["sink",5.4,-.8,-90],["painting",-4.5,-4.9,0],["painting",-.7,-4.9,0],["painting",3.2,-4.9,0]]
	var result:Array=[]
	for i in range(entries.size()):
		var e:Array=entries[i]
		result.append({"id":place+"_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return result
