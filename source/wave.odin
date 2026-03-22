package game
import "core:math/rand"
import "core:log"

WaveSpawner :: struct {
    spawns          : [EnemyKind]Enemy,
    spawn_points    : [4][2]f32,
    pack_size       : int,
    current_enemies : int,
    max_enemies     : int,
    current_pack    : int,
    wave_count      : int,
    max_waves       : int,
    current_waves   : int,
    next_spawn      : EnemyKind,
    first_spawn     : bool,
}

init_wave_spawner :: proc(ws : ^WaveSpawner, pack_size : int = 4, max_enemies : int = 19) {
    ws.spawns[ws.next_spawn] = new_chaser()
    
    size := f32(NATIVE_TILE_DIM.x)
    dim := f32(SCENE_LEVEL_DIM.x - 1) 

    ws.spawn_points[0] = { 0, 0 } * size
    ws.spawn_points[1] = { dim, 0 } * size
    ws.spawn_points[2] = { 0, dim } * size
    ws.spawn_points[3] = { dim , dim } * size

    ws.max_enemies = max_enemies
    ws.pack_size = pack_size
    ws.wave_count = 1
    ws.first_spawn = true
    ws.max_waves = 1
}

spawn_wave :: proc(spawner : ^WaveSpawner, enemies : ^EnemyData) {
    if spawner.current_pack < spawner.pack_size {
        if spawner.first_spawn {
            spawner.first_spawn = false
            progress_difficulty(1)
        }
        spawn_point_idx := rand.int32_range(0, len(spawner.spawn_points))
        next_spawn := spawner.spawns[spawner.next_spawn]
        next_spawn.kb.box.rectangle.xy = spawner.spawn_points[spawn_point_idx]
        add_enemy(next_spawn, enemies)
        spawner.current_enemies += 1
        spawner.current_pack += 1
        start_timer(&game_ctx.timers[.Wave_Spawn_Enemy])
    } else {
        spawner.current_pack = 0
        spawner.current_waves += 1
        if spawner.current_waves < spawner.max_waves {
            spawn_wave(spawner, enemies)
        } else {
            spawner.first_spawn = true
            spawner.current_waves = 0
            if can_spawn(spawner) {
                start_timer(&game_ctx.timers[.Spawn_Wave])
            }
        }
    }
}

can_spawn :: proc(ws: ^WaveSpawner) -> bool {
    return ws.current_enemies + ws.pack_size <= ws.max_enemies
}

upgrade_spawns :: proc(ws: ^WaveSpawner) {
    for &spawn in ws.spawns {
        spawn.health += 1
        spawn.speed += 0.2
        spawn.attack_rate -= 0.1
        spawn.damage += 1.0
        spawn.currency_value += 2
    }
}


