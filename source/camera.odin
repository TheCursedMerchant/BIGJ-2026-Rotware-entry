package game
import la "core:math/linalg"
import "core:math/rand"
import "core:log"

FALL_OFF_THRESHHOLD :: 0.1
CAMERA_SPEED :: 16.0
CAMERA_SNAP_DISTANCE :: 8.0
CAMERA_FOLLOW_MARGIN :: 320.0
CAMERA_MOVE_DELAY :: 0.5

Shake :: struct {
	active:    bool,
	intensity: f32,
	magnitude: f32,
	fall_off:  f32,
}

FollowCamera :: struct {
    using camera : Camera, 
    shake        : Shake,
    move_timer   : f32,
    move         : b8,
    zooming      : b8,
    target_zoom  : f32,
    zoom_speed   : f32,
}

update_camera :: proc (dt: f32) {
    camera := &game_ctx.camera
    camera.target = update_shake_pos(&camera.shake, camera.target)
    if camera.zooming {
        camera.zoom = la.lerp(camera.zoom, camera.target_zoom, 1.0 - la.exp(camera.zoom_speed * -dt))
        if la.abs(camera.zoom - camera.target_zoom) < 0.1 {
            camera.zoom = camera.target_zoom
            camera.zooming = false
        }
    }
}

update_camera_zoom :: proc(delta: f32) {
    log.debugf("Delta : %v", delta)
    game_ctx.camera.target_zoom += delta
    log.debugf("Camera target zoom : %v", game_ctx.camera.target_zoom)
    game_ctx.camera.zooming = true
}

update_camera_follow :: proc (game: ^Context, dt: f32) {
    camera := &game.camera
    player_center := get_render_center(game.player.render)
    distance_to_player := la.distance(camera.target, player_center)
    camera.target = update_shake_pos(&camera.shake, camera.target)
    if camera.move || camera.shake.active {
    	camera.target = la.lerp(
    		camera.target,
    		player_center,
    		1.0 - la.exp(CAMERA_SPEED * -dt),
    	)
    	if distance_to_player < CAMERA_SNAP_DISTANCE && !camera.shake.active {
    		game.camera.target = player_center
    		camera.move = false
    		camera.move_timer = CAMERA_MOVE_DELAY
    	}
    } else if distance_to_player > (f32(CAMERA_FOLLOW_MARGIN) / 2.0) {
    	camera.move_timer -= dt
    	if camera.move_timer <= 0.0 {
    		camera.move_timer = 0.0
    		camera.move = true
    	}
    }
}

update_shake_pos :: proc(shake: ^Shake, pos: [2]f32) -> [2]f32 {
	final_pos := pos
	if shake.active {
		x_offset := rand.float32_range(0, shake.intensity) - (shake.intensity / 2)
		y_offset := rand.float32_range(0, shake.intensity) - (shake.intensity / 2)
		final_pos += {x_offset, y_offset}
		shake.intensity *= shake.fall_off
		if shake.intensity <= FALL_OFF_THRESHHOLD {
			shake.intensity = 0
			shake.active = false
		}
	}

	return final_pos
}
