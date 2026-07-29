// Publish predicate-owned method contracts from compact HIR families.
//
// Contract identity is the dense method HIR id. Parameter identity is the
// compact parameter-family row. No raw production, parent, sibling, or
// raw-to-compact relation crosses this pass boundary.

import fixed.compact_method;
import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

struct HirMethodSignature
{
    uint first_param_token;
    uint impl_receiver_type;
    uint receiver_mode;
    uint metadata;
};

struct HirParam
{
    uint owner;
    uint name_token;
    uint type_node;
    uint ordinal;
};

struct HirRange
{
    uint start;
    uint count;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> predicate_method_contract_owner_hir;
RWStructuredBuffer<uint> predicate_method_contract_name_token;
RWStructuredBuffer<uint> predicate_method_contract_name_id;
RWStructuredBuffer<uint> predicate_method_contract_param_count;
RWStructuredBuffer<uint> predicate_method_contract_return_type_node;
RWStructuredBuffer<uint> predicate_method_contract_visibility;
RWStructuredBuffer<uint> predicate_method_contract_status;
RWStructuredBuffer<uint> predicate_method_contract_param_type_node;
RWStructuredBuffer<uint> hir_value_decl_name_present;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint MAX_METHOD_SIGNATURE_PARAMS = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;
static const uint METHOD_PARAM_COUNT_UNSUPPORTED = MAX_METHOD_SIGNATURE_PARAMS + 1u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint active_method_count()
{
    return min(compact_method_count[0u], gParams.n_hir_nodes);
}

uint active_param_count()
{
    return min(compact_param_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint hir)
{
    return hir != INVALID && hir < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint contract_status(uint flags, bool structurally_valid)
{
    if (!structurally_valid)
        return PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
    if ((flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC;
    if ((flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE;
    return PREDICATE_STATUS_OK;
}

void publish_method(uint row)
{
    if (row >= active_method_count())
        return;

    CompactMethodCore core = compact_method_cores[row];
    HirMethodSignature signature = compact_method_signatures[row];
    if (!valid_hir(core.node))
        return;

    uint name_id = valid_token(core.name_token)
        ? name_id_by_token[core.name_token]
        : INVALID;
    if (name_id != INVALID && name_id < gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        atomic_u32_or(hir_value_decl_name_present, name_id, 1u);
    HirRange params = compact_param_ranges[core.node];
    uint param_count = active_param_count();
    bool valid_range = params.count <= MAX_METHOD_SIGNATURE_PARAMS &&
                       (params.count == 0u ||
                        (params.start <= param_count &&
                         params.count <= param_count - params.start));
    bool valid_contract = valid_hir(core.owner) &&
                          valid_token(core.name_token) &&
                          name_id != INVALID &&
                          valid_range;
    uint flags = signature.metadata >> 16u;

    predicate_method_contract_owner_hir[core.node] = core.owner;
    predicate_method_contract_name_token[core.node] = core.name_token;
    predicate_method_contract_name_id[core.node] = name_id;
    predicate_method_contract_param_count[core.node] = valid_range
        ? params.count
        : METHOD_PARAM_COUNT_UNSUPPORTED;
    uint return_type = compact_fn_return_type[core.node];
    predicate_method_contract_return_type_node[core.node] =
        valid_hir(return_type) ? return_type : INVALID;
    predicate_method_contract_visibility[core.node] = signature.metadata & 0xffffu;
    predicate_method_contract_status[core.node] = contract_status(flags, valid_contract);
}

void publish_param(uint row)
{
    uint count = active_param_count();
    if (row >= count)
        return;

    HirParam parameter = compact_params[row];
    uint method_row = compact_method_row_for_hir(
        compact_method_cores,
        active_method_count(),
        parameter.owner);
    if (method_row >= active_method_count() ||
        compact_method_cores[method_row].node != parameter.owner)
        return;

    predicate_method_contract_param_type_node[row] =
        valid_hir(parameter.type_node) ? parameter.type_node : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    publish_method(row);
    publish_param(row);
}
