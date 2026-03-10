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
    tiles               : [SCENE_LEVEL_DIM.x][SCENE_LEVEL_DIM.y]Tile,
    player_start_pos    : [2]f32,
}

Tile :: struct {
    render : Render,
}

level_names := [LevelId]string {
    .Test = "test_scn.json",
}

tile_anim_map := [TileTextureName]Animation_Name {
    .Tile_Patch_0 = .Blue_Tile_Base,
}

TileAnimMap :: [TileTextureName]Animation_Name

load_level_data :: proc(lvl : ^SceneSave, id: LevelId) {
    level_path := s.concatenate({ SCENES_DIR, level_names[.Test]})
    defer delete(level_path)
    lvl^ = deserialize_game_object(SceneSave, level_path)
}

build_level_from_save :: proc(lvl: ^SceneSave) -> Level {
    out : Level
    n_tile : ^Tile
    draw_pos : [2]f32
    for cells, x in lvl.cells {
        for cell, y in cells {
            n_tile = &out.tiles[x][y]
            draw_pos = { f32(x), f32(y) } * 16
            if cell.has_tile {
                n_tile.render.anim = create_atlas_anim(tile_anim_map[cell.tile_id])
                n_tile.render.pos = draw_pos
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
