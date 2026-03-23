package game

import sa "core:container/small_array"
import rl "vendor:raylib"
import la "core:math/linalg"
import "core:log"
import "core:math/rand"

PlayerState :: enum { Idle, Dash }
PlayerOptions :: enum { Damaged }

PlayerAnim :: enum { Idle, Run }
Player :: struct {
    render          : Render,
    after_images    : sa.Small_Array(4, ColorRender),
    kinematic_body  : KinematicBody,
    last_dir_input  : DirectionInput,
    render_color    : [4]f32,
    prev_dir        : [2]int,
    speed           : f32,
    box_states      : sa.Small_Array(BOX_STATE_SMALL_ARRAY_SIZE, Box_State),
    stomp           : Stomp,
    dash            : Dash,
    spawner         : AreaSpawner,
    state           : PlayerState,
    anim            : PlayerAnim,
    health          : f32,
    prev_health     : f32,
    max_health      : f32,
    options         : bit_set[PlayerOptions],
}

AreaSpawner :: struct {
    rect                : Rectangle,
    next_area           : Box,
    max_areas           : int,
    max_size            : int,
}

Stomp :: struct {
    meter       : MeterRender,
    hitbox      : HitBoxRender,
    force       : f32,
    stun        : f32,
    damage      : f32,
}

Dash :: struct {
    renders          : ChargeRenders,
    charges         : int,
    max_charges     : int,
    multiplier      : f32,
    recharge_time   : f32,
    speed           : f32,
}

player_anims := [PlayerAnim][DirectionInputKind]Animation_Name {
    .Idle = { .Up = .Player_Idle_Up, .Down = .Player_Idle_Down, .Left = .Player_Idle_Left, .Right = .Player_Idle_Right },
    .Run = { .Up = .Player_Run_Up, .Down = .Player_Run_Down, .Left = .Player_Idle_Left, .Right = .Player_Idle_Right },
}

init_player :: proc() {
    game_ctx.player = Player {
        render = { 
            anim = create_atlas_anim(.Player_Idle_Down, true),
            offset = { -11, -14 },
        },
        render_color = { 255.0, 255.0, 255.0, 255.0 },
        anim = .Idle,
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
            hitbox = { rect = { 0, 0, 48, 48 }, color = WHITE, alt_color = BLUE },
            meter = { 
                rects = { .Bg = {0, 0, 16, 1}, .Mid = {}, .Fg = { 0, 0, 16, 1 } },
                colors = { .Bg = rl.BLACK, .Mid = {}, .Fg = rl.WHITE },
            },
        },
        dash = {
            multiplier = 4.0,
            recharge_time = 1.5,
            max_charges = 3,
            charges = 3,
            renders = {
                ready = { anim = create_atlas_anim(.Dash_Charge_Enabled), offset = { -2, 16 } },
                inactive = { anim = create_atlas_anim(.Dash_Charge_Disabled), offset = { -2, 16 } },
            }
        },
        spawner = {
            max_areas = 4,
            rect = { 0, 0, 128, 128 },
            max_size = 6,
        },
        max_health = 10.0,
        health = 10.0,
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
            set_player_anim(player, .Run)
            //player.render.anim = create_atlas_anim(player.dir_anims[player.last_dir_input.kind])
            player.prev_dir = mv_dir
        }
    } else {
        change_player_anim(player, .Idle)
        player.kinematic_body.vel = 0
    }

    dash_available := player.dash.charges > 0
    stomp_available := !game_ctx.timers[.Player_Stomp].running

    if has_mv_event && dash_available && is_input_pressed(action_inputs[.Dash]) {
        player.state = .Dash
        player.dash.charges -= 1
        target_vel := arr_cast(mv_dir, f32) * player.speed * player.dash.multiplier
        player.kinematic_body.vel = target_vel
        create_player_after_image()
        start_timer(&game_ctx.timers[.After_Image])
        if !game_ctx.timers[.Player_Dash].running {
            start_timer(&game_ctx.timers[.Player_Dash], player.dash.recharge_time)
        }
    } else if is_input_pressed(action_inputs[.Left_Stomp]) {
        left_stomp(player)
    } else if  stomp_available &&  is_input_pressed(action_inputs[.Right_Stomp]) {
        right_stomp(player)
    }
}

left_stomp :: proc (player: ^Player) {
    shake_cam(SLAM_KICK_SHAKE)
    player_center := get_rect_center(player.kinematic_body.box.rectangle)
    stomp_center_offset := player.stomp.hitbox.rect.zw / 2
    player.stomp.hitbox.rect.xy = player_center - stomp_center_offset
    stomp_center := get_rect_center(player.stomp.hitbox.rect)
    player.stomp.hitbox.current_color = player.stomp.hitbox.alt_color

    // Eat Kickboxes for currency!
    free_kbs : sa.Small_Array(16, int)
    for &kb, idx in sa.slice(&game_ctx.collision_ctx.kick_boxes) {
        if rectangle_overlap(player.stomp.hitbox.rect, kb.box.rectangle) {
            consume_area(10)
            stop_timer(&kb.timer)
            sa.append(&free_kbs, idx)
        }
    }

    #reverse for i in sa.slice(&free_kbs) {
        sa.unordered_remove(&game_ctx.collision_ctx.kick_boxes, i)
    }

    new_size : [2]int
    free_areas : sa.Small_Array(16, int)
    for &area, idx in sa.slice(&game_ctx.collision_ctx.box_areas) {
        if rectangle_overlap(player.stomp.hitbox.rect, area.rectangle) {
            new_size = area.tile_size - { 1, 1 }
            shrink_box(game_ctx.collision_ctx, &area, new_size, player.kinematic_body.box.rectangle, idx)
            if new_size.x <= 1 && new_size.y <= 1 do sa.append(&free_areas, idx)
        }
    }

    #reverse for i in sa.slice(&free_areas) {
        sa.unordered_remove(&game_ctx.collision_ctx.box_areas, i)
    }

    for &lb, idx in sa.slice(&game_ctx.collision_ctx.loot_boxes) {
        stomp_loot(player, &lb, idx)
    }
}

right_stomp :: proc(player: ^Player) {
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

    // Stun kicked enemies
    for &enemy in game_ctx.enemies.active[:] {
        enemy.attack_timer += player.stomp.stun
    }

    start_timer(&game_ctx.timers[.Player_Stomp])
}

handle_player_dash :: proc(player: ^Player) {
    if is_input_down(action_inputs[.Left_Stomp]) {
        player.state = .Idle
        player.kinematic_body.vel = 0
        left_stomp(player)
    } else if is_input_down(action_inputs[.Right_Stomp]) {
        player.state = .Idle
        player.kinematic_body.vel = 0
        right_stomp(player)
        stop_timer(&game_ctx.timers[.Player_Stomp])
    } else if vec_comp_in_range(la.abs(player.kinematic_body.vel), DASH_FALL_OFF) {
        player.state = .Idle
    }
}

create_player_after_image :: proc() {
    after_image := ColorRender { render = game_ctx.player.render, fcolor = { 255.0, 255.0, 255.0, 255.0 } }
    sa.append(&game_ctx.player.after_images, after_image)
}

damage_player :: proc(player: ^Player, value : f32) {
    if .Damaged not_in player.options {
        player.prev_health = player.health
        player.health -= value
        player.options += { .Damaged }
        if player.health <= 0 { 
            log.debug("Player died!") 
            game_ctx.menu.show = true
            sa.clear(&game_ctx.menu.display_buttons)
            sa.append(&game_ctx.menu.display_buttons, PauseMenuButtonKind.Restart)
            game_ctx.input_mode = .Menu
        }
        shake_cam(32.0)
        start_timer(&game_ctx.timers[.Player_Damaged])
    }
}

spawn_random_area :: proc(spawner : ^AreaSpawner) {
    if game_ctx.active_areas < spawner.max_areas {
        new_dim := rand.int_range(2, spawner.max_size)
        spawner.rect.xy = game_ctx.player.kinematic_body.box.rectangle.xy
        new_x := int(rand.float32_range(spawner.rect.x, spawner.rect.x + spawner.rect.z)) % 16
        new_y := int(rand.float32_range(spawner.rect.y, spawner.rect.y + spawner.rect.w)) % 16

        spawner.next_area = box_create_tile_size(pos = { new_x, new_y }, tile_size = [2]int{ new_dim, new_dim }, thick = 1.0)
        sa.append(&game_ctx.collision_ctx.box_areas, spawner.next_area)
        update_active_areas(1)
    }
}

set_player_anim :: proc(player: ^Player, anim : PlayerAnim) {
    player.anim = anim
    player.render.anim = create_atlas_anim(player_anims[anim][player.last_dir_input.kind])
}

change_player_anim :: proc(player: ^Player, anim : PlayerAnim) {
    if player.anim != anim do set_player_anim(player, anim)
}
