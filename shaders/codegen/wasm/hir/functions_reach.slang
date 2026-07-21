// Propagate WASM function reachability from reachable compact-HIR call rows.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;

RWStructuredBuffer<uint> wasm_func_decl_flag;
RWStructuredBuffer<uint> wasm_func_flag;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR = 52u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_hir(uint hir)
{
    return hir != INVALID && hir < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint active_path_count()
{
    return min(compact_path_count[0u], gParams.n_hir_nodes);
}

uint active_path_segment_count()
{
    return min(compact_path_segment_count[0u], gParams.n_tokens);
}

bool token_has_language_name(uint name_token, uint language_symbol)
{
    if (!valid_token(name_token))
        return false;
    uint name_id = name_id_by_token[name_token];
    uint language_id = language_name_id[language_symbol];
    return language_id != 0u && name_id == language_id;
}

uint path_hir_for_callee(uint callee_hir)
{
    if (!valid_hir(callee_hir))
        return INVALID;
    if (compact_hir_core[callee_hir].kind == HIR_PATH_EXPR)
        return callee_hir;
    if (compact_hir_core[callee_hir].kind != HIR_NAME_EXPR)
        return INVALID;

    uint child = compact_hir_links[callee_hir].first_child;
    return valid_hir(child) && compact_hir_core[child].kind == HIR_PATH_EXPR
        ? child
        : INVALID;
}

uint path_leaf_token_for_callee(uint callee_hir)
{
    uint path_hir = path_hir_for_callee(callee_hir);
    if (!valid_hir(path_hir))
        return INVALID;

    uint path_row = path_id_by_owner_hir[path_hir];
    if (path_row == INVALID || path_row >= active_path_count())
        return INVALID;

    HirPath path = compact_paths[path_row];
    if (path.owner != path_hir || path.segment_count == 0u ||
        path.segment_start == INVALID)
        return INVALID;

    uint segment_row = path.segment_start + path.segment_count - 1u;
    if (segment_row < path.segment_start || segment_row >= active_path_segment_count())
        return INVALID;

    HirPathSegment segment = compact_path_segments[segment_row];
    return segment.path == path_row && valid_token(segment.name_token)
        ? segment.name_token
        : INVALID;
}

uint call_site_token(uint call_hir)
{
    return valid_hir(call_hir) ? compact_hir_core[call_hir].token_start : INVALID;
}

uint call_callee_hir(uint call_hir)
{
    return valid_hir(call_hir) && compact_hir_core[call_hir].kind == HIR_CALL_EXPR
        ? compact_hir_payload[call_hir].a
        : INVALID;
}

uint expression_identity_token(uint expression_hir)
{
    if (!valid_hir(expression_hir))
        return INVALID;
    uint value_token = compact_hir_payload[expression_hir].d;
    return valid_token(value_token)
        ? value_token
        : compact_hir_core[expression_hir].token_start;
}

uint call_callee_token(uint call_hir)
{
    uint callee_hir = call_callee_hir(call_hir);
    if (!valid_hir(callee_hir))
        return INVALID;

    uint path_leaf = path_leaf_token_for_callee(callee_hir);
    if (valid_token(path_leaf))
        return path_leaf;

    if (compact_hir_core[callee_hir].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_hir].c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    uint token = expression_identity_token(callee_hir);
    return valid_token(token) ? token : INVALID;
}

uint semantic_callee_token_for_call(uint call_hir)
{
    uint call_token = call_site_token(call_hir);
    uint callee_hir = call_callee_hir(call_hir);
    if (!valid_hir(callee_hir))
        return valid_token(call_token) ? call_token : INVALID;

    if (compact_hir_core[callee_hir].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_hir].c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expression_identity_token(callee_hir);
    return valid_token(callee_token) ? callee_token : call_token;
}

uint call_metadata_token(uint call_hir, uint callee_token)
{
    uint site_token = call_site_token(call_hir);
    if (valid_token(site_token) && valid_token(call_fn_index[site_token]))
        return site_token;

    uint semantic_token = semantic_callee_token_for_call(call_hir);
    if (valid_token(semantic_token) && valid_token(call_fn_index[semantic_token]))
        return semantic_token;

    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;

    return callee_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint call_hir = linear_dispatch_id(tid);
    if (!valid_hir(call_hir) || compact_hir_core[call_hir].kind != HIR_CALL_EXPR)
        return;

    uint call_token = call_site_token(call_hir);
    uint encoded_owner = valid_token(call_token) ? enclosing_fn[call_token] : 0u;
    uint owner_fn = encoded_owner == 0u ? INVALID : encoded_owner - 1u;
    if (!valid_token(owner_fn) || wasm_func_flag[owner_fn] == 0u)
        return;

    uint callee_token = call_callee_token(call_hir);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return;

    uint metadata_token = call_metadata_token(call_hir, callee_token);
    uint fn_token = valid_token(metadata_token) ? call_fn_index[metadata_token] : INVALID;
    if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR) ||
        token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR))
        return;
    if (valid_token(fn_token) && wasm_func_decl_flag[fn_token] != 0u)
        atomic_u32_or(wasm_func_flag, fn_token, 1u);
}
