// Scatter compact Wasm call-relocation rows after the hierarchical prefix scan.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_words;
StructuredBuffer<uint> call_reloc_local_prefix;
StructuredBuffer<uint> call_reloc_block_prefix;
RWStructuredBuffer<uint> call_reloc_site;
RWStructuredBuffer<uint> call_reloc_target;
RWStructuredBuffer<uint> call_reloc_status;

static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint CALL_RELOC_MARKER = 0x100u;
static const uint WASM_CALL = 0x10u;
static const uint ERR_INVALID_CALL_RELOCATION = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint reloc_count()
{
    return inclusive_scan_total(gScan.n_blocks, call_reloc_block_prefix);
}

bool padded_call_target(uint site, out uint target)
{
    target = 0u;
    if (site == 0u || site + 5u > gScan.n_items)
        return false;
    if ((body_words[site - 1u] & 0xffu) != WASM_CALL)
        return false;

    for (uint byte_i = 0u; byte_i < 5u; byte_i += 1u)
    {
        uint byte_value = body_words[site + byte_i] & 0xffu;
        bool continuation = (byte_value & 0x80u) != 0u;
        if (continuation != (byte_i < 4u))
            return false;
        if (byte_i == 4u && (byte_value & 0x70u) != 0u)
            return false;
        target |= (byte_value & (byte_i == 4u ? 0x0fu : 0x7fu)) << (byte_i * 7u);
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i == 0u)
        call_reloc_status[0u] = reloc_count();
    if (i >= gScan.n_items || (body_words[i] & CALL_RELOC_MARKER) == 0u)
        return;

    uint row = global_exclusive_prefix(
        i,
        WG_SIZE,
        call_reloc_local_prefix,
        call_reloc_block_prefix);
    uint target = 0u;
    if (row >= gScan.out_capacity || !padded_call_target(i, target))
    {
        uint ignored;
        InterlockedAdd(call_reloc_status[1u], 1u, ignored);
        InterlockedMin(call_reloc_status[2u], i, ignored);
        InterlockedExchange(call_reloc_status[3u], ERR_INVALID_CALL_RELOCATION, ignored);
        return;
    }

    call_reloc_site[row] = i;
    call_reloc_target[row] = target;
}
