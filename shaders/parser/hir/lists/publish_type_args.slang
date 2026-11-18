// Publish pointer-jumped generic type-argument owners, ordinals, and links.

import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_owner_a;
StructuredBuffer<uint> hir_type_arg_application_owner;
StructuredBuffer<uint> hir_canonical_alias_to_dense;
StructuredBuffer<uint> hir_canonical_dense_to_raw;
StructuredBuffer<uint> hir_type_arg_rank_a;
StructuredBuffer<uint> hir_type_arg_previous;

RWStructuredBuffer<uint> hir_type_arg_start;
RWStructuredBuffer<uint> hir_type_arg_count;
RWStructuredBuffer<uint> hir_type_arg_next;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

// A type, a literal, or a negated literal (`-5`, `-0.0`), as in the canonical
// type-argument passes.
bool argument_value_kind(uint kind)
{ return kind == HIR_TYPE || kind == 23u || kind == 17u; }

bool valid_type_arg_owner(uint node)
{
    return valid_node(node) &&
           (hir_kind[node] == HIR_TYPE || hir_kind[node] == HIR_PATH_EXPR ||
            hir_kind[node] == HIR_MEMBER_EXPR);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    // Canonical HIR is produced directly from owner/rank below; this pass is
    // now only the legacy raw-table projection used by parser debug readback.
    if (gHirType.retain_debug_rows == 0u)
        return;

    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n || !valid_node(node) || !argument_value_kind(hir_kind[node]))
        return;

    uint seed = hir_type_arg_owner_a[node];
    uint owner = valid_node(seed) ? hir_type_arg_application_owner[seed] : INVALID;
    if (!valid_type_arg_owner(owner)) return;
    if (hir_kind[owner] == HIR_PATH_EXPR)
    {
        uint dense = hir_canonical_alias_to_dense[owner];
        uint capacity; uint stride;
        hir_canonical_dense_to_raw.GetDimensions(capacity, stride);
        uint canonical_raw = dense < capacity ? hir_canonical_dense_to_raw[dense] : INVALID;
        // Constructor paths alias a record literal. Other value paths keep
        // their separate headers only in the token-owned compact relation.
        if (!valid_node(canonical_raw) || hir_kind[canonical_raw] != 28u) return;
    }

    uint ordinal = hir_type_arg_rank_a[node];
    uint previous = hir_type_arg_previous[node];
    atomic_u32_min(hir_type_arg_start, owner, node);
    atomic_u32_max(hir_type_arg_count, owner, ordinal + 1u);
    if (valid_node(previous) && argument_value_kind(hir_kind[previous]))
        hir_type_arg_next[previous] = node;
}
