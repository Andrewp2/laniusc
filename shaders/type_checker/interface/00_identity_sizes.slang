// Size canonical module/declaration names before interface byte-arena scan.
//
// One lane handles the same row in the module-segment, type-declaration, and
// value-declaration domains. A following exclusive GPU scan over
// interface_name_ref_len assigns non-overlapping byte ranges.

import gpu_index;
import atomics;

struct Params
{
    uint name_capacity;
    uint module_capacity;
    uint decl_capacity;
    uint module_segment_capacity;
    uint module_segment_row_width;
};

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> name_count_out;
StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_name_id;
RWStructuredBuffer<uint> interface_name_ref_len;
RWStructuredBuffer<uint> interface_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_NAME_BYTES = 64u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_name_count()
{
    return min(name_count_out[0u], gParams.name_capacity);
}

uint active_module_count()
{
    return min(module_count_out[0u], gParams.module_capacity);
}

bool active_module_segment_slot(uint slot)
{
    if (slot >= gParams.module_segment_capacity || gParams.module_segment_row_width == 0u)
        return false;
    uint module_i = slot / gParams.module_segment_row_width;
    uint segment_i = slot - module_i * gParams.module_segment_row_width;
    return module_i < active_module_count() &&
           segment_i < min(module_key_segment_count[module_i], gParams.module_segment_row_width);
}

uint checked_name_len(uint name_id, uint ref_i)
{
    if (name_id >= active_name_count())
    {
        atomic_u32_or(interface_status, 0u, 1u);
        atomic_u32_min(interface_status, 1u, ref_i);
        atomic_u32_min(interface_status, 2u, name_id);
        return 0u;
    }
    uint len = name_spans[name_id].len;
    if (len == 0u || len > MAX_NAME_BYTES)
    {
        atomic_u32_or(interface_status, 0u, 2u);
        atomic_u32_min(interface_status, 1u, ref_i);
        atomic_u32_min(interface_status, 2u, name_id);
        atomic_u32_min(interface_status, 3u, len);
        return 0u;
    }
    return len;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint work_capacity = max(gParams.module_segment_capacity, gParams.decl_capacity);
    if (row >= work_capacity)
        return;

    uint segment_ref = row;
    uint decl_ref = gParams.module_segment_capacity + row;
    if (row < gParams.module_segment_capacity)
        interface_name_ref_len[segment_ref] = 0u;
    if (row < gParams.decl_capacity)
        interface_name_ref_len[decl_ref] = 0u;

    if (active_module_segment_slot(row))
    {
        interface_name_ref_len[segment_ref] =
            checked_name_len(module_key_segment_name_id[row], segment_ref);
    }

    uint decl_count = min(public_decl_count[0u], gParams.decl_capacity);
    if (row < decl_count)
    {
        uint decl = public_decl_local_id[row];
        if (decl >= gParams.decl_capacity)
        {
            atomic_u32_or(interface_status, 0u, 16u);
            atomic_u32_min(interface_status, 1u, decl_ref);
        }
        else
        {
            interface_name_ref_len[decl_ref] = checked_name_len(decl_name_id[decl], decl_ref);
        }
    }
}
