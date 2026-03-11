package game

// Imports
import rl "vendor:raylib"
import "core:slice"
import sa "core:container/small_array"

// Constants

MINIMUM_SIZE : f32 : 1
MAXIMUM_SIZE : f32 : 100

KICK_HITBOX :: Rectangle{0,0,10,10}
KICK_VELOCITY : [2]f32 : {10, 10}

BOX_SMALL_ARRAY_SIZE :: 30
BOX_STATE_SMALL_ARRAY_SIZE :: 10

// Globals



// Enums

Box_State :: enum u8 {
    None,
    Man,
    Woman,
}

// Structs

Rectangle :: [4]f32 // x, y, w, h

Box :: struct {
    rectangle : Rectangle,
    line_thickness : f32,
    color : rl.Color,
    state : Box_State,
}

Key_Value :: struct($T: typeid, $E: typeid) {
    key : T,
    value : E,
}


// Procs

square_create :: proc(x, y, l: f32) -> (rect: Rectangle) {
    assert(x >= 0); assert(y >= 0); assert(l >= 0)
    return Rectangle{x, y, l, l}
}

rectangle_validity_check :: proc(rect: Rectangle) -> (bool) {
    if rect.x >= 0 && rect.y >= 0 && rect.z >= 0 && rect.w >= 0 {
        return true
    }
    return false
}

box_create :: proc(rect: Rectangle, thick: f32, color: rl.Color, state: Box_State) -> (box: Box) {
    assert(rectangle_validity_check(rect)); assert(thick >= 0)
    box.rectangle = rect
    box.line_thickness = thick
    box.color = color
    box.state = state
    return
}

box_resize :: proc(box: ^Box, amount: f32) {
    box.rectangle.zw += amount
    if box.rectangle.z < 0 || box.rectangle.w < 0 {
        box.rectangle.zw = 0
        return
    }
    box.rectangle.xy -= (amount/2)
}

box_draw :: proc(box: Box) {
    assert(rectangle_validity_check(box.rectangle)); assert(box.line_thickness >= 0)
    ray_rect := rl.Rectangle{box.rectangle.x, box.rectangle.y, box.rectangle.z, box.rectangle.w}
    rl.DrawRectangleLinesEx(ray_rect, box.line_thickness, box.color)
}

box_contains_position :: proc(rect: Rectangle, box: Box) -> (contains: bool) {
    assert(rect.x >= 0); assert(rect.y >= 0)
    assert(box.rectangle.x >= 0); assert(box.rectangle.y >= 0); assert(box.rectangle.z >= 0); assert(box.rectangle.w >= 0)
    rect_pos := rect.xy
    box_pos := box.rectangle.xy
    box_end_pos := box.rectangle.xy + box.rectangle.zw
    if rect_pos.x > box_pos.x && rect_pos.y > box_pos.y && rect.x < box_end_pos.x && rect.y < box_end_pos.y {
        contains = true
    }
    return
}

box_smallest_containing_position :: proc(rect: Rectangle, arr: []Box) -> (index: int, found: bool) {
    assert(len(arr) > 0); assert(rectangle_validity_check(rect))
    filter : sa.Small_Array(BOX_SMALL_ARRAY_SIZE, Key_Value(int, Box))
    for i in 0..<len(arr) {
        if box_contains_position(rect, arr[i]) {
            pair := Key_Value(int, Box){i, arr[i]}
            sa.push(&filter, pair)
        }
    }
    if sa.len(filter) == 0 {
        return -1, false
    }
    if sa.len(filter) == 1 {
        return sa.get(filter, 0).key, true
    }
    smallest := sa.get(filter, 0)
    for i in 1..<sa.len(filter) {
        p_smallest := smallest.value.rectangle.z * smallest.value.rectangle.w
        current_area := sa.get(filter, i).value.rectangle.z * sa.get(filter, i).value.rectangle.w
        if current_area < p_smallest {
            smallest = sa.get(filter, i)
        }
    }
    return smallest.key, true
}

boxes_all_containing_position :: proc(rect: Rectangle, arr: []Box, allocator := context.allocator) -> (boxes: []Box) {
    assert(len(arr) > 0); assert(rectangle_validity_check(rect))
    filter : sa.Small_Array(BOX_SMALL_ARRAY_SIZE, Box)
    for i in 0..<len(arr) {
        if box_contains_position(rect, arr[i]) {
            sa.push(&filter, arr[i])
        }
    }
    boxes = slice.clone(sa.slice(&filter), allocator)
    return
}

box_state_find :: proc(arr: []Box, allocator := context.allocator) -> (key_state: []Box_State) {
    states : sa.Small_Array(BOX_STATE_SMALL_ARRAY_SIZE, Box_State)
    for i in arr {
        if !slice.contains(sa.slice(&states), i.state) {
            sa.push(&states, i.state)
        }
    }
    key_state = slice.clone(sa.slice(&states), allocator)
    return
}

box_state_swap :: proc(position: Rectangle, arr: []Box) -> (ok: bool) {
    assert(position.x >= 0); assert(position.y >= 0); assert(len(arr) > 0)
    smallest_index := box_smallest_containing_position(position, arr) or_return; assert(smallest_index >= 0); assert(smallest_index < len(arr))
    outer_box_index := box_smallest_containing_position(arr[smallest_index].rectangle, arr) or_return; assert(outer_box_index >= 0); assert(outer_box_index < len(arr))
    small_box := &arr[smallest_index]
    outer_box := &arr[outer_box_index]
    small_box.state, outer_box.state = outer_box.state, small_box.state
    return true
}

box_kick_determine :: proc(arr: []CollisionBody, player: Player, allocator := context.allocator) -> (mobile, static: []CollisionBody) {
    assert(len(arr) > 0)
    boxes : []Box
    temp_mobile, temp_static : sa.Small_Array(BOX_SMALL_ARRAY_SIZE, CollisionBody)
    for cb in arr {
        sa.push(&temp_static, cb)
    }
    for i in 0..<len(arr){
        boxes[i] = arr[i].box
    }
    //filter := boxes_all_containing_position(rect = {player.prev_pos.x, player.prev_pos.y, 0,0}, arr = boxes[:])
    hitbox := KICK_HITBOX
    hitbox.xy = player.prev_pos.xy + ([2]f32{f32(player.prev_dir.x), f32(player.prev_dir.y)} * player.prev_pos)
    for i := 0; i < sa.len(temp_static); i += 1 {
        if rectangle_overlap(hitbox, sa.get(temp_static, i).box.rectangle) && !box_array_contains(filter[:], sa.get(temp_static, i).box) {
            sa.push(&temp_mobile, sa.get(temp_static, i))
            sa.unordered_remove(&temp_static, i)
            i -= 1
        }
    }
    mobile = slice.clone(sa.slice(&temp_mobile), allocator)
    static = slice.clone(sa.slice(&temp_static), allocator)
    return

    box_array_contains :: proc(arr: []Box, x: Box) -> (found: bool) {
        assert(len(arr) > 0); assert(rectangle_validity_check(x.rectangle))
        for box in arr {
            if box.rectangle == x.rectangle {
                return true
            }
        }
        return
    }
}

box_kick_assign_kb :: proc(targets: []CollisionBody, player: Player, allocator := context.allocator) -> (k_bodies: []KinematicBody) {
    assert(len(targets) > 0)
    temp : sa.Small_Array(BOX_SMALL_ARRAY_SIZE, KinematicBody)
    for i in 0..<len(targets) {
        vel := [2]f32{f32(player.prev_dir.x), f32(player.prev_dir.y)} * KICK_VELOCITY
        kb := KinematicBody{
            collision_body = targets[i],
            remainder = 0,
            vel = vel,
        }
        sa.push(&temp, kb)
    }
    k_bodies = slice.clone(sa.slice(&temp), allocator)
    return
}

rectangle_overlap :: proc(a, b: Rectangle) -> (overlap: bool) {
    assert(rectangle_validity_check(a)); assert(rectangle_validity_check(b))
    a_x1_smaller := a.x < b.x + b.z
    a_x2_larger := a.x + a.z > b.x
    a_y1_smaller := a.y < b.y + b.w
    a_y2_larger := a.y + a.w > b.y
    return a_x1_smaller && a_x2_larger && a_y1_smaller && a_y2_larger
}
