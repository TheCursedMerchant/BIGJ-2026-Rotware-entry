package game

import rl "vendor:raylib"
import la "core:math/linalg"
import sa "core:container/small_array"
import "core:log"

BG_COLOR :: rl.Color{ 20, 30, 38, 255 }
RED :: [4]f32 { 255, 0, 0, 255 }
GREEN :: [4]f32 { 0, 255, 0, 255 }
BLUE :: [4]f32 { 0, 0, 255, 255 }
WHITE :: [4]f32 { 255, 255, 255, 255 }

BUTTON_TEXT_SIZE :: 10.0

Render :: struct {
    anim    : Animation,
    pos     : [2]f32,
    offset  : [2]f32,
}

ColorRender :: struct {
    render : Render,
    fcolor : [4]f32,
}

ChargeRenders :: struct {
    ready           : Render,
    inactive        : Render,
}

MeterRenderRect :: enum { Bg, Mid, Fg }
MeterRender :: struct {
    rects   : [MeterRenderRect]Rectangle,
    colors  : [MeterRenderRect]rl.Color,
    per     : f32,
}

TextButton :: struct {
    using draw      : Drawable,
    text            : DrawableText,
    is_selected     : b8,
}

Drawable :: struct {
    rect : Rectangle,
    color : rl.Color,
    alt_color : rl.Color,
}

DrawableText :: struct {
    using draw  : Drawable,
    content     : string, 
}

PickUpTextRender :: struct {
    text_draw   : DrawableText,
    timer       : Timer,
}

draw_frame :: proc(dt: f32, vdt: f32) {
	screen_dim := [2]i32{ rl.GetScreenWidth(), rl.GetScreenHeight() }
    screen_center := screen_dim / 2
    rl.BeginTextureMode(game_ctx.level_render)
	    rl.ClearBackground(rl.BLACK)
        paint_lvl_texture(dt, vdt)
        draw_health_box(&game_ctx.player, dt) 
        rl.DrawText(rl.TextFormat("%.2f", game_ctx.timers[.Spawn_Wave].time_left), 32, 16, 10.0, rl.WHITE)
        rl.DrawText(rl.TextFormat("Currency : %i", game_ctx.currency), 32, 48, 10.0, rl.WHITE)
        rl.DrawText(rl.TextFormat("Difficulty : %i", game_ctx.difficulty_lvl), 32, 64, 10.0, rl.WHITE)
        for lb in sa.slice(&game_ctx.collision_ctx.loot_boxes) {
            draw_pos := rl.GetWorldToScreen2D(lb.rect.xy, game_ctx.camera) + { -4, -8 }
            if lb.cost > 0 { rl.DrawText(rl.TextFormat("$%i", lb.cost), i32(draw_pos.x), i32(draw_pos.y), 10, rl.WHITE) }
        }
        for render in sa.slice(&game_ctx.pick_up_renders) {
            draw_pos := rl.GetWorldToScreen2D(render.text_draw.rect.xy, game_ctx.camera) + { -4, -8 }
            rl.DrawText(rl.TextFormat("%s", render.text_draw.content), i32(draw_pos.x), i32(draw_pos.y), 10.0, render.text_draw.color)
        }

        if game_ctx.menu.show do draw_menu_buttons(game_ctx.menu)
    rl.EndTextureMode()

	src_rect := rl.Rectangle{0, 0, f32(game_ctx.level_render.texture.width), f32(-game_ctx.level_render.texture.height)}
	dest_rect := rl.Rectangle{0, 0, f32(screen_dim.x), f32(screen_dim.y)}

    rl.BeginDrawing()
	    rl.DrawTexturePro(game_ctx.level_render.texture, src_rect, dest_rect, {}, 0.0, rl.WHITE)
        rl.DrawFPS(rl.GetScreenWidth() - 128, 16)
    rl.EndDrawing()
}

paint_lvl_texture :: proc(dt: f32, vdt: f32) {
    rl.BeginMode2D(game_ctx.camera)
        player := &game_ctx.player
        // Draw Tiles
        for tiles, x in game_ctx.level.tiles {
            for tile in tiles {
                draw_pixel_perfect_render(tile.render)
            }
        }

        //Draw loot boxes
        for &lb in sa.slice(&game_ctx.collision_ctx.loot_boxes) {
            lb.render.pos = lb.rect.xy
            lb.modifier.render.pos = lb.rect.xy
            update_atlas_anim(&lb.render.anim, vdt)
            draw_pixel_perfect_render(lb.render)
            update_atlas_anim(&lb.modifier.render.anim, vdt)
            draw_pixel_perfect_render(lb.modifier.render)
        }

        for &p in sa.slice(&game_ctx.collision_ctx.health_pickups) {
            p.render.pos = p.rect.xy
            draw_pixel_perfect_render(p.render)
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

        //Draw AOE Boxes
        for &pattern in sa.slice(&game_ctx.pattern_master.patterns) {
            draw_hitbox_pattern(&pattern)
        }

        //Draw Explosions
        for &e in sa.slice(&game_ctx.explosion_rects) {
            rl.DrawRectangleRec(rect_to_rectangle(e.rect), fcolor_to_color(e.color))
            e.color = fade_color(e.color, 20.0)
        }

        // Draw Ents/Player
        player.render.pos = interpolate_pos(player.kinematic_body.prev_pos, get_pos(player^), dt)

        meter_draw_pos := player.render.pos + { -2, -16 }
        player.stomp.meter.per = game_ctx.timers[.Player_Stomp].time_left / game_ctx.timers[.Player_Stomp].duration
        if game_ctx.timers[.Player_Stomp].running {
            draw_stomp_meter_at_pos(&player.stomp.meter, meter_draw_pos)
        }

        if player.dash.charges < player.dash.max_charges {
            update_dash_draw_pos(player)
            for i in 0..<player.dash.max_charges {
                player.dash.renders.inactive.pos = player.dash.start_pos + ({ 5, 0 } * f32(i))
                draw_pixel_perfect_render(player.dash.renders.inactive)
            }

            for i in 0..<player.dash.charges {
                player.dash.renders.ready.pos = player.dash.start_pos + ({ 5, 0 } * f32(i))
                draw_pixel_perfect_render(player.dash.renders.ready)
            }
        }

        rl.DrawRectangleRec(rect_to_rectangle(player.stomp.hitbox.rect), fcolor_to_color(player.stomp.hitbox.current_color))
        update_atlas_anim(&player.render.anim, vdt)
        player.stomp.hitbox.current_color = fade_color(player.stomp.hitbox.current_color, 20.0)
        draw_pixel_perfect_render(player.render)
        // DEBUG Player collision Box
        //rl.DrawRectangleRec(box_to_rect(game_ctx.player.kinematic_body.box), rl.RED)

        #reverse for &render, idx in sa.slice(&player.after_images) { 
            draw_fade_render(&render, 20.0) 
            if render.fcolor.a == 0 { sa.unordered_remove(&player.after_images, idx) }
        }
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

draw_text_button :: proc(button : TextButton) {
    m_btn_draw := button.draw
    if button.is_selected do m_btn_draw.color = button.alt_color
    rl.DrawRectangleRec(rect_to_rectangle(m_btn_draw.rect), rl.BLACK)
    rl.DrawRectangleLinesEx(rect_to_rectangle(m_btn_draw.rect), 1.0, rl.WHITE)
    text_draw := button.text.draw
    rl.DrawText(rl.TextFormat("%s", button.text.content), i32(text_draw.rect.x), i32(text_draw.rect.y), i32(text_draw.rect.w), text_draw.color)
}

draw_menu_buttons :: proc(menu: ^Menu) {
    for kind in sa.slice(&menu.display_buttons) {
        draw_text_button(menu.buttons[kind])
    }
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

draw_health_box :: proc(player: ^Player, dt: f32) {
    scale : f32 = 10.0
    screen_dim := arr_cast([2]i32{ rl.GetScreenWidth(), rl.GetScreenHeight()}, f32)
    draw_pos := [2]f32{ 32, 32 } //* game_ctx.res_scale_factor
    bg_rect := Rectangle { draw_pos.x, draw_pos.y, player.max_health * scale, 4 }
    //bg_rect.zw *= game_ctx.res_scale_factor
    if !game_ctx.timers[.Player_Damaged].running {
        player.prev_health = la.lerp(player.prev_health, player.health, dt * 0.5)
    }
    mid_rect := Rectangle { draw_pos.x, draw_pos.y, player.prev_health * scale, 4 }
    //mid_rect.zw *= game_ctx.res_scale_factor
    top_rect := Rectangle { draw_pos.x, draw_pos.y, player.health * scale, 4 }
    //top_rect.zw *= game_ctx.res_scale_factor
    rl.DrawRectangleRec(rect_to_rectangle(bg_rect), rl.DARKGRAY)
    rl.DrawRectangleRec(rect_to_rectangle(mid_rect), rl.RED)
    rl.DrawRectangleRec(rect_to_rectangle(top_rect), rl.GREEN)
}

draw_stomp_meter_at_pos :: proc(meter: ^MeterRender, pos : [2]f32) {
    bg := &meter.rects[.Bg]
    bg.xy = pos
    rl.DrawRectangleRec(rect_to_rectangle(bg^), meter.colors[.Bg])
    
    fg := &meter.rects[.Fg]
    fg.xy = pos
    fg.z = bg.z - (meter.per * bg.z)
    rl.DrawRectangleRec(rect_to_rectangle(fg^), meter.colors[.Fg])
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

text_button :: proc(pos: [2]f32, text: string, padding : [2]f32 = {}) -> TextButton {
    button : TextButton
    button.text.content = text
    text_width := f32(rl.MeasureText(rl.TextFormat("%s", text), BUTTON_TEXT_SIZE)) 
    button.rect = Rectangle {0, 0, text_width + padding.x, BUTTON_TEXT_SIZE + padding.y }
    button.rect.xy = pos
    button.text.color = rl.WHITE
    button.text.rect.xy = button.rect.xy
    button.text.rect.z = text_width
    button.text.rect.w = BUTTON_TEXT_SIZE
    button.color = rl.WHITE
    button.alt_color = rl.BLACK
    center_rect_in_rect(&button.text.rect, button.rect)
    return button
}

// Utils
center_rect_in_rect :: proc(a : ^Rectangle, b : Rectangle) {
    a.xy += get_rect_center(b) - get_rect_center(a^)
}

get_text_dimensions :: proc(font_size : i32, text: string) -> [2]i32 {
    width := rl.MeasureText(rl.TextFormat("%s", text), font_size)
    return { width, font_size }
}

rl_color_to_fcolor :: proc (color : rl.Color) -> [4]f32 {
    return { f32(color.r), f32(color.b), f32(color.g), f32(color.a) }
}
