package game 

import rl "vendor:raylib"

ActionInputKind :: enum {
    Left_Stomp,
    Right_Stomp,
    Dash,
}

ActionInput :: struct {
    key : rl.KeyboardKey,
    kind : ActionInputKind,
}

DirectionInputKind :: enum {
    Up,
    Down,
    Left,
    Right,
}

DirectionInput :: struct {
    key : rl.KeyboardKey,
    dir : [2]int,
    kind : DirectionInputKind,
}

// NOTE: This is a constant but odin doesn't like these so instead its global
// do not mutate!!!
dir_inputs := [DirectionInputKind]DirectionInput {
    .Up = { .W, {0, -1}, .Up },
    .Down = { .S, {0, 1}, .Down },
    .Left = { .A, {-1, 0}, .Left },
    .Right = { .D, {1, 0}, .Right },
}

action_inputs := [ActionInputKind]ActionInput {
    .Left_Stomp = { .H, .Left_Stomp },
    .Right_Stomp = { .J, .Right_Stomp },
    .Dash = { .K, .Dash },
}

// TODO: Add versions that take regular inputs that don't 
// have direction associated to them in this proc group
is_input_pressed :: proc {
    is_input_pressed_dir,
    is_input_pressed_action,
}

is_input_down :: proc {
    is_input_down_dir,
    is_input_down_action,
}

is_input_pressed_dir :: proc(input : DirectionInput) -> bool {
    return rl.IsKeyPressed(input.key)
}

is_input_down_dir :: proc(input : DirectionInput) -> bool {
    return rl.IsKeyDown(input.key)
}

is_input_pressed_action :: proc(input : ActionInput) -> bool {
    return rl.IsKeyPressed(input.key)
}

is_input_down_action :: proc(input : ActionInput) -> bool {
    return rl.IsKeyDown(input.key)
}
