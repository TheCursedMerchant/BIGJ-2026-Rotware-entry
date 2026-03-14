package game

import la "core:math/linalg"
import rl "vendor:raylib"
import "core:log"

EnemyState :: enum { Chase, Dead }

Enemy :: struct {
    kb              : KinematicBody,
    hit_rect        : Rectangle,
    render          : Render,
    speed           : f32,
    health          : f32,
    damage          : f32,
    attack_range    : f32,
    attack_rate     : f32,
    attack_timer    : f32,
    state           : EnemyState,
}

EnemyData :: struct {
    active  : [dynamic]Enemy,
    dead    : [dynamic]int,
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
    if la.distance(enemy_center, player_rect.xy) < enemy.attack_range {
        enemy.kb.vel = {}
        if enemy.attack_timer <= 0 {
            enemy.attack_timer = enemy.attack_rate
            enemy.hit_rect.xy = enemy_center + (dir_to_player * enemy.attack_range)
            if aabb_collision(enemy.hit_rect, player_rect) {
                log.debugf("Damage dealt!", enemy.damage)
            }
        }
    } else {
        target_vel := arr_cast(dir_to_player, f32) * enemy.speed
        enemy.kb.vel = target_vel
    }
}

basic_enemy_at_pos :: proc(pos : [2]int) -> Enemy {
    raw_pos := arr_cast(pos * NATIVE_TILE_DIM, f32)
    return Enemy{
        kb = {
            box = {
                rectangle = { raw_pos.x, raw_pos.y, 16, 16 },
                colors = { .Primary = rl.PURPLE, .Secondary = rl.RED },
                color = rl.PURPLE,
                line_thickness = 1.0,
            },
        },
        hit_rect = { 0, 0, 16, 16 },
        render = { anim = create_atlas_anim(.Player_Idle_Down), pos = raw_pos },
        health = 1.0,
        damage = 1.0,
        attack_range = 32.0,
        attack_rate = 0.5,
        speed = 4.0,
    }
}

kill_enemy :: proc(idx: int, data : ^EnemyData) {
    shake_cam(KICK_SHAKE_INTENSITY)
    enemy := &game_ctx.enemies.active[idx]
    enemy^ = { state = .Dead }
    append(&data.dead, idx)
}

add_enemy :: proc(enemy: Enemy, data: ^EnemyData) {
    if len(data.dead) > 0 {
        next_idx := pop(&data.dead)
        data.active[next_idx] = enemy
    } else {
        append(&data.active, enemy)
    }
}
