package game

import rl "vendor:raylib"
import "core:log"
import "core:c"
import la "core:math/linalg"

TARGET_FPS :: 30
FIXED_TIME_STEP :: 1.0 / f32(TARGET_FPS)
TARGET_RES :: [2]i32 { 768, 432 }
NATIVE_RES :: [2]i32{ 768, 432 }
NATIVE_TILE_DIM :: [2]int{ 16, 16 }
SCENE_LEVEL_DIM :: [2]int{ 25, 25 }
CAMERA_ZOOM_SPEED :: 16.0

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo
RenderTexture :: rl.RenderTexture2D
Camera :: rl.Camera2D

Context :: struct {
    collision_bodies        : [dynamic]CollisionBody,
    level_render            : RenderTexture,
    atlas                   : Texture,
    font                    : Font,
    player                  : Player,
    camera                  : FollowCamera,
    update_timer            : f32,
    res_scale_factor        : f32,
    level                   : ^Level,
}

Player :: struct {
    render          : Render,
    dir_anims       : [DirectionInputKind]Animation_Name,
    kinematic_body  : KinematicBody,
    last_dir_input  : DirectionInput,
    prev_dir        : [2]int,
    prev_pos        : [2]f32,
    speed           : f32,
}

Render :: struct {
    anim    : Animation,
    pos     : [2]f32,
    offset  : [2]f32,
}

run: bool
game_ctx : ^Context

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(TARGET_RES.x, TARGET_RES.y, "Kick Boxing")
    rl.SetTargetFPS(120)

    init_game_ctx()

    if atlas_data, atlas_ok := read_entire_file("assets/atlas.png"); atlas_ok {
        atlas_image := rl.LoadImageFromMemory(".png", raw_data(atlas_data), c.int(len(atlas_data)))
        game_ctx.atlas = rl.LoadTextureFromImage(atlas_image)
        rl.UnloadImage(atlas_image)
        game_ctx.font = load_atlased_font(game_ctx.atlas)
        init_player()
    }

	rl.InitAudioDevice()
    if rl.IsAudioDeviceReady() {
        log.info("Audio device is ready!")
        // TODO: Load Sounds Here
    }
}

init_game_ctx :: proc() {
    screen_res := arr_cast(TARGET_RES, f32)
    game_ctx = new(Context)
    game_ctx.level_render = rl.LoadRenderTexture(NATIVE_RES.x, NATIVE_RES.y)
    scale_vec := screen_res / arr_cast(NATIVE_RES, f32)
    game_ctx.res_scale_factor = la.min(scale_vec.x, scale_vec.y)
    rl.SetTextureFilter(game_ctx.level_render.texture, .POINT)
    game_ctx.update_timer = FIXED_TIME_STEP
    game_ctx.level = new(Level)
    new_level : SceneSave
    load_level_data(&new_level, .Test)
    game_ctx.level^ = build_level_from_save(&new_level) 

    log.debugf("Scale factor : %v", game_ctx.res_scale_factor)
    center_cell := SCENE_LEVEL_DIM.x / 2
    level_center := (arr_cast(NATIVE_TILE_DIM, f32) * f32(center_cell) * game_ctx.res_scale_factor) + (arr_cast(NATIVE_TILE_DIM, f32) / 2) 
    log.debugf("Texture center : %v", level_center)
    // Center camera onto the center tile pos
    game_ctx.camera = FollowCamera {
		offset = (screen_res / 2.0),
		target = level_center,
		zoom   = 1.0,
        zoom_speed = CAMERA_ZOOM_SPEED,
        target_zoom = 1.0,
	}
    log.debugf("Camera target : %v", game_ctx.camera.target)
}

init_player :: proc() {
    game_ctx.player = Player {
        render = { 
            anim = create_atlas_anim(.Player_Idle_Down, true),
            offset = { -10, -12 },
        },
        dir_anims = { 
            .Up = .Player_Idle_Up,
            .Down = .Player_Idle_Down,
            .Left = .Player_Idle_Left,
            .Right = .Player_Idle_Right,
        },
        speed = 2.0,
        kinematic_body = {
            collision_body = {
                box = {
                    rectangle = {game_ctx.level.player_start_pos.x, game_ctx.level.player_start_pos.y, 12, 12},
                    line_thickness = 1,
                    color = rl.BLACK,
                    state = .None },
                kind = .Slide,
            },
        },
    }
}

update :: proc() {
    dt := rl.GetFrameTime()
    game_ctx.update_timer += dt

    // TODO: Remove testing only
    if rl.IsKeyPressed(.N) {
        update_camera_zoom(1.0)
    } else if rl.IsKeyPressed(.M) {
        update_camera_zoom(-1.0)
    }

    handle_player_input(FIXED_TIME_STEP)

    for game_ctx.update_timer >= FIXED_TIME_STEP {
        game_ctx.update_timer -= FIXED_TIME_STEP
        physics_update(FIXED_TIME_STEP)
    }

    interpolated_dt := game_ctx.update_timer / FIXED_TIME_STEP

    update_camera(dt)
    draw_frame(interpolated_dt)
	free_all(context.temp_allocator)
}

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
        target_vel := arr_cast(mv_dir, f32) * player.speed
        player.kinematic_body.vel = target_vel
        if player.prev_dir != mv_dir {
            player.render.anim = create_atlas_anim(player.dir_anims[player.last_dir_input.kind])
            player.prev_dir = mv_dir
        }
    } else {
        player.kinematic_body.vel = 0
    }
}

physics_update :: proc (dt: f32) {
    game_ctx.player.prev_pos = game_ctx.player.kinematic_body.collision_body.box.rectangle.xy
    move_kinematic_body(&game_ctx.player.kinematic_body, game_ctx.collision_bodies[:], dt)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
    log.debugf("Set window size called..")
    rl.SetWindowSize(c.int(w), c.int(h))
    screen_res := arr_cast(TARGET_RES, f32)
    scale_vec := screen_res / arr_cast(NATIVE_RES, f32)
    game_ctx.res_scale_factor = la.min(scale_vec.x, scale_vec.y)
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
