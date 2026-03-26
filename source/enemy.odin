package game

import la "core:math/linalg"
import rl "vendor:raylib"
import sa "core:container/small_array"
import "core:math/rand"
import "core:log"

EnemyState :: enum { Chase, Dead }

EnemyKind :: enum { Chaser }

Enemy :: struct {
    kb              : KinematicBody,
    render          : Render,
    attack_box      : HitBoxRender,
    currency_value  : int,
    prev_x_dir      : f32,
    speed           : f32,
    health          : f32,
    damage          : f32,
    attack_range    : f32,
    attack_rate     : f32,
    attack_timer    : f32,
    drop_chance     : f32,
    state           : EnemyState,
    kind            : EnemyKind,
}

HitBoxRender :: struct {
    rect            : Rectangle,
    current_color   : [4]f32,
    color           : [4]f32,
    alt_color       : [4]f32,
}

EnemyData :: struct {
    active  : [dynamic]Enemy,
    dead    : [dynamic]int,
}

HealthPickUp :: struct {
    render  : Render,
    rect    : Rectangle,
    amount  : f32,
}

AnimDirectionKind :: enum { Right, Left }

AnimConfig :: struct {
    anims           : [AnimDirectionKind]Animation_Name,
    offset          : [2]f32,
}

enemy_anims := [EnemyKind]AnimConfig {
    .Chaser = { anims = { .Right = .Box_Cutter_Walk_Right, .Left = .Box_Cutter_Walk_Left }, offset = { -8, -8 } },
}

run_state_basic :: proc(enemy: ^Enemy) {
    switch enemy.state {
        case .Chase: move_attack_player(enemy)
        case .Dead : // No op
    }
}

move_attack_player :: proc(enemy : ^Enemy) {
    player_rect := game_ctx.player.kinematic_body.box.rectangle
    dir_to_player := la.normalize(player_rect.xy - enemy.kb.box.rectangle.xy)
    enemy_center := enemy.kb.box.rectangle.xy + (enemy.kb.box.rectangle.zw / 2.0)
    cfg := enemy_anims[enemy.kind]
    if la.distance(enemy_center, player_rect.xy) < enemy.attack_range {
        enemy.kb.vel = {}
        if enemy.attack_timer <= 0 {
            enemy.attack_timer = enemy.attack_rate
            enemy.attack_box.rect.xy = (player_rect.xy - (player_rect.zw / 2))
            enemy.attack_box.current_color = enemy.attack_box.color
            if rectangle_overlap(enemy.attack_box.rect, player_rect) {
                damage_player(&game_ctx.player, enemy.damage)
            }
        }
    } else {
        target_vel := arr_cast(dir_to_player, f32) * enemy.speed
        enemy.kb.vel = target_vel
    }

    // Gotta be a better way than this
    if dir_to_player.x > 0 && enemy.prev_x_dir < 0 {
        enemy.render.anim = create_atlas_anim(cfg.anims[.Right])
        enemy.prev_x_dir = dir_to_player.x
    } else if dir_to_player.x < 0 && enemy.prev_x_dir > 0 {
        enemy.render.anim = create_atlas_anim(cfg.anims[.Left])
        enemy.prev_x_dir = dir_to_player.x
    }
}

add_enemy_at_tile_pos :: proc(store : ^EnemyData, pos : [2]int, kind : EnemyKind = .Chaser) {
    raw_pos := arr_cast(pos * NATIVE_TILE_DIM, f32)
    enemy := new_enemy(pos = raw_pos, kind = kind)
    add_enemy_at_pos(store, enemy, raw_pos)
}

new_chaser :: proc(pos: [2]f32 = {}) -> Enemy {
    return new_enemy(pos, 2, 1, 1, 24, 2.0, 4.0, 0.1, {16, 16}, .Chaser)
}

new_enemy :: proc(
    pos                 : [2]f32 = {},
    currency_value      : int = 2,
    health              : f32 = 1.0,
    damage              : f32 = 1.0,
    range               : f32 = 24.0,
    rate                : f32 = 2.0,
    mv_speed            : f32 = 4.0,
    drop_chance         : f32 = 0.1,
    attack_box_size     : [2]f32 = { 16, 16 },
    kind                : EnemyKind = .Chaser,
) -> Enemy {
    return Enemy{
        kb = {
            box = {
                rectangle = { pos.x, pos.y, 16, 14 },
                colors = { .Primary = rl.PURPLE, .Secondary = rl.RED },
                color = rl.PURPLE,
                line_thickness = 1.0,
            },
        },
        attack_box = { rect = { 0, 0, attack_box_size.x, attack_box_size.y }, color = RED },
        render = { anim = create_atlas_anim(enemy_anims[kind].anims[.Right]), pos = pos, offset = enemy_anims[kind].offset },
        health = health,
        damage = damage,
        attack_range = range,
        attack_rate = rate,
        speed = mv_speed,
        drop_chance = drop_chance,
        kind = kind,
        prev_x_dir = 1.0,
    }
}

kill_enemy :: proc(idx: int, data : ^EnemyData) {
    shake_cam(KICK_SHAKE_INTENSITY)
    enemy := &game_ctx.enemies.active[idx]
    game_ctx.currency += enemy.currency_value

    roll := rand.float32_range(0.0, 1.0)
    if roll < enemy.drop_chance do drop_health_pick_up_pos(1.0 * f32(game_ctx.difficulty_lvl), enemy.kb.box.rectangle.xy)

    enemy^ = Enemy{ state = .Dead }
    append(&data.dead, idx)
    spawner := game_ctx.wave_spawner
    spawner.current_enemies -= 1

    if !game_ctx.timers[.Spawn_Wave].running && can_spawn(spawner) {
        start_timer(&game_ctx.timers[.Spawn_Wave])
    }
}

add_enemy_at_pos :: proc(data: ^EnemyData, enemy: Enemy, pos: [2]f32 = {}) {
    m_enemy := enemy
    m_enemy.kb.box.rectangle.xy = pos
    m_enemy.kb.prev_pos = pos
    m_enemy.render.pos = pos
    if len(data.dead) > 0 {
        data.active[pop(&data.dead)] = m_enemy
    } else {
        append(&data.active, m_enemy)
    }
}

damage_lethal :: proc(enemy: ^Enemy, dam : f32) -> bool {
    enemy.health -= dam
    return enemy.health <= 0
}

drop_health_pick_up_pos :: proc(val : f32, pos: [2]f32) {
    health_p := HealthPickUp {
        amount = val,
        render = { anim = create_atlas_anim(.Health_Pick_Up_Idle) },
        rect = { pos.x, pos.y, 6, 6 },
    }
    sa.append(&game_ctx.collision_ctx.health_pickups, health_p)
}

