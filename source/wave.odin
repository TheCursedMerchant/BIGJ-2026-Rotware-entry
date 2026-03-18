package game
import "core:math/rand"
import "core:log"

EnemyType :: enum { Base }

WaveSpawner :: struct {
    spawns          : [EnemyType]Enemy,
    spawn_points    : [4][2]f32,
    pack_size       : int,
    current_enemies : int,
    max_enemies     : int,
    current_pack    : int,
}

init_wave_spawner :: proc(ws : ^WaveSpawner, pack_size : int = 5, max_enemies : int = 20) {
    enemy := basic_enemy_at_pos({})
    ws.spawns[.Base] = enemy
    
    size := f32(NATIVE_TILE_DIM.x)
    dim := f32(SCENE_LEVEL_DIM.x - 1) 

    ws.spawn_points[0] = { 0, 0 } * size
    ws.spawn_points[1] = { dim, 0 } * size
    ws.spawn_points[2] = { 0, dim } * size
    ws.spawn_points[3] = { dim , dim } * size

    ws.max_enemies = max_enemies
    ws.pack_size = pack_size
}

spawn_wave :: proc(spawner : ^WaveSpawner, enemies : ^EnemyData) {
    if spawner.current_pack < spawner.pack_size {
        spawn_point_idx := rand.int32_range(0, len(spawner.spawn_points))
        next_spawn := spawner.spawns[.Base]
        next_spawn.kb.box.rectangle.xy = spawner.spawn_points[spawn_point_idx]
        add_enemy(next_spawn, enemies)
        spawner.current_enemies += 1
        spawner.current_pack += 1
        start_timer(&game_ctx.timers[.Wave_Spawn_Enemy])
    } else {
        spawner.current_pack = 0
        if can_spawn(spawner) {
            start_timer(&game_ctx.timers[.Spawn_Wave])
        }
    }
}

can_spawn :: proc(ws: ^WaveSpawner) -> bool {
    return ws.current_enemies + ws.pack_size <= ws.max_enemies
}
