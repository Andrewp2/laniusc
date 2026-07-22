// Diagnose unresolved value names from dense compact HIR. Expression ownership
// and source spans replace the legacy raw parent/sibling walk; type, predicate,
// call-head, and postfix syntax are left to their dedicated compact passes.

import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct TokenIn { uint kind; uint start; uint len; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> predicate_syntax_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> module_type_path_status;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> module_value_path_call_leaf;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> enclosing_fn;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_NAME = 2u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint TY_UNKNOWN = 0u;
static const uint TYPE_REF_INVALID = 0u;
static const uint INTRINSIC_NONE = 0u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint name_token(uint node)
{
    HirCore core = compact_hir_core[node];
    uint token = compact_hir_payload[node].d;
    if (!valid_token(token)) token = core.token_start;
    return valid_token(token) ? token : INVALID;
}

bool direct_call_owner(uint owner, uint node)
{
    if (!valid_hir(owner) || compact_hir_core[owner].kind != HIR_CALL_EXPR)
        return false;
    uint callee = compact_hir_payload[owner].a;
    if (!valid_hir(callee)) return false;
    uint end = compact_hir_links[callee].subtree_end;
    return callee == node || (callee < node && node < end);
}

bool owned_by_call(uint node)
{
    if (direct_call_owner(compact_hir_expr_parent[node], node) ||
        direct_call_owner(compact_hir_core[node].parent, node))
        return true;

    // A canonical path wrapper may own the name while the call owns the path.
    uint path = compact_hir_core[node].parent;
    if (!valid_hir(path) || compact_hir_core[path].kind != HIR_PATH_EXPR)
        path = compact_hir_expr_parent[node];
    return valid_hir(path) && compact_hir_core[path].kind == HIR_PATH_EXPR &&
           (direct_call_owner(compact_hir_expr_parent[path], path) ||
            direct_call_owner(compact_hir_core[path].parent, path));
}

bool postfix_or_struct_head(uint node)
{
    uint sibling = compact_hir_links[node].next_sibling;
    if (!valid_hir(sibling))
    {
        uint child = compact_hir_links[node].first_child;
        if (valid_hir(child) && compact_hir_core[child].kind == HIR_PATH_EXPR)
            sibling = compact_hir_links[child].next_sibling;
    }
    if (!valid_hir(sibling)) return false;
    uint kind = compact_hir_core[sibling].kind;
    return kind == HIR_INDEX_EXPR || kind == HIR_MEMBER_EXPR ||
           kind == HIR_STRUCT_LITERAL_EXPR;
}

bool resolved(uint token)
{
    return valid_token(visible_decl[token]) || visible_type[token] != TY_UNKNOWN ||
           valid_token(call_fn_index[token]) || call_return_type[token] != TY_UNKNOWN ||
           call_intrinsic_tag[token] != INTRINSIC_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         !(compact_hir_core[node].kind == HIR_EXPR &&
           compact_hir_payload[node].a == HIR_EXPR_NAME)))
        return;

    uint token = name_token(node);
    if (!valid_token(token)) return;
    if (enclosing_fn[token] == 0u || resolved(token)) return;
    if (predicate_syntax_token[token] != 0u ||
        type_expr_ref_tag[token] != TYPE_REF_INVALID ||
        module_type_path_status[token] != PATH_RESOLVE_STATUS_INVALID ||
        token_words[token].kind == TK_BOUND_TYPE_IDENT)
        return;
    if (module_value_path_associated_method_token[token] != INVALID ||
        method_call_name_id[token] != INVALID ||
        module_value_path_call_leaf[token] != 0u ||
        owned_by_call(node) || postfix_or_struct_head(node))
        return;

    uint detail = module_value_path_status[token];
    if (detail == PATH_RESOLVE_STATUS_OK) return;
    if (detail == PATH_RESOLVE_STATUS_INVALID) detail = 0u;

    // A multi-token path without a resolver diagnostic is owned by the path
    // pass. Single names are complete value expressions and must resolve here.
    HirCore core = compact_hir_core[node];
    if (detail == 0u && core.token_end != token + 1u) return;
    record_min_token_error(status, token, ERR_UNRESOLVED_IDENT, detail);
}
