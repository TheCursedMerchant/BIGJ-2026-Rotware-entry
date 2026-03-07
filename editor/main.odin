package editor

import rl "vendor:raylib"
import "core:log"
import "core:mem"
//import "file"

TARGET_RES :: [2]f32 { 2240, 1260 }
NATIVE_TILE_SIZE :: 16
SCENE_CELL_SIZE :: [2]int{ 24, 24 }
PANEL_DIM :: [2]int{ 8, 16 }

Texture :: rl.Texture2D
Rectangle :: rl.Rectangle
Color :: rl.Color

Rect :: [4]f32

View :: struct {
    ent_panel_items     : [dynamic]EntPanelItem,
    tile_panel_items    : [dynamic]TilePanelItem,
    panel               : Panel,
    scene_view          : SceneView,
    cursor              : Cursor,
    scale               : f32,
}

ViewGrid :: struct($ROW, $COL: int, $DATA: typeid) {
    cells       : [ROW][COL]ViewCell(DATA),
    cell_dim    : [2]int,
    cell_color  : Color,
}

ViewCell :: struct($T: typeid) {
    using drawable : Drawable,
    data : T,
}

Drawable :: struct {
    rect : Rect,
    color : Color,
}

Panel :: struct {
    grid : ViewGrid(PANEL_DIM.x, PANEL_DIM.y, int),
    using draw : Drawable,
}

SceneView :: struct {
    grid : ViewGrid(SCENE_CELL_SIZE.x, SCENE_CELL_SIZE.y, SceneCellData),
    cell_size : [2]i32,
    cell_color : Color,
    rect : Rect,
}

SceneCellOption :: enum { Ent, Tile }
SceneCellData :: struct {
    tile_id     : TileTextureName,
    ent_id      : EntTextureName,
    options     : bit_set[SceneCellOption],
}

Cursor :: struct {
    texture : Texture,
    id      : int,
    options : bit_set[SceneCellOption],
}

TileTextureName :: enum {
    Tile_Patch_0,
}

EntTextureName :: enum {
    Player,
}

TilePatchId :: enum {
    Base,
    Open_All,
    Open_Top,
    Open_Bottom,
    Open_Left,
    Open_Right,
    Connect_Top,
    Connect_Bottom,
    Connect_Left,
    Connect_Right,
    Top_Left_Corner,
    Top_Right_Corner,
    Bottom_Left_Corner,
    Bottom_Right_Corner,
}

EntPanelItem :: struct {
    t_name  : EntTextureName,
    id      : int, 
}

TilePanelItem :: struct {
    t_name  : TileTextureName,
    id      : int, 
}

tile_textures : [TileTextureName]Texture
ent_textures : [EntTextureName]Texture

main :: proc() {
    // Init
    program_allocator : mem.Allocator 
    program_arena : mem.Arena 
    program_mem_block : []byte
    make_p_arena_alloc(&program_allocator, &program_arena, &program_mem_block, 500 * mem.Megabyte)
    context.allocator = program_allocator
    context.logger = log.create_console_logger()

	rl.SetConfigFlags({})
	rl.InitWindow(i32(TARGET_RES.x), i32(TARGET_RES.y), "Kick Boxing Editor")
    rl.SetTargetFPS(120)
    load_textures()

    // View
    screen_dim := [2]f32{ f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
    screen_center := screen_dim / 2.0
    view := View {
        ent_panel_items = make([dynamic]EntPanelItem, 0),
        tile_panel_items = make([dynamic]TilePanelItem, 0),
        panel = { grid = { cell_color = rl.WHITE }, color = rl.WHITE  },
        scene_view = { cell_size = { NATIVE_TILE_SIZE, NATIVE_TILE_SIZE }, cell_color = rl.WHITE },
        scale = 3.0
    }

    for t in EntTextureName {
        append(&view.ent_panel_items, EntPanelItem{ t_name = t, id = int(t) })
    }
    for t in TileTextureName {
        append(&view.tile_panel_items, TilePanelItem{ t_name = t, id = int(t) })
    }

    // Init Scene View
    view.scene_view.rect.zw = { len(view.scene_view.grid.cells), len(view.scene_view.grid.cells[0]) } * NATIVE_TILE_SIZE * view.scale
    view.scene_view.rect.xy = screen_center
    center_rect(&view.scene_view.rect)
    n_cell_pos : [2]i32
    for &cells, x in view.scene_view.grid.cells {
        for &cell, y in cells {
            n_cell_pos = arr_cast(view.scene_view.rect.xy, i32) + ({ i32(x), i32(y) } * view.scene_view.cell_size * i32(view.scale))
            cell.rect.xy = arr_cast(n_cell_pos, f32)
            cell.rect.zw = arr_cast(view.scene_view.cell_size * i32(view.scale), f32)
        }
    }

    // Init Panel
    view.panel.rect.xy = { screen_dim.x - 460, 50 } // Left of the Screen
    view.panel.rect.zw = { len(view.panel.grid.cells), len(view.panel.grid.cells[0]) } * NATIVE_TILE_SIZE * view.scale 

    for !rl.WindowShouldClose() {
        handle_input(&view)
        draw_frame(&view)
    }

    for t in tile_textures { rl.UnloadTexture(t) }
    for e in ent_textures { rl.UnloadTexture(e) }
    free_all(program_allocator)
    rl.CloseWindow()
}

load_textures :: proc() {
    ent_textures[.Player]           = rl.LoadTexture("./editor/textures/player.png")
    tile_textures[.Tile_Patch_0]    = rl.LoadTexture("./editor/textures/tile_patch_0.png")
}

handle_input :: proc(view: ^View) {
    if rl.IsMouseButtonPressed(.LEFT) {
        mouse_pos := rl.GetMousePosition()
        if pos_in_rect(mouse_pos, view.scene_view.rect) { // Only check the scene grid if we clicked in the scene grid rect
            // Clicked the Scene
            for cells, x in view.scene_view.grid.cells {
                for cell, y in cells {
                    if pos_in_rect(mouse_pos, cell.rect) {
                        log.debugf("Clicked cell at pos : %v", [2]int{x, y})
                        break
                    }
                }
            }
        }
    }
}

draw_frame :: proc (view : ^View) {
    rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        draw_scene_view(view)
        draw_action_panel(view)
    rl.EndDrawing()
}

draw_scene_view :: proc(view: ^View) {
    i_rect : [4]i32
    cell_pos : [2]i32
    for cells, x in view.scene_view.grid.cells {
        for cell, y in cells {
            cell_pos = arr_cast(view.scene_view.rect.xy, i32) + ({ i32(x), i32(y) } * view.scene_view.cell_size * i32(view.scale))
            i_rect := arr_cast(view.scene_view.cell_size, i32) * i32(view.scale)
            rl.DrawRectangleLines(cell_pos.x, cell_pos.y, i_rect.x, i_rect.y, view.scene_view.cell_color)
            if .Ent in cell.data.options {
                // Draw Ent
                rl.DrawTextureEx(ent_textures[EntTextureName(cell.data.ent_id)], arr_cast(cell_pos, f32), 0, 1.0, view.scene_view.cell_color)
            }
            if .Tile in cell.data.options {
                // Draw Tile
                rl.DrawTextureEx(tile_textures[TileTextureName(cell.data.tile_id)], arr_cast(cell_pos, f32), 0, 1.0, view.scene_view.cell_color)
            }
        }
    }
}

draw_action_panel :: proc(view: ^View) {
    // Background
    rl.DrawRectangleRec(rect_to_rectangle(view.panel.rect), view.panel.color)
}

make_p_arena_alloc :: proc(alloc: ^mem.Allocator, arena : ^mem.Arena, block : ^[]byte, size: uint) {
    arena_err : mem.Allocator_Error
    block^, arena_err = make([]byte, size)
    if arena_err != nil {
        log.errorf("Failed to init arena with err : %v", arena_err)
        assert(false)
    }
    mem.arena_init(arena, block^)
    alloc^ = mem.arena_allocator(arena)
}

pos_in_rect :: proc(pos: [2]f32, rect: Rect) -> bool {
    return pos.x >= rect.x && pos.x <= (rect.x + rect.z) && pos.y >= rect.y && pos.y <= (rect.y + rect.w)
}

rect_to_rectangle :: proc(rect: Rect) -> Rectangle {
    return { rect.x, rect.y, rect.z, rect.w }
}

get_rect_center :: proc(rect: Rect) -> [2]f32 {
    return rect.xy - (rect.zw / 2)
}

//NOTE: Relative to it's current position
center_rect :: proc(rect: ^Rect) {
    rect.xy = get_rect_center(rect^)
}

arr_cast :: proc(arr: [$N]$T, $S : typeid) -> [N]S  {
    out : [N]S
    for val, idx in arr {
        out[idx] = S(val)
    }
    return out
}
