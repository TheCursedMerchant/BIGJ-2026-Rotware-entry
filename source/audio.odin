package game
import rl "vendor:raylib"
import "core:math/rand"

Audio :: struct {
    volume : f32
}

AudioClip :: struct {
    sound   : rl.Sound,
    path    : string,
}

AudioClipName :: enum {
    Damage,
    Death,
    Dash,
    Kick_Box,
    Pick_Up,
    Stomp,
    Explosion,
    Coin,
}

global_audio_clips := [AudioClipName]AudioClip {
    .Damage = { path =  "../assets/damage.wav" },
    .Death = { path = "../assets/die.wav" },
    .Dash = { path = "../assets/dash.wav" },
    .Kick_Box = { path = "../assets/kick_box.wav" },
    .Pick_Up = { path = "../assets/pick_up.wav" },
    .Stomp = { path = "../assets/left_stomp.wav" },
    .Explosion = { path = "../assets/explosion.wav" },
    .Coin = { path = "../assets/coin.wav" }
}

init_sounds :: proc(ctx: ^Context) {
    for &clip in global_audio_clips {
        clip.sound = rl.LoadSound(rl.TextFormat("%s", clip.path))
        rl.SetSoundVolume(clip.sound, 0.5)
    }
}

set_volume :: proc(audio: ^Audio, val : f32) {
    audio.volume = val
    for &clip in global_audio_clips {
        rl.SetSoundVolume(clip.sound, val)
    }
}

play_sound_rand_pitch :: proc (name: AudioClipName) {
    pitch := rand.float32_range(0.75, 1.25)
    new_sound := global_audio_clips[name].sound
    rl.SetSoundPitch(new_sound, pitch)
    rl.PlaySound(new_sound)
}
