// Diagnose unresolved calls from compact HIR and compact path families. Call
// resolution has already published its semantic facts; this pass only reduces
// those facts to the earliest source diagnostic.

import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };

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
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> module_value_path_associated_method_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint TY_UNKNOWN = 0u;
static const uint INTRINSIC_NONE = 0u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
uint active_path_count() { return min(gParams.n_hir_nodes, compact_path_count[0u]); }
uint active_segment_count() { return min(gParams.n_tokens, compact_path_segment_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }
bool valid_path(uint path) { return path != INVALID && path < active_path_count(); }

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

uint path_for_callee(uint callee)
{
    uint owner = path_node_for_callee(callee);
    if (!valid_hir(owner)) owner = callee;
    uint path = valid_hir(owner) ? path_id_by_owner_hir[owner] : INVALID;
    return valid_path(path) && compact_paths[path].owner == owner ? path : INVALID;
}

uint path_token(uint path, uint ordinal)
{
    if (!valid_path(path)) return INVALID;
    HirPath record = compact_paths[path];
    if (ordinal >= record.segment_count || record.segment_start == INVALID) return INVALID;
    uint row = record.segment_start + ordinal;
    if (row < record.segment_start || row >= active_segment_count()) return INVALID;
    HirPathSegment segment = compact_path_segments[row];
    return segment.path == path && valid_token(segment.name_token)
               ? segment.name_token
               : INVALID;
}

uint path_owner_token(uint path) { return path_token(path, 0u); }
uint path_leaf_token(uint path)
{
    return valid_path(path) && compact_paths[path].segment_count != 0u
               ? path_token(path, compact_paths[path].segment_count - 1u)
               : INVALID;
}

uint callee_token(uint callee)
{
    if (!valid_hir(callee)) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token)) token = core.token_start;
    return valid_token(token) ? token : INVALID;
}

bool token_resolved(uint token)
{
    return valid_token(token) &&
           (valid_token(call_fn_index[token]) ||
            call_return_type[token] != TY_UNKNOWN ||
            call_intrinsic_tag[token] != INTRINSIC_NONE ||
            method_call_name_id[token] != INVALID);
}

void observe(uint token, inout bool resolved)
{
    if (token_resolved(token)) resolved = true;
}

uint associated_method_token(uint token)
{
    if (!valid_token(token)) return INVALID;
    uint method = module_value_path_associated_method_token[token];
    return valid_token(method) ? method : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return;

    uint site = compact_hir_core[call].token_start;
    uint callee = compact_hir_payload[call].a;
    uint path = path_for_callee(callee);
    uint owner = path_owner_token(path);
    uint leaf = path_leaf_token(path);
    uint direct = callee_token(callee);
    uint member = valid_hir(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR
                      ? compact_hir_payload[callee].c
                      : INVALID;

    bool resolved = false;
    observe(site, resolved);
    observe(owner, resolved);
    observe(leaf, resolved);
    observe(member, resolved);
    observe(direct, resolved);
    observe(associated_method_token(owner), resolved);
    observe(associated_method_token(leaf), resolved);
    observe(associated_method_token(site), resolved);
    if (resolved) return;

    uint error_token = direct;
    uint detail = 0u;
    uint path_status = valid_token(owner)
                           ? module_value_path_status[owner]
                           : PATH_RESOLVE_STATUS_INVALID;
    // Enum constructors, imported value constructors, and other non-function
    // callables are resolved by the module path family rather than call_fn_index.
    // A successful path resolution is therefore a complete call-head fact.
    if (path_status == PATH_RESOLVE_STATUS_OK)
        return;
    if (path_status != PATH_RESOLVE_STATUS_INVALID &&
        path_status != PATH_RESOLVE_STATUS_OK)
    {
        error_token = owner;
        detail = path_status;
    }
    else if (valid_token(leaf))
        error_token = leaf;
    else if (valid_token(owner))
        error_token = owner;
    else if (!valid_token(error_token))
        error_token = site;

    record_min_token_error(
        status,
        valid_token(error_token) ? error_token : 0u,
        ERR_UNRESOLVED_IDENT,
        detail);
}
