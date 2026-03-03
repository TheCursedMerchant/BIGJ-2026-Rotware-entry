package game
import la "core:math/linalg"

CollisionBodyKind :: enum { Static, Slide }

CollisionBody :: struct {
    box     : Box,
    kind    : CollisionBodyKind,
}

CollisionManager :: struct {
    static_bodies : [dynamic]CollisionBody,
}

has_collision_aabb :: proc(a, b : Box) -> bool {
    return (
        a.x < b.x + b.z &&
        a.y < b.y + b.w &&
        b.x < a.x + a.z &&
        b.y < a.w + a.y
    )
}

get_collision_normal :: proc(a, b : Box) -> [2]f32 {
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
