package game

// Imports
import rl "vendor:raylib"


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


