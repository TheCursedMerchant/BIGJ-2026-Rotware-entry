package game
import "core:log"
import "core:math/rand"
import sa "core:container/small_array"

MOD_RENDER_OFFSET :: [2]f32{ 0, -16 }

PlayerModifier :: struct {
    render              : Render,
    kind                : PlayerModKind,
    dash_charge         : int,
    move_speed          : f32,
    health              : f32,
    dash_cd             : f32,
    stomp_cd            : f32,
    stomp_size          : f32,
    stomp_force         : f32,
    dash_speed          : f32,
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
    .Health = { health = 1, render = { anim = { atlas_anim = .Upgrade_Health_Idle }, offset = MOD_RENDER_OFFSET} },
    .Speed = { move_speed = 0.5, render = { anim = { atlas_anim = .Upgrade_Mv_Speed_Idle }, offset = MOD_RENDER_OFFSET } },
    .Dash_Charge = { dash_charge = 1, render = { anim = { atlas_anim = .Upgrade_Dash_Charge_Idle }, offset = MOD_RENDER_OFFSET } },
    .Dash_Speed = { dash_speed = 0.5, render = { anim = { atlas_anim = .Upgrade_Dash_Speed_Idle }, offset = MOD_RENDER_OFFSET }},
    .Dash_Cd = { dash_cd = -0.1, render = { anim = { atlas_anim = .Upgrade_Dash_Cooldown_Idle }, offset = MOD_RENDER_OFFSET }},
    .Stomp_Size = { stomp_size = 2.0, render = { anim = { atlas_anim = .Upgrade_Stomp_Size_Idle }, offset = MOD_RENDER_OFFSET}},
    .Stomp_Force = { stomp_force = 1.0, render = { anim = { atlas_anim = .Upgrade_Stomp_Force_Idle }, offset = MOD_RENDER_OFFSET }},
    .Stomp_Cd = { stomp_cd = -0.1, render = { anim = { atlas_anim = .Upgrade_Stomp_Cooldown_Idle }, offset = MOD_RENDER_OFFSET}},
}

init_mod_renders :: proc() {
    for &mod, idx in global_player_mods {
        mod.kind = PlayerModKind(idx)
        mod.render.anim = create_atlas_anim(mod.render.anim.atlas_anim)
    }
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

    n_mod := global_player_mods[PlayerModKind(drop)]
    n_mod.render.anim = create_atlas_anim(.None)
    n_loot := Lootbox {
       modifier = n_mod,
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
            log.debugf("Collect Mod : %v", lb.modifier)
            lb^ = {}
            sa.append(&game_ctx.collision_ctx.free_lb, idx)
        } else if game_ctx.currency >= lb.cost {
            log.debug("Open Box!")
            game_ctx.currency -= lb.cost
            lb.open = true
            lb.cost = 0
            lb.render.anim = create_atlas_anim(.Chest_Open)
            lb.modifier.render = global_player_mods[lb.modifier.kind].render
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
