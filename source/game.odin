package game

import rl "vendor:raylib"
import "core:log"
import "core:fmt"
import "core:c"

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo

run: bool
texture: rl.Texture
texture2: rl.Texture
texture2_rot: f32
sound_explosion : rl.Sound
debug_color : rl.Color = rl.WHITE
atlas: rl.Texture
font: Font

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	//rl.InitWindow(1280, 720, "Odin + Raylib on the web")
	rl.InitWindow(640, 360, "Odin + Raylib on the web")

	// Anything in `assets` folder is available to load.
	texture = rl.LoadTexture("assets/round_cat.png")

	// A different way of loading a texture: using `read_entire_file` that works
	// both on desktop and web. Note: You can import `core:os` and use
	// `os.read_entire_file`. But that won't work on web. Emscripten has a way
	// to bundle files into the build, and we access those using this
	// special `read_entire_file`.
	if long_cat_data, long_cat_ok := read_entire_file("assets/long_cat.png", context.temp_allocator); long_cat_ok {
		long_cat_img := rl.LoadImageFromMemory(".png", raw_data(long_cat_data), c.int(len(long_cat_data)))
		texture2 = rl.LoadTextureFromImage(long_cat_img)
		rl.UnloadImage(long_cat_img)
	}

    if atlas_data, atlas_ok := read_entire_file("assets/atlas.png"); atlas_ok {
        atlas_image := rl.LoadImageFromMemory(".png", raw_data(atlas_data), c.int(len(atlas_data)))
        atlas = rl.LoadTextureFromImage(atlas_image)
        rl.UnloadImage(atlas_image)
        font = load_atlased_font(atlas)
    }

	rl.InitAudioDevice()
    if rl.IsAudioDeviceReady() {
        debug_color = rl.RED
        log.info("Audio device is ready!")
        sound_explosion = rl.LoadSound("../assets/explosion_1.wav")
    }
}

update :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground({0, 120, 153, 255})
	{
		texture2_rot += rl.GetFrameTime()*50
		source_rect := rl.Rectangle {
			0, 0,
			f32(texture2.width), f32(texture2.height),
		}
		dest_rect := rl.Rectangle {
			300, 220,
			f32(texture2.width)*5, f32(texture2.height)*5,
		}
		rl.DrawTexturePro(texture2, source_rect, dest_rect, {dest_rect.width/2, dest_rect.height/2}, texture2_rot, rl.WHITE)
	}
	//rl.DrawTextureEx(texture, rl.GetMousePosition(), 0, 5, rl.WHITE)
    
    anim := create_atlas_anim(.Player_Idle_Down)
    draw_atlas_anim_at_pos(anim, rl.GetMousePosition(), {}, atlas)
    
    rl.DrawTextEx(font, "My text", 220, 24, 1.0, rl.WHITE)
    rl.DrawRectangleRec({0, 0, 220, 130}, rl.BLACK)
	rl.GuiLabel({10, 10, 200, 20}, "raygui works!")

	if rl.GuiButton({10, 30, 200, 20}, "Print to log (see console)") {
        rl.PlaySound(sound_explosion)
		log.info("log.info works!")
		fmt.println("fmt.println too.")
	}

	if rl.GuiButton({10, 60, 200, 20}, "Source code (opens GitHub)") {
		rl.OpenURL("https://github.com/karl-zylinski/odin-raylib-web")
	}

	if rl.GuiButton({10, 90, 200, 20}, "Quit") {
		run = false
	}

	rl.EndDrawing()

	// Anything allocated using temp allocator is invalid after this.
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
