package file

import "core:encoding/json"
import "core:encoding/cbor"
import "core:log"
import "core:os"
import s "core:strings"

CONFIG_BASE_PATH :: "resources/config/"
FILE_ENDING :: ".json"
MAX_FILE_COUNT :: 100

serialize_game_object :: proc(obj : $T, name : string, dir: string) -> bool {
    json_data, err := json.marshal(obj, { pretty = true, use_enum_names = true }) 
    defer delete(json_data)

    if err != nil {
        log.errorf("Unable to marshal JSON : %v", err)
        return false
    }

    write_path := s.concatenate({ dir, name, FILE_ENDING })
    defer delete(write_path)
    log.infof("Writing to path : %v", write_path)
    werr := os.write_entire_file_from_string(write_path, json_data)
 
    if werr != nil {
        log.errorf("Unable to write file : %v", err)
        return false
    }

    log.info("Written token list success")
    return true
}

deserialize_game_object :: proc($T: typeid, path: string) -> T {
    data, ok := os.read_entire_file_from_path(path, context.allocator)
    if ok != nil {
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

// Cbor
serialize_game_object_cbor :: proc(obj : $T, name : string, dir: string) -> bool {
    cbor_data, err := cbor.marshal(obj, cbor.ENCODE_FULLY_DETERMINISTIC) 
    defer delete(cbor_data)

    if err != nil {
        log.errorf("Unable to marshal CBOR : %v", err)
        return false
    }

    write_path := s.concatenate({ dir, name, ".cbor" })
    defer delete(write_path)
    log.infof("Writing to path : %v", write_path)
    werr := os.write_entire_file_from_bytes(write_path, cbor_data)
 
    if werr != nil {
        log.errorf("Unable to write file : %v", err)
        return false
    }

    log.info("Written token list success")
    return true
}

deserialize_game_object_cbor :: proc($T: typeid, path: string) -> T {
    data, ok := os.read_entire_file_from_path(path, context.allocator)
    if  ok != nil {
        log.errorf("File failed to load with err : %v", ok)
        return {}
    }
    defer delete(data)

    out : T
    unmarshal_err := cbor.unmarshal(string(data), &out) 
    if unmarshal_err != nil {
        log.errorf("Failed to marshal the file with error : %v", unmarshal_err)
        return {}
    }

    log.infof("Marshalled %v successfully", path)

    return out
}
