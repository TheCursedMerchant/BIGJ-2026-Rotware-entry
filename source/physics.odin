package game
import la "core:math/linalg"
import sa "core:container/small_array"
import "core:log"
import rl "vendor:raylib"

// Check for Collisions
MAX_ITERS :: 4
DRAG : f32 : 60.0
BOX_SPEED :: 10.0
KICK_SHAKE_INTENSITY :: 6.5

KinematicBody :: struct {
    box             : Box,
    remainder       : [2]f32,
    vel             : [2]f32,
    prev_pos        : [2]f32,
    timer           : Timer,
}

AxisVel :: struct {
    remainder   : f32,
    vel         : f32,
}

MAX_STATIC_BODIES :: 32
MAX_BOX_BODIES :: 32

CollisionContext :: struct {
    static      : sa.Small_Array(MAX_STATIC_BODIES, Box),
    box_areas   : sa.Small_Array(MAX_BOX_BODIES, Box),
    kick_boxes  : sa.Small_Array(MAX_BOX_BODIES, KinematicBody),
}

add_area_box :: proc(
    ctx : ^CollisionContext,
    pos: [2]int = {},
    tile_size : [2]int = {},
    thick: f32 = 1.0,
    colors: [BoxColor]rl.Color = { .Primary = rl.WHITE, .Secondary = rl.RED },
    state: Box_State = .None,
) {
    box := box_create_tile_size(pos, tile_size, thick, colors, state) 
    sa.append(&ctx.box_areas, box)
}

move_axis :: proc(
    kb          : ^KinematicBody,
    colliders   : ^sa.Small_Array(16, int),
    solids      : []Box,
    k_bodies    : []KinematicBody,
    axis_vec    : [2]f32,
) {
    axis_vel := axis_vec * kb.vel 
    axis_remainder := axis_vec * kb.remainder
    vel := get_axis(axis_vel)
    remainder := get_axis(axis_remainder)

    remainder += vel
    move := la.floor(remainder)

    if (move != 0) {
        remainder -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.box.rectangle
        for move != 0 {
            test_rect.xy += f32(sign) * axis_vec
            for solid in solids {
                if aabb_collision(test_rect, solid.rectangle) {
                    has_collision = true
                    break
                }
            }

            for &k, idx in k_bodies { 
                if aabb_collision(test_rect, k.box.rectangle) && (&k != kb) {
                    has_collision = true
                    sa.append(colliders, idx)
                    break
                }
            }

            if kb != &game_ctx.player.kinematic_body {
                has_collision ||= aabb_collision(test_rect, game_ctx.player.kinematic_body.box.rectangle)
            }

            if has_collision {
                kb.remainder = remainder * axis_vec
                kb.vel *= axis_vec.yx
                break
            } else {
                test_rect.xy += f32(sign) * axis_vec
                move -= sign
                kb.remainder = remainder * axis_vec
                kb.box.rectangle = test_rect
            }
        }
    }
}

enemy_move_axis :: proc(
    kb              : ^KinematicBody,
    kb_colliders    : ^sa.Small_Array(16, int),
    solids          : []Box,
    k_bodies        : []KinematicBody,
    enemies         : []Enemy,
    axis_vec        : [2]f32,
) {
    axis_vel := axis_vec * kb.vel 
    axis_remainder := axis_vec * kb.remainder
    vel := get_axis(axis_vel)
    remainder := get_axis(axis_remainder)

    remainder += vel
    move := la.floor(remainder)

    if (move != 0) {
        remainder -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.box.rectangle
        for move != 0 {
            test_rect.xy += f32(sign) * axis_vec
            for solid in solids {
                if aabb_collision(test_rect, solid.rectangle) {
                    has_collision = true
                    break
                }
            }

            for &k, idx in k_bodies { 
                if aabb_collision(test_rect, k.box.rectangle) && (&k != kb) {
                    has_collision = true
                    sa.append(kb_colliders, idx)
                    break
                }
            }

            has_collision ||= aabb_collision(test_rect, game_ctx.player.kinematic_body.box.rectangle)

            for &e, idx in enemies {
                if e.state == .Dead do continue
                if aabb_collision(test_rect, e.kb.box.rectangle) && (&e.kb != kb) {
                    has_collision = true
                    break
                }
            }

            if has_collision {
                kb.remainder = remainder * axis_vec
                kb.vel *= axis_vec.yx
                break
            } else {
                test_rect.xy += f32(sign) * axis_vec
                move -= sign
                kb.remainder = remainder * axis_vec
                kb.box.rectangle = test_rect
            }
        }
    }
}

move_axis_kbs_enemies :: proc(
    kb              : ^KinematicBody,
    kb_colliders    : ^sa.Small_Array(16, int),
    solids          : []Box,
    k_bodies        : []KinematicBody,
    enemies         : []Enemy,
    axis_vec        : [2]f32,
) {
    axis_vel := axis_vec * kb.vel 
    axis_remainder := axis_vec * kb.remainder
    vel := get_axis(axis_vel)
    remainder := get_axis(axis_remainder)

    remainder += vel
    move := la.floor(remainder)

    if (move != 0) {
        remainder -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.box.rectangle
        for move != 0 {
            test_rect.xy += f32(sign) * axis_vec
            for solid in solids {
                if aabb_collision(test_rect, solid.rectangle) {
                    has_collision = true
                    break
                }
            }

            for &k, idx in k_bodies { 
                if aabb_collision(test_rect, k.box.rectangle) && (&k != kb) {
                    has_collision = true
                    sa.append(kb_colliders, idx)
                    break
                }
            }

            has_collision ||= aabb_collision(test_rect, game_ctx.player.kinematic_body.box.rectangle)

            for &e, idx in enemies {
                if e.state != .Dead && (&e.kb != kb) {
                    if aabb_collision(test_rect, e.kb.box.rectangle) {
                        e.health -= kb.box.active_dam
                        if e.health <= 0 do kill_enemy(idx, game_ctx.enemies)
                        log.debugf("Enemy health after box : %v", e.health)
                    }
                }
            }

            if has_collision {
                kb.remainder = remainder * axis_vec
                kb.vel *= axis_vec.yx
                break
            } else {
                test_rect.xy += f32(sign) * axis_vec
                move -= sign
                kb.remainder = remainder * axis_vec
                kb.box.rectangle = test_rect
            }
        }
    }
}

// Returns non zero axis
get_axis :: proc(vec: [2]f32) -> f32 {
    if vec.x != 0 {
        return vec.x
    } else {
        return vec.y
    }
}

move_player :: proc(kb: ^KinematicBody, ctx : ^CollisionContext, dt : f32) {
    solids := sa.slice(&ctx.static)
    k_bodies := sa.slice(&ctx.kick_boxes)
    collider_idxs : sa.Small_Array(16, int)
    move_axis(kb, &collider_idxs, solids, k_bodies, { 1.0, 0.0 })
    move_axis(kb, &collider_idxs, solids, k_bodies, { 0.0, 1.0 })
}

move_enemy :: proc(kb: ^KinematicBody, ctx : ^CollisionContext, enemies : []Enemy, dt : f32) {
    solids := sa.slice(&ctx.static)
    k_bodies := sa.slice(&ctx.kick_boxes)
    collider_idxs : sa.Small_Array(16, int) 
    enemy_move_axis(kb, &collider_idxs, solids, k_bodies, enemies, { 1, 0 })
    enemy_move_axis(kb, &collider_idxs, solids, k_bodies, enemies, { 0, 1 })
}

move_kickbox :: proc(kb: ^KinematicBody, ctx : ^CollisionContext, dt : f32) {
    solids := sa.slice(&ctx.static)
    k_bodies := sa.slice(&ctx.kick_boxes)
    collider_idxs : sa.Small_Array(16, int)
    origin_vel := kb.vel
    move_axis(kb, &collider_idxs, solids, k_bodies, { 1.0, 0.0 })
    move_axis(kb, &collider_idxs, solids, k_bodies, { 0.0, 1.0 })
    target_vel : [2]f32
    for idx in sa.slice(&collider_idxs) {
        ctx.kick_boxes.data[idx].vel = origin_vel * 1.5
    }
}

move_active_kickbox :: proc(
    kb: ^KinematicBody, 
    ctx : ^CollisionContext,
    enemies : []Enemy, 
    dt : f32
) {
    solids := sa.slice(&ctx.static)
    k_bodies := sa.slice(&ctx.kick_boxes)
    collider_idxs : sa.Small_Array(16, int)
    origin_vel := kb.vel
    move_axis_kbs_enemies(kb, &collider_idxs, solids, k_bodies, enemies, { 1.0, 0.0 })
    move_axis_kbs_enemies(kb, &collider_idxs, solids, k_bodies, enemies, { 0.0, 1.0 })
    target_vel : [2]f32
    for idx in sa.slice(&collider_idxs) {
        ctx.kick_boxes.data[idx].vel = origin_vel * 1.5
    }
}

point_in_rect :: proc(point : [2]f32, rect: Rectangle) -> bool {
    return point.x <= (rect.x + rect.z) && point.x >= rect.x && point.y <= (rect.y + rect.z) && point.y >= rect.y
}

aabb_collision :: proc(a, b : Rectangle) -> bool {
    return ( a.x < (b.x + b.z) ) && ( (a.x + a.z) > b.x ) && ( a.y < (b.y + b.w) ) && ( (a.y + a.w) > b.y ) 
}

approach :: proc(current, target, increase : f32) -> f32 {
    if current < target {
        return min(current + increase, target)
    }
    return max(current - increase, target)
}

get_pos :: proc {
    get_pos_player,
    get_pos_kinematic_body,
    get_pos_collision_body,
}

get_pos_player :: proc(player: Player) -> [2]f32 {
    return get_pos_kinematic_body(player.kinematic_body)
}

get_pos_kinematic_body :: proc(kb: KinematicBody) -> [2]f32 {
    return get_pos_collision_body(kb.box)
}

get_pos_collision_body :: proc(c_body: Box) -> [2]f32 {
    return c_body.rectangle.xy
}
