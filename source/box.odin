package game

// Imports
import rl "vendor:raylib"
import "core:math"


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
    o_dim, new_dim := box.rectangle.zw, box.rectangle.zw
    o_dim *= o_dim
    o_hypot := math.sqrt(o_dim.x + o_dim.y)
    new_dim += amount
    if new_dim.x <= 0 || new_dim.y <= 0 {
        new_dim = 1
    }
    box.rectangle.zw = new_dim
    new_dim *= new_dim
    new_hypot := math.sqrt(new_dim.x + new_dim.y)
    diff_hypot := new_hypot - o_hypot
    box.rectangle.xy -= (diff_hypot/2)
}


