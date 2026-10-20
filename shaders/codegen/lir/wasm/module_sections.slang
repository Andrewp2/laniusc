import codegen.lir.wasm.host_abi;

// Linear memory (docs/wasm-memory-layout.md): the string data segment at 0,
// then the shadow stack, which grows down from its top, then the host heap.
// Global 0 is the stack pointer; global 1, exported as `__heap_base`, is the
// first byte the host may allocate. The initial memory covers data and stack.
static const uint WASM_SHADOW_STACK_BYTES = 0x100000u;
static const uint WASM_MEMORY_SECTION_LENGTH = 17u;
static const uint WASM_GLOBAL_SECTION_LENGTH = 21u;
static const uint WASM_EXPORT_SECTION_LENGTH = 45u;

uint wasm_stack_top(uint data_len)
{
    return ((data_len + 15u) & ~15u) + WASM_SHADOW_STACK_BYTES;
}

uint wasm_initial_pages(uint data_len)
{
    return (wasm_stack_top(data_len) + 0xffffu) >> 16u;
}

uint wasm_memory_section_byte(uint pos, uint initial_pages)
{
    if (pos == 0u) return 5u;
    if (pos <= 5u) return wasm_host_leb5_byte(11u, pos - 1u);
    if (pos <= 10u) return wasm_host_leb5_byte(1u, pos - 6u);
    if (pos == 11u) return 0u;
    return wasm_host_leb5_byte(initial_pages, pos - 12u);
}

// Two i32 globals initialized to the stack top: the mutable stack pointer,
// then the immutable heap base.
uint wasm_global_section_byte(uint pos, uint stack_top)
{
    if (pos == 0u) return 6u;
    if (pos == 1u) return 19u;
    if (pos == 2u) return 2u;
    uint rel = (pos - 3u) % 9u;
    if (rel == 0u) return 0x7fu;
    if (rel == 1u) return pos < 12u ? 1u : 0u;
    if (rel == 2u) return 0x41u;
    if (rel <= 7u) return wasm_host_leb5_byte(stack_top, rel - 3u);
    return 0x0bu;
}

uint wasm_export_section_byte(uint pos, uint entry_function)
{
    if (pos == 0u) return 7u;
    if (pos <= 5u) return wasm_host_leb5_byte(39u, pos - 1u);
    if (pos <= 10u) return wasm_host_leb5_byte(3u, pos - 6u);
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
    if (pos == 29u) return 2u;
    if (pos == 30u) return 0u;
    if (pos == 31u) return 11u;
    if (pos >= 32u && pos < 43u)
    {
        static const uint heap_name[11] =
            {0x5fu, 0x5fu, 0x68u, 0x65u, 0x61u, 0x70u, 0x5fu, 0x62u, 0x61u, 0x73u, 0x65u};
        return heap_name[pos - 32u];
    }
    return pos == 43u ? 3u : pos == 44u ? 1u : 0u;
}
