package game

import rl "vendor:raylib"
import "core:log"
import "core:c"
import la "core:math/linalg"
import "core:math/rand"
import sa "core:container/small_array"
import "core:mem"

TARGET_FPS :: 144
TIME_STEP_FPS :: 30
FIXED_TIME_STEP :: 1.0 / f32(TIME_STEP_FPS)
TARGET_RES :: [2]i32 { 768, 432 }
NATIVE_RES :: [2]i32{ 768, 432 }
NATIVE_TILE_DIM :: [2]int{ 16, 16 }
SCENE_LEVEL_DIM :: [2]int{ 25, 25 }
CAMERA_ZOOM_SPEED :: 2.5
DASH_MULTIPLIER :: 4.0
DASH_FALL_OFF :: [2]f32{ 5.0, 5.0 }
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
    pattern_master          : ^HitboxPatternMaster,
    enemies                 : ^EnemyData,
    level                   : ^Level,
    collision_ctx           : ^CollisionContext,
    active_kbs              : int,
}

TimerTag :: enum { After_Image, Player_Dash, Player_Stomp, Spawn_Pattern, Spawn_Area }
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
    dash_speed      : f32,
    box_states      : sa.Small_Array(BOX_STATE_SMALL_ARRAY_SIZE, Box_State),
    state           : PlayerState,
    stomp           : Stomp,
    spawner         : AreaSpawner,
    health          : f32,
}

AreaSpawner :: struct {
    rect                : Rectangle,
    next_area           : Box,
    max_areas           : int,
    max_size            : int,
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
	rl.SetConfigFlags({.WINDOW_RESIZABLE })
	rl.InitWindow(TARGET_RES.x, TARGET_RES.y, "Kick Boxing")
    rl.SetTargetFPS(TARGET_FPS)
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
    game_ctx.pattern_master = new(HitboxPatternMaster, main_allocator)
    game_ctx.timers[.After_Image] = { duration = 0.064 }
    game_ctx.timers[.Player_Dash] = { duration = 1.0 }
    game_ctx.timers[.Player_Stomp] = { duration = 1.0 }
    game_ctx.timers[.Spawn_Pattern] = { duration = 5.0 }
    game_ctx.timers[.Spawn_Area] = { duration = 2.0 }
    add_test_data(game_ctx.collision_ctx, game_ctx.pattern_master)
}

calc_box_rect :: proc(pos : [2]f32 = {}, size := [2]int{ 1, 1 }) -> Rectangle {
    dim := arr_cast(size * NATIVE_TILE_DIM.x, f32)
    return {pos.x, pos.y, dim.x, dim.y }
}

spawn_random_area :: proc(spawner : ^AreaSpawner) {
    if game_ctx.active_kbs < spawner.max_areas {
        new_dim := rand.int_range(2, spawner.max_size)
        spawner.rect.xy = game_ctx.player.kinematic_body.box.rectangle.xy
        new_x := int(rand.float32_range(spawner.rect.x, spawner.rect.x + spawner.rect.z)) % 16
        new_y := int(rand.float32_range(spawner.rect.y, spawner.rect.y + spawner.rect.w)) % 16

        spawner.next_area = box_create_tile_size(pos = { new_x, new_y }, tile_size = [2]int{ new_dim, new_dim }, thick = 1.0)
        sa.append(&game_ctx.collision_ctx.box_areas, spawner.next_area)
        update_active_kbs(1)
    }
}

// NOTE: For testing only
add_test_data :: proc(ctx: ^CollisionContext, pm : ^HitboxPatternMaster) {
//    f_tile_dim := arr_cast(NATIVE_TILE_DIM, f32)
//      test_box := box_create_tile_size(pos = {16, 16}, tile_size = [2]int{4, 4},thick = 1.0)
//      sa.append(&game_ctx.collision_ctx.box_areas, test_box)
//    test_box = box_create_tile_size(pos = {6, 6}, tile_size = [2]int{4, 4},thick = 1.0)
//    sa.append(&game_ctx.collision_ctx.box_areas, test_box)
//
//    test_box = box_create_tile_size(pos = {12, 12}, tile_size = [2]int{3, 3},thick = 1.0)
//    sa.append(&game_ctx.collision_ctx.box_areas, test_box)
//    test_box = box_create_tile_size(pos = {4, 2}, tile_size = [2]int{2, 2},thick = 1.0)
//    sa.append(&game_ctx.collision_ctx.box_areas, test_box)

    add_enemy(basic_enemy_at_pos({ 1, 1 }), game_ctx.enemies)
    add_enemy(basic_enemy_at_pos({ 1, 2 }), game_ctx.enemies)
    add_enemy(basic_enemy_at_pos({ 1, 3 }), game_ctx.enemies)
    add_enemy(basic_enemy_at_pos({ 1, 4 }), game_ctx.enemies)
    add_enemy(basic_enemy_at_pos({ 1, 5 }), game_ctx.enemies)
    add_enemy(basic_enemy_at_pos({ 1, 6 }), game_ctx.enemies)
    add_enemy(basic_enemy_at_pos({ 1, 7 }), game_ctx.enemies)

    single_hitbox := hitbox_pattern_single(render = { rect = {0, 0, 128, 128}, color = RED, current_color = RED }, duration = 1.0)
    sa.append(&pm.patterns, single_hitbox)

    start_timer(&game_ctx.timers[.Spawn_Pattern])
    start_timer(&game_ctx.timers[.Spawn_Area])
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
        },
        spawner = {
            max_areas = 4,
            rect = { 0, 0, 128, 128 },
            max_size = 6,
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
    game_ctx.pattern_master = new(HitboxPatternMaster)
    add_test_data(game_ctx.collision_ctx, game_ctx.pattern_master)
}

update :: proc() {
    if rl.IsKeyPressed(.R) { reset_level() }
    dt := rl.GetFrameTime()
    game_ctx.update_timer += dt
    
    update_global_timers(dt)
    for &pattern in sa.slice(&game_ctx.pattern_master.patterns) {
        update_hitbox_pattern_timers(&pattern, dt)
    }

    update_kickbox_timers(game_ctx.collision_ctx, &game_ctx.player, dt)

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

update_global_timers :: proc(dt: f32) {
    complete_timers : sa.Small_Array(16, TimerTag)
    for &timer, idx in game_ctx.timers { 
        if update_timer(&timer, dt) do sa.append(&complete_timers, TimerTag(idx))
    }

    for tag in sa.slice(&complete_timers) {
        switch tag {
            case .After_Image:
                if game_ctx.player.state == .Dash {
                    create_player_after_image()
                    start_timer(&game_ctx.timers[.After_Image])
                }
            case .Spawn_Pattern:
                new_pos : [2]f32
                for pattern in sa.slice(&game_ctx.pattern_master.patterns) {
                    new_pos.x = rand.float32_range(0.0, f32(SCENE_LEVEL_DIM.x * NATIVE_TILE_DIM.x))
                    new_pos.y = rand.float32_range(0.0, f32(SCENE_LEVEL_DIM.y * NATIVE_TILE_DIM.y))
                    log.debugf("Spawining pattern at pos : %v", new_pos)
                    spawn_hitbox_pattern_at_pos(&game_ctx.pattern_master.patterns.data[0], new_pos)
                }
            case .Spawn_Area:
                spawner := &game_ctx.player.spawner
                spawn_random_area(spawner)
            case .Player_Dash: // Noop
            case .Player_Stomp: // Noop
        }
    }
}

update_kickbox_timers :: proc(ctx: ^CollisionContext, player: ^Player, dt : f32) {
    free_kbs : sa.Small_Array(MAX_BOX_BODIES, int)
    for &kb, idx in sa.slice(&ctx.kick_boxes) {
        if update_timer(&kb.timer, dt) {
            //TODO : Blowup
            sa.append(&free_kbs, idx)
            update_active_kbs(-1)
        }
    }

    for i in sa.slice(&free_kbs) {
        sa.unordered_remove(&game_ctx.collision_ctx.kick_boxes, i)
    }
}

update_active_kbs :: proc(delta : int) {
    game_ctx.active_kbs += delta
    max_areas := game_ctx.player.spawner.max_areas
    if !game_ctx.timers[.Spawn_Area].running && game_ctx.active_kbs < max_areas {
        start_timer(&game_ctx.timers[.Spawn_Area])
    }
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

    dash_available := !game_ctx.timers[.Player_Dash].running
    stomp_available := !game_ctx.timers[.Player_Stomp].running

    if has_mv_event && dash_available && is_input_pressed(action_inputs[.Dash]) {
        player.state = .Dash
        target_vel := arr_cast(mv_dir, f32) * player.speed * DASH_MULTIPLIER
        player.kinematic_body.vel = target_vel
        create_player_after_image()
        start_timer(&game_ctx.timers[.After_Image])
        start_timer(&game_ctx.timers[.Player_Dash])
    } else if stomp_available && is_input_pressed(action_inputs[.Stomp]) {
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
            start_timer(&kb.timer)
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

    start_timer(&game_ctx.timers[.Player_Stomp])
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

update_timer :: proc(timer: ^Timer, dt: f32) -> (complete: bool) {
    if !timer.running do return false
    timer.time_left -= dt
    if timer.time_left <= 0 {
        timer.running = false
        return true
    }
    return false
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
    move_player(&game_ctx.player.kinematic_body, game_ctx.collision_ctx, dt)
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
            case .None : move_kickbox(&kb, game_ctx.collision_ctx, dt)
            case .Active : move_active_kickbox(&kb, game_ctx.collision_ctx, game_ctx.enemies.active[:], dt)
        }
    }

    for &enemy in game_ctx.enemies.active {
        if enemy.state == .Dead do continue
        enemy.kb.prev_pos = enemy.kb.box.rectangle.xy
        enemy.kb.vel = la.lerp(enemy.kb.vel, [2]f32{}, 12.0 * dt)
        if abs(enemy.kb.vel.x) < 0.05 && abs(enemy.kb.vel.y) < 0.05 do enemy.kb.vel = {}
        //if vec_comp_in_range(la.abs(enemy.kb.vel), [2]f32{ 0.05, 0.05 }) do enemy.kb.vel = {}
        move_enemy(&enemy.kb, game_ctx.collision_ctx, game_ctx.enemies.active[:], dt)
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
