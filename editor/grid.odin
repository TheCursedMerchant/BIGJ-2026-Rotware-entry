package editor

import rl "vendor:raylib" 

ViewGrid :: struct($ROW, $COL: int, $DATA: typeid) {
    cells       : [ROW][COL]ViewCell(DATA),
    cell_dim    : [2]f32,
    cell_color  : Color,
    using draw  : Drawable,
}

ViewCell :: struct($T: typeid) {
    using drawable : Drawable,
    using data : T,
}

init_view_grid :: proc(grid : ^ViewGrid($R, $COL, $T), default: T, scale : f32 = 1.0) {
    n_cell_pos : [2]f32
    for &cells, x in grid.cells {
        for &cell, y in cells {
            n_cell_pos = grid.rect.xy + ({ f32(x), f32(y) } * grid.cell_dim * scale)
            cell.rect.xy = arr_cast(n_cell_pos, f32)
            cell.rect.zw = grid.cell_dim * scale
            cell.color = grid.cell_color
            cell.data = default
        }
    }
}

is_grid_clicked :: proc(grid: ^ViewGrid($R, $COL, $T)) -> (pos : [2]int, clicked : bool) {
    if rl.IsMouseButtonPressed(.LEFT) {
        mouse_pos := rl.GetMousePosition()
        if pos_in_rect(mouse_pos, grid.rect) { // Only check the scene grid if we clicked in the scene grid rect
            for cells, x in grid.cells {
                for cell, y in cells {
                    if pos_in_rect(mouse_pos, cell.rect) {
                        return [2]int{ x, y }, true
                    }
                }
            }
        }
    }
    return {}, false
}
