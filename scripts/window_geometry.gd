extends RefCounted
## Visual openings only. The source wall record remains solid for navigation.
const FLOOR_Y:float=.16
const ATTACHMENT_OFFSET:float=.015
const TOLERANCE:float=.005

static func opening(window:Node3D, wall:Dictionary, height:float, base_y:float=FLOOR_Y, require_full_span:bool=true)->Rect2:
	if not window.has_meta("window_aperture"):return Rect2()
	var normal:Vector3=window.basis.z.normalized()
	var horizontal:bool=float(wall.w)>float(wall.d)
	if absf(normal.z if horizontal else normal.x)<.999:return Rect2()
	var depth:float=float(wall.d) if horizontal else float(wall.w)
	var center:Vector3=Vector3(float(wall.x),base_y,float(wall.z))
	if absf((window.position-center).dot(normal)-(depth*.5+ATTACHMENT_OFFSET))>TOLERANCE:return Rect2()
	var offset:float=window.position.x-center.x if horizontal else window.position.z-center.z
	var length:float=float(wall.w) if horizontal else float(wall.d)
	var frame:Rect2=window.get_meta("window_frame_bounds")
	# A single-wall caller requires the whole frame. The level-aware renderer
	# first validates continuous collinear support before clipping each part.
	if require_full_span and (offset+frame.position.x < -length*.5-TOLERANCE or offset+frame.end.x > length*.5+TOLERANCE):return Rect2()
	var y:float=window.position.y-base_y
	if y+frame.position.y < -TOLERANCE or y+frame.end.y > height+TOLERANCE:return Rect2()
	var aperture:Rect2=window.get_meta("window_aperture")
	return Rect2(Vector2(offset,y)+aperture.position,aperture.size)

static func supported_wall_ids(window:Node3D, walls:Array)->Array[String]:
	var groups:Array[Dictionary]=[]
	var along_x:bool=absf(window.basis.z.z)>.999
	for wall:Dictionary in walls:
		if not opening(window,wall,float(wall.display_height),float(wall.base_y),false).has_area():continue
		var plane:float=float(wall.z) if along_x else float(wall.x)
		var index:int=-1
		for i:int in groups.size():
			if absf(float(groups[i].plane)-plane)<.001:index=i;break
		if index<0:index=groups.size();groups.append({"plane":plane,"walls":[]})
		groups[index].walls.append(wall)
	var center:float=window.position.x if along_x else window.position.z
	var frame:Rect2=window.get_meta("window_frame_bounds")
	for group:Dictionary in groups:
		var spans:Array[Vector2]=[]
		for wall:Dictionary in group.walls:
			var c:float=float(wall.x) if along_x else float(wall.z)
			var length:float=float(wall.w) if along_x else float(wall.d)
			spans.append(Vector2(c-length*.5,c+length*.5))
		spans.sort_custom(func(a:Vector2,b:Vector2)->bool:return a.x<b.x)
		var covered:float=center+frame.position.x
		for span:Vector2 in spans:
			if span.y<covered-.001:continue
			if span.x>covered+.001:break
			covered=maxf(covered,span.y)
			if covered>=center+frame.end.x-.001:
				var ids:Array[String]=[]
				for wall:Dictionary in group.walls:ids.append(str(wall.id))
				return ids
	return []

static func subtract(rectangles:Array[Rect2], hole:Rect2)->Array[Rect2]:
	var result:Array[Rect2]=[]
	for rect:Rect2 in rectangles:
		var overlap:Rect2=rect.intersection(hole)
		if not overlap.has_area():result.append(rect);continue
		# Four disjoint strips preserve the wall's full thickness and create
		# genuine jamb, sill and lintel faces around each opening.
		var pieces:Array[Rect2]=[
			Rect2(rect.position,Vector2(overlap.position.x-rect.position.x,rect.size.y)),
			Rect2(Vector2(overlap.end.x,rect.position.y),Vector2(rect.end.x-overlap.end.x,rect.size.y)),
			Rect2(Vector2(overlap.position.x,rect.position.y),Vector2(overlap.size.x,overlap.position.y-rect.position.y)),
			Rect2(Vector2(overlap.position.x,overlap.end.y),Vector2(overlap.size.x,rect.end.y-overlap.end.y))]
		for piece:Rect2 in pieces:
			if piece.size.x>.00001 and piece.size.y>.00001:result.append(piece)
	return result
