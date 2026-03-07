package tests

import game "../../source"
import "core:testing"
import rl "vendor:raylib"
import "core:log"


@(test)
utest_box_resize :: proc(t: ^testing.T) {
    box := game.box_create(
        rect = {10, 10, 20, 20},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    game.box_resize(&box, 2)
    testing.expect_value(t, box.rectangle.x, 9)
    testing.expect_value(t, box.rectangle.y, 9)
    testing.expect_value(t, box.rectangle.z, 22)
    testing.expect_value(t, box.rectangle.w, 22)
}

@(test)
utest_box_smallest_containing_position :: proc(t: ^testing.T) {
    bigger_box := game.box_create(
        rect = {10, 10, 20, 20},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    smaller_box := game.box_create(
        rect = {17, 17, 5, 5},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    smallest_box := game.box_create(
        rect = {19,19,2,2},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    arr := [3]game.Box{bigger_box, smallest_box, smaller_box}
    position := game.Rectangle{20,20,0,0}
    index,found := game.box_smallest_containing_position(position, arr[:])

    testing.expect_value(t, found, true)
    testing.expect_value(t, index, 1)
}

@(test)
utest_boxes_all_containing_position :: proc(t: ^testing.T) {
    box1 := game.box_create(
        rect = {0,0,100,100},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    box2 := game.box_create(
        rect = {10,10,80,80},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    box3 := game.box_create(
        rect = {20,20,60,60},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    box4 := game.box_create(
        rect = {30,30,40,40},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    box5 := game.box_create(
        rect = {40,40,20,20},
        thick = 1,
        color = rl.BLACK,
        state = .None
    )
    position1 := game.Rectangle{50,50,0,0}
    position2 := game.Rectangle{25,25,0,0}
    arr := [5]game.Box{box1, box2, box3, box4, box5}

    test_arr1 := game.boxes_all_containing_position(position1, arr[:])
    testing.expect_value(t, len(test_arr1), 5)

    test_arr2 := game.boxes_all_containing_position(position2, arr[:])
    testing.expect_value(t, len(test_arr2), 3)
}

@(test)
utest_box_state_swap :: proc(t: ^testing.T) {
    box1 := game.box_create(
        rect = {0,0,100,100},
        thick = 1,
        color = rl.BLACK,
        state = .Man
    )
    box2 := game.box_create(
        rect = {10,10,80,80},
        thick = 1,
        color = rl.BLACK,
        state = .Woman
    )
    position1 := game.Rectangle{50,50,0,0}
    arr := []game.Box{box1, box2}

    ok := game.box_state_swap(position1, arr)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, arr[0].state, game.Box_State.Woman)
    testing.expect_value(t, arr[1].state, game.Box_State.Man)
}