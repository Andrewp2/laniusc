// Materialize typechecker path metadata directly from compact HIR paths.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;

RWStructuredBuffer<uint> path_start;
RWStructuredBuffer<uint> path_len;
RWStructuredBuffer<uint> path_owner_hir;
RWStructuredBuffer<uint> path_call_hir;
RWStructuredBuffer<uint> path_owner_token;
RWStructuredBuffer<uint> path_id_by_owner_hir;
RWStructuredBuffer<uint> path_id_by_owner_token;
RWStructuredBuffer<uint> path_kind;
RWStructuredBuffer<uint> path_count_out;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);

    uint count = min(compact_path_count[0u], gParams.n_hir_nodes);
    if (row == 0u)
        path_count_out[0u] = count;
    if (row >= count)
        return;

    HirPath path = compact_paths[row];
    if (path.owner >= hir_count || path.segment_count == 0u ||
        path.segment_start >= compact_path_segment_count[0u])
        return;
    HirPathSegment first = compact_path_segments[path.segment_start];
    uint owner_token = first.name_token;
    if (owner_token >= gParams.n_tokens)
        return;

    path_start[row] = owner_token;
    path_len[row] = path.segment_count;
    path_owner_hir[row] = path.owner;
    uint call = compact_hir_expr_parent[path.owner];
    if (call >= hir_count || compact_hir_core[call].kind != HIR_CALL_EXPR)
    {
        uint wrapper = compact_hir_core[path.owner].parent;
        call = wrapper < hir_count && compact_hir_core[wrapper].kind == HIR_NAME_EXPR
            ? compact_hir_expr_parent[wrapper]
            : INVALID;
    }
    path_call_hir[row] = call < hir_count && compact_hir_core[call].kind == HIR_CALL_EXPR
        ? call
        : INVALID;
    path_owner_token[row] = owner_token;
    path_id_by_owner_hir[path.owner] = row;
    path_id_by_owner_token[owner_token] = row;
    path_kind[row] = path.kind;
}
