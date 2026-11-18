import hir_records;

// Collect nominal references from resolved declarations and ordered operands.
// A declaration owns its symbolic application, including every parameter in
// declaration order. A nongeneric declaration has a zero-argument application.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<HirRange> compact_path_type_arg_ranges;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
StructuredBuffer<uint> compact_generic_param_count;
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<HirRange> compact_generic_param_ranges;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

#include "named_application_owner.slang"

bool bare_nominal(uint token)
{
    if (!valid_token(token) || type_decl_generic_param_count_by_owner_token[token] != 0u ||
        type_decl_const_param_count_by_owner_token[token] != 0u) return false;
    uint node = type_decl_hir_node_by_token[token];
    if (node >= active_hir_count()) return false;
    uint kind = compact_hir_core[node].kind;
    return (kind == 26u || kind == 27u || compact_hir_payload[node].a == 8u) &&
        compact_hir_payload[node].b == token;
}

void publish_declaration(uint owner, uint token)
{
    HirRange parameters = compact_generic_param_ranges[owner];
    uint total = min(compact_generic_param_count[0u], gParams.n_hir_nodes);
    if (parameters.count > 32u || (parameters.count != 0u &&
        (parameters.start > total || parameters.count > total - parameters.start))) return;
    uint types = 0u; uint constants = 0u; bool saw_constant = false; bool interleaved = false;
    for (uint i = 0u; i < parameters.count; i++)
    {
        HirGenericParam parameter = compact_generic_params[parameters.start + i];
        if (parameter.owner != owner || (parameter.kind != 1u && parameter.kind != 2u)) return;
        if (parameter.kind == 2u) { constants |= 1u << i; saw_constant = true; }
        else { types++; interleaved = interleaved || saw_constant; }
    }
    type_instance_kind[token] = TYPE_INSTANCE_NAMED;
    type_instance_head_token[token] = token;
    type_instance_decl_token[token] = token;
    type_instance_arg_start[token] = parameters.count == 0u ? INVALID : parameters.start;
    type_instance_arg_count[token] = parameters.count;
    type_instance_len_kind[token] = types | (interleaved ? 0x80000000u : 0u);
    type_instance_len_payload[token] = constants;
    type_instance_state[token] = TYPE_INSTANCE_RESOLVED;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint owner = linear_thread_id(dtid);
    if (owner >= active_hir_count())
        return;
    uint owner_kind = compact_hir_core[owner].kind;
    if (owner_kind == 26u || owner_kind == 27u ||
        (compact_hir_payload[owner].a == 8u && compact_type_alias_target[owner] < active_hir_count()))
    {
        uint declaration = compact_hir_payload[owner].b;
        if (valid_token(declaration))
        {
            publish_declaration(owner, declaration);
            type_expr_ref_tag[declaration] = TYPE_REF_INSTANCE;
            type_expr_ref_payload[declaration] = declaration;
        }
        return;
    }
    if (owner_kind != HIR_PATH_EXPR && owner_kind != HIR_RECORD_APPLICATION_OWNER &&
        (owner_kind != HIR_TYPE || compact_hir_payload[owner].a != HIR_TYPE_FORM_PATH))
        return;

    uint leaf_token = instance_token_for_owner(owner);
    if (!valid_token(leaf_token)) return;
    HirRange args = compact_path_type_arg_ranges[leaf_token];
    uint owner_token = compact_hir_core[owner].token_start;
    if (!valid_token(owner_token) || !valid_token(leaf_token))
        return;

    if (args.count == 0u)
    {
        if (owner_kind == HIR_PATH_EXPR) return;
        uint path = path_id_by_owner_hir[owner];
        if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return;
        uint declaration = resolved_type_decl[path];
        if (declaration >= gParams.n_hir_nodes ||
            (decl_kind[declaration] != 6u && decl_kind[declaration] != 7u &&
             decl_kind[declaration] != 8u)) return;
        uint token = decl_name_token[declaration];
        if (!bare_nominal(token)) return;
        type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
        type_expr_ref_payload[owner_token] = token;
        type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
        type_expr_ref_payload[leaf_token] = token;
        return;
    }
    if (args.start == INVALID) return;

    if (owner_kind == HIR_TYPE || owner_kind == HIR_RECORD_APPLICATION_OWNER)
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
        type_expr_ref_payload[owner_token] = leaf_token;
    }
    type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[leaf_token] = leaf_token;
    type_instance_kind[leaf_token] = TYPE_INSTANCE_NAMED;
    type_instance_head_token[leaf_token] = leaf_token;
    // The compact-row scan overwrites this provisional value before argument
    // refs are scattered. Keeping a non-invalid seed preserves the existing
    // scan contract without imposing a fixed argument width.
    type_instance_arg_start[leaf_token] = args.start;
    type_instance_arg_count[leaf_token] = args.count;
    type_instance_len_kind[leaf_token] = args.count; // Provisional type-only prefix.
    type_instance_len_payload[leaf_token] = 0u; // No constant operands published yet.
    type_instance_state[leaf_token] = TYPE_INSTANCE_UNRESOLVED;
}
