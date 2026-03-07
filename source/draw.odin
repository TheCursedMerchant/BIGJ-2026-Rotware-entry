package game

import rl "vendor:raylib"
import la "core:math/linalg"

draw_frame :: proc(dt: f32) {
    rl.BeginTextureMode(game_ctx.level_render)
	    rl.ClearBackground({0, 120, 153, 255})
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
        for body in game_ctx.collision_bodies {
            box_draw(body.box)
        }
        player.render.pos = interpolate_pos(player.prev_pos, get_pos(player^), dt)
        draw_pixel_perfect_render(player.render)
        // DEBUG Player collision Box
        //rl.DrawRectangleRec(box_to_rect(game_ctx.player.kinematic_body.collision_body.box), rl.RED)
    rl.EndMode2D()
}

draw_pixel_perfect_render :: proc(render: Render) {
    draw_pos := la.round(render.pos + render.offset) 
    draw_atlas_anim_at_pos(
        render.anim,
        draw_pos,
        {},
        game_ctx.atlas,
    )
}

draw_atlas_anim_at_pos :: proc(anim: Animation, pos: [2]f32, offset: [2]f32, atlas: Texture) {
	anim_texture := anim_atlas_texture(anim)
	atlas_rect := anim_texture.rect
	atlas_offset := [2]f32{anim_texture.offset_left, anim_texture.offset_top}
	dest := Rect {
		pos.x + atlas_offset.x + offset.x,
		pos.y + atlas_offset.y + offset.y,
		anim_texture.rect.width,
		anim_texture.rect.height,
	}
	rl.DrawTexturePro(atlas, atlas_rect, dest, {}, 0, rl.WHITE)
}

interpolate_pos :: proc(prev, current: [2]f32, dt : f32) -> [2]f32 {
    return la.lerp(prev, current, dt)
}

get_render_center :: proc(render: Render) -> [2]f32 {
    anim_texture := anim_atlas_texture(render.anim)
    half_dim := [2]f32{ anim_texture.rect.width, anim_texture.rect.height } / 2.0 
    return render.pos + render.offset + half_dim + { anim_texture.offset_left, anim_texture.offset_top }
}
