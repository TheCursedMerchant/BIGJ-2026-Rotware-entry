package game

import rl "vendor:raylib"
import "core:log"
import "core:c"
import la "core:math/linalg"
import sa "core:container/small_array"
import "core:mem"

TARGET_FPS :: 30
FIXED_TIME_STEP :: 1.0 / f32(TARGET_FPS)
TARGET_RES :: [2]i32 { 768, 432 }
NATIVE_RES :: [2]i32{ 768, 432 }
NATIVE_TILE_DIM :: [2]int{ 16, 16 }
SCENE_LEVEL_DIM :: [2]int{ 25, 25 }
CAMERA_ZOOM_SPEED :: 2.5
DASH_MULTIPLIER :: 4.0
DASH_FALL_OFF :: [2]f32{ 1.0, 1.0 }
MAX_TIMERS :: 16
SLAM_KICK_SHAKE :: 13

// Alias's
Font :: rl.Font
Texture :: rl.Texture
Rect :: rl.Rectangle
GlyphInfo :: rl.GlyphInfo
RenderTexture :: rl.RenderTexture2D
Camera :: rl.Camera2D

Context :: struct {
    timers                  : [TimerTag]Timer,
    level_render            : RenderTexture,
    atlas                   : Texture,
    font                    : Font,
    player                  : Player,
    camera                  : FollowCamera,
    update_timer            : f32,
    res_scale_factor        : f32,
    enemies                 : ^EnemyData,
    level                   : ^Level,
    collision_ctx           : ^CollisionContext,
}

TimerTag :: enum { After_Image }
Timer :: struct {
    time_left   : f32,
    duration    : f32,
    running     : bool,
    callback    : proc(),
}

PlayerState :: enum { Idle, Dash }

Player :: struct {
    render          : Render,
    after_images    : sa.Small_Array(4, ColorRender),
    dir_anims       : [DirectionInputKind]Animation_Name,
    kinematic_body  : KinematicBody,
    last_dir_input  : DirectionInput,
    render_color    : [4]f32,
    prev_dir        : [2]int,
    speed           : f32,
    box_states      : sa.Small_Array(BOX_STATE_SMALL_ARRAY_SIZE, Box_State),
    state           : PlayerState,
    stomp           : Stomp,
}

Stomp :: struct {
    hitbox      : HitBoxRender,
    force       : f32,
    stun        : f32,
    damage      : f32,
}

Render :: struct {
    anim    : Animation,
    pos     : [2]f32,
    offset  : [2]f32,
}

ColorRender :: struct {
    render : Render,
    fcolor : [4]f32,
}

run: bool
game_ctx : ^Context
main_allocator : mem.Allocator
main_arena : mem.Arena
main_block : []u8

init :: proc() {
    run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(TARGET_RES.x, TARGET_RES.y, "Kick Boxing")
    rl.SetTargetFPS(120)

    make_p_arena_alloc(&main_allocator, &main_arena, &main_block, 5 * mem.Megabyte)

    init_game_ctx()
    update_tile_frames()

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


    log.debugf("Color render size : %v", size_of(ColorRender))
    log.debugf("Context size : %v", size_of(Context))
    log.debugf("Collision Context size : %v", size_of(CollisionContext))
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

    center_cell := SCENE_LEVEL_DIM.x / 2
    level_center := (arr_cast(NATIVE_TILE_DIM, f32) * f32(center_cell) * game_ctx.res_scale_factor) + (arr_cast(NATIVE_TILE_DIM, f32) / 2) 
    // Center camera onto the center tile pos
    game_ctx.camera = FollowCamera {
		offset = (screen_res / 2.0),
		target = level_center,
        origin_pos = level_center,
		zoom   = 1.0,
        zoom_speed = CAMERA_ZOOM_SPEED,
        target_zoom = 1.0,
        shake = { fall_off = FALL_OFF_THRESHHOLD }
	}
    game_ctx.collision_ctx = new(CollisionContext)
    game_ctx.enemies = new(EnemyData, main_allocator)
    game_ctx.enemies.active = make([dynamic]Enemy, 0, 32, main_allocator)
    game_ctx.enemies.dead = make([dynamic]int, 0, main_allocator)
    add_test_data(game_ctx.collision_ctx)
    game_ctx.timers[.After_Image] = { duration = 0.064 }
}

calc_box_rect :: proc(pos : [2]f32 = {}, size := [2]int{ 1, 1 }) -> Rectangle {
    dim := arr_cast(size * NATIVE_TILE_DIM.x, f32)
    return {pos.x, pos.y, dim.x, dim.y }
}

// NOTE: For testing only
add_test_data :: proc(ctx: ^CollisionContext) {
    f_tile_dim := arr_cast(NATIVE_TILE_DIM, f32)
    test_box := box_create_tile_size(pos = {8, 8}, tile_size = [2]int{4, 4},thick = 1.0)
    sa.append(&game_ctx.collision_ctx.box_areas, test_box)
    test_box = box_create_tile_size(pos = {6, 6}, tile_size = [2]int{4, 4},thick = 1.0)
    sa.append(&game_ctx.collision_ctx.box_areas, test_box)

    test_box = box_create_tile_size(pos = {12, 12}, tile_size = [2]int{3, 3},thick = 1.0)
    sa.append(&game_ctx.collision_ctx.box_areas, test_box)
    test_box = box_create_tile_size(pos = {4, 2}, tile_size = [2]int{2, 2},thick = 1.0)
    sa.append(&game_ctx.collision_ctx.box_areas, test_box)

   add_enemy(basic_enemy_at_pos({ 1, 1 }), game_ctx.enemies)
   add_enemy(basic_enemy_at_pos({ 1, 2 }), game_ctx.enemies)
   add_enemy(basic_enemy_at_pos({ 1, 3 }), game_ctx.enemies)
   add_enemy(basic_enemy_at_pos({ 1, 4 }), game_ctx.enemies)
   add_enemy(basic_enemy_at_pos({ 1, 5 }), game_ctx.enemies)
   add_enemy(basic_enemy_at_pos({ 1, 6 }), game_ctx.enemies)
   add_enemy(basic_enemy_at_pos({ 1, 7 }), game_ctx.enemies)
}

init_player :: proc() {
    game_ctx.player = Player {
        render = { 
            anim = create_atlas_anim(.Player_Idle_Down, true),
            offset = { -11, -14 },
        },
        render_color = { 255.0, 255.0, 255.0, 255.0 },
        dir_anims = { 
            .Up = .Player_Idle_Up,
            .Down = .Player_Idle_Down,
            .Left = .Player_Idle_Left,
            .Right = .Player_Idle_Right,
        },
        speed = 6.0,
        kinematic_body = {
            box = {
            rectangle = { game_ctx.level.player_start_pos.x, game_ctx.level.player_start_pos.y, 10, 10 },
                line_thickness = 1,
                color = rl.BLACK,
                state = .None,
            },
        },
        stomp = {
            damage = 1.0,
            force = 20.0,
            stun = 0.2,
            hitbox = { rect = { 0, 0, 48, 48 }, color = WHITE },
        }
    }
}

reset_level :: proc () {
    log.debug("Resetting game!")
    free_all(context.temp_allocator)
    free_all(main_allocator)
    init_player()
    game_ctx.collision_ctx^ = CollisionContext{}
    center_cell := SCENE_LEVEL_DIM.x / 2
    level_center := (arr_cast(NATIVE_TILE_DIM, f32) * f32(center_cell) * game_ctx.res_scale_factor) + (arr_cast(NATIVE_TILE_DIM, f32) / 2) 
    screen_res := arr_cast(TARGET_RES, f32)
    game_ctx.camera = FollowCamera {
		offset = (screen_res / 2.0),
		target = level_center,
        origin_pos = level_center,
		zoom   = 1.0,
        zoom_speed = CAMERA_ZOOM_SPEED,
        target_zoom = 1.0,
        shake = { fall_off = FALL_OFF_THRESHHOLD }
	}
    game_ctx.enemies = new(EnemyData, main_allocator)
    game_ctx.enemies.active = make([dynamic]Enemy, 0, 32, main_allocator)
    game_ctx.enemies.dead = make([dynamic]int, 0, main_allocator)
    add_test_data(game_ctx.collision_ctx)
}

update :: proc() {
    if rl.IsKeyPressed(.R) { reset_level() }
    dt := rl.GetFrameTime()
    game_ctx.update_timer += dt
    after_image_t := &game_ctx.timers[.After_Image] 
    if after_image_t.running {
        after_image_t.time_left -= dt
        if after_image_t.time_left <= 0 {
            after_image_t.running = false
            if game_ctx.player.state == .Dash {
                create_player_after_image()
                start_timer(after_image_t)
            }
        }
    }

    // TODO: Remove testing only
    if rl.IsKeyPressed(.N) {
        log.debug("Increasing zoom!")
        update_camera_zoom(1.0)
    } else if rl.IsKeyPressed(.M) {
        log.debug("Decreasing zoom!")
        update_camera_zoom(-1.0)
    }

    handle_player_input(FIXED_TIME_STEP)

    for game_ctx.update_timer >= FIXED_TIME_STEP {
        for &enemy in game_ctx.enemies.active {
            enemy.attack_timer -= FIXED_TIME_STEP
            run_state_basic(&enemy)
        }
        game_ctx.update_timer -= FIXED_TIME_STEP
        physics_update(FIXED_TIME_STEP)
    }

    interpolated_dt := game_ctx.update_timer / FIXED_TIME_STEP
    update_camera(interpolated_dt)
    draw_frame(interpolated_dt)
	free_all(context.temp_allocator)
}

handle_player_input :: proc(dt: f32) {
    player := &game_ctx.player
    switch player.state {
        case .Idle: handle_player_idle(player)
        case .Dash: handle_player_dash(player)
    }
}

handle_player_idle :: proc(player: ^Player) {
    mv_dir : [2]int
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

    if is_input_pressed(action_inputs[.Dash]) {
        player.state = .Dash
        target_vel := arr_cast(player.last_dir_input.dir, f32) * player.speed * DASH_MULTIPLIER
        player.kinematic_body.vel = target_vel
        create_player_after_image()
        start_timer(&game_ctx.timers[.After_Image])
    } else if is_input_pressed(action_inputs[.Stomp]) {
        stomp(player)
    }
}

stomp :: proc (player: ^Player) {
    shake_cam(SLAM_KICK_SHAKE)
    player_center := get_rect_center(player.kinematic_body.box.rectangle)
    stomp_center_offset := player.stomp.hitbox.rect.zw / 2
    player.stomp.hitbox.rect.xy = player_center - stomp_center_offset
    stomp_center := get_rect_center(player.stomp.hitbox.rect)
    player.stomp.hitbox.current_color = player.stomp.hitbox.color
    
    // Slam Boxes away
    kick_dir : [2]f32
    kb_center : [2]f32
    for &kb in sa.slice(&game_ctx.collision_ctx.kick_boxes) {
        if rectangle_overlap(player.stomp.hitbox.rect, kb.box.rectangle) {
            kb_center = get_rect_center(kb.box.rectangle)
            kick_dir = la.normalize(kb_center - stomp_center)
            kb.box.active_dam = player.stomp.damage
            kb.vel = kick_dir * player.stomp.force
            kb.box.state = .Active
            kb.box.color = kb.box.colors[.Secondary]
        }
    }
    
    for &area, idx in sa.slice(&game_ctx.collision_ctx.box_areas) {
        if rectangle_overlap(player.stomp.hitbox.rect, area.rectangle) {
            shrink_box(game_ctx.collision_ctx, &area, area.tile_size - { 1, 1 }, player.kinematic_body.box.rectangle, idx)
        }
    }

    // Stun kicked enemies
    for &enemy in game_ctx.enemies.active[:] {
        enemy.attack_timer += player.stomp.stun
    }
}

handle_player_dash :: proc(player: ^Player) {
    if is_input_down(action_inputs[.Stomp]) {
        player.state = .Idle
        player.kinematic_body.vel = 0
        stomp(player)
    } else if vec_comp_in_range(la.abs(player.kinematic_body.vel), DASH_FALL_OFF) {
        player.state = .Idle
    }
}

start_timer :: proc(timer: ^Timer) {
    timer.time_left = timer.duration
    timer.running = true
}

create_player_after_image :: proc() {
    after_image := ColorRender { render = game_ctx.player.render, fcolor = { 255.0, 255.0, 255.0, 255.0 } }
    sa.append(&game_ctx.player.after_images, after_image)
}

vec_comp_in_range :: proc(a, b : [2]$T) -> bool {
    return a.x < b.x && a.y < b.y
}

physics_update :: proc (dt: f32) {
    player := &game_ctx.player
    player.kinematic_body.prev_pos = player.kinematic_body.box.rectangle.xy
    player.kinematic_body.vel = la.lerp(player.kinematic_body.vel, [2]f32{}, 12.0 * dt)
    move_and_collide_kbs(&game_ctx.player.kinematic_body, game_ctx.collision_ctx, dt)
    sa.clear(&game_ctx.player.box_states)
    for &area in sa.slice(&game_ctx.collision_ctx.box_areas) {
        area.color = area.colors[.Primary]
        area.preview_rect = {}
        area.preview_color.rgb = area.colors[.Primary].rgb
        if rectangle_overlap(game_ctx.player.kinematic_body.box.rectangle, area.rectangle) {
            area.color = area.colors[.Secondary]
            append_box_state(area, &game_ctx.player.box_states)
            set_box_preview_rect(&area)
            if rectangle_overlap(game_ctx.player.kinematic_body.box.rectangle, area.preview_rect) {
                area.preview_color.rgb = area.colors[.Secondary].rgb
            }
        }
    }

    for &kb in sa.slice(&game_ctx.collision_ctx.kick_boxes) {
        kb.prev_pos = kb.box.rectangle.xy
        kb.vel = la.lerp(kb.vel, [2]f32{}, 12.0 * dt)
        if abs(kb.vel.x) < 0.05 && abs(kb.vel.y) < 0.05 { 
            kb.vel = {}
            kb.box.state = .None
            kb.box.color = kb.box.colors[.Primary]
        }
        switch kb.box.state {
            case .None : move_and_collide_kbs(&kb, game_ctx.collision_ctx, dt)
            case .Active : move_and_collide_kbs_enemies(&kb, game_ctx.collision_ctx, game_ctx.enemies.active[:], dt)
        }
    }

    for &enemy in game_ctx.enemies.active {
        if enemy.state == .Dead do continue
        enemy.kb.prev_pos = enemy.kb.box.rectangle.xy
        enemy.kb.vel = la.lerp(enemy.kb.vel, [2]f32{}, 12.0 * dt)
        if abs(enemy.kb.vel.x) < 0.05 && abs(enemy.kb.vel.y) < 0.05 do enemy.kb.vel = {}
        //if vec_comp_in_range(la.abs(enemy.kb.vel), [2]f32{ 0.05, 0.05 }) do enemy.kb.vel = {}
        move_and_collide_enemies(&enemy.kb, game_ctx.collision_ctx, game_ctx.enemies.active[:], dt)
    }
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

get_rect_center :: proc(rect: Rectangle) -> [2]f32 {
    return rect.xy + (rect.zw / 2)
}

make_p_arena_alloc :: proc(alloc: ^mem.Allocator, arena : ^mem.Arena, block : ^[]byte, size: uint) {
    arena_err : mem.Allocator_Error
    block^, arena_err = make([]byte, size)
    if arena_err != nil {
        log.errorf("Failed to init arena with err : %v", arena_err)
        assert(false)
    }
    mem.arena_init(arena, block^)
    alloc^ = mem.arena_allocator(arena)
}
