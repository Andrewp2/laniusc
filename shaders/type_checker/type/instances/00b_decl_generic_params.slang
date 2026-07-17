// Ingest compact HIR generic-parameter rows into type-check metadata.
//
// Generic ownership is keyed by the declaration's unique source anchor token,
// never by a raw parser node. Named declarations use their name token; impls
// and other unnamed owners use the dense HIR core's anchor token.

import atomics;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirGenericParam { uint owner; uint name_token; uint kind; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_generic_param_count;
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> type_decl_generic_param_count;
RWStructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
RWStructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
RWStructuredBuffer<uint> generic_param_count_out;
RWStructuredBuffer<uint> generic_param_owner_token;
RWStructuredBuffer<uint> generic_param_name_id;
RWStructuredBuffer<uint> generic_param_token;
RWStructuredBuffer<uint> generic_param_node;
RWStructuredBuffer<uint> generic_param_kind;
RWStructuredBuffer<uint> generic_param_key_order;
RWStructuredBuffer<uint> generic_param_slot_order;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint GENERIC_PARAM_KIND_CONST = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint GENERIC_STATUS_BAD_COMPACT_ROW = 23u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

void increment_owner_count(uint owner_token, uint kind)
{
    if (!valid_token(owner_token))
        return;
    if (kind == GENERIC_PARAM_KIND_CONST)
        atomic_u32_add(type_decl_const_param_count_by_owner_token, owner_token, 1u);
    else
        atomic_u32_add(type_decl_generic_param_count_by_owner_token, owner_token, 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint count = min(compact_generic_param_count[0u], gParams.n_tokens);
    if (row == 0u)
        generic_param_count_out[0u] = count;
    if (row >= count)
        return;

    HirGenericParam parameter = compact_generic_params[row];
    if (parameter.owner >= compact_hir_count[0u] || !valid_token(parameter.name_token) ||
        (parameter.kind != GENERIC_PARAM_KIND_TYPE &&
         parameter.kind != GENERIC_PARAM_KIND_CONST))
    {
        record_min_token_error(status,
                               valid_token(parameter.name_token) ? parameter.name_token : 0u,
                               ERR_BAD_HIR,
                               GENERIC_STATUS_BAD_COMPACT_ROW);
        return;
    }

    HirCore owner_core = compact_hir_core[parameter.owner];
    HirPayload owner_payload = compact_hir_payload[parameter.owner];
    uint owner_token = valid_token(owner_payload.b)
        ? owner_payload.b
        : owner_core.token_start;
    if (!valid_token(owner_token))
    {
        record_min_token_error(status,
                               parameter.name_token,
                               ERR_BAD_HIR,
                               GENERIC_STATUS_BAD_COMPACT_ROW);
        return;
    }

    generic_param_owner_token[row] = owner_token;
    generic_param_name_id[row] = name_id_by_token[parameter.name_token];
    generic_param_token[row] = parameter.name_token;
    generic_param_node[row] = row;
    generic_param_kind[row] = parameter.kind;
    generic_param_key_order[row] = row;
    generic_param_slot_order[row] = row;

    increment_owner_count(owner_token, parameter.kind);
    if (parameter.kind == GENERIC_PARAM_KIND_TYPE)
    {
        uint head_token = owner_core.token_start;
        if (valid_token(head_token) && head_token != owner_token)
            atomic_u32_add(type_decl_generic_param_count, head_token, 1u);
        atomic_u32_add(type_decl_generic_param_count, owner_token, 1u);
    }
}
