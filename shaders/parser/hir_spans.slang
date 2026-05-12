// Compute token spans for HIR-facing parse nodes.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHir;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> token_kinds;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_PATH_EXPR = 33u;
static const uint TK_IDENT = 1u;
static const uint TK_COLON = 38u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_ll1 != 0u ? min(gHir.n, ll1_status[5u]) : gHir.n;
}

uint token_kind_at_source_pos(uint i)
{
    return i < token_count[0] ? token_kinds[i + 1u] : 0u;
}

bool is_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT ||
           kind == TK_LET_IDENT;
}

uint path_expr_token_end(uint start)
{
    uint n_tokens = token_count[0];
    uint end = start + 1u;
    [loop]
    for (uint guard = 0u; guard < 32u && end + 2u < n_tokens; guard += 1u)
    {
        if (token_kind_at_source_pos(end) != TK_COLON ||
            token_kind_at_source_pos(end + 1u) != TK_COLON ||
            !is_path_segment(token_kind_at_source_pos(end + 2u)))
            break;
        end += 3u;
    }
    return min(end, n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint start = hir_token_pos[i];
    if (start == INVALID)
    {
        hir_token_end[i] = INVALID;
        return;
    }

    if (hir_kind[i] == HIR_PATH_EXPR)
    {
        hir_token_end[i] = path_expr_token_end(start);
        return;
    }

    uint end_node = min(subtree_end[i], n);
    uint max_pos = start;
    if (end_node > i + 1u)
    {
        uint last_pos = hir_token_pos[end_node - 1u];
        if (last_pos != INVALID)
            max_pos = last_pos;
    }

    uint n_tokens = token_count[0];
    hir_token_end[i] = max_pos >= n_tokens ? n_tokens : max_pos + 1u;
}
