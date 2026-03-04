package game
import la "core:math/linalg"

// Check for Collisions
MAX_ITERS :: 4
DRAG : f32 : 25.0

CollisionBodyKind :: enum { Static, Slide }

KinematicBody :: struct {
    collision_body  : CollisionBody,
    vel             : [2]f32,
    acc             : f32,
}

CollisionBody :: struct {
    box     : Box,
    kind    : CollisionBodyKind,
}

CollisionManager :: struct {
    static_bodies : [dynamic]CollisionBody,
}

has_collision_aabb :: proc(a, b : Box) -> bool {
    a_rect, b_rect := a.rectangle, b.rectangle
    return (
        a_rect.x < b_rect.x + b_rect.z &&
        a_rect.y < b_rect.y + b_rect.w &&
        b_rect.x < a_rect.x + a_rect.z &&
        b_rect.y < a_rect.w + a_rect.y
    )
}

get_collision_normal :: proc(a, b : Box) -> [2]f32 {
    a, b := a.rectangle, b.rectangle
    a_center := a.xy + (a.zw / 2)
    b_center := b.xy + (b.zw / 2)
    x_overlap := ((a.z / 2) + (b.z / 2)) - la.abs(a_center.x - b_center.x)
    y_overlap := ((a.w / 2) + (b.w / 2)) - la.abs(a_center.y - b_center.y)

    if x_overlap < y_overlap {
        if a_center.x < b_center.x {
            return { 1, 0 }
        } else {
            return { -1, 0 }
        }
    } else {
        if a_center.y < b_center.y {
            return { 0, 1 }
        } else {
            return { 0, -1 }
        }
    }
}

check_collision :: proc(move_box : Box, collision_bodies : []CollisionBody) -> (CollisionBody, bool) {
    for body in collision_bodies {
        if has_collision_aabb(move_box, body.box) {
            return body, true
        }
    }
    return {}, false
}

slide_move :: proc(kb: ^KinematicBody, collision_bodies : []CollisionBody, dt: f32) {
    kb.vel = la.lerp(kb.vel, [2]f32{}, DRAG * dt)
    new_box := kb.collision_body.box
    new_box.rectangle.xy = kb.collision_body.box.rectangle.xy + kb.vel
    c_body, has_collision := check_collision(new_box, collision_bodies)
    if has_collision {
        normal := get_collision_normal(new_box, c_body.box)
        slide_vel := kb.vel - normal * (la.vector_dot(kb.vel ,normal))
        kb.vel = slide_vel
        for _ in 0..<MAX_ITERS {
            new_box = kb.collision_body.box
            new_box.rectangle.xy = kb.collision_body.box.rectangle.xy + kb.vel
            c_body, has_collision = check_collision(new_box, game_ctx.collision_bodies[:])
            if has_collision {
                normal = get_collision_normal(new_box, c_body.box)
                slide_vel = kb.vel - normal * (la.vector_dot(kb.vel ,normal))
                kb.vel = slide_vel
            } else { break }
        }
        //kb.vel = la.lerp(kb.vel, [2]f32{}, DRAG * dt)
        kb.collision_body.box.rectangle.xy += kb.vel
    } else {
        kb.collision_body.box.rectangle.xy = new_box.rectangle.xy
    }
}

