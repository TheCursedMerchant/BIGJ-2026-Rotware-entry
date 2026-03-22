package game

// Imports
import rl "vendor:raylib"
import "core:slice"
import sa "core:container/small_array"
import la "core:math/linalg"
import "core:log"

// Constants

MINIMUM_SIZE :: f32(NATIVE_TILE_DIM.x)
MAXIMUM_SIZE : f32 : 100

KICK_HITBOX :: Rectangle{0,0,10,10}
KICK_VELOCITY : [2]f32 : {10, 10}

BOX_SMALL_ARRAY_SIZE :: 30
BOX_STATE_SMALL_ARRAY_SIZE :: 10

TILE_UNIT_RECT :: Rectangle{0, 0, f32(NATIVE_TILE_DIM.x), f32(NATIVE_TILE_DIM.y)}
// Globals



// Enums

Box_State :: enum u8 {
    None,
    Active,
}

// Structs

Rectangle :: [4]f32 // x, y, w, h

BoxColor :: enum { Primary, Secondary }

Box :: struct {
    colors          : [BoxColor]rl.Color,
    explode_rect    : Rectangle,
    rectangle       : Rectangle,
    preview_rect    : Rectangle,
    preview_color   : rl.Color,
    color           : rl.Color,
    explode_color   : [4]f32,
    tile_size       : [2]int, 
    draw_offset     : [2]f32,
    creator_idx     : int,
    line_thickness  : f32,
    state           : Box_State,
    active_dam      : f32,
}

Key_Value :: struct($T: typeid, $E: typeid) {
    key : T,
    value : E,
}

BoxStateList :: sa.Small_Array(BOX_STATE_SMALL_ARRAY_SIZE, Box_State)

// Procs

square_create :: proc(x, y, l: f32) -> (rect: Rectangle) {
    assert(x >= 0); assert(y >= 0); assert(l >= 0)
    return Rectangle{x, y, l, l}
}

rectangle_validity_check :: proc(rect: Rectangle) -> (bool) {
    //if rect.x >= 0 && rect.y >= 0 && rect.z >= 0 && rect.w >= 0 {
    if rect.z >= 0 && rect.w >= 0 {
        return true
    }
    return false
}

box_create_tile_size :: proc(
    pos: [2]int = {},
    tile_size : [2]int = {},
    thick: f32 = 1.0,
    colors: [BoxColor]rl.Color = { .Primary = rl.WHITE, .Secondary = rl.RED },
    state: Box_State = .None,
) -> Box {
    rect : Rectangle
    rect.xy = get_tile_world_pos(pos) 
    rect.zw = arr_cast(tile_size * NATIVE_TILE_DIM, f32)
    return box_create(rect, thick, colors, state)
}

box_create :: proc(rect: Rectangle, thick: f32, colors: [BoxColor]rl.Color, state: Box_State) -> (box: Box) {
    assert(rectangle_validity_check(rect)); assert(thick >= 0)
    box.rectangle = rect
    box.explode_rect = rect
    box.line_thickness = thick
    box.colors = colors
    box.color = box.colors[.Primary]
    box.state = state
    box.tile_size = arr_cast(la.round(rect.zw), int) / NATIVE_TILE_DIM
    set_box_preview_rect(&box)
    return
}

set_box_preview_rect :: proc (box: ^Box) {
    rect_center := box.rectangle.xy + ( box.rectangle.zw / 2.0 )
    unit_rect_center := box.rectangle.xy + (TILE_UNIT_RECT.zw / 2.0)
    center_offset := rect_center - unit_rect_center
    box.preview_rect = TILE_UNIT_RECT
    box.preview_rect.xy = box.rectangle.xy + center_offset
    box.preview_color = box.colors[.Primary]
    box.preview_color.a = 20
}

box_resize :: proc(box: ^Box, amount: f32) {
    box.rectangle.zw += amount
    if box.rectangle.z < 0 || box.rectangle.w < 0 {
        box.rectangle.zw = 0
        return
    }
    box.rectangle.xy -= (amount/2)
}


box_set_size :: proc {
    box_set_size_unsafe,
    box_set_size_kb,
}

box_set_size_kb :: proc(box: ^Box, size : [2]int, player_rect : Rectangle, k_bodies : []KinematicBody) {
    if size == { 1, 1 } {
        for kb in k_bodies {
            if rectangle_overlap(kb.box.rectangle, box.preview_rect) {
                return
            }
        }

        for &e, idx in game_ctx.enemies.active {
            if rectangle_overlap(e.kb.box.rectangle, box.rectangle) {
                kill_enemy(idx, game_ctx.enemies)
            }
        }
    }

    box_set_size_unsafe(box, size, player_rect)
}

box_set_size_unsafe :: proc(box: ^Box, size : [2]int, player_rect : Rectangle) {
    size := size
    size.x = la.max(size.x, 1)
    size.y = la.max(size.y, 1)
    size_diff := size - box.tile_size

    new_rect := box.rectangle
    orig_center_offset := new_rect.zw / 2
    new_size := arr_cast(size * NATIVE_TILE_DIM, f32)
    new_rect.zw = new_size
    new_rect.xy += orig_center_offset - (new_size / 2)

    if size_diff == 0 do return

    box.tile_size = size
    box.rectangle = new_rect

    // Update rectangle preview
    set_box_preview_rect(box)
}

shrink_box :: proc(ctx: ^CollisionContext, box: ^Box, size : [2]int, player_rect : Rectangle, box_idx: int) {
    box_set_size_kb(box, size, player_rect, sa.slice(&ctx.kick_boxes))
    if box.tile_size == { 1, 1 } {
        if rectangle_overlap(box.rectangle, player_rect) {
            log.debugf("Eating kickbox!")
            consume_area(10)
        } else {
            kick_box := KinematicBody {
                box = {
                    tile_size = box.tile_size,
                    rectangle = box.rectangle,
                    colors = box.colors,
                    color = box.colors[.Primary],
                    line_thickness = 1.0,
                },
                prev_pos = box.rectangle.xy,
                timer = { duration = 2.0 }
            }
            sa.append(&ctx.kick_boxes, kick_box)
        }
        clear_box(box)
    }
}

consume_area :: proc(currency : int) {
    update_currency(currency)
    update_active_areas(-1)
}

clear_box :: proc(box: ^Box) {
    box.rectangle = {}
    box.preview_rect = {}
    box.preview_color = {}
}

box_draw :: proc(box: Box) {
    assert(rectangle_validity_check(box.rectangle)); assert(box.line_thickness >= 0)
    ray_rect := rl.Rectangle {
        box.rectangle.x, 
        box.rectangle.y, 
        box.rectangle.z + box.draw_offset.x, 
        box.rectangle.w + box.draw_offset.y
    }
    rl.DrawRectangleLinesEx(ray_rect, box.line_thickness, box.color)
    rl.DrawRectangleLinesEx(rect_to_rectangle(box.preview_rect), box.line_thickness, box.preview_color)
}

box_draw_at_pos :: proc(box: Box, pos : [2]f32) {
    assert(rectangle_validity_check(box.rectangle)); assert(box.line_thickness >= 0)
    ray_rect := rl.Rectangle {
        pos.x, 
        pos.y, 
        box.rectangle.z + box.draw_offset.x, 
        box.rectangle.w + box.draw_offset.y
    }
    rl.DrawRectangleLinesEx(ray_rect, box.line_thickness, box.color)
    rl.DrawRectangleLinesEx(rect_to_rectangle(box.preview_rect), box.line_thickness, box.preview_color)
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

boxes_all_containing_position :: proc(
    rect: Rectangle, 
    arr: []Box, 
) -> (boxes: sa.Small_Array(BOX_SMALL_ARRAY_SIZE, Box)) {
    assert(len(arr) > 0); assert(rectangle_validity_check(rect))
    for i in 0..<len(arr) {
        if box_contains_position(rect, arr[i]) {
            sa.append(&boxes, arr[i])
        }
    }
    return boxes
}

box_state_find :: proc(
    arr: []Box
) -> (key_state: BoxStateList) {
    for i in arr {
        if !slice.contains(sa.slice(&key_state), i.state) {
            sa.append(&key_state, i.state)
        }
    }
    return key_state
}

append_box_state :: proc(box: Box, list : ^$T) {
    if !slice.contains(sa.slice(list), box.state) {
        sa.append(list, box.state)
    }
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

box_kick_determine :: proc(
    arr: []Box, 
    player: Player, 
) -> (mobile, static: sa.Small_Array(BOX_SMALL_ARRAY_SIZE, Box)) {
    assert(len(arr) > 0)
    for cb in arr {
        sa.push(&static, cb)
    }
    filter := boxes_all_containing_position(rect = {player.kinematic_body.prev_pos.x, player.kinematic_body.prev_pos.y, 0,0}, arr = arr)
    hitbox := KICK_HITBOX
    hitbox.xy = player.kinematic_body.prev_pos + ([2]f32{f32(player.prev_dir.x), f32(player.prev_dir.y)} * player.kinematic_body.prev_pos)
    for i := 0; i < sa.len(static); i += 1 {
        if rectangle_overlap(hitbox, sa.get(static, i).rectangle) && !box_array_contains(sa.slice(&filter), sa.get(static, i)) {
            sa.push(&mobile, sa.get(static, i))
            sa.unordered_remove(&static, i)
            i -= 1
        }
    }
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

box_kick_assign_kb :: proc(targets: []Box, player: Player, allocator := context.allocator) -> (k_bodies: []KinematicBody) {
    assert(len(targets) > 0)
    temp : sa.Small_Array(BOX_SMALL_ARRAY_SIZE, KinematicBody)
    for i in 0..<len(targets) {
        vel := [2]f32{f32(player.prev_dir.x), f32(player.prev_dir.y)} * KICK_VELOCITY
        kb := KinematicBody{
            box = targets[i],
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

rect_to_rectangle :: proc (rect: Rectangle) -> rl.Rectangle {
    return { rect.x, rect.y, rect.z, rect.w }
}
