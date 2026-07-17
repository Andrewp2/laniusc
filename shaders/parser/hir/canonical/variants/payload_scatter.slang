import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> payload_owner_raw;
StructuredBuffer<uint> raw_to_variant;
RWStructuredBuffer<uint> variant_payload_start;
RWStructuredBuffer<uint> variant_payload_count;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirVariantPayload> hir_variant_payloads;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint semantic_anchor(uint raw)
{
    uint kind = hir_kind[raw];
    uint callee = hir_call_callee_node[raw];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[raw * 4u + 3u];
    return canonical_hir_anchor(kind, hir_token_pos[raw], hir_token_end[raw], open, value_token,
                                operator_token, gCanonical.canonical_capacity);
}
uint mapped(uint raw)
{
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint direct = raw_to_hir[raw];
    if (direct != INVALID) return direct;
    uint anchor = semantic_anchor(raw);
    if (anchor >= gCanonical.canonical_capacity) return INVALID;
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    return winner_plus_one == 0u ? INVALID : raw_to_hir[winner_plus_one - 1u];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;
    uint block = raw / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[raw];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    uint owner_raw = payload_owner_raw[raw];
    uint variant = owner_raw < gCanonical.raw_capacity ? raw_to_variant[owner_raw] : INVALID;
    HirVariantPayload payload;
    payload.variant = variant;
    payload.type_node = mapped(raw);
    payload.ordinal = INVALID;
    payload.file_id = hir_token_file_id[raw];
    hir_variant_payloads[row] = payload;
    if (variant < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(variant_payload_start[variant], row, ignored);
        InterlockedAdd(variant_payload_count[variant], 1u, ignored);
    }
}
