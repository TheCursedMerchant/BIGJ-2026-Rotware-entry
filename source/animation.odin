package game

Animation :: struct {
	atlas_anim : Animation_Name,
	current_frame : Texture_Name,
	timer       : f32,
    loop        : bool,
    finished    : bool,
}

create_atlas_anim :: proc(anim: Animation_Name, loop: bool = true) -> Animation {
	a := atlas_animations[anim]

	return {
		current_frame = a.first_frame,
		atlas_anim = anim,
		timer = atlas_textures[a.first_frame].duration,
        loop = loop,
	}
}

update_atlas_anim :: proc(a: ^Animation, dt: f32) {
	a.timer -= dt

	if a.timer <= 0 {
		a.current_frame = Texture_Name(int(a.current_frame) + 1)
		anim := atlas_animations[a.atlas_anim]

		if a.current_frame > anim.last_frame { 
            a.current_frame = anim.last_frame
            a.finished = true
            if a.loop {
                a.finished = false
                a.current_frame = anim.first_frame
            }
		}

		a.timer = atlas_textures[a.current_frame].duration
	}
}

atlas_anim_len :: proc(anim: Animation_Name) -> f32 {
	l: f32
	aa := atlas_animations[anim]

	for i in aa.first_frame..=aa.last_frame {
		t := atlas_textures[i]
		l += t.duration
	}

	return l
}

anim_atlas_texture :: proc(anim: Animation) -> Atlas_Texture {
	return atlas_textures[anim.current_frame]
}
