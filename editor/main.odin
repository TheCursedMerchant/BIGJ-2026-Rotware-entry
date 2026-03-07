package editor

/* 
Basic grid based tile editor, to support creation of levles for the Kick Boxing game
Basic approach is to init any drawable components with a top level Scale applied by
the View struct. This lets us scale the ui arbitrarily at start up without having to apply
the scale in all of our draw calls, makes it easier to think about.
There is a top level arena for easy memory management and since the UI is pretty
limited in size we don't really need to free any memory for anything until the very end.

Textures are a set of png files that live in the Textures directory at the same level as this program.
So to add new ones you need to add a file that directory, add it to the load_textures proc, and then edit the appropriate
Texture Array with a new Enum value that gives the texture a name. Please add new enum values at the end of the enum,
to maintain the serialized Id that the game will use to rebuild the level correctly. If the Id's change order it will
change which entities and tiles get loaded by the consumer (The Game)
*/

import rl "vendor:raylib"
import "core:log"
import "core:mem"
//import "file"

TARGET_RES :: [2]f32 { 2240, 1260 }
NATIVE_TILE_SIZE :: 16
NATIVE_TILE_DIM :: [2]f32{ NATIVE_TILE_SIZE, NATIVE_TILE_SIZE }
SCENE_CELL_SIZE :: [2]int{ 24, 24 }
PANEL_DIM :: [2]int{ 8, 16 }

Texture :: rl.Texture2D
Rectangle :: rl.Rectangle
Color :: rl.Color

Rect :: [4]f32

View :: struct {
    panel               : Panel,
    scene_view          : SceneView,
    cursor              : Cursor,
    scale               : f32,
}

Drawable :: struct {
    rect : Rect,
    color : Color,
}

PanelGrid :: ViewGrid(PANEL_DIM.x, PANEL_DIM.y, PanelItem)
Panel :: struct {
    grids : [SceneItemOption]PanelGrid,
    current_grid : SceneItemOption,
}

PanelItem :: struct {
    t_id     : int,
    has_item : bool,
}

SceneView :: ViewGrid(SCENE_CELL_SIZE.x, SCENE_CELL_SIZE.y, SceneItem)

SceneItemOption :: enum { Ent, Tile }
SceneItem :: struct {
    tile_id     : TileTextureName,
    ent_id      : EntTextureName,
    options     : bit_set[SceneItemOption],
}

CursorOptions :: enum { Dragging }
Cursor :: struct {
    texture     : Texture,
    id          : int,
    item_type   : SceneItemOption,
    using draw  : Drawable,
    options     : bit_set[CursorOptions],
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
    panel_grid := ViewGrid(PANEL_DIM.x, PANEL_DIM.y, PanelItem) {
        color = rl.WHITE,
        cell_dim = NATIVE_TILE_DIM,
        cell_color = rl.WHITE,
    }

    view := View {
        panel = { grids = { .Ent = panel_grid, .Tile = panel_grid }, current_grid = .Tile },
        scene_view = { cell_dim = NATIVE_TILE_DIM, cell_color = rl.WHITE },
        scale = 3.0
    }

    init_action_panel(&view.panel, { screen_dim.x - 460, 50 }, view.scale)
    init_scene_view(&view.scene_view, screen_center, view.scale)

    for !rl.WindowShouldClose() {
        handle_input(&view)
        draw_frame(&view)
    }

    for t in tile_textures { rl.UnloadTexture(t) }
    for e in ent_textures { rl.UnloadTexture(e) }
    free_all(program_allocator)
    rl.CloseWindow()
}

init_scene_view :: proc(view: ^SceneView, pos : [2]f32, scale: f32) {
    view.rect.zw = { len(view.cells), len(view.cells[0]) } * NATIVE_TILE_SIZE * scale
    view.rect.xy = pos
    center_rect(&view.rect)
    init_view_grid(view, SceneItem{}, scale)
}

init_action_panel :: proc(panel: ^Panel, pos : [2]f32, scale: f32) {
    init_panel_grid(&panel.grids[.Tile], .Tile, pos, scale)
    init_panel_grid(&panel.grids[.Ent], .Ent, pos, scale)
    panel.current_grid = .Tile
}

init_panel_grid :: proc(grid: ^PanelGrid, type: SceneItemOption, pos : [2]f32, scale: f32) {
    grid.rect.xy = pos
    grid.rect.zw = { len(grid.cells), len(grid.cells[0]) } * NATIVE_TILE_SIZE * scale 
    init_view_grid(grid, PanelItem{ t_id = -1 },  scale)
    grid_pos : [2]int
    switch type {
    case .Ent:
        for ent_texture, idx in ent_textures {
            grid_pos = calc_grid_pos_from_count(int(idx), len(grid.cells))
            grid.cells[grid_pos.x][grid_pos.y].data = { t_id = int(idx), has_item = true }
        }
    case .Tile:
        for t_texture, idx in tile_textures {
            grid_pos = calc_grid_pos_from_count(int(idx), len(grid.cells))
            grid.cells[grid_pos.x][grid_pos.y].data = { t_id = int(idx), has_item = true }
        }
    }
}

get_panel_current_grid :: proc(panel: ^Panel) -> ^PanelGrid {
    return &panel.grids[panel.current_grid]
}

calc_grid_pos_from_count :: proc(count : int, grid_width: int) -> [2]int {
    x := count % grid_width
    y := count / grid_width
    return { x, y }
}

load_textures :: proc() {
    ent_textures[.Player]           = rl.LoadTexture("./editor/textures/player.png")
    tile_textures[.Tile_Patch_0]    = rl.LoadTexture("./editor/textures/tile_patch_0.png")
}

handle_input :: proc(view: ^View) {
    mouse_pos := rl.GetMousePosition()
    if rl.IsMouseButtonPressed(.LEFT) {
        current_grid := get_panel_current_grid(&view.panel)
        click_pos, panel_clicked := is_pos_in_cell(current_grid, mouse_pos)
        if panel_clicked {
            cell := current_grid.cells[click_pos.x][click_pos.y]
            if cell.has_item {
                rl.HideCursor()
                view.cursor.id = cell.t_id
                view.cursor.item_type = view.panel.current_grid
                view.cursor.rect.zw = cell.rect.zw
                view.cursor.options += { .Dragging }
                switch view.panel.current_grid {
                case .Ent: 
                    view.cursor.texture = ent_textures[EntTextureName(cell.t_id)]
                case .Tile: 
                    view.cursor.texture = tile_textures[TileTextureName(cell.t_id)]
                }
            } 
        } else {
            scene_item : ^SceneItem
            scene_clicked : bool
            click_pos, scene_clicked = is_pos_in_cell(&view.scene_view, mouse_pos)
            if scene_clicked && ( .Dragging in view.cursor.options ) {
                scene_item = &view.scene_view.cells[click_pos.x][click_pos.y]
                switch view.cursor.item_type {
                case .Ent:
                    scene_item.ent_id = EntTextureName(view.cursor.id)
                    scene_item.options += { .Ent }
                case .Tile:
                    scene_item.tile_id = TileTextureName(view.cursor.id)
                    scene_item.options += { .Tile }
                }
                rl.ShowCursor()
                view.cursor = {}
            }
        }
    } else if rl.IsMouseButtonPressed(.RIGHT) {
        scene_item : ^SceneItem
        click_pos, scene_clicked := is_pos_in_cell(&view.scene_view, mouse_pos)
        if scene_clicked {
            scene_item = &view.scene_view.cells[click_pos.x][click_pos.y]
            if .Ent in scene_item.options {
                scene_item.options -= { .Ent }
            } else if .Tile in scene_item.options {
                scene_item.options -= { .Tile }
            }
        }
    }
}

draw_frame :: proc (view : ^View) {
    rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        draw_scene_view(&view.scene_view)
        draw_action_panel(&view.panel)
        draw_cursor(&view.cursor)
    rl.EndDrawing()
}

draw_scene_view :: proc(view: ^SceneView) {
    i_rect : [4]i32
    cell_pos : [2]i32
    for cells, x in view.cells {
        for cell, y in cells {
            draw_rectangle_lines(cell)
            if .Ent in cell.options {
                rl.DrawTexture(ent_textures[cell.ent_id], i32(cell.rect.x), i32(cell.rect.y), cell.color)
            }
            if .Tile in cell.options {
                rl.DrawTexturePro(tile_textures[cell.tile_id], {0, 0, 16, 16}, rect_to_rectangle(cell.rect), {}, 0, rl.WHITE)
            }
        }
    }
}

draw_action_panel :: proc(panel: ^Panel) {
    // Background
    current_grid := get_panel_current_grid(panel)
    draw_rectangle_lines(current_grid^)
    item_texture : Texture
    for cells, x in current_grid.cells {
        for cell, y in cells {
            draw_rectangle_lines(cell)
            if cell.has_item {
                switch panel.current_grid {
                case .Ent: 
                    item_texture = ent_textures[EntTextureName(cell.t_id)] 
                    rl.DrawTexture(item_texture, i32(cell.rect.x), i32(cell.rect.y), cell.color)
                case .Tile: 
                    item_texture = tile_textures[TileTextureName(cell.t_id)]
                    rl.DrawTexturePro(item_texture, {0, 0, 16, 16}, rect_to_rectangle(cell.rect), {}, 0, rl.WHITE) 
                }
            }
        }
    }
}

draw_rectangle_lines :: proc(drawable: Drawable) {
    i_rect := arr_cast(drawable.rect, i32)
    rl.DrawRectangleLines(i_rect.x, i_rect.y, i_rect.z, i_rect.w, drawable.color)
}

draw_cursor :: proc(cursor: ^Cursor) {
    cursor.rect.xy = rl.GetMousePosition() - (cursor.rect.zw / 2)
    switch cursor.item_type {
    case .Ent:
        rl.DrawTexture(cursor.texture, i32(cursor.rect.x), i32(cursor.rect.y), cursor.color)
    case .Tile:
        rl.DrawTexturePro(cursor.texture, {0, 0, 16, 16}, rect_to_rectangle(cursor.rect), {}, 0, rl.WHITE) 
    }
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
