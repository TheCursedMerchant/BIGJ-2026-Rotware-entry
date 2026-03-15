package game

import s "core:strings"

SCENES_DIR :: "assets/scenes/"

SceneSave :: struct {
    cells : [SCENE_LEVEL_DIM.x][SCENE_LEVEL_DIM.y]SceneCellSave,
}

SceneCellSave :: struct {
    tile_id     : TileTextureName,
    ent_id      : EntTextureName,
    has_tile    : b8,
    has_ent     : b8,
}

TileTextureName :: enum {
    Tile_Patch_0,
}

EntTextureName :: enum {
    Player,
}

LevelId :: enum {
    Test,
}

Level :: struct {
    tiles               : [dynamic][dynamic]Tile,
    player_start_pos    : [2]f32,
}

Tile :: struct {
    render      : Render,
    has_tile    : b8,
}

level_names := [LevelId]string {
    .Test = "test_scn.json",
}

tile_anim_map := [TileTextureName]Animation_Name {
    .Tile_Patch_0 = .Place_Holder_Tile_Idle,
}

TileAnimMap :: [TileTextureName]Animation_Name

load_level_data :: proc(lvl : ^SceneSave, id: LevelId) {
    level_path := s.concatenate({ SCENES_DIR, level_names[.Test]})
    defer delete(level_path)
    lvl^ = deserialize_game_object(SceneSave, level_path)
}

build_level_from_save :: proc(lvl: ^SceneSave) -> Level {
    out := Level { tiles = make([dynamic][dynamic]Tile, SCENE_LEVEL_DIM.x) }
    for &tiles in out.tiles {
        tiles = make([dynamic]Tile, SCENE_LEVEL_DIM.y)
    }
    n_tile : ^Tile
    draw_pos : [2]f32
    for cells, x in lvl.cells {
        for cell, y in cells {
            n_tile = &out.tiles[x][y]
            draw_pos = { f32(x), f32(y) } * 16
            if cell.has_tile {
                n_tile.render.anim = create_atlas_anim(tile_anim_map[cell.tile_id])
                n_tile.render.pos = draw_pos
                n_tile.has_tile = true
            }
            if cell.has_ent {
                if cell.ent_id == .Player {
                    out.player_start_pos = draw_pos
                }
            }
        }
    }
    return out
}

update_tile_frames :: proc() {
    t_frame : u8
    for &tiles, x in &game_ctx.level.tiles {
        for &tile, y in tiles {
            t_frame = u8(tile.render.anim.current_frame)
            t_frame += get_tile_frame({x, y})
            tile.render.anim.current_frame = Texture_Name(t_frame)
        }
    }
}

// Auto tile Stuff
CardinalDir :: enum { North, West, East, South }
bit_dir := [CardinalDir]u8 {
    .North = 1,
    .West = 2,
    .East = 4,
    .South = 8,
}

vec_dir := [CardinalDir][2]int {
    .North = {0, -1},
    .West = {-1, 0},
    .East = {1, 0},
    .South = {0, 1},
}

get_tile_frame :: proc(pos : [2]int) -> (frame : u8) {
    n_tile : ^Tile
    for dir in CardinalDir {
        n_tile = get_tile_from_grid_pos(vec_dir[dir] + pos)
        if( n_tile != nil ) {
            frame += bit_dir[dir] * u8(n_tile.has_tile)
        }
    }
    return frame
}

get_tile_from_world_pos :: proc(pos : [2]f32) -> ^Tile {
    grid_pos := arr_cast(pos / arr_cast(SCENE_LEVEL_DIM, f32), int)
    return get_tile_from_grid_pos(grid_pos)
}

get_tile_from_grid_pos :: proc(pos : [2]int) -> ^Tile {
    if pos_in_grid(pos) {
        return &game_ctx.level.tiles[pos.x][pos.y]
    }
    return nil
}

get_tile_world_pos :: proc(pos: [2]int) -> [2]f32 {
    return arr_cast(pos * NATIVE_TILE_DIM, f32)
}

pos_in_grid :: proc(pos: [2]int) -> bool {
    return pos.x >= 0 && pos.x < SCENE_LEVEL_DIM.x && pos.y >= 0 && pos.y < SCENE_LEVEL_DIM.y
}
