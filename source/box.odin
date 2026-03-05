package game

// Imports
import rl "vendor:raylib"
import "core:slice"

// Constants





// Globals



// Enums

Box_State :: enum u8 {
    None,

}

// Structs

Rectangle :: [4]f32 // x, y, h, w

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

rectangle_create :: proc(x, y, l: f32) -> (rect: Rectangle) {
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
    filter : [dynamic]Key_Value(int, Box); defer {delete(filter)}
    for i in 0..<len(arr) {
        if box_contains_position(rect, arr[i]) {
            pair := Key_Value(int, Box){i, arr[i]}
            append(&filter, pair)
        }
    }
    if len(filter) == 0 {
        return -1, false
    }
    if len(filter) == 1 {
        return filter[0].key, true
    }
    smallest := filter[0]
    for i in 1..<len(filter) {
        p_smallest := smallest.value.rectangle.z * smallest.value.rectangle.w
        current_area := filter[i].value.rectangle.z * filter[i].value.rectangle.w
        if current_area < p_smallest {
            smallest = filter[i]
        }
    }
    return smallest.key, true
}

boxes_all_containing_position :: proc(rect: Rectangle, arr: []Box) -> (boxes: []Box) {
    filter : [dynamic]Box; defer{delete(filter)}
    for i in 0..<len(arr) {
        if box_contains_position(rect, arr[i]) {
            append(&filter, arr[i])
        }
    }
    boxes = filter[:]
    return
}

box_state_determine :: proc(arr: []Box) -> (state: Box_State) {
    states : [dynamic]Box_State; defer{delete(states)}
    for i in arr {
        if !slice.contains(states[:], i.state) {
            append(&states, i.state)
        }
    }
    

    return
}
