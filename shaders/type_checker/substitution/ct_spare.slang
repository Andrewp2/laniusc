// A lane's unpublished canonical record and argument block, binding slots
// of parameter leaves, and environment bindings. Graph-free, so every kernel
// can import it. (Placeholder for P3's p3-ct-subst version of this module:
// same names and contracts; take P3's on merge.)
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;

// A lane's unpublished record and argument block. Both are reused for the
// lane's next key until a key is published with them; nobody else reads
// them, so rewriting is safe.
public struct CtSpare
{
    public uint record;
    public uint args;
    public uint arg_len;
}

public CtSpare ct_spare_none()
{
    CtSpare spare;
    spare.record = CT_NONE;
    spare.args = 0u;
    spare.arg_len = 0u;
    return spare;
}

// Point the key's arguments at the lane's argument block.
public bool ct_spare_reserve(inout CtSpare spare, inout CtKey key)
{
    uint arity = (key.head.x >> 8u) & 0xffu;
    if (arity == 0u || !key.ok) return key.ok;
    if (spare.arg_len < arity)
    {
        if (!ct_key_reserve_args(key)) return false;
        spare.args = key.arg_base;
        spare.arg_len = arity;
        return true;
    }
    key.arg_base = spare.args;
    return true;
}

// Look a built key up, or (when `intern`) publish it through the spare.
// Returns the published ID, CT_NONE for a lookup miss, or CT_UNKNOWN.
public uint ct_spare_publish(CtKey key, uint2 extra, bool intern, inout CtSpare spare)
{
    uint found = ct_lookup(key);
    if (found != CT_NONE || !intern) return found;
    if (spare.record == CT_NONE) spare.record = ct_alloc_record();
    if (spare.record == CT_UNKNOWN) { spare.record = CT_NONE; return CT_UNKNOWN; }
    ct_key_store(key, spare.record, extra);
    uint id = ct_intern(spare.record, key);
    if (id == spare.record)
    {
        spare.record = CT_NONE;
        spare.arg_len = 0u;
    }
    return id;
}

// ---------------------------------------------------------------------------
// Binding slots of local parameter leaves, read from the tables the kernel
// binds. Implementations return CT_SLOT_NONE for unknown or out-of-range
// tokens.
public static const uint CT_SLOT_NONE = 32u;

public interface ICtSlots
{
    uint type_slot(uint token);
    uint const_slot(uint token);
    // The declared scalar of constant parameter `token`, 0 when unsupported.
    uint const_scalar(uint token);
}

// The binding slot of a parameter leaf; dependency leaves carry their own.
public uint ct_param_slot<S : ICtSlots>(S slots, uint param)
{
    if (ct_is_dep_param(param)) return ct_dep_param_slot(param);
    uint token = ct_param_token(param);
    uint slot = ct_is_const_param(param) ? slots.const_slot(token) : slots.type_slot(token);
    return min(slot, CT_SLOT_NONE);
}

// The declared scalar of a constant parameter leaf, 0 when unsupported.
public uint ct_param_scalar<S : ICtSlots>(S slots, uint param)
{
    return ct_is_dep_param(param) ? ct_dep_param_scalar(param) : slots.const_scalar(ct_param_token(param));
}

// The `ordinal`-th set bit of `mask`, or 32.
public uint ct_nth_set_bit(uint mask, uint ordinal)
{
    for (uint step = 0u; step < ordinal && mask != 0u; step++) mask &= mask - 1u;
    return mask == 0u ? 32u : firstbitlow(mask);
}

// The binding of type (or constant) slot `slot`, or CT_UNKNOWN when the
// environment does not bind it. An environment is a CT_ENV record or a
// named application (type slot i is its i-th type operand).
public uint ct_env_binding(uint env, uint slot, bool constant)
{
    if (slot >= 32u) return CT_UNKNOWN;
    uint kind = ct_kind(env);
    uint index = 32u;
    if (kind == CT_KIND_ENV)
    {
        uint3 words = ct_words(env);
        uint mask = constant ? words.z : words.y;
        if ((mask & (1u << slot)) != 0u)
            index = countbits(mask & ((1u << slot) - 1u)) + (constant ? countbits(words.y) : 0u);
    }
    else if (kind == CT_KIND_NAMED)
    {
        uint arity = ct_arity(env);
        uint operands = arity >= 32u ? 0xffffffffu : (1u << arity) - 1u;
        uint constants = ct_named_constant_mask(env);
        index = ct_nth_set_bit(constant ? constants & operands : operands & ~constants, slot);
    }
    uint binding = index < 32u ? ct_arg(env, index) : CT_NONE;
    if (!ct_is_resolved(binding) || ct_is_constant(binding) != constant) return CT_UNKNOWN;
    return binding;
}
