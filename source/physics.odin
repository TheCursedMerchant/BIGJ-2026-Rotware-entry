package game
import la "core:math/linalg"
import "core:log"

// Check for Collisions
MAX_ITERS :: 4
DRAG : f32 : 25.0

CollisionBodyKind :: enum { Static, Slide }

KinematicBody :: struct {
    collision_body  : CollisionBody,
    vel             : [2]f32,
    acc             : f32,
    remainder       : [2]f32,
}

CollisionBody :: struct {
    box     : Box,
    kind    : CollisionBodyKind,
}

move_x :: proc(kb: ^KinematicBody, solids : []CollisionBody) {
    kb.remainder.x += kb.vel.x
    move := la.round(kb.remainder.x)

    if (move != 0) {
        kb.remainder.x -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.collision_body.box.rectangle
        for move != 0 {
            test_rect.x += f32(sign)
            for solid in solids {
                if aabb_collision(test_rect, solid.box.rectangle) {
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
                kb.collision_body.box.rectangle = test_rect
            }
        }
    }
}


move_y :: proc(kb: ^KinematicBody, solids : []CollisionBody) {
    kb.remainder.y += kb.vel.y
    move := la.round(kb.remainder.y)

    if (move != 0) {
        kb.remainder.y -= f32(move)
        sign := la.sign(move)
        has_collision : bool
        test_rect := kb.collision_body.box.rectangle
        for move != 0 {
            test_rect.y += f32(sign)
            for solid in solids {
                if aabb_collision(test_rect, solid.box.rectangle) {
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
                kb.collision_body.box.rectangle = test_rect
            }
        }
    }
}

move_kinematic_body :: proc(kb: ^KinematicBody, solids : []CollisionBody, dt : f32) {
    kb.vel = la.lerp(kb.vel, [2]f32{}, DRAG * dt)
    move_x(kb, solids)
    move_y(kb, solids)
}

collide_at :: proc(solids: []CollisionBody, pos : [2]f32) -> bool {
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

