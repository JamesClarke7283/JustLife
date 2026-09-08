extends RefCounted
class_name LifeNeighborhood
## Original small-town destinations. Layout IDs remain stable for saved actions.
const PLACES={
	"home":{"name":"Your home","tag":"Make yourself at home","description":"Your household's own space. Rest, cook, build, and make room for the next chapter.","color":"d3987f"},
	"park":{"name":"Juniper Gardens","tag":"Breathe a little deeper","description":"A leafy public garden with benches, flowers, and space to meet the neighbors. Tend the greenery or take an unhurried break.","color":"8bab70"},
	"library":{"name":"The Reading Room","tag":"A quiet kind of adventure","description":"A neighborhood library with reading nooks and shared computers. Discover a book, practice a skill, or get some work done.","color":"7394a9"},
	"studio":{"name":"Common Ground Studio","tag":"Make something that is yours","description":"A sunlit community studio. Try your hand at the easels, meet another creative Lifelet, and turn an idea into your next canvas.","color":"c58b74"}
}
static func layout(place:String) -> Array:
	var entries:Array=[]
	match place:
		"park":entries=[["bench",-3,1.8,20],["bench",3,1.8,-20],["plant",-3.7,-2.8,0],["plant",-2.4,-3.3,0],["plant",2.4,-3.3,0],["plant",3.7,-2.8,0],["easel",-5,0,60],["dining",4.6,-.6,0],["chair",4.6,.42,180],["chair",4.6,-1.62,0]]
		"library":entries=[["bookshelf",-5.1,-4.2,0],["bookshelf",-3.4,-4.2,0],["bookshelf",-1.7,-4.2,0],["bookshelf",1.4,-4.2,0],["bookshelf",3.1,-4.2,0],["bookshelf",4.8,-4.2,0],["rug",-3,.3,0],["sofa",-3,-1.0,0],["table",-3,1.0,0],["lamp",-5.2,-1,0],["plant",-.5,-1.9,0],["desk",3.8,-.5,0],["chair",3.8,.48,180],["desk",3.8,3.2,180],["chair",3.8,2.22,0],["chair",-4.1,3.5,155],["chair",-2.2,3.5,205],["plant",5.4,4.1,180]]
		"studio":entries=[["easel",-4.9,-3.4,0],["easel",-2.6,-3.4,0],["easel",-.3,-3.4,0],["easel",2,-3.4,0],["easel",4.4,-3.4,0],["desk",-4,3.7,180],["chair",-4,2.77,0],["sofa",3.5,3.4,180],["table",3.5,1.8,0],["rug",3.5,2.5,0],["plant",5.1,.4,0],["bookshelf",-5.2,-.4,90],["sink",5.4,-.8,-90],["painting",-4.5,-4.9,0],["painting",-.7,-4.9,0],["painting",3.2,-4.9,0]]
	var result:Array=[]
	for i in range(entries.size()):
		var e:Array=entries[i]
		result.append({"id":place+"_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return result
