// Stable runtime boundary shared with the existing Lanius Wasm hosts.
//
// The table is deliberately data-oriented: target lowering maps every
// semantic host operation to one ordinary Wasm call, while this module owns
// the import names and canonical function signatures.  No host operation
// owns a bespoke byte-emission fragment.

import codegen.lowering_ir;

static const uint WASM_HOST_IMPORT_COUNT = 42u;
static const uint WASM_HOST_TYPE_COUNT = 10u;
static const uint WASM_HOST_TYPE_ENTRIES_LENGTH = 132u;
static const uint WASM_HOST_IMPORT_SECTION_LENGTH = 712u;
static const uint WASM_HOST_INVALID = 0xffffffffu;
static const uint WASM_HOST_I32 = 0x7fu;
static const uint WASM_HOST_I64 = 0x7eu;

uint wasm_host_import_for_service(uint service)
{
    if (service == HOST_SERVICE_OPEN_READ_PATH) return 28u;
    if (service == HOST_SERVICE_OPEN_WRITE_PATH) return 29u;
    if (service == HOST_SERVICE_READ_I32) return 24u;
    if (service == HOST_SERVICE_WRITE_TEXT) return 30u;
    if (service >= HOST_SERVICE_WRITE_I32 && service <= HOST_SERVICE_WRITE_NEWLINE)
        return service + 1u;
    if (service == HOST_SERVICE_CLOSE_FILE) return 14u;
    if (service == HOST_SERVICE_EXIT) return 41u;
    if (service == HOST_SERVICE_SECURE_U32) return 5u;
    if (service >= HOST_SERVICE_ALLOC && service <= HOST_SERVICE_DEALLOC)
        return service - 9u;
    if (service >= HOST_SERVICE_ARGC && service <= HOST_SERVICE_ARG_READ)
        return service - 31u;
    if (service >= HOST_SERVICE_UNIX_SECONDS && service <= HOST_SERVICE_CURRENT_DIR_READ)
        return service - 30u;
    if (service >= HOST_SERVICE_VAR_COUNT && service <= HOST_SERVICE_VAR_READ)
        return service - 29u;
    if (service >= HOST_SERVICE_CLOSE && service <= HOST_SERVICE_OPEN_APPEND)
        return service - 29u;
    if (service == HOST_SERVICE_WRITE_STDOUT) return 1u;
    if (service >= HOST_SERVICE_WRITE_STDERR && service <= HOST_SERVICE_READ_STDIN)
        return service - 30u;
    if (service >= HOST_SERVICE_FILL_SECURE_BYTES && service <= HOST_SERVICE_ALLOC_FAILED)
        return service - 22u;
    return WASM_HOST_INVALID;
}

uint wasm_host_type_param_count(uint type_i)
{
    static const uint counts[10] = {1u, 0u, 1u, 2u, 3u, 4u, 3u, 0u, 1u, 2u};
    return type_i < WASM_HOST_TYPE_COUNT ? counts[type_i] : 0u;
}

uint wasm_host_type_result_count(uint type_i)
{
    return type_i >= 1u && type_i <= 5u ? 1u : 0u;
}

uint wasm_host_type_entry_length(uint type_i)
{
    return 11u + wasm_host_type_param_count(type_i) +
        wasm_host_type_result_count(type_i);
}

uint wasm_host_type_entry_offset(uint type_i)
{
    static const uint offsets[11] =
        {0u, 12u, 24u, 37u, 51u, 66u, 82u, 96u, 107u, 119u, 132u};
    return offsets[min(type_i, WASM_HOST_TYPE_COUNT)];
}

uint wasm_host_leb5_byte(uint value, uint byte_i)
{
    uint part = (value >> (byte_i * 7u)) & 0x7fu;
    return byte_i < 4u ? part | 0x80u : part;
}

uint wasm_host_type_entry_byte(uint type_i, uint byte_i)
{
    uint params = wasm_host_type_param_count(type_i);
    uint results = wasm_host_type_result_count(type_i);
    if (byte_i == 0u) return 0x60u;
    if (byte_i <= 5u) return wasm_host_leb5_byte(params, byte_i - 1u);
    uint value_i = byte_i - 6u;
    if (value_i < params)
        return type_i == 0u ? WASM_HOST_I64 : WASM_HOST_I32;
    uint result_count_pos = 6u + params;
    if (byte_i < result_count_pos + 5u)
        return wasm_host_leb5_byte(results, byte_i - result_count_pos);
    return results != 0u ? WASM_HOST_I32 : 0u;
}

uint wasm_host_type_entries_byte(uint pos)
{
    for (uint type_i = 0u; type_i < WASM_HOST_TYPE_COUNT; type_i += 1u)
    {
        uint start = wasm_host_type_entry_offset(type_i);
        uint end = wasm_host_type_entry_offset(type_i + 1u);
        if (pos >= start && pos < end)
            return wasm_host_type_entry_byte(type_i, pos - start);
    }
    return 0u;
}

uint wasm_host_import_name_offset(uint import_i)
{
    static const uint offsets[43] = {
        0u, 9u, 21u, 25u, 32u, 40u, 50u, 62u, 78u, 93u, 102u,
        113u, 125u, 132u, 140u, 145u, 149u, 154u, 163u, 173u, 184u,
        196u, 206u, 211u, 218u, 226u, 235u, 245u, 258u, 272u, 287u,
        297u, 314u, 325u, 335u, 345u, 351u, 365u, 376u, 388u, 395u,
        407u, 411u
    };
    return offsets[min(import_i, WASM_HOST_IMPORT_COUNT)];
}

uint wasm_host_import_name_byte(uint pos)
{
    static const uint words[103] = {
        0x6e697270u, 0x36695f74u, 0x69727734u, 0x735f6574u, 0x756f6474u,
        0x67726174u, 0x67726163u, 0x6e656c5fu, 0x5f677261u, 0x64616572u,
        0x75636573u, 0x755f6572u, 0x6e753233u, 0x735f7869u, 0x6e6f6365u,
        0x75637364u, 0x6e657272u, 0x69645f74u, 0x65725f72u, 0x75636461u,
        0x6e657272u, 0x69645f74u, 0x656c5f72u, 0x7261766eu, 0x756f635fu,
        0x6176746eu, 0x656b5f72u, 0x656c5f79u, 0x7261766eu, 0x79656b5fu,
        0x6165725fu, 0x72617664u, 0x6e656c5fu, 0x5f726176u, 0x64616572u,
        0x736f6c63u, 0x61657265u, 0x69727764u, 0x706f6574u, 0x725f6e65u,
        0x6f646165u, 0x5f6e6570u, 0x74697277u, 0x65706f65u, 0x70615f6eu,
        0x646e6570u, 0x74697277u, 0x74735f65u, 0x72726564u, 0x64616572u,
        0x6474735fu, 0x6c616e69u, 0x64636f6cu, 0x6c6c6165u, 0x6572636fu,
        0x695f6461u, 0x72773233u, 0x5f657469u, 0x77323369u, 0x65746972u,
        0x7479625fu, 0x69727765u, 0x6e5f6574u, 0x696c7765u, 0x706f656eu,
        0x725f6e65u, 0x5f646165u, 0x68746170u, 0x6e65706fu, 0x6972775fu,
        0x705f6574u, 0x77687461u, 0x65746972u, 0x7865745fu, 0x6c696674u,
        0x65735f6cu, 0x65727563u, 0x7479625fu, 0x65727365u, 0x65766f6du,
        0x6c69665fu, 0x65726365u, 0x5f657461u, 0x72726964u, 0x766f6d65u,
        0x69645f65u, 0x6e657272u, 0x6d656d61u, 0x746f6e6fu, 0x63696e6fu,
        0x6165725fu, 0x73797364u, 0x5f6d6574u, 0x64616572u, 0x65656c73u,
        0x736d5f70u, 0x3233695fu, 0x6c616572u, 0x61636f6cu, 0x636f6c6cu,
        0x6961665fu, 0x6564656cu, 0x00746978u
    };
    return pos < 411u ? (words[pos >> 2u] >> ((pos & 3u) * 8u)) & 0xffu : 0u;
}

uint wasm_host_import_type(uint import_i)
{
    static const uint types[42] = {
        0u, 3u, 1u, 2u, 4u, 1u, 1u, 3u, 1u, 1u, 2u, 4u, 3u, 5u,
        2u, 4u, 4u, 3u, 3u, 3u, 3u, 3u, 3u, 6u, 3u, 3u, 3u, 2u,
        3u, 3u, 4u, 3u, 3u, 3u, 3u, 5u, 3u, 3u, 2u, 5u, 9u, 8u
    };
    return import_i < WASM_HOST_IMPORT_COUNT ? types[import_i] : 0u;
}

uint wasm_host_import_entry_length(uint import_i)
{
    return 7u + wasm_host_import_name_offset(import_i + 1u) -
        wasm_host_import_name_offset(import_i);
}

uint wasm_host_import_entry_byte(uint import_i, uint pos)
{
    uint name_start = wasm_host_import_name_offset(import_i);
    uint name_length = wasm_host_import_name_offset(import_i + 1u) - name_start;
    if (pos == 0u) return 3u;
    if (pos == 1u) return 101u;
    if (pos == 2u) return 110u;
    if (pos == 3u) return 118u;
    if (pos == 4u) return name_length;
    if (pos >= 5u && pos < 5u + name_length)
        return wasm_host_import_name_byte(name_start + pos - 5u);
    if (pos == 5u + name_length) return 0u;
    if (pos == 6u + name_length) return wasm_host_import_type(import_i);
    return 0u;
}

uint wasm_host_import_section_byte(uint pos)
{
    if (pos == 0u) return 2u;
    if (pos >= 1u && pos < 6u)
        return wasm_host_leb5_byte(WASM_HOST_IMPORT_SECTION_LENGTH - 6u, pos - 1u);
    if (pos == 6u) return WASM_HOST_IMPORT_COUNT;
    uint entry_pos = pos - 7u;
    uint offset = 0u;
    for (uint import_i = 0u; import_i < WASM_HOST_IMPORT_COUNT; import_i += 1u)
    {
        uint length = wasm_host_import_entry_length(import_i);
        if (entry_pos < offset + length)
            return wasm_host_import_entry_byte(import_i, entry_pos - offset);
        offset += length;
    }
    return 0u;
}
