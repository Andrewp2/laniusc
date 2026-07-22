// Project raw-HIR struct-literal inference contexts into dense semantic HIR.
// This is the sole raw-to-dense boundary for this fact; downstream semantic
// consumers never index parser rows.

import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> struct_lit_context_decl_token;
StructuredBuffer<uint> struct_lit_context_instance;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (raw >= gParams.n_hir_nodes) return;
    uint dense = raw_to_compact_hir[raw];
    if (dense == INVALID || dense >= gParams.n_hir_nodes) return;

    uint instance = struct_lit_context_instance[raw];
    if (valid_token(instance))
    {
        semantic_expr_ref_tag_by_hir[dense] = TYPE_REF_INSTANCE;
        semantic_expr_ref_payload_by_hir[dense] = instance;
        return;
    }

    uint decl = struct_lit_context_decl_token[raw];
    if (!valid_token(decl)) return;
    uint tag = decl_type_ref_tag[decl];
    if (tag == TYPE_REF_INVALID) return;
    semantic_expr_ref_tag_by_hir[dense] = tag;
    semantic_expr_ref_payload_by_hir[dense] = decl_type_ref_payload[decl];
}
