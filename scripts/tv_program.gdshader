shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int programme = 0;
uniform float playback = 0.0;
uniform vec4 screen_bounds = vec4(-0.5, -0.5, 1.0, 1.0);
varying vec2 screen_uv;
float box(vec2 p, vec2 a, vec2 b) { return step(a.x,p.x)*step(a.y,p.y)*step(p.x,b.x)*step(p.y,b.y); }
float disc(vec2 p, vec2 c, float r) { return 1.0-smoothstep(r-.008,r+.008,length(p-c)); }
void vertex() {
	// The authored screens have a bevelled-box UV atlas. Project their local
	// front plane so every model displays the entire programme upright.
	screen_uv=(VERTEX.xy-screen_bounds.xy)/screen_bounds.zw;
	screen_uv.y=1.0-screen_uv.y;
}
void fragment() {
	vec2 p=screen_uv;
	vec3 color;
	if (programme==0) {
		// Garden mystery: the detective walks past a greenhouse and a robin.
		color=mix(vec3(.45,.73,.86),vec3(.19,.40,.20),step(.62,p.y));
		color=mix(color,vec3(.75,.91,.85),box(p,vec2(.48,.24),vec2(.92,.65)));
		color=mix(color,vec3(.21,.38,.31),box(p,vec2(.67,.24),vec2(.69,.65)));
		float x=.18+.10*sin(playback*.6);
		color=mix(color,vec3(.72,.51,.32),box(p,vec2(x-.035,.47),vec2(x+.035,.72)));
		color=mix(color,vec3(.88,.71,.53),disc(p,vec2(x,.42),.05));
		color=mix(color,vec3(.28,.24,.20),box(p,vec2(x-.075,.35),vec2(x+.07,.39)));
		color=mix(color,vec3(.88,.31,.12),disc(p,vec2(.8+.035*sin(playback),.70),.025));
	} else if (programme==1) {
		// Cooking programme: chef, work surface and a gently steaming dish.
		color=vec3(.92,.80,.63);
		color=mix(color,vec3(.54,.29,.14),box(p,vec2(0,.68),vec2(1,1)));
		color=mix(color,vec3(.94,.96,.91),box(p,vec2(.20,.40),vec2(.35,.69)));
		color=mix(color,vec3(.76,.52,.35),disc(p,vec2(.27,.33),.065));
		color=mix(color,vec3(.98),box(p,vec2(.18,.22),vec2(.36,.29)));
		color=mix(color,vec3(.95,.87,.70),disc(p,vec2(.65,.66),.13));
		color=mix(color,vec3(.34,.55,.23),disc(p,vec2(.65,.64),.085));
		color=mix(color,vec3(.99),disc(p,vec2(.64+.02*sin(playback*2.),.44+.04*sin(playback)),.022));
	} else {
		// Match coverage: pitch markings, two teams and a moving football.
		color=vec3(.13,.43,.25);
		color=mix(color,vec3(.82,.90,.80),box(p,vec2(.495,0),vec2(.505,1)));
		float ring=abs(length(p-vec2(.5))-.20);
		color=mix(color,vec3(.82,.90,.80),1.0-smoothstep(.008,.015,ring));
		for (int i=0;i<4;i++) {
			float n=float(i);
			color=mix(color,vec3(.83,.20,.16),disc(p,vec2(.18+n*.16,.3+.12*sin(playback*.7+n)),.025));
			color=mix(color,vec3(.21,.42,.92),disc(p,vec2(.26+n*.17,.7+.12*cos(playback*.7+n)),.025));
		}
		color=mix(color,vec3(.98),disc(p,vec2(.5+.29*sin(playback*.65),.5+.16*cos(playback*.65)),.019));
	}
	ALBEDO=color;
}
