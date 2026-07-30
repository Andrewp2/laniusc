import codegen.lir.wasm.host_abi;

static const uint WASM_MEMORY_SECTION_LENGTH = 17u;
static const uint WASM_GLOBAL_SECTION_LENGTH = 12u;
static const uint WASM_EXPORT_SECTION_LENGTH = 31u;

uint wasm_memory_section_byte(uint pos, uint initial_pages)
{
    if (pos == 0u) return 5u;
    if (pos <= 5u) return wasm_host_leb5_byte(11u, pos - 1u);
    if (pos <= 10u) return wasm_host_leb5_byte(1u, pos - 6u);
    if (pos == 11u) return 0u;
    return wasm_host_leb5_byte(initial_pages, pos - 12u);
}

uint wasm_global_section_byte(uint pos, uint bump_start)
{
    if (pos == 0u) return 6u;
    if (pos == 1u) return 10u;
    if (pos == 2u) return 1u;
    if (pos == 3u) return 0x7fu;
    if (pos == 4u) return 1u;
    if (pos == 5u) return 0x41u;
    if (pos <= 10u) return wasm_host_leb5_byte(bump_start, pos - 6u);
    return 0x0bu;
}

uint wasm_export_section_byte(uint pos, uint entry_function)
{
    if (pos == 0u) return 7u;
    if (pos <= 5u) return wasm_host_leb5_byte(25u, pos - 1u);
    if (pos <= 10u) return wasm_host_leb5_byte(2u, pos - 6u);
    if (pos == 11u) return 4u;
    if (pos >= 12u && pos < 16u)
    {
        static const uint name[4] = {0x6du, 0x61u, 0x69u, 0x6eu};
        return name[pos - 12u];
    }
    if (pos == 16u) return 0u;
    if (pos <= 21u) return wasm_host_leb5_byte(entry_function, pos - 17u);
    if (pos == 22u) return 6u;
    if (pos >= 23u && pos < 29u)
    {
        static const uint memory_name[6] =
            {0x6du, 0x65u, 0x6du, 0x6fu, 0x72u, 0x79u};
        return memory_name[pos - 23u];
    }
    return pos == 29u ? 2u : 0u;
}
