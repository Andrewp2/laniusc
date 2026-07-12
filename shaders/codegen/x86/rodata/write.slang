// Copy parser-owned string literal payload bytes into final x86 ELF rodata.

import atomics;
import byte_packing;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_string_data_offset;
StructuredBuffer<uint> hir_string_decoded_len;
StructuredBuffer<uint> hir_string_data_words;
StructuredBuffer<uint> hir_string_node;
StructuredBuffer<uint> hir_string_count;
StructuredBuffer<uint> x86_rodata_size_by_node;
StructuredBuffer<uint> x86_rodata_offset_by_node;
StructuredBuffer<uint> x86_rodata_len;
StructuredBuffer<uint> x86_rodata_status;
StructuredBuffer<uint> x86_elf_layout;
StructuredBuffer<uint> layout_status;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint X86_RODATA_OK = 1u;
static const uint X86_LAYOUT_OK = 1u;
static const uint X86_ERR_RODATA_WRITE = 65u;

static const uint LAYOUT_FILE_LEN = 2u;
static const uint LAYOUT_RODATA_OFFSET = 6u;
static const uint LAYOUT_RODATA_LEN = 7u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool upstream_ok()
{
    uint file_len = x86_elf_layout[LAYOUT_FILE_LEN];
    return x86_rodata_status[0u] == X86_RODATA_OK &&
           x86_rodata_status[1u] == 0u &&
           layout_status[0u] == X86_LAYOUT_OK &&
           layout_status[1u] == 0u &&
           layout_status[3u] == file_len &&
           x86_elf_layout[LAYOUT_RODATA_LEN] == x86_rodata_len[0u] &&
           file_len <= gParams.out_capacity;
}

void scatter_file_byte(uint file_pos, uint byte_value)
{
    uint word_i = file_pos >> 2u;
    uint lane_shift = (file_pos & 3u) * 8u;
    atomic_u32_or(out_words, word_i, (byte_value & 0xffu) << lane_shift);
}

void publish_output_error(uint detail)
{
    if (status[2u] != 0u)
        return;

    atomic_u32_min(status, 3u, detail);
    if (status[3u] == detail)
    {
        status[0u] = 0u;
        status[1u] = 0u;
        status[2u] = X86_ERR_RODATA_WRITE;
    }
}

void publish_upstream_error()
{
    if (status[2u] != 0u)
        return;

    status[0u] = 0u;
    status[1u] = 0u;
    if (x86_rodata_status[1u] != 0u)
    {
        status[2u] = x86_rodata_status[1u];
        status[3u] = x86_rodata_status[2u];
        return;
    }
    if (layout_status[1u] != 0u)
    {
        status[2u] = layout_status[1u];
        status[3u] = layout_status[2u];
        return;
    }
    status[2u] = X86_ERR_RODATA_WRITE;
    status[3u] = INVALID;
}

uint canonical_string_byte(uint pos)
{
    uint packed = hir_string_data_words[pos >> 2u];
    return (packed >> ((pos & 3u) * 8u)) & 0xffu;
}

void write_node_rodata(uint node, uint rodata_offset, uint lane)
{
    uint start = hir_string_data_offset[node];
    uint decoded_len = hir_string_decoded_len[node];
    uint data_offset = x86_rodata_offset_by_node[node];
    uint size = x86_rodata_size_by_node[node];
    if (size == 0u)
        return;
    if (decoded_len + 1u != size)
    {
        publish_output_error(node);
        return;
    }

    for (uint byte_i = lane; byte_i < decoded_len; byte_i += WG_SIZE)
    {
        uint file_pos = rodata_offset + data_offset + byte_i;
        if (file_pos >= gParams.out_capacity)
        {
            publish_output_error(node);
            return;
        }
        scatter_file_byte(file_pos, canonical_string_byte(start + byte_i));
    }
    if (lane == 0u)
        scatter_file_byte(rodata_offset + data_offset + decoded_len, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = gid.x + gid.y * MAX_GROUPS_X;
    bool ok = upstream_ok();

    if (row == 0u && ltid.x == 0u)
    {
        if (!ok && status[2u] == 0u)
            publish_upstream_error();
    }

    if (!ok || row >= hir_string_count[0u] || x86_rodata_len[0u] == 0u)
        return;

    uint node = hir_string_node[row];
    if (node >= active_hir_node_count())
        return;
    write_node_rodata(node, x86_elf_layout[LAYOUT_RODATA_OFFSET], ltid.x);
}
