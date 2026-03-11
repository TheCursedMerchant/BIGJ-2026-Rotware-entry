package game
import la "core:math/linalg"
import sa "core:container/small_array"

// Check for Collisions
MAX_ITERS :: 4
DRAG : f32 : 60.0

KinematicBody :: struct {
    box             : Box,
    remainder       : [2]f32,
    vel             : [2]f32,
}

MAX_STATIC_BODIES :: 32
MAX_BOX_BODIES :: 32

CollisionContext :: struct {
    static      : sa.Small_Array(MAX_STATIC_BODIES, Box),
    box_areas   : sa.Small_Array(MAX_BOX_BODIES, Box),
    kick_boxes  : sa.Small_Array(MAX_BOX_BODIES, KinematicBody),
}

move_x :: proc(kb: ^KinematicBody, solids : []Box) {
    kb.remainder.x += kb.vel.x
    move := la.floor(kb.remainder.x)

    if (move != 0) {
        kb.remainder.x -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.box.rectangle
        for move != 0 {
            test_rect.x += f32(sign)
            for solid in solids {
                if aabb_collision(test_rect, solid.rectangle) {
                    has_collision = true
                    break
                }
            }

            if has_collision {
                kb.vel.x = 0
                break
            } else {
                test_rect.x += f32(sign)
                move -= sign
                kb.box.rectangle = test_rect
            }
        }
    }
}


move_y :: proc(kb: ^KinematicBody, solids : []Box) {
    kb.remainder.y += kb.vel.y
    move := la.floor(kb.remainder.y)

    if (move != 0) {
        kb.remainder.y -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.box.rectangle
        for move != 0 {
            test_rect.y += f32(sign)
            for solid in solids {
                if aabb_collision(test_rect, solid.rectangle) {
                    has_collision = true
                    break
                }
            }

            if has_collision {
                kb.vel.y = 0
                break
            } else {
                test_rect.y += f32(sign)
                move -= sign
                kb.box.rectangle = test_rect
            }
        }
    }
}

move_kinematic_body :: proc(kb: ^KinematicBody, ctx : ^CollisionContext, dt : f32) {
    solids := sa.slice(&ctx.static)
    move_x(kb, solids)
    move_y(kb, solids)
}

collide_at :: proc(solids: []Box, pos : [2]f32) -> bool {
    return false
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
