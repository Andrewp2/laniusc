// Publish predicate-owned trait/impl method contract records.
//
// This pass is a bounded bridge toward sorted trait-method contract keys: each
// method node gets explicit owner/name/visibility/status/signature-head records.
// Method names, owners, visibility, signature flags, return types, and
// parameters consume parser-owned `hir_method_*`, `hir_method_signature_flags`,
// `hir_fn_return_type_node`, `hir_param_record`, and `hir_param_type_node` rows
// for trait declarations plus inherent and trait impls. Impl method ownership is
// accepted only through `hir_method_owner_node`; this pass must not rediscover
// that owner by checking parse parents.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_method_owner_node;
StructuredBuffer<uint> hir_method_name_token;
StructuredBuffer<uint> hir_method_visibility;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;

RWStructuredBuffer<uint> predicate_method_contract_owner_node;
RWStructuredBuffer<uint> predicate_method_contract_name_token;
RWStructuredBuffer<uint> predicate_method_contract_name_id;
RWStructuredBuffer<uint> predicate_method_contract_param_count;
RWStructuredBuffer<uint> predicate_method_contract_first_param_node;
RWStructuredBuffer<uint> predicate_method_contract_return_type_node;
RWStructuredBuffer<uint> predicate_method_contract_visibility;
RWStructuredBuffer<uint> predicate_method_contract_status;
RWStructuredBuffer<uint> predicate_method_contract_param_next_node;
RWStructuredBuffer<uint> predicate_method_contract_param_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint MAX_METHOD_SIGNATURE_PARAMS = 32u;
static const uint METHOD_PARAM_COUNT_UNSUPPORTED = MAX_METHOD_SIGNATURE_PARAMS + 1u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

static const uint METHOD_VIS_PRIVATE = 0u;
static const uint METHOD_VIS_PUBLIC = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint parent_node(uint node)
{
    return valid_node(node) ? parent[node] : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) && parent_node(child) == node ? child : INVALID;
}

bool trait_method_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_TRAIT_METHOD || kind == PROD_TRAIT_METHOD_PUB;
}

bool method_contract_production(uint node)
{
    if (!valid_node(node))
        return false;
    return trait_method_node(node) || node_kind[node] == PROD_IMPL_FN;
}

bool method_contract_node(uint node)
{
    return method_contract_production(node) &&
           valid_node(hir_method_owner_node[node]);
}

bool param_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_PARAM_NAMED ||
           kind == PROD_PARAM_SELF ||
           kind == PROD_PARAM_SELF_REF;
}

uint method_name_token(uint method_node)
{
    if (valid_node(method_node))
    {
        uint parser_method_token = hir_method_name_token[method_node];
        if (valid_token(parser_method_token))
            return parser_method_token;
    }
    return INVALID;
}

uint method_name_id(uint method_node)
{
    uint token = method_name_token(method_node);
    return valid_token(token) ? name_id_by_token[token] : INVALID;
}

bool valid_visibility(uint visibility)
{
    return visibility == METHOD_VIS_PRIVATE || visibility == METHOD_VIS_PUBLIC;
}

uint method_owner_node(uint method_node)
{
    uint parser_owner = valid_node(method_node) ? hir_method_owner_node[method_node] : INVALID;
    return valid_node(parser_owner) ? parser_owner : INVALID;
}

uint method_visibility(uint method_node)
{
    uint parser_visibility = valid_node(method_node) ? hir_method_visibility[method_node] : METHOD_VIS_PRIVATE;
    uint parser_owner = valid_node(method_node) ? hir_method_owner_node[method_node] : INVALID;
    return valid_visibility(parser_visibility) && valid_node(parser_owner)
        ? parser_visibility
        : METHOD_VIS_PRIVATE;
}

uint method_return_type_node(uint method_node)
{
    uint type_node = valid_node(method_node) ? hir_fn_return_type_node[method_node] : INVALID;
    return valid_node(type_node) ? type_node : INVALID;
}

uint method_contract_status(uint method_node)
{
    uint flags = valid_node(method_node) ? hir_method_signature_flags[method_node] : 0u;
    if ((flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC;
    if ((flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
        return PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE;
    return PREDICATE_STATUS_OK;
}

uint param_from_container(uint container)
{
    uint param = first_child_node(container);
    return param_node(param) ? param : INVALID;
}

uint previous_param_for_after_comma_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_PARAMS_AFTER_COMMA_MORE)
        return INVALID;

    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return param_from_container(previous_container);
}

uint previous_param_node(uint param)
{
    uint container = parent_node(param);
    return previous_param_for_after_comma_container(container);
}

uint parser_parameter_type_node(uint node)
{
    uint type_node = valid_node(node) ? hir_param_type_node[node] : INVALID;
    return valid_node(type_node) ? type_node : INVALID;
}

bool parser_method_param_record(uint param, out uint owner, out uint ordinal)
{
    owner = INVALID;
    ordinal = INVALID;
    if (!valid_node(param))
        return false;

    uint4 record = hir_param_record[param];
    uint record_owner = record.x;
    if (record.w != param || !valid_node(record_owner) ||
        !method_contract_node(record_owner))
        return false;

    owner = record_owner;
    ordinal = record.y;
    return true;
}

bool parser_method_param_record_matches(uint param, uint expected_owner, uint expected_ordinal)
{
    uint owner = INVALID;
    uint ordinal = INVALID;
    return parser_method_param_record(param, owner, ordinal) &&
           owner == expected_owner &&
           ordinal == expected_ordinal;
}

void mark_method_param_sequence_unsupported(uint owner)
{
    atomic_u32_max(
        predicate_method_contract_param_count,
        owner,
        METHOD_PARAM_COUNT_UNSUPPORTED);
}

void publish_method_record(uint node)
{
    uint owner = method_owner_node(node);
    uint name_token = method_name_token(node);
    uint name_id = method_name_id(node);
    uint status = method_contract_status(node);
    if (!valid_node(owner) || !valid_token(name_token) || name_id == INVALID)
        status = PREDICATE_STATUS_METHOD_ARITY_MISMATCH;

    predicate_method_contract_owner_node[node] = owner;
    predicate_method_contract_name_token[node] = name_token;
    predicate_method_contract_name_id[node] = name_id;
    predicate_method_contract_return_type_node[node] = method_return_type_node(node);
    predicate_method_contract_visibility[node] = method_visibility(node);
    predicate_method_contract_status[node] = status;
}

void publish_param_record(uint node)
{
    uint owner = INVALID;
    uint ordinal = INVALID;
    bool valid_ordinal = false;
    if (parser_method_param_record(node, owner, ordinal))
    {
        valid_ordinal = ordinal < METHOD_PARAM_COUNT_UNSUPPORTED;
    }
    else
    {
        return;
    }

    if (!valid_ordinal || ordinal >= MAX_METHOD_SIGNATURE_PARAMS)
    {
        mark_method_param_sequence_unsupported(owner);
        return;
    }

    atomic_u32_max(predicate_method_contract_param_count, owner, ordinal + 1u);
    predicate_method_contract_param_type_node[node] = parser_parameter_type_node(node);

    if (ordinal == 0u)
    {
        if (valid_node(previous_param_node(node)))
        {
            mark_method_param_sequence_unsupported(owner);
            return;
        }
        predicate_method_contract_first_param_node[owner] = node;
        return;
    }

    uint previous = previous_param_node(node);
    if (parser_method_param_record_matches(previous, owner, ordinal - 1u))
    {
        predicate_method_contract_param_next_node[previous] = node;
        return;
    }

    mark_method_param_sequence_unsupported(owner);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    if (method_contract_node(node))
        publish_method_record(node);

    if (param_node(node))
        publish_param_record(node);
}
