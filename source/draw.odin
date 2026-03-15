package game

import rl "vendor:raylib"
import la "core:math/linalg"
import sa "core:container/small_array"
import "core:log"

BG_COLOR :: rl.Color{ 20, 30, 38, 255 }

draw_frame :: proc(dt: f32) {
    rl.BeginTextureMode(game_ctx.level_render)
	    rl.ClearBackground(rl.BLACK)
        paint_lvl_texture(dt)
    rl.EndTextureMode()

	screen_dim := [2]i32{ rl.GetScreenWidth(), rl.GetScreenHeight() }
	src_rect := rl.Rectangle{0, 0, f32(game_ctx.level_render.texture.width), f32(-game_ctx.level_render.texture.height)}
	dest_rect := rl.Rectangle{0, 0, f32(screen_dim.x), f32(screen_dim.y)}

    rl.BeginDrawing()
	    rl.DrawTexturePro(game_ctx.level_render.texture, src_rect, dest_rect, {}, 0.0, rl.WHITE)
    rl.EndDrawing()
}

paint_lvl_texture :: proc(dt: f32) {
    rl.BeginMode2D(game_ctx.camera)
        player := &game_ctx.player
        // Draw Tiles
        for tiles, x in game_ctx.level.tiles {
            for tile in tiles {
                draw_pixel_perfect_render(tile.render)
            }
        }
        
        // Draw Collision Bodies
        for body in sa.slice(&game_ctx.collision_ctx.static) { box_draw(body) }
        for body in sa.slice(&game_ctx.collision_ctx.box_areas) { box_draw(body) }
        kb_draw_pos : [2]f32
        for &body in sa.slice(&game_ctx.collision_ctx.kick_boxes) { 
            kb_draw_pos = interpolate_pos(body.prev_pos, body.box.rectangle.xy, dt)
            box_draw_at_pos(body.box, kb_draw_pos) 
        }

        //Draw Enemies
        for &enemy in game_ctx.enemies.active {
            kb_draw_pos = interpolate_pos(enemy.kb.prev_pos, enemy.kb.box.rectangle.xy, dt)
            box_draw_at_pos(enemy.kb.box, kb_draw_pos)
            rl.DrawRectangleRec(rect_to_rectangle(enemy.attack_box.rect), fcolor_to_color(enemy.attack_box.current_color))
            enemy.attack_box.current_color = fade_color(enemy.attack_box.current_color, 20.0)
        }

        // Draw Ents/Player
        #reverse for &render, idx in sa.slice(&player.after_images) { 
            draw_fade_render(&render, 20.0) 
            if render.fcolor.a == 0 { sa.unordered_remove(&player.after_images, idx) }
        }
        rl.DrawRectangleRec(rect_to_rectangle(player.stomp.hitbox.rect), fcolor_to_color(player.stomp.hitbox.current_color))
        player.stomp.hitbox.current_color = fade_color(player.stomp.hitbox.current_color, 20.0)
        player.render.pos = interpolate_pos(player.kinematic_body.prev_pos, get_pos(player^), dt)
        draw_pixel_perfect_render(player.render)
        // DEBUG Player collision Box
//        rl.DrawRectangleRec(box_to_rect(game_ctx.player.kinematic_body.box), rl.RED)
    rl.EndMode2D()
}

draw_fade_render :: proc(render: ^ColorRender, fade_amount : f32) {
    render.fcolor = fade_color(render.fcolor, fade_amount)
    render.fcolor.rg -= { fade_amount, fade_amount }
    tint := rl.WHITE
    tint.rga = arr_cast(render.fcolor.rga, u8)
    draw_pixel_perfect_render(render.render, tint)
}

fade_color :: proc(fcolor : [4]f32, amount : f32) -> [4]f32 {
    return la.max(fcolor.a - amount, 0)
}

draw_pixel_perfect_render :: proc(render: Render, tint: rl.Color = rl.WHITE) {
    draw_pos := la.round(render.pos + render.offset) 
    draw_atlas_anim_at_pos(
        render.anim,
        draw_pos,
        {},
        game_ctx.atlas,
        tint,
    )
}

draw_atlas_anim_at_pos :: proc(anim: Animation, pos: [2]f32, offset: [2]f32, atlas: Texture, tint: rl.Color) {
	anim_texture := anim_atlas_texture(anim)
	atlas_rect := anim_texture.rect
	atlas_offset := [2]f32{anim_texture.offset_left, anim_texture.offset_top}
	dest := Rect {
		pos.x + atlas_offset.x + offset.x,
		pos.y + atlas_offset.y + offset.y,
		anim_texture.rect.width,
		anim_texture.rect.height,
	}
	rl.DrawTexturePro(atlas, atlas_rect, dest, {}, 0, tint)
}

interpolate_pos :: proc(prev, current: [2]f32, dt : f32) -> [2]f32 {
    return la.lerp(prev, current, dt)
}

get_render_center :: proc(render: Render) -> [2]f32 {
    anim_texture := anim_atlas_texture(render.anim)
    half_dim := [2]f32{ anim_texture.rect.width, anim_texture.rect.height } / 2.0 
    return render.pos + render.offset + half_dim + { anim_texture.offset_left, anim_texture.offset_top }
}

fcolor_to_color :: proc(fcolor : [4]f32) -> rl.Color {
    color : rl.Color
    color.rgba = arr_cast(fcolor, u8).rgba
    return color
}
