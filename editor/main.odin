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
import sa "core:container/small_array"
import "file"

TARGET_RES :: [2]f32 { 2240, 1260 }
NATIVE_TILE_SIZE :: 16
NATIVE_TILE_DIM :: [2]f32{ NATIVE_TILE_SIZE, NATIVE_TILE_SIZE }
SCENE_CELL_SIZE :: [2]int{ 24, 24 }
PANEL_DIM :: [2]int{ 8, 16 }
BUTTON_TEXT_SIZE :: 24.0
SCENE_PATH :: "./editor/scenes"

Texture :: rl.Texture2D
Rectangle :: rl.Rectangle
Color :: rl.Color

Rect :: [4]f32

View :: struct {
    panel               : Panel,
    scene_view          : SceneView,
    file_dialog         : FileDialog,
    cursor              : Cursor,
    scale               : f32,
}

Drawable :: struct {
    rect : Rect,
    color : Color,
}

PanelButtonId :: enum { Ent, Tile, Save }
PanelGrid :: ViewGrid(PANEL_DIM.x, PANEL_DIM.y, PanelItem)
Panel :: struct {
    grids           : [SceneItemOption]PanelGrid,
    current_grid    : SceneItemOption,
    buttons         : [PanelButtonId]TextButton,
}

TextButton :: struct {
    using draw      : Drawable,
    text            : DrawableText
}

DrawableText :: struct {
    using draw  : Drawable,
    content     : string, 
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

SceneSave :: struct {
    cells : [SCENE_CELL_SIZE.x][SCENE_CELL_SIZE.y]SceneCellSave,
}

SceneCellSave :: struct {
    tile_id     : TileTextureName,
    ent_id      : EntTextureName,
    has_tile    : b8,
    has_ent     : b8,
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
        file_dialog = {
            rect = { screen_center.x, screen_center.y, 800, 800 },
            color = rl.WHITE,
            text_button_template = { 
                rect = { 0, 0, 768, BUTTON_TEXT_SIZE },
                color = rl.WHITE,
                text = { rect = {0, 0, 768, BUTTON_TEXT_SIZE }, color = rl.WHITE },
            },
            inner_padding = { 16, 16 },
            item_v_padding = 16,
        },
        scale = 3.0,
    }

    center_rect(&view.file_dialog.rect)

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

    panel_rect := panel.grids[.Tile].rect
    tile_pos := panel_rect.xy + { 0, panel_rect.w } + { 0, 16 }
    panel.buttons[.Tile] = text_button(tile_pos, "Tiles", { 16, 16 })
    ent_pos := tile_pos + { panel.buttons[.Tile].rect.z + 8, 0 }
    panel.buttons[.Ent] = text_button(ent_pos, "Ents", { 16, 16 })
    save_pos := ent_pos + { 0, panel.buttons[.Ent].rect.w + 8 }
    panel.buttons[.Save] = text_button(save_pos, "Save", {16, 16})
}

text_button :: proc(pos: [2]f32, text: string, padding : [2]f32 = {}) -> TextButton {
    button : TextButton
    button.text.content = text
    text_width := f32(rl.MeasureText(rl.TextFormat("%s", text), BUTTON_TEXT_SIZE)) 
    button.rect = Rect {0, 0, text_width + padding.x, BUTTON_TEXT_SIZE + padding.y }
    button.rect.xy = pos
    button.text.color = rl.WHITE
    button.text.rect.xy = button.rect.xy
    button.text.rect.z = text_width
    button.text.rect.w = BUTTON_TEXT_SIZE
    button.color = rl.WHITE
    center_rect_in_rect(&button.text.rect, button.rect)
    return button
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
    if view.file_dialog.show {
        if rl.IsMouseButtonPressed(.LEFT) {
            info, clicked := is_pos_in_file_button(&view.file_dialog, mouse_pos) 
            if clicked {
                load_scene_from_path(view, info.fullpath)
                view.file_dialog.show = false
            }
        }
    } else {
        if rl.IsMouseButtonPressed(.LEFT) {
            handle_scene_left_click(view, mouse_pos)
            handle_panel_left_click(view, mouse_pos)
            if pos_in_rect(mouse_pos, view.panel.buttons[.Tile].rect) {
                view.panel.current_grid = .Tile
            } else if pos_in_rect(mouse_pos, view.panel.buttons[.Ent].rect) {
                view.panel.current_grid = .Ent
            } else if pos_in_rect(mouse_pos, view.panel.buttons[.Save].rect) {
                save_scene(view)
            }
        } else if rl.IsMouseButtonPressed(.RIGHT) {
            handle_scene_right_click(view, mouse_pos)
        }
    }

    // Open File Dialog
    if rl.IsKeyPressed(.F) {
        view.file_dialog.show = !view.file_dialog.show
        if view.file_dialog.show {
            load_fis_from_path(&view.file_dialog, SCENE_PATH)
        } else {
            sa.clear(&view.file_dialog.fis)
        }
    }
}

handle_scene_left_click :: proc(view: ^View, mouse_pos : [2]f32) {
    scene_item : ^SceneItem
    click_pos, scene_clicked := is_pos_in_cell(&view.scene_view, mouse_pos)
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

handle_scene_right_click :: proc(view: ^View, mouse_pos: [2]f32) {
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

handle_panel_left_click :: proc(view: ^View, mouse_pos : [2]f32) {
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
    }
}

draw_frame :: proc (view : ^View) {
    rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        draw_scene_view(&view.scene_view)
        draw_action_panel(&view.panel)
        if view.file_dialog.show {
            draw_file_dialog(&view.file_dialog)
        }
        draw_cursor(&view.cursor)
    rl.EndDrawing()
}


draw_scene_view :: proc(view: ^SceneView) {
    i_rect : [4]i32
    cell_pos : [2]i32
    ent_texture : Texture
    for cells, x in view.cells {
        for cell, y in cells {
            draw_rectangle_lines(cell)
            if .Tile in cell.options {
                rl.DrawTexturePro(tile_textures[cell.tile_id], {0, 0, 16, 16}, rect_to_rectangle(cell.rect), {}, 0, rl.WHITE)
            }
            if .Ent in cell.options {
                ent_texture = ent_textures[cell.ent_id]
                rl.DrawTexturePro(ent_texture, {0, 0, f32(ent_texture.width), f32(ent_texture.height)}, rect_to_rectangle(cell.rect), {}, 0, rl.WHITE) 
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
                    rl.DrawTexturePro(item_texture, {0, 0, f32(item_texture.width), f32(item_texture.height)}, rect_to_rectangle(cell.rect), {}, 0, rl.WHITE) 
                case .Tile: 
                    item_texture = tile_textures[TileTextureName(cell.t_id)]
                    rl.DrawTexturePro(item_texture, {0, 0, 16, 16}, rect_to_rectangle(cell.rect), {}, 0, rl.WHITE) 
                }
            }
        }
    }

    for button in panel.buttons {
        draw_text_button(button)
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
        rl.DrawTexturePro(cursor.texture, {0, 0, f32(cursor.texture.width), f32(cursor.texture.height)}, rect_to_rectangle(cursor.rect), {}, 0, rl.WHITE) 
    case .Tile:
        rl.DrawTexturePro(cursor.texture, {0, 0, 16, 16}, rect_to_rectangle(cursor.rect), {}, 0, rl.WHITE) 
    }
}

draw_text_button :: proc(button : TextButton) {
    draw_rectangle_lines(button.draw)
    text_draw := button.text.draw
    rl.DrawText(rl.TextFormat("%s", button.text.content), i32(text_draw.rect.x), i32(text_draw.rect.y), i32(text_draw.rect.w), text_draw.color)
}

save_scene :: proc(view: ^View) {
    scn := &view.scene_view
    save_cells : [SCENE_CELL_SIZE.x][SCENE_CELL_SIZE.y]SceneCellSave
    for cells, x in scn.cells {
        for cell, y in cells {
            save_cells[x][y].ent_id = cell.ent_id
            save_cells[x][y].has_ent = .Ent in cell.options
            save_cells[x][y].tile_id = cell.tile_id
            save_cells[x][y].has_tile = .Tile in cell.options
        }
    }
    file.serialize_game_object_cbor(SceneSave { cells = save_cells }, "test_scn", "editor/scenes/")
}

load_scene_from_path :: proc(view: ^View, path: string) {
    save_scene := file.deserialize_game_object_cbor(SceneSave, path)
    n_item : ^SceneItem
    for cells, x in save_scene.cells {
        for cell, y in cells {
            n_item = &view.scene_view.cells[x][y]
            if cell.has_ent {
                n_item.ent_id = cell.ent_id
                n_item.options += { .Ent }
            } 
            if cell.has_tile {
                n_item.tile_id = cell.tile_id
                n_item.options += { .Tile }
            }
        }
    }
}

// Utils
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
    return rect.xy + (rect.zw / 2)
}

center_rect_in_rect :: proc(a : ^Rect, b : Rect) {
    a.xy += get_rect_center(b) - get_rect_center(a^)
}

get_rect_center_offset :: proc(rect: Rect) -> [2]f32 {
    return rect.xy - (rect.zw / 2)
}

//NOTE: Relative to it's current position
center_rect :: proc(rect: ^Rect) {
    rect.xy = get_rect_center_offset(rect^)
}

arr_cast :: proc(arr: [$N]$T, $S : typeid) -> [N]S  {
    out : [N]S
    for val, idx in arr {
        out[idx] = S(val)
    }
    return out
}
