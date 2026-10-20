// The route of a bound-member call of the closure (closure_calls.slang,
// closure_bound_call) under one instance environment, as methods/09 routes
// it in a replay: the closed receiver R = E(P) selects the implementation of
// the member's trait whose receiver pattern matches R. 03c inserts the
// generic implementation method it reaches; the instance table types the
// call's row from it (table_rows.slang). Included after closure_calls.slang.
//
// v1 routes a pattern that is R's named head applied to the implementation's
// type and constant parameters (each slot at least once) or to closed
// arguments equal to R's. Type and constant parameters have separate slots
// (methods/09 leaf_slot); a constant binds R's constant operand there, as
// 09 publishes it (identity mode 0). Anything else is left to the replays:
// a nested parameter, a method with parameters of its own, an imported
// trait or receiver head, a pattern without a canonical ID, or no unique
// match.
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_lookup_head;
StructuredBuffer<uint> method_lookup_next;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;

static const uint BOUND_NO_MATCH = 0u;
static const uint BOUND_CONCRETE = 1u;
static const uint BOUND_GENERIC = 2u;
static const uint BOUND_UNKNOWN = 3u;
static const uint TRAIT_REFERENCE_DEPENDENCY_BIT = 0x80000000u;

// Whether implementation `impl` implements local trait item `trait`
// (methods/09 `implements`, local bound).
bool implements_local(uint impl, uint trait)
{
    if (!valid_node(impl)) return false;
    uint reference = predicate_bound_reference[impl];
    return (reference & TRAIT_REFERENCE_DEPENDENCY_BIT) == 0u &&
        reference < min(decl_count_out[0u], gParams.n_tokens) && decl_hir_node[reference] == trait;
}

// The slot of pattern leaf `leaf` among its kind's parameters (type slots
// below `counts.x`, constant slots below `counts.y`), or INVALID for a
// dependency parameter, another kind than `constant`, or a slot past its
// kind's count.
uint pattern_slot(uint leaf, bool constant, uint2 counts)
{
    if (!ct_is_param(leaf) || ct_is_dep_param(leaf) || ct_is_const_param(leaf) != constant) return INVALID;
    uint token = ct_param_token(leaf);
    uint slot = constant ? SourceSlots().const_slot(token) : SourceSlots().type_slot(token);
    return slot < (constant ? counts.y : counts.x) ? slot : INVALID;
}

// The receiver's argument where pattern `pattern` first spells slot `slot`
// of kind `constant` (helper: the loop returns from inside instead of
// breaking).
uint slot_binding(uint pattern, uint actual, uint slot, bool constant, uint2 counts)
{
    uint arity = ct_arity(pattern);
    for (uint index = 0u; index < arity; index++)
        if (pattern_slot(ct_arg(pattern, index), constant, counts) == slot) return ct_arg(actual, index);
    return CT_UNKNOWN;
}

// The slots generic pattern `pattern` binds against receiver `actual` (x
// type slots, y constant slots; see the file comment), or INVALID in x when
// they do not match that way. `flat` is false when the pattern has a child
// this v1 cannot compare.
uint2 bind_flat_pattern(uint pattern, uint actual, uint2 counts, out bool flat)
{
    flat = true;
    if (!ct_is_stored(pattern) || !ct_is_stored(actual) || any(ct_head[pattern] != ct_head[actual]))
        return uint2(INVALID, 0u);
    uint arity = ct_arity(pattern);
    uint2 bound = uint2(0u, 0u);
    for (uint index = 0u; index < arity; index++)
    {
        uint child = ct_arg(pattern, index);
        uint value = ct_arg(actual, index);
        if (ct_is_param(child))
        {
            bool constant = ct_is_const_param(child);
            uint slot = pattern_slot(child, constant, counts);
            if (slot == INVALID) { flat = false; return uint2(INVALID, 0u); }
            if (!ct_closed(value) || ct_is_constant(value) != constant) return uint2(INVALID, 0u);
            uint bit = 1u << slot;
            uint seen = constant ? bound.y : bound.x;
            if ((seen & bit) != 0u && slot_binding(pattern, actual, slot, constant, counts) != value)
                return uint2(INVALID, 0u);
            if (constant) bound.y |= bit;
            else bound.x |= bit;
        }
        else if (!ct_closed(child)) { flat = false; return uint2(INVALID, 0u); }
        else if (child != value || !ct_is_resolved(child)) return uint2(INVALID, 0u);
    }
    return bound;
}

// How method row `row` answers bound call `name_id` of trait `trait` on
// receiver `actual` (BOUND_*); `counts` are its implementation's type and
// constant parameter counts.
uint match_candidate(uint row, uint name_id, uint trait, uint actual, out uint2 counts)
{
    counts = uint2(0u, 0u);
    HirMethodCore core = compact_method_cores[row];
    uint candidate = core.name_token;
    if (!valid_token(candidate) || method_decl_name_id[candidate] != name_id ||
        !implements_local(core.impl_node, trait)) return BOUND_NO_MATCH;
    uint pattern = ct_ref(method_decl_receiver_ref_tag[candidate], method_decl_receiver_ref_payload[candidate]);
    if (!ct_is_resolved(pattern)) return BOUND_UNKNOWN;
    uint parameters = compact_generic_param_ranges[core.impl_node].count;
    if (parameters == 0u) return ct_closed(pattern) && pattern == actual ? BOUND_CONCRETE : BOUND_NO_MATCH;
    uint member = fn_hir_by_decl_token[candidate];
    uint impl_token = hir_generic_owner_token(compact_hir_core[core.impl_node],
        compact_hir_payload[core.impl_node], gParams.n_tokens);
    if (parameters >= 32u || !valid_node(member) || compact_generic_param_ranges[member].count != 0u ||
        !valid_token(impl_token))
        return BOUND_UNKNOWN;
    uint constants = type_decl_const_param_count_by_owner_token[impl_token];
    if (constants > parameters) return BOUND_UNKNOWN;
    counts = uint2(parameters - constants, constants);
    bool flat;
    uint2 bound = bind_flat_pattern(pattern, actual, counts, flat);
    if (!flat) return BOUND_UNKNOWN;
    if (bound.x == INVALID) return BOUND_NO_MATCH;
    return countbits(bound.x) == counts.x && countbits(bound.y) == counts.y ? BOUND_GENERIC : BOUND_UNKNOWN;
}

// The receiver of the bound call at method token `token` in its template:
// the type parameter its value has (substitute it under the caller's
// environment for the closed receiver).
uint bound_call_receiver(uint token)
{
    return ct_ref(TYPE_REF_GENERIC_PARAM, method_call_receiver_ref_payload[token]);
}

// Route the bound call at method token `token` on closed receiver
// `receiver`: the implementation method row (compact_method_cores) it
// selects, or INVALID when the route is unknown or not unique. `env` is a
// generic implementation method's tagged environment (its implementation's
// type parameters, then its constant parameters, tagged with the method's
// HIR row + 1, as 03c inserts it), CT_NONE for a nongeneric one, and
// CT_UNKNOWN when it cannot be interned or stays open.
uint route_bound_receiver(uint token, uint receiver, inout CtSpare env_spare, out uint env)
{
    env = CT_UNKNOWN;
    uint declaration = ct_named_decl_token(receiver);
    uint name_id = method_call_name_id[token];
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    if (!ct_is_resolved(receiver) || !ct_closed(receiver) || !valid_token(declaration) ||
        name_id == INVALID || count == 0u)
        return INVALID;
    uint trait = bound_member_trait(call_fn_index[token]);
    MethodReceiverHead head;
    head.shape = 3u;
    head.identity = uint3(declaration, 0u, 0u);
    head.arity = ct_arity(receiver);
    uint link = method_lookup_head[method_lookup_bucket(head, name_id, count)];
    uint matches = 0u;
    uint selected = INVALID;
    uint2 selected_counts = uint2(0u, 0u);
    bool unknown = false;
    for (uint visited = 0u; visited < count && link != 0u; visited++)
    {
        uint row = link - 1u;
        if (row >= count) { unknown = true; link = 0u; continue; }
        link = method_lookup_next[row];
        uint2 counts;
        uint answer = match_candidate(row, name_id, trait, receiver, counts);
        if (answer == BOUND_UNKNOWN) unknown = true;
        if (answer != BOUND_CONCRETE && answer != BOUND_GENERIC) continue;
        matches++;
        selected = row;
        selected_counts = counts;
    }
    if (unknown || matches != 1u) return INVALID;
    // A nongeneric implementation's method is concrete.
    uint parameters = selected_counts.x + selected_counts.y;
    if (parameters == 0u)
    {
        env = CT_NONE;
        return selected;
    }
    uint candidate = compact_method_cores[selected].name_token;
    uint member = fn_hir_by_decl_token[candidate];
    uint pattern = ct_ref(method_decl_receiver_ref_tag[candidate], method_decl_receiver_ref_payload[candidate]);
    CtKey key = ct_key_begin(CT_KIND_ENV, parameters, selected_counts.x,
        uint3(member + 1u, low_bits(selected_counts.x), low_bits(selected_counts.y)));
    if (!ct_spare_reserve(env_spare, key)) return selected;
    // Type slots, then constant slots (ct_env_binding).
    for (uint index = 0u; index < parameters; index++)
    {
        bool constant = index >= selected_counts.x;
        uint slot = constant ? index - selected_counts.x : index;
        ct_key_arg(key, index, slot_binding(pattern, receiver, slot, constant, selected_counts));
    }
    if (!key.ok || (key.flags & (CTF_TYPE_PARAM | CTF_CONST_PARAM)) != 0u) return selected;
    env = ct_spare_publish(key, uint2(0xffffffffu, 0u), true, env_spare);
    return selected;
}

// route_bound_receiver under caller environment `caller`.
uint route_bound_call(uint token, uint caller, inout CtSpare subst_spare,
    inout CtSpare env_spare, out uint env)
{
    uint receiver = ct_subst(SourceSlots(), caller, bound_call_receiver(token), true, subst_spare);
    return route_bound_receiver(token, receiver, env_spare, env);
}
