package game

import rl "vendor:raylib"
import "core:log"
import "core:c"
import la "core:math/linalg"

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo

Player :: struct {
    render  : Render, 
    box     : Box,
    vel     : [2]f32,
    acc     : f32,
}

Box :: [4]f32

Render :: struct {
    anim    : Animation,
    pos     : [2]f32,
    offset  : [2]f32,
}

InputKind :: enum {
    Up,
    Down,
    Left,
    Right,
}

Input :: struct {
    key : rl.KeyboardKey,
    dir : [2]int,
    kind : InputKind,
}


run: bool
atlas: rl.Texture
font: Font
player : Player

inputs := [InputKind]Input {
    .Up = { .W, {0, -1}, .Up },
    .Down = { .S, {0, 1}, .Down },
    .Left = { .A, {-1, 0}, .Left },
    .Right = { .D, {1, 0}, .Right },
}

is_input_pressed :: proc(input : Input) -> bool {
    return rl.IsKeyPressed(input.key)
}

is_input_down :: proc(input : Input) -> bool {
    return rl.IsKeyDown(input.key)
}

handle_player_input :: proc(dt: f32) {
    mv_dir : [2]f32
    for i in inputs {
        if is_input_down(i) {
            switch i.kind {
            case .Up, .Down, .Left, .Right :
                mv_dir = arr_cast(i.dir, f32)
                player.vel += player.acc * dt * mv_dir
            }
        }
    }
}

// Check for Collisions
DRAG : f32 : 25.0
physics_update :: proc (dt: f32) {
    player.vel = la.lerp(player.vel, [2]f32{}, DRAG * dt) 
    player.box.xy += player.vel
}

arr_cast :: proc(arr: [$N]$T, $S : typeid) -> [N]S  {
    out : [N]S
    for val, idx in arr {
        out[idx] = S(val)
    }
    return out
}

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(640, 360, "Odin + Raylib on the web")
    rl.SetTargetFPS(60)

    if atlas_data, atlas_ok := read_entire_file("assets/atlas.png"); atlas_ok {
        atlas_image := rl.LoadImageFromMemory(".png", raw_data(atlas_data), c.int(len(atlas_data)))
        atlas = rl.LoadTextureFromImage(atlas_image)
        rl.UnloadImage(atlas_image)
        font = load_atlased_font(atlas)

        player.render.anim = create_atlas_anim(.Player_Idle_Down, true)
        player.box.xy = { 32, 32 }
        player.acc = 250.0
    }

	rl.InitAudioDevice()
    if rl.IsAudioDeviceReady() {
        log.info("Audio device is ready!")
        // TODO: Load Sounds Here
    }
}

update :: proc() {
    dt := rl.GetFrameTime()
    handle_player_input(dt)
    physics_update(dt)
	rl.BeginDrawing()
	    rl.ClearBackground({0, 120, 153, 255})
        rl.DrawRectangleLines(0, 0, rl.GetScreenWidth() + 1, rl.GetScreenHeight() + 1, rl.WHITE)
        update_atlas_anim(&player.render.anim, dt)
        draw_atlas_anim_at_pos(player.render.anim, player.box.xy, {}, atlas) 
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
		anim_texture.rect.width * 4,
		anim_texture.rect.height * 4,
	}
	rl.DrawTexturePro(atlas, atlas_rect, dest, {}, 0, rl.WHITE)
}
