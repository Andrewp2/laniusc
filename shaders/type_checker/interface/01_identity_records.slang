// Scatter canonical module paths and public declaration identities.
// Signature/type/member fields remain a separate typed-graph export stage.

import gpu_index;
import atomics;

struct Params
{
    uint library_id;
    uint name_capacity;
    uint module_capacity;
    uint decl_capacity;
    uint module_segment_capacity;
    uint module_segment_row_width;
    uint name_byte_capacity;
};

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

struct ModuleRecord
{
    uint first_segment;
    uint segment_count;
};

struct ModuleSegmentRecord
{
    uint name_hash_lo;
    uint name_hash_hi;
    uint name_byte_start;
    uint name_byte_len;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> name_count_out;
StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> module_segment_prefix;
StructuredBuffer<uint> module_segment_total;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> interface_name_ref_len;
StructuredBuffer<uint> interface_name_ref_prefix;
RWStructuredBuffer<ModuleRecord> interface_modules;
RWStructuredBuffer<ModuleSegmentRecord> interface_module_segments;
RWStructuredBuffer<uint> interface_declaration_words;
RWStructuredBuffer<uint> interface_counts;
RWStructuredBuffer<uint> interface_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint DECL_WORDS = 14u;
static const uint INVALID = 0xffffffffu;

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

bool active_module_segment_slot(uint slot, out uint module_i, out uint segment_i)
{
    module_i = 0u;
    segment_i = 0u;
    if (slot >= gParams.module_segment_capacity || gParams.module_segment_row_width == 0u)
        return false;
    module_i = slot / gParams.module_segment_row_width;
    segment_i = slot - module_i * gParams.module_segment_row_width;
    return module_i < active_module_count() &&
           segment_i < min(module_key_segment_count[module_i], gParams.module_segment_row_width);
}

void write_decl(uint dst, uint decl, uint name_ref)
{
    if (decl >= gParams.decl_capacity)
    {
        atomic_u32_or(interface_status, 0u, 16u);
        atomic_u32_min(interface_status, 1u, name_ref);
        return;
    }
    uint name_id = decl_name_id[decl];
    if (name_id >= active_name_count() || interface_name_ref_len[name_ref] == 0u)
    {
        atomic_u32_or(interface_status, 0u, 4u);
        atomic_u32_min(interface_status, 1u, name_ref);
        atomic_u32_min(interface_status, 2u, name_id);
        return;
    }
    uint base = dst * DECL_WORDS;
    interface_declaration_words[base + 0u] = decl_module_id[decl];
    interface_declaration_words[base + 1u] = name_hash_lo[name_id];
    interface_declaration_words[base + 2u] = name_hash_hi[name_id];
    interface_declaration_words[base + 3u] = interface_name_ref_prefix[name_ref];
    interface_declaration_words[base + 4u] = interface_name_ref_len[name_ref];
    interface_declaration_words[base + 5u] = decl_namespace[decl];
    interface_declaration_words[base + 6u] = decl_kind[decl];
    interface_declaration_words[base + 7u] = INVALID;
    interface_declaration_words[base + 8u] = 0u;
    interface_declaration_words[base + 9u] = 0u;
    uint local_owner = decl_parent_type_decl[decl];
    uint persisted_owner =
        local_owner < gParams.decl_capacity
            ? public_decl_index_by_local[local_owner]
            : INVALID;
    if (local_owner < gParams.decl_capacity && persisted_owner == INVALID)
    {
        atomic_u32_or(interface_status, 0u, 32u);
        atomic_u32_min(interface_status, 1u, name_ref);
    }
    interface_declaration_words[base + 10u] = persisted_owner;
    interface_declaration_words[base + 11u] = 0u;
    interface_declaration_words[base + 12u] = 0u;
    interface_declaration_words[base + 13u] = 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint work_capacity = max(
        gParams.module_segment_capacity,
        max(gParams.module_capacity, gParams.decl_capacity));
    if (row >= work_capacity)
        return;

    uint module_count = active_module_count();
    uint segment_count = min(module_segment_total[0u], gParams.module_segment_capacity);
    uint declaration_count = min(public_decl_count[0u], gParams.decl_capacity);

    if (row == 0u)
    {
        uint ref_count = gParams.module_segment_capacity + gParams.decl_capacity;
        uint name_byte_count = ref_count == 0u
                                   ? 0u
                                   : interface_name_ref_prefix[ref_count - 1u] +
                                         interface_name_ref_len[ref_count - 1u];
        interface_counts[0u] = gParams.library_id;
        interface_counts[1u] = module_count;
        interface_counts[2u] = segment_count;
        interface_counts[3u] = declaration_count;
        interface_counts[4u] = name_byte_count;
        if (name_byte_count > gParams.name_byte_capacity)
        {
            atomic_u32_or(interface_status, 0u, 8u);
            atomic_u32_min(interface_status, 1u, name_byte_count);
        }
    }
    if (row < module_count)
    {
        ModuleRecord record;
        record.first_segment = module_segment_prefix[row];
        record.segment_count = min(
            module_key_segment_count[row],
            gParams.module_segment_row_width);
        interface_modules[row] = record;
    }
    uint segment_module;
    uint segment_ordinal;
    if (active_module_segment_slot(row, segment_module, segment_ordinal))
    {
        uint name_id = module_key_segment_name_id[row];
        uint name_ref = row;
        if (name_id < active_name_count() && interface_name_ref_len[name_ref] != 0u)
        {
            ModuleSegmentRecord record;
            record.name_hash_lo = name_hash_lo[name_id];
            record.name_hash_hi = name_hash_hi[name_id];
            record.name_byte_start = interface_name_ref_prefix[name_ref];
            record.name_byte_len = interface_name_ref_len[name_ref];
            uint dst = module_segment_prefix[segment_module] + segment_ordinal;
            if (dst < segment_count)
                interface_module_segments[dst] = record;
        }
    }
    if (row < declaration_count)
        write_decl(
            row,
            public_decl_local_id[row],
            gParams.module_segment_capacity + row);
}
