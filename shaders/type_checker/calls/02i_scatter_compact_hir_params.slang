// Scatter compact HIR function-parameter rows.
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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
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
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(compact_hir_count[0u], gParams.n_tokens);
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
    uint param_row = linear_thread_id(dtid);
    uint param_count = min(compact_param_count[0u], gParams.n_tokens);
    if (param_row >= param_count || call_param_row_flag[param_row] == 0u)
        return;

    HirParam parameter = compact_params[param_row];
    uint fn_node = parameter.owner;
    uint ordinal = parameter.ordinal;
    if (!valid_node(fn_node))
        return;

    uint fn_token = compact_hir_payload[fn_node].b;
    if (!valid_token(fn_token))
        return;

    uint count = call_param_count[fn_token];
    uint start = call_param_row_start[fn_token];
    uint row = start + ordinal;
    if (start == INVALID ||
        ordinal >= count ||
        row < start ||
        row >= call_param_row_count_out[0u] ||
        row >= gParams.n_hir_nodes)
        return;

    call_param_row_node[row] = param_row;
    call_param_row_fn_token[row] = fn_token;
    call_param_row_ordinal[row] = ordinal;
    call_param_row_type[row] = call_param_row_node_type[param_row];
    call_param_row_ref_tag[row] = call_param_row_node_ref_tag[param_row];
    call_param_row_ref_payload[row] = call_param_row_node_ref_payload[param_row];

    if (ordinal == 0u)
    {
        call_param_row_start[fn_token] = start;
        call_param_row_count[fn_token] = count;
    }
}
