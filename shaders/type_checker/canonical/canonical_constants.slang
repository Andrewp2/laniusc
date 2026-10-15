// Constant keys shared by every interning source (checked constants and
// dependency signature nodes), so one constant has one key whichever source
// interns it first: CC_VALUE for a typed value with its count facts, and
// CC_CAST for a symbolic count projection.
import type_checker.canonical.canonical_api;
import constant_value;
import primitive_types;

// Key builders build a complete key, with its ct_extra facts, and return
// CT_KEY_BUILT, or return the final reference (a sentinel) without a key.
// The caller stores the key in a record and publishes it.
public static const uint CT_KEY_BUILT = 0u;

public CtKey ct_empty_key()
{
    return ct_key_begin(0u, 0u, 0u, uint3(0u, 0u, 0u));
}

// The typed value key. The count class is a small dynamic record interned
// first, so a value's stored facts do not depend on which lane publishes it.
public uint ct_build_value(uint3 value, out CtKey key)
{
    key = ct_empty_key();
    uint count;
    bool countable = constant_value_to_count(value, count);
    uint klass = CT_NONE;
    if (countable)
    {
        uint spare = CT_NONE;
        klass = cc_intern_count(count, spare);
        if (!ct_is_resolved(klass)) return CT_UNKNOWN;
    }
    key = ct_key_begin(CC_KIND_VALUE, 0u, 0u, value);
    key.extra = uint2(countable ? count : 0xffffffffu, klass);
    return CT_KEY_BUILT;
}

// A projection to the integer scalar `target` of the interned constant
// `child`. A concrete count folds to the target's value once every level
// fits: `fold` is set with `value`, and the caller builds the value key (at
// its one ct_build_value site). A symbolic child is CC_CAST(target; child),
// counted like its child. `param_scalar` is the declared scalar of `child`
// when it is a constant parameter.
public uint ct_build_projection(uint target, uint child, uint param_scalar,
    out bool fold, out uint3 value, out CtKey key)
{
    key = ct_empty_key();
    fold = false;
    value = uint3(0u, 0u, 0u);
    // Acquire: the child's record was published before its reference.
    DeviceMemoryBarrier();
    uint kind = ct_kind(child);
    if (kind == CC_KIND_VALUE)
    {
        uint count = cc_count(child);
        // A value that is not a count, or does not fit the target, has no
        // folded identity: an unsupported shape, not an empty candidate.
        fold = count != 0xffffffffu && constant_value_from_count(count, target, value);
        return fold ? CT_KEY_BUILT : CT_UNKNOWN;
    }
    uint child_scalar = ct_is_const_param(child) ? param_scalar
        : kind == CC_KIND_CAST ? ct_words(child).x : 0u;
    if (!scalar_is_integer(child_scalar) || !scalar_is_integer(target)) return CT_UNKNOWN;
    key = ct_key_begin(CC_KIND_CAST, 1u, 0u, uint3(target, 0u, 0u));
    if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
    ct_key_arg(key, 0u, child);
    if (!key.ok) return CT_UNKNOWN;
    key.extra = uint2(0xffffffffu, cc_count_class(child));
    return CT_KEY_BUILT;
}
