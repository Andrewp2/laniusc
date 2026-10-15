// Matching a declared pattern against an actual type over canonical IDs
// (docs/canonical-type-ids.md, "Matching"). ct_match binds the pattern's
// parameters so that the pattern under the bindings is the actual:
//
// - Only the pattern's open nodes are visited. A closed child is compared by
//   ID, and a parameter child is an occurrence of its binding slot.
// - Repeated type parameters agree by ID.
// - Constant parameters take claims. A named operand or the operand of a cast
//   is an exact claim: the actual typed constant, whose scalar must be the
//   declared one. An array length is a count claim: the actual length's
//   count class, which must fit the declared scalar. All claims of a slot
//   share one count class and all exact claims one typed ID, and an exact
//   claim wins. A slot with count claims only is bound to the count in the
//   declared scalar: a value, the counted parameter itself, or a symbolic
//   cast that keeps its pending fit. Each actual array keeps its own fit
//   obligations.
// - A slot that the prior environment binds is checked against that binding,
//   as if it were an exact claim.
// - A root slice pattern may accept an actual array (the root coercion).
//
// The bindings are interned as a CT_ENV record (owner 0; bound type slots,
// then bound constant slots, as type_checker/substitution builds call
// environments). There is no stack and no per-lane array: a shape pass
// checks heads and closed children and collects the parameter masks, then
// one pass per bound slot folds that slot's occurrences. Each pass walks
// the pattern by re-descending from the root along a packed child path.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_spare;
import constant_value;
import primitive_types;

// Flags: root 0 (root 1) may accept an actual array for a pattern slice.
public static const uint CT_MATCH_SLICE_ROOT0 = 1u;
public static const uint CT_MATCH_SLICE_ROOT1 = 2u;

// Results other than an environment ID.
public static const uint CT_MATCH_FAILED = 0xfffffffeu;   // CT_UNKNOWN: no match
public static const uint CT_MATCH_OVERFLOW = 0xffffffffu; // CT_PENDING: interning failed
public static const uint CT_MATCH_OK = 0xfffffffdu;       // CT_NONE: matched, nothing interned

static const uint SLOTS = 32u;
// Packed path: five bits per level, six levels per word; level 0 is the
// virtual parent of the root.
static const uint DEPTH_LIMIT = 24u;
static const uint STEP_LIMIT = 1024u;
// Unset count class of a slot.
static const uint NO_CLASS = 0xffffffffu;

static const uint POSITION_TYPE = 0u;
static const uint POSITION_EXACT = 1u;
static const uint POSITION_COUNT = 2u;

uint path_index(uint4 path, uint level)
{
    uint word = level / 6u;
    uint packed = word == 0u ? path.x : word == 1u ? path.y : word == 2u ? path.z : path.w;
    return (packed >> ((level % 6u) * 5u)) & 31u;
}

uint4 path_with(uint4 path, uint level, uint index)
{
    uint word = level / 6u;
    uint shift = (level % 6u) * 5u;
    uint keep = ~(31u << shift);
    uint bits = index << shift;
    return uint4(word == 0u ? (path.x & keep) | bits : path.x,
        word == 1u ? (path.y & keep) | bits : path.y,
        word == 2u ? (path.z & keep) | bits : path.z,
        word == 3u ? (path.w & keep) | bits : path.w);
}

// The scalar of a typed constant: a value's or cast's own, a constant
// parameter's declared one; 0 for anything else.
uint typed_scalar<S : ICtSlots>(S slots, uint ref)
{
    if (ct_is_const_param(ref)) return ct_param_scalar<S>(slots, ref);
    uint kind = ct_kind(ref);
    return kind == CC_KIND_VALUE || kind == CC_KIND_CAST ? ct_words(ref).x : 0u;
}

// One slot's claims so far.
struct SlotClaims
{
    // The type binding, or the exact (or prior) constant binding; CT_NONE.
    uint binding;
    // The count class every constant claim shares, or NO_CLASS.
    uint klass;
    // The declared scalar of a constant slot, from its occurrences.
    uint scalar;
    bool exact;
}

// Occurrence of pattern parameter `leaf` at `position` against `actual`.
// The shape pass (item 0) validates the parameter and collects its slot;
// slot pass `item` (1 + type slot, or 33 + constant slot) folds its own
// slot's claim.
bool fold_occurrence<S : ICtSlots>(S slots, uint leaf, uint position, uint actual, uint item,
    inout uint type_mask, inout uint const_mask, inout SlotClaims claims)
{
    bool constant = ct_is_const_param(leaf);
    uint slot = ct_param_slot<S>(slots, leaf);
    uint scalar = constant ? ct_param_scalar<S>(slots, leaf) : 0u;
    if (item == 0u)
    {
        // Owner validation: a parameter of the matched declaration has a
        // slot of its own kind, and a count claim needs an integer.
        if (slot >= SLOTS || constant != (position != POSITION_TYPE)) return false;
        if (constant && (!constant_scalar_is_supported(scalar) ||
            (position == POSITION_COUNT && !scalar_is_integer(scalar)))) return false;
        // Type and constant parameters have slots of their own.
        if (constant) const_mask |= 1u << slot;
        else type_mask |= 1u << slot;
        return true;
    }
    if (item != (constant ? SLOTS + 1u : 1u) + slot) return true;
    if (!ct_is_resolved(actual) || ct_kind(actual) == CT_KIND_ENV) return false;
    if (!constant)
    {
        if (ct_is_constant(actual)) return false;
        if (claims.binding == CT_NONE) claims.binding = actual;
        return claims.binding == actual;
    }
    if (claims.scalar != 0u && claims.scalar != scalar) return false;
    claims.scalar = scalar;
    uint klass = actual;
    if (position == POSITION_COUNT)
    {
        // An actual length is a count class: a count that must fit the
        // declared scalar, or an integer constant parameter.
        uint3 value;
        bool count = ct_kind(actual) == CC_KIND_COUNT;
        if (count ? !constant_value_from_count(cc_count(actual), scalar, value)
            : !ct_is_const_param(actual) || !scalar_is_integer(typed_scalar<S>(slots, actual))) return false;
    }
    else
    {
        if (!ct_is_constant(actual) || typed_scalar<S>(slots, actual) != scalar) return false;
        if (claims.exact && claims.binding != actual) return false;
        claims.binding = actual;
        claims.exact = true;
        klass = cc_count_class(actual);
    }
    if (claims.klass != NO_CLASS && claims.klass != klass) return false;
    claims.klass = klass;
    return true;
}

// One pass over the root pair (pattern, actual).
bool match_pass<S : ICtSlots>(S slots, uint pattern, uint actual, bool slice, uint item,
    inout uint type_mask, inout uint const_mask, inout SlotClaims claims)
{
    uint depth = 0u;
    uint4 path = uint4(0u, 0u, 0u, 0u);
    uint cursor = 0u;
    bool enter = true;
    for (uint step = 0u; step < STEP_LIMIT; step++)
    {
        // Re-descend to the current node; depth 1 is the root.
        uint node = pattern;
        uint other = actual;
        for (uint level = 2u; level <= depth; level++)
        {
            uint index = path_index(path, level);
            node = ct_arg(node, index);
            other = ct_arg(other, index);
        }
        bool top = depth == 0u;
        uint kind = top ? 0u : ct_kind(node);
        uint arity = top ? 1u : ct_arity(node);
        if (enter && !top && item == 0u)
        {
            // Heads are (kind, arity, type slots, words): the declaration of
            // a named type, the target of a cast.
            bool coerce = slice && depth == 1u && kind == CT_KIND_SLICE && ct_kind(other) == CT_KIND_ARRAY;
            if (!ct_is_stored(other) || arity > SLOTS || kind < CT_KIND_NAMED ||
                (kind > CT_KIND_REF && kind != CC_KIND_CAST)) return false;
            if (!coerce && any(ct_head[node] != ct_head[other])) return false;
        }
        uint operands = kind == CT_KIND_NAMED ? ct_named_constant_mask(node) : kind == CC_KIND_CAST ? 1u : 0u;
        uint next = arity;
        for (uint index = cursor; index < arity; index++)
        {
            uint child = top ? pattern : ct_arg(node, index);
            uint value = top ? actual : ct_arg(other, index);
            bool parameter = ct_is_param(child);
            bool coerce = top && slice && ct_kind(child) == CT_KIND_SLICE && ct_kind(value) == CT_KIND_ARRAY;
            if (!parameter && ct_is_record(child) && (coerce || !ct_closed(child)))
            {
                // An open child is visited after this node's other children.
                if (next == arity) next = index;
                if (!enter) break;
                continue;
            }
            if (!enter) continue;
            if (parameter)
            {
                uint position = top ? (ct_is_const_param(child) ? POSITION_EXACT : POSITION_TYPE)
                    : kind == CT_KIND_ARRAY && index == 1u ? POSITION_COUNT
                    : ((operands >> index) & 1u) != 0u ? POSITION_EXACT : POSITION_TYPE;
                if (!fold_occurrence<S>(slots, child, position, value, item, type_mask, const_mask, claims))
                    return false;
            }
            else if (item == 0u && (child != value || !ct_is_resolved(child))) return false;
        }
        if (next < arity)
        {
            if (depth + 1u >= DEPTH_LIMIT) return false;
            depth++;
            path = path_with(path, depth, next);
            cursor = 0u;
            enter = true;
            continue;
        }
        if (top) return true;
        cursor = path_index(path, depth) + 1u;
        depth--;
        enter = false;
    }
    return false;
}

// Match up to two roots jointly (pattern1 CT_NONE for one) under `prior`, a
// CT_ENV or CT_NONE. Returns the interned environment of every parameter
// slot the patterns use, or CT_MATCH_OK without `intern`; CT_MATCH_FAILED
// when they do not match, CT_MATCH_OVERFLOW when interning failed.
// `count_mask` is the constant slots bound by count claims only (their
// claim identity is a count's).
public uint ct_match<S : ICtSlots>(S slots, uint pattern0, uint actual0, uint pattern1, uint actual1,
    uint prior, uint flags, bool intern, inout CtSpare spare, out uint count_mask)
{
    count_mask = 0u;
    uint type_mask = 0u;
    uint const_mask = 0u;
    CtKey key = ct_key_begin(0u, 0u, 0u, uint3(0u, 0u, 0u));
    uint index = 0u;
    // Item 0 is the shape pass, 1..32 the type slots, 33..64 the constant
    // slots: one pass site, one fold site.
    for (uint item = 0u; item <= 2u * SLOTS; item++)
    {
        bool constant = item > SLOTS;
        uint slot = (item - 1u) & (SLOTS - 1u);
        uint bit = 1u << slot;
        if (item == 1u && intern)
        {
            key = ct_key_begin(CT_KIND_ENV, countbits(type_mask) + countbits(const_mask),
                countbits(type_mask), uint3(0u, type_mask, const_mask));
            if (!ct_spare_reserve(spare, key)) return CT_MATCH_OVERFLOW;
        }
        if (item != 0u && ((constant ? const_mask : type_mask) & bit) == 0u) continue;
        SlotClaims claims;
        claims.binding = item == 0u ? CT_UNKNOWN : ct_env_binding(prior, slot, constant);
        if (!ct_is_resolved(claims.binding)) claims.binding = CT_NONE;
        claims.exact = claims.binding != CT_NONE;
        claims.klass = claims.exact && constant ? cc_count_class(claims.binding) : NO_CLASS;
        claims.scalar = 0u;
        for (uint root = 0u; root < 2u; root++)
        {
            uint pattern = root == 0u ? pattern0 : pattern1;
            if (root == 1u && pattern == CT_NONE) break;
            if (!match_pass<S>(slots, pattern, root == 0u ? actual0 : actual1, ((flags >> root) & 1u) != 0u,
                item, type_mask, const_mask, claims)) return CT_MATCH_FAILED;
        }
        if (item == 0u) continue;
        uint binding = claims.binding;
        if (constant && claims.exact && typed_scalar<S>(slots, binding) != claims.scalar) return CT_MATCH_FAILED;
        if (constant && !claims.exact)
        {
            count_mask |= bit;
            // Count claims only: the count in the declared scalar.
            uint klass = claims.klass;
            bool symbolic = ct_is_const_param(klass);
            uint3 value = uint3(0u, 0u, 0u);
            if (!symbolic) constant_value_from_count(cc_count(klass), claims.scalar, value);
            binding = symbolic && typed_scalar<S>(slots, klass) == claims.scalar ? klass
                : !intern ? CT_NONE
                : ct_intern_small(symbolic ? CC_KIND_CAST : CC_KIND_VALUE, symbolic ? 1u : 0u,
                    symbolic ? uint3(claims.scalar, 0u, 0u) : value, uint2(klass, 0u),
                    uint2(symbolic ? 0xffffffffu : cc_count(klass), klass), spare.record);
        }
        if (!intern) continue;
        ct_key_arg(key, index, binding);
        index++;
    }
    if (!intern) return CT_MATCH_OK;
    if (!key.ok) return CT_MATCH_OVERFLOW;
    uint environment = ct_spare_publish(key, uint2(0xffffffffu, 0u), true, spare);
    return ct_is_resolved(environment) ? environment : CT_MATCH_OVERFLOW;
}
