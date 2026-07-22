// Project resolved call facts from the type checker's token-indexed working
// tables into one canonical record per dense call-expression HIR row.
//
// Token tables have intentionally different domains: call_fn_index stores a
// declaration-name token, backend_call_fn_index stores a function-start token,
// and call_return_type at the callee token stores the checked per-call result
// after generic/method substitution. This pass is the only boundary that joins
// those domains; downstream semantic passes consume the dense record directly.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };
struct CheckedCallArtifact
{
    uint target_token;
    uint dependency_decl;
    uint intrinsic_tag;
    uint return_type;
    uint receiver_hir;
    uint arg_count;
    uint return_ref_tag;
    uint return_ref_payload;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> backend_call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
uint active_path_count() { return min(gParams.n_hir_nodes, compact_path_count[0u]); }
uint active_path_segment_count()
{
    return min(gParams.n_tokens, compact_path_segment_count[0u]);
}
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint path_node_for_callee(uint callee)
{
    if (!valid_hir(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_PATH_EXPR) return callee;
    if (compact_hir_core[callee].kind != HIR_NAME_EXPR) return INVALID;
    uint child = compact_hir_links[callee].first_child;
    return valid_hir(child) && compact_hir_core[child].kind == HIR_PATH_EXPR
               ? child
               : INVALID;
}

uint path_leaf_token_for_callee(uint callee)
{
    uint owner = path_node_for_callee(callee);
    if (!valid_hir(owner)) return INVALID;
    uint path_i = path_id_by_owner_hir[owner];
    if (path_i == INVALID || path_i >= active_path_count()) return INVALID;
    HirPath path = compact_paths[path_i];
    if (path.owner != owner || path.segment_start == INVALID ||
        path.segment_count == 0u)
        return INVALID;
    uint row = path.segment_start + path.segment_count - 1u;
    if (row < path.segment_start || row >= active_path_segment_count()) return INVALID;
    HirPathSegment segment = compact_path_segments[row];
    return segment.path == path_i && valid_token(segment.name_token)
               ? segment.name_token
               : INVALID;
}

uint callee_token_for_call(uint call)
{
    uint callee = compact_hir_payload[call].a;
    uint path_leaf = path_leaf_token_for_callee(callee);
    if (valid_token(path_leaf)) return path_leaf;
    if (!valid_hir(callee)) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token)) token = core.token_start;
    return valid_token(token) ? token : INVALID;
}

CheckedCallArtifact empty_call()
{
    CheckedCallArtifact call;
    call.target_token = INVALID;
    call.dependency_decl = INVALID;
    call.intrinsic_tag = 0u;
    call.return_type = 0u;
    call.receiver_hir = INVALID;
    call.arg_count = 0u;
    call.return_ref_tag = 0u;
    call.return_ref_payload = INVALID;
    return call;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.n_hir_nodes) return;

    CheckedCallArtifact call = empty_call();
    if (valid_hir(row) && compact_hir_core[row].kind == HIR_CALL_EXPR)
    {
        uint callee = compact_hir_payload[row].a;
        uint callee_token = callee_token_for_call(row);
        if (valid_token(callee_token))
        {
            call.target_token = backend_call_fn_index[callee_token];
            call.dependency_decl = call_dependency_decl[callee_token];
            call.intrinsic_tag = call_intrinsic_tag[callee_token];
            call.return_type = call_return_type[callee_token];
            uint return_token = call_return_type_token[callee_token];
            if (valid_token(return_token))
            {
                call.return_ref_tag = type_expr_ref_tag[return_token];
                call.return_ref_payload = type_expr_ref_payload[return_token];
                if (call.return_ref_tag == 0u)
                {
                    call.return_ref_tag = decl_type_ref_tag[return_token];
                    call.return_ref_payload = decl_type_ref_payload[return_token];
                }
            }
            if (call.return_ref_tag == 0u)
            {
                uint target = call_fn_index[callee_token];
                if (valid_token(target))
                {
                    call.return_ref_tag = decl_type_ref_tag[target];
                    call.return_ref_payload = decl_type_ref_payload[target];
                }
            }
        }
        call.receiver_hir = valid_hir(callee) &&
                            compact_hir_core[callee].kind == HIR_MEMBER_EXPR
                                ? compact_hir_payload[callee].b
                                : INVALID;
        call.arg_count = compact_hir_payload[row].c;
    }
    semantic_calls_by_hir[row] = call;
}
