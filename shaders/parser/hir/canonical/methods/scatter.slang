import hir_records;
import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
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
StructuredBuffer<uint> method_owner;
StructuredBuffer<uint> method_impl;
StructuredBuffer<uint> method_name_token;
StructuredBuffer<uint> method_first_param_token;
StructuredBuffer<uint> method_receiver_mode;
StructuredBuffer<uint> method_visibility;
StructuredBuffer<uint> method_signature_flags;
StructuredBuffer<uint> method_impl_receiver_type;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirMethodCore> method_cores;
RWStructuredBuffer<HirMethodSignature> method_signatures;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint semantic_anchor(uint raw)
{
    uint callee = hir_call_callee_node[raw];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint kind = hir_kind[raw];
    uint expr_form = hir_expr_record[raw * 4u];
    uint identity_kind = canonical_hir_identity_kind(kind, expr_form, false);
    uint operator_token = canonical_hir_operator_anchor(
        identity_kind, expr_form, right_start, hir_token_end[raw],
        gCanonical.canonical_capacity);
    return canonical_hir_anchor(identity_kind, hir_token_pos[raw], hir_token_end[raw], open,
                                hir_expr_record[raw * 4u + 3u], operator_token,
                                gCanonical.canonical_capacity);
}
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
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
    uint row = (block == 0u ? 0u : family_block_prefix[block - 1u]) + family_local_prefix[raw];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    uint impl_raw = method_impl[raw];
    HirMethodCore core;
    core.node = mapped(raw);
    core.owner = mapped(method_owner[raw]);
    core.impl_node = impl_raw == INVALID ? INVALID : mapped(impl_raw);
    core.name_token = method_name_token[raw];
    method_cores[row] = core;
    HirMethodSignature signature;
    signature.first_param_token = method_first_param_token[raw];
    signature.impl_receiver_type = impl_raw == INVALID ? INVALID : mapped(method_impl_receiver_type[impl_raw]);
    signature.receiver_mode = method_receiver_mode[raw];
    signature.metadata = (method_visibility[raw] & 0xffffu) | ((method_signature_flags[raw] & 0xffffu) << 16u);
    method_signatures[row] = signature;
}
