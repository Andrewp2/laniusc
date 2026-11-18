import hir_records;
import prefix_scan;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> raw_to_hir;
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
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (dense == 0u) family_count[0u] = total;
    if (dense >= min(canonical_count[0u], gCanonical.canonical_capacity) ||
        family_flag[dense] == 0u) return;
    uint raw = canonical_dense_to_raw[dense];
    uint block = dense / 256u;
    uint row = (block == 0u ? 0u : family_block_prefix[block - 1u]) + family_local_prefix[dense];
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
