// The edges and instance keys of the instance closure (instance_closure.slang),
// shared by 01_mark and 03_expand. Included after the kernel's own Params,
// HIR buffers and INVALID.
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> type_decl_generic_param_count;

static const uint HIR_FN = 3u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_FILE = 1u;
static const uint HIR_IMPL = 35u;
static const uint HIR_ITEM = 2u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_node(uint node) { return node < hir_count(); }
bool valid_token(uint token) { return token < gParams.n_tokens; }

#include "../calls/callable_generic_requirements.slang"

// The low `count` bits.
uint low_bits(uint count) { return count == 0u ? 0u : 0xffffffffu >> (32u - min(count, 32u)); }

// The callee token of a call node, or INVALID (as 02_publish_call_envs,
// whose call_env_ct rows it reads).
uint call_token(uint call)
{
    uint kind = compact_hir_core[call].kind;
    if (kind == 28u || kind == 33u) return compact_hir_core[call].token_start;
    if (kind != 19u) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return INVALID;
    bool dotted = compact_hir_core[callee].kind == 21u;
    uint token = dotted ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    return token < gParams.n_tokens ? token : compact_hir_core[callee].token_start;
}

// Whether function row `row` has a body a replay can instantiate: a
// top-level function or a method of an impl. Trait members (required or
// provided) are reached through bounds and stay with the replays. A `pub`
// item row wraps a public function or method and is not a container; only
// a trait item or another function is.
bool closure_body(uint row)
{
    uint node = compact_hir_core[row].parent;
    for (uint depth = 0u; depth < hir_count() && valid_node(node); depth++)
    {
        uint kind = compact_hir_core[node].kind;
        if (kind == HIR_IMPL) return true;
        if (kind == HIR_FILE) return compact_hir_payload[row].a == HIR_ITEM_KIND_FN;
        if (kind == HIR_FN) return false;
        if (kind == HIR_ITEM && compact_hir_payload[node].a == HIR_ITEM_KIND_TRAIT) return false;
        uint parent = compact_hir_core[node].parent;
        if (parent >= node) break;
        node = parent;
    }
    return compact_hir_payload[row].a == HIR_ITEM_KIND_FN;
}

// A call of the closure: a call expression row (the row the retained call
// facts name) whose callee is a generic local function body. Its callee path
// row resolves to the same function but is not a call. Sets its callee
// token, the callee's function row and its candidate slot masks (the
// composed arity, as candidate_masks in 02_publish_call_envs).
bool closure_call(uint call, out uint token, out uint callee, out uint2 masks)
{
    callee = INVALID;
    masks = uint2(0u, 0u);
    token = INVALID;
    if (compact_hir_core[call].kind != HIR_CALL_EXPR) return false;
    token = call_token(call);
    if (!valid_token(token) || call_dependency_library_id[token] != INVALID) return false;
    uint target = call_fn_index[token];
    if (!valid_token(target)) return false;
    uint row = fn_hir_by_decl_token[target];
    if (!valid_node(row) || compact_hir_core[row].kind != HIR_FN ||
        hir_generic_owner_token(compact_hir_core[row], compact_hir_payload[row], gParams.n_tokens) != target ||
        !closure_body(row)) return false;
    uint2 counts = required_callable_generic_counts(token);
    masks = uint2(low_bits(counts.x), low_bits(counts.y));
    callee = row;
    return (masks.x | masks.y) != 0u;
}

StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> predicate_method_contract_owner_hir;

static const uint HIR_MEMBER_EXPR = 21u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;

// The trait HIR item whose required member is declaration `target`, or
// INVALID (a required member publishes no method row; methods/02_collect).
uint bound_member_trait(uint target)
{
    if (!valid_token(target) || method_decl_method_row[target] != INVALID) return INVALID;
    uint member = fn_hir_by_decl_token[target];
    if (!valid_node(member)) return INVALID;
    uint trait = predicate_method_contract_owner_hir[member];
    return valid_node(trait) && compact_hir_core[trait].kind == HIR_ITEM &&
        compact_hir_payload[trait].a == HIR_ITEM_KIND_TRAIT ? trait : INVALID;
}

// A bound-member call of the closure (D3): `value.member(...)` whose
// receiver is a type parameter (methods/07a) and whose callee is the
// required member of a trait of this unit. A replay routes it to the
// implementation its concrete receiver selects (methods/09); 03c routes it
// under each instance environment. Sets the method token.
bool closure_bound_call(uint call, out uint token)
{
    token = INVALID;
    if (compact_hir_core[call].kind != HIR_CALL_EXPR) return false;
    uint callee = compact_hir_payload[call].a;
    if (!valid_node(callee) || compact_hir_core[callee].kind != HIR_MEMBER_EXPR) return false;
    token = compact_hir_payload[callee].c;
    if (!valid_token(token) || call_dependency_library_id[token] != INVALID) return false;
    if (method_call_receiver_ref_tag[token] != TYPE_REF_GENERIC_PARAM ||
        !valid_token(method_call_receiver_ref_payload[token])) return false;
    return bound_member_trait(call_fn_index[token]) != INVALID;
}

// The instance key of the call at `token` (callee row `callee`, candidate
// masks `masks`) inside the instance whose tagged environment is `caller`
// (CT_NONE in a nongeneric function): the call's value environment with
// every binding substituted, tagged with the callee. CT_NONE when the call
// environment has a hole or stays open there, CT_UNKNOWN when substitution
// or interning fails. The bindings substitute through `subst_spare` while
// the key's arguments sit in `env_spare`'s block, so the two never share.
uint closure_instance_env(uint token, uint callee, uint2 masks, uint caller,
    inout CtSpare subst_spare, inout CtSpare env_spare)
{
    uint environment = ct_call_env(token).x;
    if (!ct_is_record(environment) || ct_kind(environment) != CT_KIND_ENV) return CT_NONE;
    uint3 words = ct_words(environment);
    if (words.y != masks.x || words.z != masks.y) return CT_NONE;
    uint arity = ct_arity(environment);
    CtKey key = ct_key_begin(CT_KIND_ENV, arity, ct_type_slots(environment),
        uint3(callee + 1u, words.y, words.z));
    if (!ct_spare_reserve(env_spare, key)) return CT_UNKNOWN;
    for (uint index = 0u; index < arity; index++)
    {
        uint binding = ct_subst(SourceSlots(), caller, ct_arg(environment, index), true, subst_spare);
        if (!ct_is_resolved(binding)) return CT_UNKNOWN;
        ct_key_arg(key, index, binding);
    }
    if (!key.ok) return CT_UNKNOWN;
    if ((key.flags & (CTF_TYPE_PARAM | CTF_CONST_PARAM)) != 0u) return CT_NONE;
    return ct_spare_publish(key, uint2(0xffffffffu, 0u), true, env_spare);
}
