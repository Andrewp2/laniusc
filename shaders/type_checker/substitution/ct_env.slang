// The one CT_ENV builder (docs/canonical-type-ids.md, "Environments").
//
// An environment binds type slots and constant slots of one binder:
// words = (0, type mask, constant mask); args = the bound type slots in slot
// order, then the bound constant slots in slot order; extra = (INVALID, 0).
// Envs reach only terms of their own binder, so the owner word is 0 and
// parameter owners are validated where bindings are produced.
//
// The caller supplies the bindings through ICtEnvBindings. The builder calls
// binding() from one site, at most twice per candidate slot: once to find the
// bound slots and compare them with the published environment, and once,
// only when they differ, to write the new key.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
import type_checker.substitution.ct_spare;

public interface ICtEnvBindings
{
    // The canonical ID bound to `item` (type slot 0..31, or 32 + constant
    // slot), or an unresolved reference when the slot is unbound.
    [mutating] uint binding(uint item);
}

// Bindings that are unresolved are left out of the environment (a hole).
// Without it, an unresolved candidate makes the result CT_UNKNOWN.
public static const uint CT_ENV_PARTIAL = 1u;

public static const uint CT_ENV_SLOTS = 32u;

// The environment of `b`'s bindings for the candidate slots `type_mask` and
// `const_mask`: `prior` itself when it binds exactly the same slots to the
// same IDs, else the interned environment; CT_UNKNOWN on a missing binding
// (without CT_ENV_PARTIAL) or an interning overflow.
public uint ct_env_publish<B : ICtEnvBindings>(inout B b, uint type_mask, uint const_mask,
    uint flags, uint prior, inout CtSpare spare)
{
    bool partial = (flags & CT_ENV_PARTIAL) != 0u;
    bool same = ct_is_record(prior) && ct_kind(prior) == CT_KIND_ENV;
    uint3 prior_words = same ? ct_words(prior) : uint3(0u, 0u, 0u);
    uint types = 0u;
    uint constants = 0u;
    uint pending_types = type_mask;
    uint pending_constants = const_mask;
    CtKey key = ct_empty_key();
    bool writing = false;
    uint index = 0u;
    // The first pass visits each candidate slot, the second each bound one;
    // the step between them begins the key.
    for (uint step = 0u; step <= 4u * CT_ENV_SLOTS; step++)
    {
        if (pending_types == 0u && pending_constants == 0u)
        {
            if (writing) break;
            if (same && prior_words.y == types && prior_words.z == constants) return prior;
            key = ct_key_begin(CT_KIND_ENV, countbits(types) + countbits(constants),
                countbits(types), uint3(0u, types, constants));
            if (!ct_spare_reserve(spare, key)) return CT_UNKNOWN;
            writing = true;
            pending_types = types;
            pending_constants = constants;
            if (pending_types == 0u && pending_constants == 0u) break;
        }
        bool constant = pending_types == 0u;
        uint slot = firstbitlow(constant ? pending_constants : pending_types);
        if (constant) pending_constants &= pending_constants - 1u;
        else pending_types &= pending_types - 1u;
        uint bit = 1u << slot;
        uint id = b.binding(constant ? CT_ENV_SLOTS + slot : slot);
        bool bound = ct_is_resolved(id) && ct_is_constant(id) == constant;
        if (writing)
        {
            if (!bound) return CT_UNKNOWN;
            ct_key_arg(key, index, id);
            index++;
            continue;
        }
        if (!bound)
        {
            if (!partial) return CT_UNKNOWN;
            continue;
        }
        if (constant) constants |= bit; else types |= bit;
        uint prior_mask = constant ? prior_words.z : prior_words.y;
        uint ordinal = countbits(prior_mask & (bit - 1u)) + (constant ? countbits(prior_words.y) : 0u);
        if (same && ((prior_mask & bit) == 0u || ct_arg(prior, ordinal) != id)) same = false;
    }
    if (!writing || !key.ok) return CT_UNKNOWN;
    return ct_spare_publish(key, uint2(0xffffffffu, 0u), true, spare);
}
