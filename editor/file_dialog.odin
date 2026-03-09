package editor

import "core:os"
import "core:log"
import s "core:strings"
import sa "core:container/small_array"
import rl "vendor:raylib"

import "file"

FileDialogOption :: enum { Init }

FileDialog :: struct {
    fis                     : sa.Small_Array(file.MAX_FILE_COUNT, os.File_Info),
    options                 : bit_set[FileDialogOption],
    text_button_template    : TextButton,
    using draw              : Drawable,
    inner_padding           : [2]f32,
    item_v_padding          : f32,
    show                    : b8,
}

load_fis_from_path :: proc(file_dialog: ^FileDialog, path: string) {
	level_dir, level_dir_error := os.open(path)
	if level_dir_error != nil {
		log.errorf("No directiory found : %v", level_dir_error)
	}

	fis, _ := os.read_dir(level_dir, file.MAX_FILE_COUNT, context.allocator)
	defer { 
        os.file_info_slice_delete(fis, context.allocator)
	    os.close(level_dir)
    }

	t_info: os.File_Info
	for f in fis {
		t_info = {
			size              = f.size,
			mode              = f.mode,
            type              = f.type,
			access_time       = f.access_time,
			creation_time     = f.creation_time,
			modification_time = f.modification_time,
			name              = s.clone(f.name),
			fullpath          = s.clone(f.fullpath),
		}
		sa.append(&file_dialog.fis, t_info)
	}
}

delete_file_dialog :: proc(file_dialog: ^FileDialog) {
    if .Init in file_dialog.options {
		for f in sa.slice(&file_dialog.fis) {
			delete(f.name)
			delete(f.fullpath)
		}
        file_dialog.fis = {}
	}
	file_dialog.options = {}
}

draw_file_dialog :: proc(fd: ^FileDialog) {
    rl.DrawRectangleRec(rect_to_rectangle(fd.rect), rl.BLACK)
    draw_rectangle_lines(fd)
    n_btn : TextButton
    for info, idx in sa.slice(&fd.fis) {
        n_btn = fd.text_button_template
        n_btn.rect.xy = fd.rect.xy + fd.inner_padding
        n_btn.rect.y += f32(idx) * (n_btn.rect.w + fd.item_v_padding)
        n_btn.text.content = info.name
        n_btn.text.rect.xy = n_btn.rect.xy + { 16, 0 }
        draw_text_button(n_btn)
    }
}

is_pos_in_file_button :: proc(fd: ^FileDialog, pos: [2]f32) -> (os.File_Info, bool) {
    n_btn : TextButton
    if pos_in_rect(pos, fd.rect) {
        for info, idx in sa.slice(&fd.fis) {
            n_btn = fd.text_button_template
            n_btn.rect.xy = fd.rect.xy + fd.inner_padding
            n_btn.rect.y += f32(idx) * (n_btn.rect.w + fd.item_v_padding)
            if pos_in_rect(pos, n_btn.rect) {
                return info, true
            }
        }
    }
    return {}, false
}

on_file_button_click :: proc(fd: ^FileDialog, info : os.File_Info) {}
