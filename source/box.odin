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
Entity_Id :: distinct int

Id_Generator :: Entity_Id

Box :: struct {
    id : Entity_Id,
    rectangle : Rectangle,  // 16 bytes
    line_thickness : f32,   // 4 bytes
    color : rl.Color,       // 4 bytes
    state : Box_State       // 1 byte
}


// Procs

entity_id_get :: proc(id_gen: ^Id_Generator) -> (id: Entity) {
    id = id_gen
    id_gen += 1
    return
}

rectangle_create :: proc(x, y, l: f32) -> (rect: Rectangle) {
    assert(x >= 0); assert(y >= 0); assert(l >= 0)
    return Rectangle{x, y, l, l}
}

rectangle_validity_check :: proc(rect: Rectangle) -> (bool) {
    if rect.x >= 0 && rect.y >= 0 && rect.z >= 0 && rect.w >= 0 {
        return true
    }
    return
}

box_create :: proc(id_gen: ^Id_Generator, rect: Rectangle, thick: f32, color: rl.Color, state: Box_State) -> (box: Box) {
    assert(id_gen >= 0); assert(rectangle_validity_check(rect)); assert(thick >= 0)
    box.id = entity_id_get(id_gen)
    box.rectangle = rect
    box.line_thickness = thick
    box.color = rl.Color
    box.state = state
    assert(box.id >= 0)
    return
}

box_resize :: proc(box: ^Box, amount: f32) {
    o_dim, new_dim := box.rectangle.zw
    o_dim *= o_dim
    o_hypot := math.sqrt(o_dim + o_dim)
    new_dim += amount
    if new_dim.x <= 0 || new_dim.y <= 0 {
        new_dim = 1
    }
    box.rectangle.zw = new_dim
    new_dim *= new_dim
    new_hypot := math.sqrt(new_dim + new_dim)
    diff_hypot := new_dim - o_dim
    box.rectangle.xy -= (diff_hypot/2)
}


