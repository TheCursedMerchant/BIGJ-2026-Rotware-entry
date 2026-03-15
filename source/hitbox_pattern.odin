package game

import sa "core:container/small_array"
import rl "vendor:raylib"
import "core:log"

MAX_HITBOX_PATTERNS :: 16
MAX_HITBOXES_IN_PATTERN :: 4

PatternHitboxSa :: sa.Small_Array(MAX_HITBOXES_IN_PATTERN, PatternHitbox)

PatternHitbox :: struct {
    render      : HitBoxRender,
    rel_pos     : [2]f32,
    timer       : Timer,
}

HitboxPattern :: struct {
    hitboxes        : PatternHitboxSa,
    damage          : f32,
    running_boxes   : int, 
}

HitboxPatternMaster :: struct {
    patterns : sa.Small_Array(MAX_HITBOX_PATTERNS, HitboxPattern)
}

hitbox_pattern_single :: proc(render : HitBoxRender, damage : f32 = 1.0, duration : f32 = 1.0) -> (pattern : HitboxPattern) {
    boxes : PatternHitboxSa
    sa.append(&boxes, PatternHitbox{ render = render, timer = { duration = duration, time_left = duration } })
    return { hitboxes = boxes, damage = damage }
}

spawn_hitbox_pattern_at_pos :: proc(pattern: ^HitboxPattern, pos : [2]f32) {
    for &box in sa.slice(&pattern.hitboxes) {
        box.render.rect.xy = pos + box.rel_pos
        box.render.current_color = box.render.color
        start_timer(&box.timer)
        pattern.running_boxes += 1
    }
}

update_hitbox_pattern_timers :: proc(pattern: ^HitboxPattern, dt: f32) {
    for &box, idx in sa.slice(&pattern.hitboxes) {
        if update_timer(&box.timer, dt) {
            box.timer.time_left = box.timer.duration
            if rectangle_overlap(box.render.rect, game_ctx.player.kinematic_body.box.rectangle) {
                log.debugf("Damaging player : %v", pattern.damage)
            }
            pattern.running_boxes -= 1
            if pattern.running_boxes <= 0 {
                start_timer(&game_ctx.timers[.Spawn_Pattern])
            }
        }
    }
}

draw_hitbox_pattern :: proc(pattern : ^HitboxPattern) {
    time_ratio : f32
    for &box in sa.slice(&pattern.hitboxes) {
        time_ratio = box.timer.time_left / box.timer.duration
        box.render.current_color.a = 255 * (1.0 - time_ratio)
        draw_hitbox_render(box.render)
    }
}

draw_hitbox_render :: proc(render: HitBoxRender) {
    rl.DrawRectangleRec(rect_to_rectangle(render.rect), fcolor_to_color(render.current_color))
}
