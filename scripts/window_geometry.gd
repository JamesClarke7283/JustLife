extends RefCounted
## Visual openings only. The source wall record remains solid for navigation.
const FLOOR_Y:float=.16
const ATTACHMENT_OFFSET:float=.015
const TOLERANCE:float=.006

static func opening(window:Node3D, wall:Dictionary, height:float)->Rect2:
	if not window.has_meta("window_aperture"):return Rect2()
	var normal:Vector3=window.basis.z.normalized()
	var horizontal:bool=float(wall.w)>float(wall.d)
	if absf(normal.z if horizontal else normal.x)<.999:return Rect2()
	var depth:float=float(wall.d) if horizontal else float(wall.w)
	var center:Vector3=Vector3(float(wall.x),FLOOR_Y,float(wall.z))
	if absf((window.position-center).dot(normal)-(depth*.5+ATTACHMENT_OFFSET))>TOLERANCE:return Rect2()
	var offset:float=window.position.x-center.x if horizontal else window.position.z-center.z
	var length:float=float(wall.w) if horizontal else float(wall.d)
	var frame:Rect2=window.get_meta("window_frame_bounds")
	# The entire frame must fit one wall, at its displayed height. Nearby or
	# split walls cannot collectively support a floating frame across a gap.
	if offset+frame.position.x < -length*.5-TOLERANCE or offset+frame.end.x > length*.5+TOLERANCE:return Rect2()
	var y:float=window.position.y-FLOOR_Y
	if y+frame.position.y < -TOLERANCE or y+frame.end.y > height+TOLERANCE:return Rect2()
	var aperture:Rect2=window.get_meta("window_aperture")
	return Rect2(Vector2(offset,y)+aperture.position,aperture.size)

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
