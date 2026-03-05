package game

import rl "vendor:raylib"
import "core:log"
import "core:c"
import la "core:math/linalg"

SPRITE_SCALE :: 4.0

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo
RenderTexture :: rl.RenderTexture2D

Player :: struct {
    render          : Render,
    kinematic_body  : KinematicBody,
    prev_dir        : [2]int,
    max_speed       : f32,
}

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

Context :: struct {
    collision_bodies        : [dynamic]CollisionBody,
    level_render            : RenderTexture,
    atlas                   : Texture,
    font                    : Font,
    player                  : Player,
    native_res              : [2]i32,
    native_to_screen_ratio  : i32,
}

run: bool
game_ctx : ^Context

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
    mv_dir : [2]int
    player := &game_ctx.player
    has_mv_event : bool
    for i in inputs {
        if is_input_down(i) {
            switch i.kind {
            case .Up, .Down, .Left, .Right :
                has_mv_event = true
                mv_dir += i.dir
            }
        }
    }

    if !has_mv_event {
        player.kinematic_body.vel.x = approach(player.kinematic_body.vel.x, 0.0, DRAG * dt)
        player.kinematic_body.vel.y = approach(player.kinematic_body.vel.y, 0.0, DRAG * dt)
    } else {
        target_vel := arr_cast(mv_dir, f32) * player.max_speed / f32(game_ctx.native_to_screen_ratio)
        vel_diff := target_vel - player.kinematic_body.vel
        player.kinematic_body.vel += vel_diff * (player.kinematic_body.acc * f32(game_ctx.native_to_screen_ratio)) * dt
        if player.prev_dir != mv_dir {
            player.kinematic_body.collision_body.box.rectangle.xy = la.round(player.kinematic_body.collision_body.box.rectangle.xy)
        }
        player.prev_dir = mv_dir
    }
}

physics_update :: proc (dt: f32) {
    move_kinematic_body(&game_ctx.player.kinematic_body, game_ctx.collision_bodies[:], dt)
}

in_screen_bounds :: proc (pos: [2]f32) -> bool {
    return pos.x >= 0 && pos.x < f32(rl.GetScreenWidth()) && pos.y >= 0 && pos.y < f32(rl.GetScreenHeight())
}

arr_cast :: proc(arr: [$N]$T, $S : typeid) -> [N]S  {
    out : [N]S
    for val, idx in arr {
        out[idx] = S(val)
    }
    return out
}

box_to_rect :: proc(box: Box) -> rl.Rectangle {
    return rl.Rectangle{ box.rectangle.x, box.rectangle.y, box.rectangle.z, box.rectangle.w }
}

init :: proc() {
	run = true
    screen_res := [2]i32{ 1920, 1080 }
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(screen_res.x, screen_res.y, "Odin + Raylib on the web")
    rl.SetTargetFPS(60)
    
    game_ctx = new(Context)
    game_ctx.native_res = [2]i32{ 480, 270 } 
    res_ratio := screen_res / game_ctx.native_res
    game_ctx.level_render = rl.LoadRenderTexture(game_ctx.native_res.x, game_ctx.native_res.y)
    game_ctx.native_to_screen_ratio = la.min(res_ratio.x, res_ratio.y)
    log.infof("Scaled ratio is : %v", game_ctx.native_to_screen_ratio)
    rl.SetTextureFilter(game_ctx.level_render.texture, .POINT)
    
    // Adding test level geometry
    append(&game_ctx.collision_bodies, CollisionBody{
        box = {
            rectangle = { 64, 32, 16, 16 },
            line_thickness = 1,
            color = rl.BLACK,
            state = .None}, 
        kind = .Static})
    append(&game_ctx.collision_bodies, CollisionBody{ 
        box = {
            rectangle ={ 64, 64, 16, 16 },
            line_thickness = 1,
            color = rl.BLACK,
            state = .None}, 
        kind = .Static})
    append(&game_ctx.collision_bodies, CollisionBody{ 
        box = {
            rectangle = { 64, 96, 16, 16 },
            line_thickness = 1,
            color = rl.BLACK,
            state = .None}, 
        kind = .Static})
    append(&game_ctx.collision_bodies, CollisionBody{ 
        box = {
            rectangle = { 64, 128, 16, 16 },
            line_thickness = 1,
            color = rl.BLACK,
            state = .None}, 
        kind = .Static})
    append(&game_ctx.collision_bodies, CollisionBody{ 
        box = {
            rectangle = { 96, 128, 16, 16 },
            line_thickness = 1,
            color = rl.BLACK,
            state = .None}, 
        kind = .Static})

    if atlas_data, atlas_ok := read_entire_file("assets/atlas.png"); atlas_ok {
        atlas_image := rl.LoadImageFromMemory(".png", raw_data(atlas_data), c.int(len(atlas_data)))
        game_ctx.atlas = rl.LoadTextureFromImage(atlas_image)
        rl.UnloadImage(atlas_image)
        game_ctx.font = load_atlased_font(game_ctx.atlas)

        // Init Player
        game_ctx.player.render.anim = create_atlas_anim(.Player_Idle_Down, true)
        game_ctx.player.kinematic_body = { 
            collision_body = { 
                box = { 
                    rectangle = {32, 32, 12, 12},
                    line_thickness = 1,
                    color = rl.BLACK,
                    state = .None }, 
                kind = .Slide, 
            }, 
            acc = 8.0,
        }
        game_ctx.player.max_speed = 4.0
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
    draw_frame(dt)
	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
//	rl.SetWindowSize(c.int(w), c.int(h))
//    screen_size := [2]i32{ rl.GetScreenWidth(), rl.GetScreenHeight() }
//    new_res := screen_size / game_ctx.native_res
//    game_ctx.native_to_screen_ratio = la.min(new_res.x, new_res.y)
}

shutdown :: proc() {
	rl.CloseWindow()
    rl.UnloadRenderTexture(game_ctx.level_render)
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
