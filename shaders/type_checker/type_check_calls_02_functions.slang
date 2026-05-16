// HIR function metadata projection.
//
// This pass consumes parser/HIR records plus semantic type-reference records.
// It intentionally does not read token kinds, source bytes, source-level names, or
// whole function bodies. Parameter typing belongs in a separate HIR expression
// and declaration-type pass so this shader stays within the WebGPU storage
// buffer limit.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> function_lookup_key;
RWStructuredBuffer<uint> function_lookup_fn;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_INT = 3u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ENTRYPOINT_MAIN = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint declaration_token_for_function(uint fn_node)
{
    uint decl_token = hir_token_pos[fn_node];
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint name_token_for_function(uint fn_node)
{
    uint name_token = hir_item_name_token[fn_node];
    return valid_token(name_token) ? name_token : INVALID;
}

uint semantic_type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint name_id = valid_token(payload) ? name_id_by_token[payload] : INVALID;
        return name_id == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + name_id;
    }
    if (tag == TYPE_REF_INSTANCE)
    {
        uint head = valid_token(payload) ? payload : INVALID;
        uint resolved = valid_token(head) ? module_type_path_type[head] : TY_UNKNOWN;
        return resolved;
    }
    return TY_UNKNOWN;
}

uint return_type_token_for_ref(uint tag, uint payload)
{
    return (tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_INSTANCE) && valid_token(payload)
               ? payload
               : INVALID;
}

uint return_type_for_function(uint fn_node, uint fn_decl_token)
{
    uint tag = fn_return_ref_tag[fn_decl_token];
    uint payload = fn_return_ref_payload[fn_decl_token];
    if (tag != TYPE_REF_INVALID)
        return semantic_type_code_for_ref(tag, payload);
    if (fn_entrypoint_tag[fn_node] == ENTRYPOINT_MAIN ||
        (valid_token(fn_decl_token) && fn_entrypoint_tag[fn_decl_token] == ENTRYPOINT_MAIN))
        return TY_INT;
    return TY_VOID;
}

void publish_function_lookup(uint fn_node)
{
    uint fn_decl_token = declaration_token_for_function(fn_node);
    uint fn_name_token = name_token_for_function(fn_node);
    if (!valid_token(fn_decl_token) || !valid_token(fn_name_token))
        return;

    call_fn_index[fn_decl_token] = fn_decl_token;
    uint tag = fn_return_ref_tag[fn_decl_token];
    uint payload = fn_return_ref_payload[fn_decl_token];
    call_return_type_token[fn_decl_token] = return_type_token_for_ref(tag, payload);
    call_return_type[fn_decl_token] = return_type_for_function(fn_node, fn_decl_token);

    uint key = name_id_by_token[fn_name_token];
    if (key == INVALID)
        return;

    uint cap = lookup_capacity();
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint old_fn;
        InterlockedCompareExchange(function_lookup_fn[slot], INVALID, fn_decl_token, old_fn);
        if (old_fn == INVALID)
        {
            function_lookup_key[slot] = key;
            return;
        }
        if (function_lookup_key[slot] == key)
        {
            uint old_min;
            InterlockedMin(function_lookup_fn[slot], fn_decl_token, old_min);
            return;
        }
    }
}

bool function_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN || item_kind == HIR_ITEM_KIND_EXTERN_FN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count() || !function_item_kind(hir_item_kind[node]))
        return;

    publish_function_lookup(node);
}
