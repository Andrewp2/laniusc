// Resident HIR scope type publication.
//
// This pass is the resident compiler path replacement for the legacy token
// scope shader. It only consumes semantic type-reference records and the
// GPU-resolved visible declaration table. It does not inspect token kinds,
// token neighborhoods, source bytes, helper names, or function body shapes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint instance_kind = type_instance_kind[payload];
        if (instance_kind == TYPE_INSTANCE_ARRAY || instance_kind == TYPE_INSTANCE_SLICE)
        {
            uint elem_tag = type_instance_elem_ref_tag[payload];
            uint elem_payload = type_instance_elem_ref_payload[payload];
            return elem_tag == TYPE_REF_SCALAR ? TY_ARRAY_BASE + elem_payload
                                               : TY_ARRAY_BASE + TY_UNKNOWN;
        }

        if (instance_kind == TYPE_INSTANCE_NAMED)
        {
            uint decl_token = type_instance_decl_token[payload];
            if (valid_token(decl_token))
                return visible_type[decl_token];
        }
    }
    return TY_UNKNOWN;
}

uint declaration_type_from_ref(uint decl_i)
{
    if (!valid_token(decl_i))
        return TY_UNKNOWN;
    return type_code_for_ref(decl_type_ref_tag[decl_i], decl_type_ref_payload[decl_i]);
}

uint resolved_visible_decl(uint ident_i)
{
    return valid_token(ident_i) ? visible_decl[ident_i] : INVALID;
}

void publish_hir_visible_type(uint token_i)
{
    if (!valid_token(token_i))
        return;

    uint direct_ty = declaration_type_from_ref(token_i);
    if (direct_ty != TY_UNKNOWN)
        visible_type[token_i] = direct_ty;

    uint decl = resolved_visible_decl(token_i);
    if (decl == INVALID || decl == token_i || !valid_token(decl))
        return;

    uint decl_ty = declaration_type_from_ref(decl);
    if (decl_ty == TY_UNKNOWN)
        decl_ty = visible_type[decl];
    if (decl_ty != TY_UNKNOWN)
        visible_type[token_i] = decl_ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    publish_hir_visible_type(linear_thread_id(tid));
}
