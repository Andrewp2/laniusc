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

ByteAddressBuffer source_bytes;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> x86_rodata_size_by_node;
StructuredBuffer<uint> x86_rodata_offset_by_node;
StructuredBuffer<uint> x86_rodata_len;
StructuredBuffer<uint> x86_rodata_status;
StructuredBuffer<uint> x86_elf_layout;
StructuredBuffer<uint> layout_status;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;
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

uint source_byte(uint pos)
{
    if (pos >= gParams.source_len)
        return 0u;
    return byte_address_load_u8(source_bytes, pos);
}

uint decoded_escape_byte(uint escaped)
{
    if (escaped == 110u) return 10u;  // n
    if (escaped == 114u) return 13u;  // r
    if (escaped == 116u) return 9u;   // t
    if (escaped == 48u) return 0u;    // 0
    if (escaped == 34u) return 34u;   // "
    if (escaped == 92u) return 92u;   // backslash
    return escaped;
}

uint decoded_string_len(uint start, uint raw_len)
{
    uint decoded_len = 0u;
    for (uint byte_i = 0u; byte_i < raw_len; byte_i += 1u)
    {
        uint byte_value = source_byte(start + byte_i);
        if (byte_value == 92u && byte_i + 1u < raw_len)
        {
            byte_i += 1u;
            decoded_escape_byte(source_byte(start + byte_i));
        }
        decoded_len += 1u;
    }
    return decoded_len;
}

void write_node_rodata(uint node, uint rodata_offset)
{
    uint start = hir_expr_string_start[node];
    uint raw_len = hir_expr_string_len[node];
    uint data_offset = x86_rodata_offset_by_node[node];
    uint size = x86_rodata_size_by_node[node];
    if (size == 0u)
        return;
    if (start == INVALID || start > gParams.source_len || raw_len > gParams.source_len - start)
    {
        publish_output_error(node);
        return;
    }

    uint decoded_len = decoded_string_len(start, raw_len);
    if (decoded_len + 1u != size)
    {
        publish_output_error(node);
        return;
    }

    uint out_i = 0u;
    for (uint byte_i = 0u; byte_i < raw_len; byte_i += 1u)
    {
        uint byte_value = source_byte(start + byte_i);
        if (byte_value == 92u && byte_i + 1u < raw_len)
        {
            byte_i += 1u;
            byte_value = decoded_escape_byte(source_byte(start + byte_i));
        }

        uint file_pos = rodata_offset + data_offset + out_i;
        if (file_pos >= gParams.out_capacity)
        {
            publish_output_error(node);
            return;
        }
        scatter_file_byte(file_pos, byte_value);
        out_i += 1u;
    }
    scatter_file_byte(rodata_offset + data_offset + decoded_len, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint active_count = active_hir_node_count();
    bool ok = upstream_ok();

    if (node == 0u)
    {
        if (!ok && status[2u] == 0u)
            publish_upstream_error();
    }

    if (!ok || node >= active_count || x86_rodata_len[0u] == 0u)
        return;

    write_node_rodata(node, x86_elf_layout[LAYOUT_RODATA_OFFSET]);
}
