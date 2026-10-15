// Declaration-side references under a receiver application, over canonical
// IDs (in place of checked_scoped_reference's scoped hash, equality and
// index walkers). A reference written in a declaration's scope (a field's
// declared type) is substituted under the application row that binds that
// declaration's parameters: its ID under the application's ID (ct_subst),
// realized as a checked row (ct_realize). The caller names the receiver of
// the reference's own declaration; owners are validated where receivers are
// chosen.
//
// Stackless: rows produced during inference are interned on demand
// (ct_intern_checked), and the substitution and realization keep their own
// progress records.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.mutable_checked_type_graph;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;

// Why a scoped reference has no result: unsupported or malformed (INVALID),
// a full table or arena (CAPACITY), or another lane writing a row it needs
// (BUSY; a later dispatch finds that row).
public static const uint CT_SCOPED_INVALID = 1u;
public static const uint CT_SCOPED_CAPACITY = 2u;
public static const uint CT_SCOPED_BUSY = 3u;

// The checked reference of (tag, payload) under application row `context`
// (INVALID: the reference is already in the caller's scope). Scalars and
// parameters with a slot are their own references; a parameter under a
// context is the context's argument, which is already in the caller's scope
// and is not substituted again; an instance outside a context, or a closed
// one, is itself. `failure` is 0 on success, else CT_SCOPED_*.
public bool ct_scoped_reference(uint tag, uint payload, uint context, uint token_capacity,
    out uint result_tag, out uint result_payload, out uint failure)
{
    static const uint INVALID = 0xffffffffu;
    result_tag = 0u; result_payload = INVALID;
    failure = CT_SCOPED_INVALID;
    uint rows = mutable_type_capacity();
    if (context != INVALID && ((context & 0x80000000u) != 0u || context >= rows)) return false;
    if (tag == 2u && context != INVALID)
    {
        uint slot = payload < token_capacity ? type_generic_param_slot_by_token[payload] : INVALID;
        if (slot == INVALID || !MutableCheckedTypeGraph.environment_argument(context, slot, tag, payload))
            return false;
        context = INVALID;
    }
    if ((tag == 1u && payload != 0u && payload != INVALID) ||
        (tag == 2u && payload < token_capacity && type_generic_param_slot_by_token[payload] != INVALID))
    {
        result_tag = tag; result_payload = payload;
        failure = 0u;
        return true;
    }
    if (tag != 3u || payload >= rows) return false;
    uint kind = type_instance_kind[payload];
    if (kind < 1u || kind > 4u) return false;
    if (context == INVALID)
    {
        result_tag = 3u; result_payload = payload;
        failure = 0u;
        return true;
    }
    uint row_spare = CT_NONE;
    uint term = ct_intern_checked<CtMutableRows>(3u, payload, row_spare);
    if (!ct_is_resolved(term)) return false;
    if (ct_closed(term))
    {
        result_tag = 3u; result_payload = payload;
        failure = 0u;
        return true;
    }
    uint environment = ct_intern_checked<CtMutableRows>(3u, context, row_spare);
    if (!ct_is_record(environment) || ct_kind(environment) != CT_KIND_NAMED) return false;
    CtSpare spare = ct_spare_none();
    uint id = ct_subst(SourceSlots(), environment, term, true, spare);
    if (!ct_is_resolved(id) || ct_is_constant(id))
    {
        uint overflow = ct_subst_counts[CT_SUBST_COUNT_OVERFLOW];
        if ((overflow & (CT_SUBST_OVERFLOW_MEMO | CT_SUBST_OVERFLOW_ROWS)) != 0u ||
            ct_counts[CT_COUNT_OVERFLOW] != 0u) failure = CT_SCOPED_CAPACITY;
        return false;
    }
    uint realized;
    uint2 reference = ct_realize(id, realized);
    if (realized == CT_REALIZE_BUSY) { failure = CT_SCOPED_BUSY; return false; }
    if (realized == CT_REALIZE_CAPACITY) { failure = CT_SCOPED_CAPACITY; return false; }
    if (realized != 0u || reference.x < 1u || reference.x > 3u || reference.y == INVALID) return false;
    result_tag = reference.x; result_payload = reference.y;
    failure = 0u;
    return true;
}
