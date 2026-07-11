// Scatter compact parser-owned HIR function-parameter rows.
//
// Parameter type projection writes per-HIR-node facts and per-function counts.
// The host scans those counts to assign each function-token segment a dense
// row base. This pass publishes each parameter at base + ordinal, so row
// identity does not depend on HIR node adjacency.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_flag;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_node_type;
StructuredBuffer<uint> call_param_row_node_ref_tag;
StructuredBuffer<uint> call_param_row_node_ref_payload;

RWStructuredBuffer<uint> call_param_row_node;
RWStructuredBuffer<uint> call_param_row_fn_token;
RWStructuredBuffer<uint> call_param_row_ordinal;
RWStructuredBuffer<uint> call_param_row_type;
RWStructuredBuffer<uint> call_param_row_ref_tag;
RWStructuredBuffer<uint> call_param_row_ref_payload;
RWStructuredBuffer<uint> call_param_row_start;
RWStructuredBuffer<uint> call_param_row_count;

static const uint INVALID = 0xffffffffu;
static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;
static const uint HIR_PARAM = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (node >= n || call_param_row_flag[node] == 0u)
        return;

    if (hir_kind[node] != HIR_PARAM)
        return;

    uint4 record = hir_param_record[node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    if (!valid_node(fn_node))
        return;

    uint fn_token = hir_token_pos[fn_node];
    if (!valid_token(fn_token))
        return;

    uint count = call_param_count[fn_token];
    uint start = call_param_row_start[fn_token];
    uint row = start + ordinal;
    if (start == INVALID ||
        ordinal >= count ||
        row < start ||
        row >= call_param_row_count_out[0u] ||
        row >= n)
        return;

    call_param_row_node[row] = node;
    call_param_row_fn_token[row] = fn_token;
    call_param_row_ordinal[row] = ordinal;
    call_param_row_type[row] = call_param_row_node_type[node];
    call_param_row_ref_tag[row] = call_param_row_node_ref_tag[node];
    call_param_row_ref_payload[row] = call_param_row_node_ref_payload[node];

    if (ordinal == 0u)
    {
        call_param_row_start[fn_token] = start;
        call_param_row_count[fn_token] = count;
    }
}
