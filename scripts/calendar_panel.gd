extends RefCounted
class_name LifeCalendarPanel
const P=preload("res://scripts/palette.gd")
var app:Node
var week:int=0
var selected_day:int=1
var categories:Dictionary={"school":true,"work":true,"birthday":true}

func _init(owner:Node) -> void:app=owner

func open() -> void:
	week=0;selected_day=app.household.day
	categories={"school":true,"work":true,"birthday":true}
	show_calendar()

func change_week(offset:int) -> void:
	week=clampi(offset,0,1);selected_day=mini(1000000,app.household.day+week*7)
	show_calendar()

func choose_day(date:int) -> void:
	selected_day=date;show_calendar()

func toggle(kind:String) -> void:
	categories[kind]=not bool(categories[kind]);show_calendar()

func show_calendar() -> void:
	if app.mode!="live":return
	app._begin_pause_overlay();app.menus.shade()
	app.card(Vector2(176,105),Vector2(1088,690),P.WHITE,24,app.overlay)
	app.small_caps("Phone · Household calendar",Vector2(211,126),Vector2(790,24),app.overlay)
	app.text_label("The days ahead.",Vector2(208,163),Vector2(890,53),37,P.INK,true,app.overlay)
	app.paragraph("School, work and birthdays for everyone at home.",Vector2(212,222),Vector2(989,33),18,P.MUTED,app.overlay)
	app.button("Back to phone",Vector2(1047,133),Vector2(181,40),app.adoption_flow.show_phone,false,app.overlay).name="CalendarBack"
	var first:int=mini(1000000,int(app.household.day)+week*7)
	var events:Array=LifeCalendar.entries(app.household,first)
	app.button("This week",Vector2(213,271),Vector2(129,37),change_week.bind(0),week==0,app.overlay).name="CalendarThisWeek"
	var next:Button=app.button("Next week",Vector2(350,271),Vector2(129,37),change_week.bind(1),week==1,app.overlay)
	next.name="CalendarNextWeek";next.disabled=int(app.household.day)+7>1000000
	for index:int in range(3):
		var kind:String=["school","work","birthday"][index]
		var label:String=["School","Work","Birthdays"][index]
		var filter:Button=app.button(label,Vector2(807+index*141,271),Vector2(131,37),toggle.bind(kind),bool(categories[kind]),app.overlay)
		filter.name="CalendarFilter_"+kind;filter.tooltip_text="Show "+label.to_lower() if not categories[kind] else "Hide "+label.to_lower()
	for index:int in range(7):
		var date:int=first+index
		if date>1000000:break
		var total:int=events.filter(func(entry:Dictionary)->bool:return int(entry.day)==date and bool(categories[entry.kind])).size()
		var label:String=LifeEducation.weekday_name(date).left(3)+" · Day "+str(date)+"\n"+(str(total)+(" plan" if total==1 else " plans"))
		var day_button:Button=app.button(label,Vector2(213+index*145,326),Vector2(137,70),choose_day.bind(date),selected_day==date,app.overlay)
		day_button.name="CalendarDay_"+str(date)
	app.text_label(LifeEducation.weekday_name(selected_day)+" · Day "+str(selected_day)+( " · Today" if selected_day==app.household.day else ""),Vector2(214,415),Vector2(976,36),24,P.INK,true,app.overlay)
	var scroll:=ScrollContainer.new();scroll.name="CalendarAgenda";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true
	app.rect(scroll,Vector2(213,465),Vector2(1015,220),app.overlay)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",9);scroll.add_child(column)
	var shown:int=0
	for entry:Dictionary in events:
		if int(entry.day)!=selected_day or not bool(categories[entry.kind]):continue
		shown+=1
		var row:=Control.new();row.name="CalendarEntry_"+str(entry.kind)+"_"+str(entry.member_id);row.custom_minimum_size=Vector2(989,98);column.add_child(row)
		app.card(Vector2.ZERO,Vector2(989,98),P.PALE,12,row)
		var time:String=LifeCalendar.clock_text(float(entry.minutes))
		if entry.kind!="birthday":time+="–"+LifeCalendar.clock_text(float(entry.end))
		app.text_label(time,Vector2(15,13),Vector2(142,27),16,P.TEAL,false,row)
		app.text_label(str(entry.status),Vector2(15,48),Vector2(158,41),13,P.MUTED,false,row)
		var title:Label=app.text_label(str(entry.name)+" · "+str(entry.title),Vector2(185,10),Vector2(782,30),20,P.INK,true,row)
		title.name="AgendaTitle"
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.size.x=782
		title.mouse_filter=Control.MOUSE_FILTER_PASS;title.tooltip_text=title.text
		app.paragraph(str(entry.detail),Vector2(186,45),Vector2(781,46),15,P.MUTED,row)
	if shown==0:
		var empty:=Label.new();empty.name="CalendarEmpty";empty.text="No plans in these categories today.";empty.add_theme_color_override("font_color",P.MUTED);empty.add_theme_font_size_override("font_size",20);column.add_child(empty)
	app.paragraph("Birthdays are estimates from your aging settings. Future routines are shown up to each Lifelet's next age change.",Vector2(215,698),Vector2(757,53),14,P.MUTED,app.overlay)
	app.button("Back to life",Vector2(995,718),Vector2(234,42),app.close_overlay,true,app.overlay).name="CalendarClose"
