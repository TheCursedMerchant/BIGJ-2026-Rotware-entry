package editor

import rl "vendor:raylib"
import "core:log"
import "core:mem"
//import "file"

TARGET_RES :: [2]f32 { 1920, 1080 }
NATIVE_TILE_SIZE :: 16
SCENE_CELL_SIZE :: [2]int{ 24, 24 }

Texture :: rl.Texture2D
Rectangle :: rl.Rectangle
Color :: rl.Color

Rect :: [4]f32

View :: struct {
    ent_panel_items     : [dynamic]EntPanelItem,
    tile_panel_items    : [dynamic]TilePanelItem,
    panel               : Panel,
    scene_view          : SceneView,
    scale               : f32,
}

Panel :: struct {
    grid : [3][8]int,
    rect : Rect,
    color : Color, 
}

SceneView :: struct {
    grid : [SCENE_CELL_SIZE.x][SCENE_CELL_SIZE.y]SceneCell,
    cell_size : [2]i32,
    cell_color : Color,
    rect : Rect,
}

SceneCellOption :: enum { Ent, Tile }
SceneCell :: struct {
    tile_id     : TileTextureName,
    ent_id      : EntTextureName,
    options     : bit_set[SceneCellOption],
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
    program_allocator : mem.Allocator 
    program_arena : mem.Arena 
    program_mem_block : []byte
    make_p_arena_alloc(&program_allocator, &program_arena, &program_mem_block, 500 * mem.Megabyte)
    context.allocator = program_allocator
    context.logger = log.create_console_logger()

	rl.SetConfigFlags({})
	rl.InitWindow(i32(TARGET_RES.x), i32(TARGET_RES.y), "Kick Boxing Editor")
    rl.SetTargetFPS(120)

    screen_center := [2]f32{ f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())} / 2.0

    view := View {
        ent_panel_items = make([dynamic]EntPanelItem, 0),
        tile_panel_items = make([dynamic]TilePanelItem, 0),
        panel = { rect = { screen_center.x, screen_center.y, 320, 320 }, color = rl.WHITE },
        scene_view = { cell_size = { NATIVE_TILE_SIZE, NATIVE_TILE_SIZE }, cell_color = rl.WHITE },
        scale = 2.0
    }

    //view.panel.rect.xy -= (view.panel.rect.zw / 2)
    //center_rect(&view.panel.rect)

    view.scene_view.rect.zw = { len(view.scene_view.grid), len(view.scene_view.grid[0]) } * NATIVE_TILE_SIZE
    view.scene_view.rect.xy = screen_center
    center_rect(&view.scene_view.rect, view.scale)

    load_textures()

    for t in EntTextureName {
        append(&view.ent_panel_items, EntPanelItem{ t_name = t, id = int(t) })
    }
    for t in TileTextureName {
        append(&view.tile_panel_items, TilePanelItem{ t_name = t, id = int(t) })
    }

    for !rl.WindowShouldClose() {
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

draw_frame :: proc (view : ^View) {
    rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        i_rect : [4]i32
        cell_pos : [2]i32
        for cells, x in view.scene_view.grid {
            for cell, y in cells {
                cell_pos = arr_cast(view.scene_view.rect.xy, i32) + ({ i32(x), i32(y) } * view.scene_view.cell_size * i32(view.scale))
                i_rect := arr_cast(view.scene_view.cell_size, i32) * i32(view.scale)
                rl.DrawRectangleLines(cell_pos.x, cell_pos.y, i_rect.x, i_rect.y, view.scene_view.cell_color)
                if .Ent in cell.options {
                    // Draw Ent
                    rl.DrawTextureEx(ent_textures[EntTextureName(cell.ent_id)], arr_cast(cell_pos, f32), 0, 1.0, view.scene_view.cell_color)
                }
                if .Tile in cell.options {
                    // Draw Tile
                    rl.DrawTextureEx(tile_textures[TileTextureName(cell.tile_id)], arr_cast(cell_pos, f32), 0, 1.0, view.scene_view.cell_color)
                }
            }
        }
        //rl.DrawRectangleRec(rect_to_rectangle(view.panel.rect), view.panel.color)
    rl.EndDrawing()
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

get_rect_center :: proc(rect: Rect, scale : f32 = 1.0) -> [2]f32 {
    return rect.xy - ((rect.zw * scale) / 2)
}

//NOTE: Relative to it's current position
center_rect :: proc(rect: ^Rect, scale : f32 = 1.0) {
    rect.xy = get_rect_center(rect^, scale)
}

arr_cast :: proc(arr: [$N]$T, $S : typeid) -> [N]S  {
    out : [N]S
    for val, idx in arr {
        out[idx] = S(val)
    }
    return out
}
