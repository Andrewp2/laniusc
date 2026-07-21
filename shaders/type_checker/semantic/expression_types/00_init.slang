// Seed one checked scalar result-type record per dense compact-HIR expression.
//
// Leaves consume type-checker facts directly. Operators whose result type is
// inherited link to an operand; the following pointer-jump pass resolves every
// chain in logarithmic parallel steps. Comparisons retain their bool result
// while backends can read the checked type of their operand rows.

import gpu_index;

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
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> backend_call_fn_index;
RWStructuredBuffer<uint> compact_expr_scalar_type_out;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint SCALAR_TYPE_LINK_MASK = 0x0fffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }
uint active_path_count() { return min(gParams.n_hir_nodes, compact_path_count[0u]); }
uint active_path_segment_count()
{
    return min(gParams.n_tokens, compact_path_segment_count[0u]);
}

uint checked_scalar_type(uint ty)
{
    return ty <= TY_STRING ? ty : TY_UNKNOWN;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token)) return TY_UNKNOWN;
    uint ty = checked_scalar_type(visible_type[token]);
    if (ty != TY_UNKNOWN) return ty;
    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = checked_scalar_type(visible_type[decl]);
        if (ty != TY_UNKNOWN) return ty;
    }
    return checked_scalar_type(call_return_type[token]);
}

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

uint compact_call_callee_token(uint call)
{
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee = compact_hir_payload[call].a;
    uint path_leaf = path_leaf_token_for_callee(callee);
    if (valid_token(path_leaf)) return path_leaf;
    if (!valid_hir(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_MEMBER_EXPR)
        return compact_hir_payload[callee].c;
    uint token = compact_hir_payload[callee].d;
    if (!valid_token(token)) token = compact_hir_core[callee].token_start;
    return valid_token(token) ? token : INVALID;
}

uint compact_call_result_type(uint call)
{
    uint site = valid_hir(call) ? compact_hir_core[call].token_start : INVALID;
    uint callee = compact_call_callee_token(call);
    uint metadata = valid_token(site) && valid_token(backend_call_fn_index[site])
                        ? site
                        : callee;
    uint ty = valid_token(metadata)
                  ? checked_scalar_type(call_return_type[metadata])
                  : TY_UNKNOWN;
    if (ty != TY_UNKNOWN) return ty;
    uint target = valid_token(metadata) ? backend_call_fn_index[metadata] : INVALID;
    if (valid_token(target))
    {
        ty = checked_scalar_type(call_return_type[target]);
        if (ty != TY_UNKNOWN) return ty;
    }
    return valid_token(callee)
               ? checked_scalar_type(call_return_type[callee])
               : TY_UNKNOWN;
}

uint pack_scalar_type(uint ty, uint link)
{
    uint packed_link = valid_hir(link) && link < SCALAR_TYPE_LINK_MASK
                           ? link
                           : SCALAR_TYPE_LINK_MASK;
    return (checked_scalar_type(ty) << SCALAR_TYPE_SHIFT) | packed_link;
}

bool inherited_scalar_form(uint form)
{
    return form == HIR_EXPR_NEG || form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB || form == HIR_EXPR_MUL ||
           form == HIR_EXPR_MOD || form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR || form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND || form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

uint direct_result_type(uint node)
{
    if (!valid_hir(node)) return TY_UNKNOWN;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint form = payload.a;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE || form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ || form == HIR_EXPR_NE || form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT || form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND || form == HIR_EXPR_OR)
        return TY_BOOL;
    if (form == HIR_EXPR_INT) return TY_INT;
    if (form == HIR_EXPR_FLOAT) return TY_FLOAT;
    if (form == HIR_EXPR_STRING) return TY_STRING;
    if (form == HIR_EXPR_NAME || core.kind == HIR_NAME_EXPR)
        return visible_type_for_token(payload.d);
    if (core.kind == HIR_MEMBER_EXPR)
        return visible_type_for_token(payload.c);
    if (core.kind == HIR_CALL_EXPR)
        return compact_call_result_type(node);
    if (core.kind == HIR_INDEX_EXPR || core.kind == HIR_MATCH_EXPR)
        return visible_type_for_token(core.token_start);
    return TY_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    uint ty = direct_result_type(node);
    if (ty != TY_UNKNOWN)
    {
        compact_expr_scalar_type_out[node] = pack_scalar_type(ty, INVALID);
        return;
    }
    HirPayload payload = compact_hir_payload[node];
    uint link = inherited_scalar_form(payload.a) &&
                        valid_hir(payload.b) && payload.b != node
                    ? payload.b
                    : INVALID;
    compact_expr_scalar_type_out[node] = pack_scalar_type(TY_UNKNOWN, link);
}
