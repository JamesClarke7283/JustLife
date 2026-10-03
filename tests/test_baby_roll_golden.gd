extends SceneTree
## A golden snapshot of LifeBabyPlan.roll() for parents who are not Elders.
##
## The roll is seeded from the parents' names and the birth serial, and every
## inherited trait draws from one random stream, so changing how many draws are
## made would quietly change every baby. These lines were recorded from the roll
## before Elders were allowed to be parents. If this test fails, the stream moved:
## a change to `_inherit` or `roll` must still make the same draws in the same
## order for two adult parents. (Changing the rolled looks on purpose means
## recording these lines again, and every long playthrough baby changes with them.)

var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

const TWO_ADULTS: Array[String] = [
	"age_stage=baby|aspiration=Maker|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=-0.15|chin_length=0.22|eye_color=55738f|eye_spacing=0.46|face_length=-0.31|face_round=0.26|frame=0|gender=female|hair=2|hair_color=2a2420|height_scale=1.0|jaw_strong=0.29|life_stage=minor|lip_fullness=-0.17|mouth_width=-0.11|name=Marin Vale|nose_bridge=-0.36|nose_length=-0.59|nose_wide=0.57|outfit=0|skin_color=d9a17d|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Successful|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=0.16|chin_length=-0.47|eye_color=55738f|eye_spacing=0.19|face_length=0.58|face_round=0.31|frame=1|gender=male|hair=2|hair_color=54382a|height_scale=1.0|jaw_strong=0.07|life_stage=minor|lip_fullness=0.51|mouth_width=0.11|name=Kit Vale|nose_bridge=0.48|nose_length=0.2|nose_wide=0.15|outfit=0|skin_color=d9a17d|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Maker|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=0.25|chin_length=0.45|eye_color=547365|eye_spacing=0.23|face_length=0.27|face_round=0.61|frame=1|gender=male|hair=1|hair_color=2a2420|height_scale=1.0|jaw_strong=0.2|life_stage=minor|lip_fullness=-0.5|mouth_width=-0.16|name=Alex Vale|nose_bridge=-0.26|nose_length=-0.5|nose_wide=0.45|outfit=0|skin_color=613e30|top_color=3d4145|traits=[]",
	"age_stage=baby|aspiration=Maker|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=-0.27|chin_length=0.19|eye_color=55738f|eye_spacing=0.36|face_length=0.08|face_round=0.17|frame=0|gender=female|hair=1|hair_color=54382a|height_scale=1.0|jaw_strong=0.38|life_stage=minor|lip_fullness=0.61|mouth_width=-0.31|name=Finley Vale|nose_bridge=0.45|nose_length=0.38|nose_wide=0.31|outfit=0|skin_color=b77e58|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Successful|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=-0.48|chin_length=0.51|eye_color=55738f|eye_spacing=0.74|face_length=-0.02|face_round=0.58|frame=1|gender=male|hair=1|hair_color=54382a|height_scale=1.0|jaw_strong=0.58|life_stage=minor|lip_fullness=0.13|mouth_width=-0.54|name=Kit Vale|nose_bridge=-0.3|nose_length=0.11|nose_wide=0.41|outfit=0|skin_color=d9a17d|top_color=efeadb|traits=[]",
	"age_stage=baby|aspiration=Successful|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=0.62|chin_length=0.06|eye_color=547365|eye_spacing=0.13|face_length=-0.44|face_round=0.34|frame=0|gender=female|hair=0|hair_color=2a2420|height_scale=1.0|jaw_strong=0.48|life_stage=minor|lip_fullness=-0.46|mouth_width=-0.11|name=Jules Vale|nose_bridge=0.25|nose_length=0.48|nose_wide=0.73|outfit=0|skin_color=d9a17d|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Successful|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=-0.03|chin_length=0.28|eye_color=547365|eye_spacing=0.75|face_length=0.29|face_round=0.59|frame=1|gender=male|hair=0|hair_color=54382a|height_scale=1.0|jaw_strong=0.65|life_stage=minor|lip_fullness=0.64|mouth_width=-0.61|name=Alex Vale|nose_bridge=0.0|nose_length=0.4|nose_wide=0.49|outfit=0|skin_color=d9a17d|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Maker|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=-0.23|chin_length=-0.2|eye_color=704b36|eye_spacing=0.65|face_length=0.47|face_round=0.69|frame=1|gender=male|hair=0|hair_color=54382a|height_scale=1.0|jaw_strong=0.18|life_stage=minor|lip_fullness=0.41|mouth_width=0.46|name=Kit Vale|nose_bridge=0.45|nose_length=-0.54|nose_wide=0.33|outfit=0|skin_color=d9a17d|top_color=7195b3|traits=[]",
	"age_stage=baby|aspiration=Successful|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=0.65|chin_length=0.02|eye_color=704b36|eye_spacing=0.66|face_length=-0.54|face_round=0.21|frame=1|gender=male|hair=2|hair_color=89563a|height_scale=1.0|jaw_strong=0.26|life_stage=minor|lip_fullness=-0.05|mouth_width=-0.23|name=Remy Vale|nose_bridge=-0.07|nose_length=-0.24|nose_wide=0.67|outfit=0|skin_color=b77e58|top_color=7195b3|traits=[]",
	"age_stage=baby|aspiration=Maker|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=0.37|chin_length=-0.15|eye_color=704b36|eye_spacing=0.5|face_length=0.47|face_round=0.12|frame=0|gender=female|hair=0|hair_color=54382a|height_scale=1.0|jaw_strong=0.43|life_stage=minor|lip_fullness=-0.15|mouth_width=0.45|name=Robin Vale|nose_bridge=-0.32|nose_length=0.14|nose_wide=0.03|outfit=0|skin_color=b77e58|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Successful|body_scale=1.0|bottom=0|bottom_color=51697c|brow_arch=-0.65|chin_length=0.52|eye_color=55738f|eye_spacing=0.62|face_length=0.32|face_round=0.14|frame=1|gender=male|hair=2|hair_color=54382a|height_scale=1.0|jaw_strong=0.68|life_stage=minor|lip_fullness=-0.53|mouth_width=0.47|name=Remy Vale|nose_bridge=0.24|nose_length=0.06|nose_wide=0.02|outfit=0|skin_color=b77e58|top_color=7195b3|traits=[]",
	"age_stage=baby|aspiration=Maker|body_scale=1.0|bottom=0|bottom_color=3e5955|brow_arch=-0.15|chin_length=0.04|eye_color=704b36|eye_spacing=0.1|face_length=-0.57|face_round=0.05|frame=0|gender=female|hair=0|hair_color=2a2420|height_scale=1.0|jaw_strong=0.74|life_stage=minor|lip_fullness=-0.5|mouth_width=0.44|name=Robin Vale|nose_bridge=-0.37|nose_length=-0.5|nose_wide=0.37|outfit=0|skin_color=b77e58|top_color=417a71|traits=[]"
]

## The creator's name-and-gender dice roll with no parents at all.
const NO_PARENTS: Array[String] = [
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=51697c|brow_arch=0.62|chin_length=-0.44|eye_color=b18d54|eye_spacing=0.32|face_length=-0.13|face_round=0.46|frame=1|gender=male|hair=0|hair_color=784e49|height_scale=1.0|jaw_strong=0.52|life_stage=minor|lip_fullness=-0.05|mouth_width=-0.52|name=Alex|nose_bridge=0.45|nose_length=-0.5|nose_wide=0.45|outfit=0|skin_color=e7b98f|top_color=efeadb|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=eadfc9|brow_arch=0.56|chin_length=0.52|eye_color=547365|eye_spacing=0.09|face_length=-0.26|face_round=0.27|frame=0|gender=female|hair=0|hair_color=784e49|height_scale=1.0|jaw_strong=0.34|life_stage=minor|lip_fullness=0.62|mouth_width=0.2|name=Rowan|nose_bridge=0.59|nose_length=0.06|nose_wide=0.62|outfit=0|skin_color=925c40|top_color=c97c66|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=-0.17|chin_length=-0.33|eye_color=b18d54|eye_spacing=0.38|face_length=-0.42|face_round=0.56|frame=0|gender=female|hair=2|hair_color=784e49|height_scale=1.0|jaw_strong=0.56|life_stage=minor|lip_fullness=0.21|mouth_width=-0.27|name=Noa|nose_bridge=0.21|nose_length=-0.44|nose_wide=0.12|outfit=0|skin_color=613e30|top_color=7195b3|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=0.05|chin_length=-0.37|eye_color=77797c|eye_spacing=0.45|face_length=0.08|face_round=0.46|frame=0|gender=female|hair=2|hair_color=784e49|height_scale=1.0|jaw_strong=0.57|life_stage=minor|lip_fullness=0.23|mouth_width=-0.57|name=Noa|nose_bridge=-0.25|nose_length=0.17|nose_wide=0.01|outfit=0|skin_color=d9a17d|top_color=3d4145|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=-0.19|chin_length=0.4|eye_color=547365|eye_spacing=0.24|face_length=0.65|face_round=0.14|frame=0|gender=female|hair=2|hair_color=dfccb0|height_scale=1.0|jaw_strong=0.19|life_stage=minor|lip_fullness=0.52|mouth_width=-0.22|name=Rowan|nose_bridge=-0.24|nose_length=-0.31|nose_wide=0.25|outfit=0|skin_color=613e30|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=292f32|brow_arch=0.6|chin_length=0.46|eye_color=77797c|eye_spacing=0.35|face_length=0.46|face_round=0.71|frame=1|gender=male|hair=2|hair_color=89563a|height_scale=1.0|jaw_strong=0.29|life_stage=minor|lip_fullness=-0.28|mouth_width=-0.43|name=Sage|nose_bridge=-0.48|nose_length=0.26|nose_wide=0.72|outfit=0|skin_color=925c40|top_color=c97c66|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=51697c|brow_arch=-0.07|chin_length=-0.23|eye_color=547365|eye_spacing=0.12|face_length=-0.19|face_round=0.08|frame=0|gender=female|hair=0|hair_color=784e49|height_scale=1.0|jaw_strong=0.09|life_stage=minor|lip_fullness=0.27|mouth_width=0.52|name=Marin|nose_bridge=-0.49|nose_length=-0.43|nose_wide=0.45|outfit=0|skin_color=e7b98f|top_color=417a71|traits=[]",
	"age_stage=baby|aspiration=Balanced|body_scale=1.0|bottom=0|bottom_color=b88a72|brow_arch=-0.32|chin_length=-0.2|eye_color=77797c|eye_spacing=0.69|face_length=0.23|face_round=0.68|frame=1|gender=male|hair=1|hair_color=784e49|height_scale=1.0|jaw_strong=0.07|life_stage=minor|lip_fullness=-0.47|mouth_width=0.03|name=Marin|nose_bridge=-0.58|nose_length=-0.07|nose_wide=0.68|outfit=0|skin_color=925c40|top_color=efeadb|traits=[]"
]

static func line(baby:Dictionary)->String:
	var keys:Array=baby.keys()
	keys.sort()
	var parts:Array[String]=[]
	for key:String in keys:parts.append("%s=%s" % [key,str(baby[key])])
	return "|".join(parts)

func _initialize()->void:
	var mother:Dictionary={"name":"Ada Vale","age_stage":"adult","life_stage":"adult","gender":"female","skin_color":"d9a17d","hair_color":"54382a","eye_color":"55738f","top_color":"417a71","bottom_color":"3e5955","aspiration":"Maker"}
	var father:Dictionary={"name":"Ben Vale","age_stage":"young_adult","life_stage":"adult","gender":"male","skin_color":"b77e58","hair_color":"2a2420","eye_color":"704b36","top_color":"7195b3","bottom_color":"292f32","aspiration":"Successful"}
	var same:int=0
	for serial:int in range(1,TWO_ADULTS.size()+1):
		var rolled:String=line(LifeBabyPlan.roll(mother,father,serial))
		if rolled==TWO_ADULTS[serial-1]:same+=1
		else:print("MOVED serial ",serial,"\n  got  ",rolled,"\n  want ",TWO_ADULTS[serial-1])
	check(same==TWO_ADULTS.size(),"Two adult parents roll exactly the recorded babies (%d of %d)." % [same,TWO_ADULTS.size()])
	same=0
	for serial:int in range(1,NO_PARENTS.size()+1):
		if line(LifeBabyPlan.roll({},{},serial))==NO_PARENTS[serial-1]:same+=1
	check(same==NO_PARENTS.size(),"The creator's dice roll with no parents is unchanged (%d of %d)." % [same,NO_PARENTS.size()])
	# Only an Elder's grey is held back: a grey-haired adult still passes theirs on.
	var grey_adult:Dictionary=father.duplicate(true)
	grey_adult.hair_color="d9d6cd"
	var passed_on:int=0
	for serial:int in range(1,41):
		if str(LifeBabyPlan.roll(mother,grey_adult,serial).hair_color)=="d9d6cd":passed_on+=1
	check(passed_on>0,"A grey-haired adult father can still pass his hair colour on (%d of 40)." % passed_on)
	print("BABY_ROLL_GOLDEN %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
