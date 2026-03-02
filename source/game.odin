package game

import rl "vendor:raylib"
import "core:log"
import "core:c"

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo

run: bool
atlas: rl.Texture
font: Font

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(640, 360, "Odin + Raylib on the web")

    if atlas_data, atlas_ok := read_entire_file("assets/atlas.png"); atlas_ok {
        atlas_image := rl.LoadImageFromMemory(".png", raw_data(atlas_data), c.int(len(atlas_data)))
        atlas = rl.LoadTextureFromImage(atlas_image)
        rl.UnloadImage(atlas_image)
        font = load_atlased_font(atlas)
    }

	rl.InitAudioDevice()
    if rl.IsAudioDeviceReady() {
        log.info("Audio device is ready!")
        // TODO: Load Sounds Here
    }
}

update :: proc() {
	rl.BeginDrawing()
	    rl.ClearBackground({0, 120, 153, 255})
        anim := create_atlas_anim(.Player_Idle_Down)
        draw_atlas_anim_at_pos(anim, rl.GetMousePosition(), {}, atlas) 
        rl.DrawTextEx(font, "My text", 220, 24, 1.0, rl.WHITE)
	rl.EndDrawing()

	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	rl.CloseWindow()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}
	return run
}

load_atlased_font :: proc(atlas: Texture) -> Font {
	num_glyphs := len(atlas_glyphs)
	font_rects := make([]Rect, num_glyphs)
	glyphs := make([]GlyphInfo, num_glyphs)
	for ag, idx in atlas_glyphs {
		font_rects[idx] = ag.rect
		glyphs[idx] = {
			value    = ag.value,
			offsetX  = i32(ag.offset_x),
			offsetY  = i32(ag.offset_y),
			advanceX = i32(ag.advance_x),
		}
	}

	return {
		baseSize = ATLAS_FONT_SIZE,
		glyphCount = i32(num_glyphs),
		glyphPadding = 0,
		texture = atlas,
		recs = raw_data(font_rects),
		glyphs = raw_data(glyphs),
	}
}

draw_atlas_anim_at_pos :: proc(anim: Animation, pos: [2]f32, offset: [2]f32, atlas: Texture) {
	anim_texture := anim_atlas_texture(anim)
	atlas_rect := anim_texture.rect
	atlas_offset := [2]f32{anim_texture.offset_left, anim_texture.offset_top}
	dest := Rect {
		pos.x + atlas_offset.x + offset.x,
		pos.y + atlas_offset.y + offset.y,
		anim_texture.rect.width,
		anim_texture.rect.height,
	}
	rl.DrawTexturePro(atlas, atlas_rect, dest, {}, 0, rl.WHITE)
}
