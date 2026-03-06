package game

import rl "vendor:raylib"
import "core:log"
import "core:c"
import la "core:math/linalg"

TARGET_FPS :: 30
FIXED_TIME_STEP :: 1.0 / f32(TARGET_FPS)

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo
RenderTexture :: rl.RenderTexture2D

Player :: struct {
    render          : Render,
    dir_anims       : [DirectionInputKind]Animation_Name,
    kinematic_body  : KinematicBody,
    last_dir_input  : DirectionInput,
    prev_dir        : [2]int,
    prev_pos        : [2]f32,
    max_speed       : f32,
}

Render :: struct {
    anim    : Animation,
    pos     : [2]f32,
    offset  : [2]f32,
}

Context :: struct {
    collision_bodies        : [dynamic]CollisionBody,
    level_render            : RenderTexture,
    atlas                   : Texture,
    font                    : Font,
    player                  : Player,
    native_res              : [2]i32,
    native_to_screen_ratio  : f32,
    unit_size               : f32,
    update_timer            : f32,
}

run: bool
game_ctx : ^Context

handle_player_input :: proc(dt: f32) {
    mv_dir : [2]int
    player := &game_ctx.player
    has_mv_event : bool
    for i in dir_inputs {
        if is_input_down(i) {
            switch i.kind {
            case .Up, .Down, .Left, .Right :
                has_mv_event = true
                mv_dir += i.dir
                player.last_dir_input = i
            }
        }
    }

    if has_mv_event {
        target_vel := arr_cast(mv_dir, f32) * player.max_speed
        vel_diff := target_vel - player.kinematic_body.vel
        player.kinematic_body.vel += vel_diff * player.kinematic_body.acc * dt
        // Smooths jitter when changing directions
        if player.prev_dir != mv_dir {
            // When we change direction change our animation
            player.render.anim = create_atlas_anim(player.dir_anims[player.last_dir_input.kind])
            player.kinematic_body.collision_body.box.rectangle.xy = la.round(player.kinematic_body.collision_body.box.rectangle.xy)
        }
        player.prev_dir = mv_dir
    } else {
        player.kinematic_body.vel.x = approach(player.kinematic_body.vel.x, 0.0, DRAG * dt)
        player.kinematic_body.vel.y = approach(player.kinematic_body.vel.y, 0.0, DRAG * dt)
    }
}

physics_update :: proc (dt: f32) {
    game_ctx.player.prev_pos = game_ctx.player.kinematic_body.collision_body.box.rectangle.xy
    move_kinematic_body(&game_ctx.player.kinematic_body, game_ctx.collision_bodies[:], dt)
}

init_game_ctx :: proc() {
    screen_res := [2]i32{ 768, 432 }
    game_ctx = new(Context)
    game_ctx.native_res = [2]i32{ 768, 432 } 
    res_ratio := screen_res / game_ctx.native_res
    game_ctx.level_render = rl.LoadRenderTexture(game_ctx.native_res.x, game_ctx.native_res.y)
    game_ctx.native_to_screen_ratio = la.min(f32(res_ratio.x), f32(res_ratio.y))
    game_ctx.unit_size = 1.0 / game_ctx.native_to_screen_ratio
    rl.SetTextureFilter(game_ctx.level_render.texture, .POINT)
    game_ctx.update_timer = FIXED_TIME_STEP
}

init_player :: proc() {
    game_ctx.player = Player {
        render = { anim = create_atlas_anim(.Player_Idle_Down, true) },
        dir_anims = { 
            .Up = .Player_Idle_Up,
            .Down = .Player_Idle_Down,
            .Left = .Player_Idle_Left,
            .Right = .Player_Idle_Right,
        },
        max_speed = 3.0,
        kinematic_body = { 
            collision_body = { 
                box = { 
                    rectangle = {32, 32, 12, 12},
                    line_thickness = 1,
                    color = rl.BLACK,
                    state = .None }, 
                kind = .Slide, 
            }, 
            acc = 12.0,
        },
    }
}

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(640, 360, "Odin + Raylib on the web")
    rl.SetTargetFPS(120)

    init_game_ctx()

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
        init_player()
        // Init Player
    }

	rl.InitAudioDevice()
    if rl.IsAudioDeviceReady() {
        log.info("Audio device is ready!")
        // TODO: Load Sounds Here
    }
}

update :: proc() {
    dt := rl.GetFrameTime()

    game_ctx.update_timer += dt 

    for game_ctx.update_timer >= FIXED_TIME_STEP {
        game_ctx.update_timer -= FIXED_TIME_STEP
        handle_player_input(FIXED_TIME_STEP)
        physics_update(FIXED_TIME_STEP)
    }

    interpolated_dt := game_ctx.update_timer / FIXED_TIME_STEP

    draw_frame(interpolated_dt)
	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
    rl.SetWindowSize(c.int(w), c.int(h))
    screen_size := [2]i32{ rl.GetScreenWidth(), rl.GetScreenHeight() }
    new_res := screen_size / game_ctx.native_res
    game_ctx.native_to_screen_ratio = la.min(f32(new_res.x), f32(new_res.y))
    game_ctx.unit_size = 1.0 / game_ctx.native_to_screen_ratio
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

// Utils
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
