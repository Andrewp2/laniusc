// x86_64 read-only data sizing for parser-owned string literal HIR rows.

import gpu_index;
import status;
import byte_packing;

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;

RWStructuredBuffer<uint> x86_rodata_size_by_node;
RWStructuredBuffer<uint> x86_rodata_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint X86_RODATA_OK = 1u;
static const uint X86_ERR_RODATA_SIZE = 63u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_source_range(uint start, uint len)
{
    return start != INVALID &&
           start <= gParams.source_len &&
           len <= gParams.source_len - start;
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

uint expr_form(uint node)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        HIR_EXPR_RECORD_STRIDE,
        HIR_EXPR_RECORD_FORM,
        0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint active_count = active_hir_node_count();

    if (node == 0u)
    {
        x86_rodata_status[0u] = X86_RODATA_OK;
        x86_rodata_status[1u] = 0u;
        x86_rodata_status[2u] = INVALID;
        x86_rodata_status[3u] = active_count;
    }

    if (node >= active_count)
        return;

    uint size = 0u;
    if (expr_form(node) == HIR_EXPR_STRING)
    {
        uint start = hir_expr_string_start[node];
        uint len = hir_expr_string_len[node];
        if (!valid_source_range(start, len))
            publish_stage_error_min_detail4(x86_rodata_status, X86_ERR_RODATA_SIZE, node);
        else
            size = decoded_string_len(start, len) + 1u;
    }

    x86_rodata_size_by_node[node] = size;
}
