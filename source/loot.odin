package game
import "core:log"
import "core:math/rand"
import sa "core:container/small_array"
import rl "vendor:raylib"

MOD_RENDER_OFFSET :: [2]f32{ 0, -16 }
MOD_RENDER_DISPLAY_TIME : f32 : 1.5
MOD_TEXT_MOVE_SPEED : f32 : 8.0

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
    .Stomp_Force = { stomp_force = 5.0, render = { anim = { atlas_anim = .Upgrade_Stomp_Force_Idle }, offset = MOD_RENDER_OFFSET }},
    .Stomp_Cd = { stomp_cd = -0.1, render = { anim = { atlas_anim = .Upgrade_Stomp_Cooldown_Idle }, offset = MOD_RENDER_OFFSET}},
}

global_player_mod_strings := [PlayerModKind]string {
   .Health = "Health Up",
   .Speed = "Speed Up",
   .Dash_Charge = "Extra Charge",
   .Dash_Speed = "Dash Speed Up",
   .Dash_Cd = "Dash Cooldown Reduction",
   .Stomp_Size = "Stomp Size Up",
   .Stomp_Force = "Stomp Force Up",
   .Stomp_Cd = "Stom Cooldown Reduction",
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
        if lb.open {
            apply_player_modifer(player, lb.modifier)
            add_pick_up_render_at_pos(lb.modifier.kind, get_rect_center(lb.rect))
            lb^ = {}
            sa.append(&game_ctx.collision_ctx.free_lb, idx)
        } else if game_ctx.currency >= lb.cost {
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

// Center's relative to input pos
add_pick_up_render_at_pos :: proc(kind: PlayerModKind, pos: [2]f32) {
    text_dim := get_text_dimensions(10, global_player_mod_strings[kind])
    text_half_dim := text_dim / 2
    text_pos := pos - arr_cast(text_half_dim, f32)
    n_render := PickUpTextRender{
        text_draw = {
            content = global_player_mod_strings[kind],
            rect = { text_pos.x, text_pos.y, f32(text_dim.x), f32(text_dim.y) },
            color = rl.WHITE,
        },
        timer = { duration = MOD_RENDER_DISPLAY_TIME },
    }
    start_timer(&n_render.timer)
    sa.append(&game_ctx.pick_up_renders, n_render)
}

update_pick_up_renders :: proc(dt: f32) {
    for &render, idx in sa.slice(&game_ctx.pick_up_renders) {
        render.text_draw.rect.y -= MOD_TEXT_MOVE_SPEED * dt
        fcolor := rl_color_to_fcolor(render.text_draw.color)
        fcolor.a -= 8.0 * dt
        render.text_draw.color = fcolor_to_color(fcolor)
    }
}

update_pick_up_render_timers :: proc(dt: f32) {
    free_idx : sa.Small_Array(16, int)
    for &render, idx in sa.slice(&game_ctx.pick_up_renders) {
        if update_timer(&render.timer, dt) {
            sa.append(&free_idx, idx)
        }
    }

    #reverse for i in sa.slice(&free_idx) {
        sa.unordered_remove(&game_ctx.pick_up_renders, i)
    }
}
