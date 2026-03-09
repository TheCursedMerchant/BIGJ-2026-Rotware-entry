package game

import "core:encoding/json"
import "core:log"

serialize_game_object :: proc(obj : $T, name : string, dir: string) -> bool {
    json_data, err := json.marshal(obj, { pretty = true, use_enum_names = true }) 
    defer delete(json_data)

    if err != nil {
        log.errorf("Unable to marshal JSON : %v", err)
        return false
    }

    write_path := s.concatenate({ dir, name, ".json" })
    defer delete(write_path)
    log.infof("Writing to path : %v", write_path)
    ok := write_entire_file(write_path, json_data)
 
    if !ok {
        log.errorf("Unable to write file : %v", ok)
        return false
    }

    log.info("Written token list success")
    return true
}

deserialize_game_object :: proc($T: typeid, path: string) -> T {
    data, ok := read_entire_file(path, context.allocator)
    if !ok {
        log.errorf("File failed to load!")
        return {}
    }
    defer delete(data)

    out : T
    unmarshal_err := json.unmarshal(data, &out)
 
    if unmarshal_err != nil {
        log.errorf("Failed to marshal the file with error : %v", unmarshal_err)
        return {}
    }

    log.infof("Marshalled %v successfully", path)

    return out
}
