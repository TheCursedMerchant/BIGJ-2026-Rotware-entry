package game
import "core:log"
import "core:math/rand"
import sa "core:container/small_array"

PlayerModifier :: struct {
    move_speed          : f32,
    health              : f32,
    dash_cd             : f32,
    stomp_cd            : f32,
    stomp_size          : f32,
    stomp_force         : f32,
    dash_speed          : f32,
    dash_charge         : int,
}

Lootbox :: struct {
    modifier    : PlayerModifier,
    rect        : Rectangle,
    render      : Render,
    cost        : int,
    open        : bool,
}

PlayerModKind :: enum { 
    Health, 
    Speed, 
    Dash_Charge, 
    Dash_Speed, 
    Dash_Cd, 
    Stomp_Size, 
    Stomp_Force, 
    Stomp_Cd,
}

global_player_mods := [PlayerModKind]PlayerModifier {
    .Health = { health = 1 },
    .Speed = { move_speed = 0.5 },
    .Dash_Charge = { dash_charge = 1 },
    .Dash_Speed = { dash_speed = 0.5 },
    .Dash_Cd = { dash_cd = -0.1 },
    .Stomp_Size = { stomp_size = 2.0 },
    .Stomp_Force = { stomp_force = 1.0 },
    .Stomp_Cd = { stomp_cd = -0.1 },
}

spawn_loot :: proc() {
    drops := len(global_player_mods)
    drop := rand.int_range(0, drops)
    loot_rect : Rectangle 

    tile_free := false
    ctx := game_ctx.collision_ctx
    for !tile_free {
        tile_free = true
        loot_rect = rand_tile_rect()

        if rectangle_overlap(loot_rect, game_ctx.player.kinematic_body.box.rectangle) {
            tile_free = false
            continue
        }

        for s in sa.slice(&ctx.static) {
            if rectangle_overlap(loot_rect, s.rectangle) {
                tile_free = false
                break
            }
        }

        for kb in sa.slice(&ctx.kick_boxes) {
            if rectangle_overlap(loot_rect, kb.box.rectangle) {
                tile_free = false
                break
            }
        }
    }

    n_loot := Lootbox {
       modifier = global_player_mods[PlayerModKind(drop)],
       rect = loot_rect,
       render = { anim = create_atlas_anim(.Chest_Closed) },
       cost = 35 * game_ctx.difficulty_lvl,
    }

    if ctx.free_lb.len > 0 {
        next_idx := sa.pop_back(&ctx.free_lb)
        ctx.loot_boxes.data[next_idx] = n_loot
    } else {
        sa.append(&ctx.loot_boxes, n_loot)
    }

    rand_tile_rect :: proc() -> (rect : Rectangle) {
        new_tile_pos := [2]int{ rand.int_range(0, SCENE_LEVEL_DIM.x), rand.int_range(0, SCENE_LEVEL_DIM.y)}
        new_pos := arr_cast(new_tile_pos * NATIVE_TILE_DIM, f32)
        rect = Rectangle{new_pos.x, new_pos.y, 16, 16 }
        return rect
    }
}

stomp_loot :: proc(player: ^Player, lb: ^Lootbox, idx: int) {
    if rectangle_overlap(player.stomp.hitbox.rect, lb.rect) {
        log.debug("Stomp hit loot!")
        if lb.open {
            apply_player_modifer(player, lb.modifier)
            lb^ = {}
            sa.append(&game_ctx.collision_ctx.free_lb, idx)
            log.debug("Collect Box!")
        } else if game_ctx.currency >= lb.cost {
            log.debug("Open Box!")
            game_ctx.currency -= lb.cost
            lb.open = true
            lb.render.anim = create_atlas_anim(.Chest_Open)
        }
    }
}

apply_player_modifer :: proc(player: ^Player, modifier : PlayerModifier) {
    log.debugf("Applying modifier : %v", modifier)
    player.max_health += modifier.health
    player.health += modifier.health
    player.stomp.force += modifier.stomp_force
    player.stomp.hitbox.rect.zw += modifier.stomp_size
    player.dash.max_charges += modifier.dash_charge
    player.dash.charges += modifier.dash_charge
    player.dash.multiplier += modifier.dash_speed
    player.speed += modifier.move_speed
    game_ctx.timers[.Player_Stomp].duration += modifier.stomp_cd
    game_ctx.timers[.Player_Dash].duration += modifier.dash_cd
}
