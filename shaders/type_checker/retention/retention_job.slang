// Job side of program retention (retention_store.slang): the frontend job's
// own tables, read once at the end of the job before its workspace is
// reused, and the job-lifetime scratch that translates them.
//
// Nothing here survives the job. Every value written to the store goes
// through one of the translations below: a declaration row becomes a
// DeclId, a parameter token a ParamId, a canonical ID a TermId, and a row,
// token or side-table index inside a body becomes relative to that body.
import primitive_types;
import hir_records;
import callable_identity;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retained_row_classes;

// Job tables (bound by their type-check graph or parser names).
public StructuredBuffer<uint> compact_hir_count;
public StructuredBuffer<HirCore> compact_hir_core;
public StructuredBuffer<HirLinks> compact_hir_links;
public StructuredBuffer<HirPayload> compact_hir_payload;
public StructuredBuffer<uint> compact_hir_nearest_fn;
public StructuredBuffer<uint> compact_generic_param_count;
public StructuredBuffer<HirGenericParam> compact_generic_params;
public StructuredBuffer<HirRange> compact_generic_param_ranges;
public StructuredBuffer<uint> compact_method_count;
public StructuredBuffer<HirMethodCore> compact_method_cores;
public StructuredBuffer<HirMethodSignature> compact_method_signatures;
public StructuredBuffer<uint> decl_id_by_name_token;
public StructuredBuffer<uint> interface_public_decl_index_by_local;
public StructuredBuffer<uint> interface_public_decl_index_by_hir;
public StructuredBuffer<uint> type_const_param_scalar_by_token;
public StructuredBuffer<uint> compact_variant_count;
public StructuredBuffer<HirVariant> compact_variants;

// Job scratch owned by the retention store's build object, never by the
// frontend workspace.
//   rt_x_counts       RT_X_* words
//   rt_x_param_key/val  token + 1 -> ParamId (open addressing)
//   rt_x_term_map     canonical ID -> TermId (RT_UNKNOWN when untranslatable)
//   rt_x_order        canonical IDs grouped by height
//   rt_x_args         translated arguments, at their canonical arg base
//   rt_x_row          per HIR row: (DeclId, directory entry, segment, token end)
public globallycoherent RWStructuredBuffer<uint> rt_x_counts;
public globallycoherent RWStructuredBuffer<uint> rt_x_param_key;
public globallycoherent RWStructuredBuffer<uint> rt_x_param_val;
public globallycoherent RWStructuredBuffer<uint> rt_x_term_map;
public globallycoherent RWStructuredBuffer<uint> rt_x_order;
public globallycoherent RWStructuredBuffer<uint> rt_x_args;
public globallycoherent RWStructuredBuffer<uint4> rt_x_row;
// A use that needs a new environment keeps the claimed slot plus one until
// 14b publishes its final term. The key fields are immutable once claimed.
public struct RtUseEnvironment
{
    public uint callee;
    public uint env;
    public uint term;
}
public globallycoherent RWStructuredBuffer<RtUseEnvironment> rt_x_use_envs;
public RWStructuredBuffer<uint> rt_x_use_env_slot;
//   rt_x_span         per function row: largest exclusive token end of its body
//   rt_x_stats        per function row, 4 words: RT_STAT_* counters of its body
//   rt_x_flags/scan   per HIR row: the uint4 scan's input and exclusive prefix
public globallycoherent RWStructuredBuffer<uint> rt_x_span;
public globallycoherent RWStructuredBuffer<uint> rt_x_stats;
public globallycoherent RWStructuredBuffer<uint4> rt_x_flags;
public globallycoherent RWStructuredBuffer<uint4> rt_x_scan;
//   rt_x_fn_by_token  function start token -> function row + 1 (0 when none);
//                     a checked local call names its callee by that token
public globallycoherent RWStructuredBuffer<uint> rt_x_fn_by_token;
//   rt_x_decl_by_token name token -> declaration row + 1, or
//                     RT_X_VARIANT_BIT | variant index; 0 when none (step 01b)
public globallycoherent RWStructuredBuffer<uint> rt_x_decl_by_token;
//   rt_x_seg_token    job segment ordinal -> the body's first token (step 10),
//                     ascending, so a token finds its body by binary search
public globallycoherent RWStructuredBuffer<uint> rt_x_seg_token;
// rt_x_callee: row -> syntax marks (step 1b): RT_X_MARK_CALLEE when the
// row is a call's callee (a callee row's HIR parent is not necessarily its
// call), RT_X_MARK_PATTERN when it is a match arm's or payload's pattern.
public globallycoherent RWStructuredBuffer<uint> rt_x_callee;
public static const uint RT_X_MARK_CALLEE = 1u;
public static const uint RT_X_MARK_PATTERN = 2u;
public static const uint RT_X_VARIANT_BIT = 0x80000000u;

// The function row whose span starts at `token`, or INVALID.
public uint function_at_token(uint token)
{
    uint count; uint stride;
    rt_x_fn_by_token.GetDimensions(count, stride);
    uint row = token < count ? rt_x_fn_by_token[token] : 0u;
    return row != 0u && valid_row(row - 1u) ? row - 1u : 0xffffffffu;
}

// rt_x_flags components, and the store records their exclusive prefixes place.
//   x: the row belongs to a retained body       -> segment row
//   y: the row is a call inside a function       -> use record
//   z: the row declares something               -> directory entry
//   w: the row is a retained body's function    -> segment
public static const uint RT_STAT_UNTYPED = 0u;    // value rows without a type reference
public static const uint RT_STAT_FOREIGN = 1u;    // row/token/index references outside the body
public static const uint RT_STAT_OWNERSHIP = 2u;  // terms naming a parameter outside the binder chain
public static const uint RT_STAT_UNTRANSLATED = 3u; // exported references whose canonical term did not translate

// rt_x_counts layout.
public static const uint RT_X_HEIGHTS = 80u;          // height buckets
public static const uint RT_X_BUCKET = 0u;            // + h: records of height h
public static const uint RT_X_BUCKET_BASE = 80u;      // + h: first rt_x_order index of height h
public static const uint RT_X_ROUND = 160u;           // current translation height
public static const uint RT_X_SCAN_N = 161u;          // items of the current uint4 scan
public static const uint RT_X_SCAN_TOTAL = 164u;      // + 4: its totals
public static const uint RT_X_BASE = 168u;            // + arena: the job's reserved base
public static const uint RT_X_SEG_FIRST = 184u;       // first segment index of the job
public static const uint RT_X_DIR_FIRST = 185u;       // first directory entry of the job
public static const uint RT_X_USE_FIRST = 186u;       // first use of the job
public static const uint RT_X_ROW_FIRST = 187u;       // first segment row of the job
public static const uint RT_X_UNTRANSLATED = 188u;  // canonical records that did not translate
public static const uint RT_X_TRAIT_TOTAL = 192u;     // + 4: totals of the trait-fact scan (14c)
public static const uint RT_X_WORDS = 256u;

// Indirect dispatch slots (rt_x_counts[RT_X_DISPATCH + 3 * slot]).
public static const uint RT_D_HIR = 0u;
public static const uint RT_D_PARAMS = 1u;
public static const uint RT_D_RECORDS = 2u;
public static const uint RT_D_ROUND = 3u;
public static const uint RT_D_SIDE = 4u;
public static const uint RT_D_SCHEMA = 5u;
public static const uint RT_D_COMMIT_DIR = 6u;
public static const uint RT_D_ROLLBACK = 7u;
public static const uint RT_D_ROOTS = 8u;
public static const uint RT_D_SLOTS = 16u;

public static const uint HIR_FILE = 1u;
public static const uint HIR_ITEM = 2u;
public static const uint HIR_FN = 3u;
public static const uint HIR_PARAM = 4u;
public static const uint HIR_TYPE = 5u;
public static const uint HIR_CALL_EXPR = 19u;
public static const uint HIR_MEMBER_EXPR = 21u;
public static const uint HIR_ENUM_ITEM = 26u;
public static const uint HIR_STRUCT_ITEM = 27u;
public static const uint HIR_CONST_ITEM = 25u;
public static const uint HIR_TYPE_ALIAS_ITEM = 29u;
public static const uint HIR_IMPL = 35u;
public static const uint HIR_ITEM_KIND_FN = 4u;
public static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
public static const uint HIR_ITEM_KIND_TRAIT = 10u;
public static const uint GENERIC_PARAM_KIND_TYPE = 1u;
public static const uint GENERIC_PARAM_KIND_CONST = 2u;

// Directory kinds (rt_dir d0.y).
public static const uint RT_DECL_FREE_FN = 1u;
public static const uint RT_DECL_METHOD = 2u;          // a method of an impl (inherent or trait)
public static const uint RT_DECL_REQUIRED_MEMBER = 3u; // signature-only member of a trait
public static const uint RT_DECL_EXTERN_FN = 4u;
public static const uint RT_DECL_STRUCT = 5u;
public static const uint RT_DECL_ENUM = 6u;
public static const uint RT_DECL_IMPL = 7u;
public static const uint RT_DECL_TRAIT = 8u;
public static const uint RT_DECL_CONST = 9u;

// Invariant codes (rt_counts[RT_C_FIRST_INVARIANT] keeps the smallest).
public static const uint RT_INV_PARAM_OWNER = 1u;     // a generic parameter's owner has no declaration identity
public static const uint RT_INV_TERM = 2u;            // a canonical record did not translate
public static const uint RT_INV_HEIGHT = 3u;          // a canonical record exceeds the translated heights
public static const uint RT_INV_SEGMENT = 4u;         // a body's rows or side tables are not contiguous
public static const uint RT_INV_OWNERSHIP = 5u;       // an exported term names a parameter outside its record's binder chain
public static const uint RT_INV_DUPLICATE_DECL = 6u;  // two committed entries define one declaration
public static const uint RT_INV_PARAM_MAP = 7u;       // the parameter map is full
public static const uint RT_INV_ENV_OWNER = 8u;       // a call environment names a different callee
public static const uint RT_INV_RECEIVER_SCOPE = 9u;  // a receiver parameter term is neither the matched receiver nor a reference to it
public static const uint RT_INV_TRAIT_FACT = 10u;     // a predicate, impl head or impl method lacks an accepted producer fact
public static const uint RT_INV_TRAIT_ORDER = 11u;    // an owner's trait facts are not one contiguous block in source order
public static const uint RT_INV_TRAIT_IDENTITY = 12u; // trait, required-member or native-target identities disagree

public uint job_library() { return ct_counts[CT_COUNT_LIBRARY]; }
public uint job_unit() { return ct_counts[CT_COUNT_UNIT]; }

public uint hir_count()
{
    uint rows; uint stride;
    compact_hir_core.GetDimensions(rows, stride);
    return min(compact_hir_count[0u], rows);
}

public bool valid_row(uint row) { return row < hir_count(); }

public uint token_capacity()
{
    uint count; uint stride;
    decl_id_by_name_token.GetDimensions(count, stride);
    return count;
}

// The impl or trait item that directly contains declaration row `row`, or
// INVALID at file level. A `pub` item row is a wrapper, not a container.
public uint container_of(uint row)
{
    uint node = compact_hir_core[row].parent;
    for (uint depth = 0u; depth < 8u && valid_row(node); depth++)
    {
        uint kind = compact_hir_core[node].kind;
        if (kind == HIR_IMPL) return node;
        if (kind == HIR_ITEM && compact_hir_payload[node].a == HIR_ITEM_KIND_TRAIT) return node;
        if (kind == HIR_FILE || kind == HIR_FN) return 0xffffffffu;
        uint parent = compact_hir_core[node].parent;
        if (parent >= node) break;
        node = parent;
    }
    return 0xffffffffu;
}

public bool is_trait_row(uint row)
{
    return valid_row(row) && compact_hir_core[row].kind == HIR_ITEM &&
        compact_hir_payload[row].a == HIR_ITEM_KIND_TRAIT;
}

// Canonical method rows are compacted in increasing dense HIR order
// (codegen/lir/semantic/function_method.slang).
public uint method_row(uint row)
{
    uint count = min(compact_method_count[0u], hir_count());
    uint lo = 0u; uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_method_cores[mid].node < row) lo = mid + 1u;
        else hi = mid;
    }
    return lo < count && compact_method_cores[lo].node == row ? lo : 0xffffffffu;
}

// The native callable identity lowering gives function row `row`
// (function_method.slang), so a caller in another unit names it with the
// same (library, unit, local) triple. A required trait member uses the
// interface method identity even when private.
public uint callable_local(uint row)
{
    if (is_trait_row(container_of(row))) return interface_method_symbol(row);
    uint index = interface_public_decl_index_by_hir[row];
    if (index != 0xffffffffu) return local_callable_symbol(index, row, false, compact_hir_core[row].token_start);
    uint method = method_row(row);
    bool public_method = method != 0xffffffffu && compact_method_cores[method].impl_node != 0xffffffffu &&
        (compact_method_signatures[method].metadata & 0xffffu) == 1u;
    return local_callable_symbol(index, row, public_method, compact_hir_core[row].token_start);
}

// The canonical store's nominal identity (canonical_candidates.slang).
public uint nominal_local(uint name_token)
{
    if (name_token >= token_capacity()) return 0xffffffffu;
    uint local = decl_id_by_name_token[name_token];
    uint count; uint stride;
    interface_public_decl_index_by_local.GetDimensions(count, stride);
    if (local >= count) return 0xffffffffu;
    uint persisted = interface_public_decl_index_by_local[local];
    return persisted != 0xffffffffu ? persisted : CT_PRIVATE_LOCAL_BIT | local;
}

// A constant's identity: its interface index, or 0x40000000 | its first
// token when private (as a private callable).
public uint const_local(uint row)
{
    uint index = interface_public_decl_index_by_hir[row];
    if (index != 0xffffffffu) return index;
    uint token = compact_hir_core[row].token_start;
    return token < 0x40000000u ? 0x40000000u | token : 0xffffffffu;
}

// The declaration key of a declaration row, or a key with INVALID local.
public uint4 decl_key_of_row(uint row)
{
    uint4 key = uint4(job_library(), job_unit(), 0u, 0xffffffffu);
    if (!valid_row(row)) return key;
    HirCore core = compact_hir_core[row];
    HirPayload payload = compact_hir_payload[row];
    if (core.kind == HIR_FN) { key.z = RT_NS_CALLABLE; key.w = callable_local(row); }
    else if (core.kind == HIR_IMPL) { key.z = RT_NS_IMPL; key.w = row; }
    else if (core.kind == HIR_STRUCT_ITEM || core.kind == HIR_ENUM_ITEM)
    {
        key.z = RT_NS_NOMINAL;
        key.w = nominal_local(hir_generic_owner_token(core, payload, token_capacity()));
    }
    else if (is_trait_row(row))
    {
        // A trait is a nominal identity of the canonical store: a NAMED
        // term naming the trait (a bound, an impl header) and the trait's
        // own declaration meet at one DeclId.
        key.z = RT_NS_NOMINAL;
        key.w = nominal_local(hir_generic_owner_token(core, payload, token_capacity()));
    }
    else if (core.kind == HIR_CONST_ITEM)
    {
        key.z = RT_NS_VALUE;
        key.w = const_local(row);
    }
    return key;
}

public bool decl_row(uint row)
{
    if (!valid_row(row)) return false;
    uint kind = compact_hir_core[row].kind;
    return kind == HIR_FN || kind == HIR_IMPL || kind == HIR_STRUCT_ITEM || kind == HIR_ENUM_ITEM ||
        kind == HIR_CONST_ITEM || is_trait_row(row);
}

public uint intern_row_decl(uint row)
{
    uint4 key = decl_key_of_row(row);
    if (key.z == 0u || key.w == 0xffffffffu) return RT_INVALID;
    return rt_intern_decl(key);
}

// ---------------------------------------------------------------------------
// Parameter map: declaration token of a parameter (or a trait's owner token
// for its implicit Self) -> ParamId.
uint param_map_slots()
{
    uint count; uint stride;
    rt_x_param_key.GetDimensions(count, stride);
    return count;
}

public void param_map_insert(uint token, uint param)
{
    uint slots = param_map_slots();
    uint slot = rt_mix(0x51ed270bu, token) & (slots - 1u);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value;
        InterlockedCompareExchange(rt_x_param_key[slot], 0u, token + 1u, value);
        if (value == 0u || value == token + 1u)
        {
            rt_x_param_val[slot] = param;
            return;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    rt_invariant(RT_INV_PARAM_MAP);
}

public uint param_map_find(uint token)
{
    uint slots = param_map_slots();
    uint slot = rt_mix(0x51ed270bu, token) & (slots - 1u);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rt_x_param_key[slot];
        if (value == 0u) return RT_INVALID;
        if (value == token + 1u) return rt_x_param_val[slot];
        slot = (slot + 1u) & (slots - 1u);
    }
    return RT_INVALID;
}

// ---------------------------------------------------------------------------
// Canonical reference -> term reference.
uint term_map_capacity()
{
    uint count; uint stride;
    rt_x_term_map.GetDimensions(count, stride);
    return count;
}

// A canonical reference of this job in the store: scalars keep their
// preseeded IDs, records map through rt_x_term_map, a local parameter leaf
// through the parameter map, and a dependency-signature slot leaf keeps its
// bits (RT_SLOT_BIT is CT_DEP_PARAM_BIT). RT_UNKNOWN when untranslatable,
// RT_NONE when there is nothing to translate.
public uint translate_ref(uint ref)
{
    if (ref == CT_NONE || ref == CT_PENDING) return RT_NONE;
    if (ref == CT_UNKNOWN) return RT_UNKNOWN;
    if (ref == 0xfffffffcu) return RT_FIT_FAILED; // CT_FIT_FAILED (constant-fit integration)
    if (ct_is_param(ref))
    {
        if (ct_is_dep_param(ref)) return ref;
        uint param = param_map_find(ct_param_token(ref));
        return param == RT_INVALID ? RT_UNKNOWN : rt_param_leaf(param);
    }
    if (!ct_is_record(ref)) return RT_UNKNOWN;
    if (ref <= SCALAR_NEVER) return ref;
    return ref < term_map_capacity() ? rt_x_term_map[ref] : RT_UNKNOWN;
}

// A checked (tag, payload) reference of this job in the store.
public uint translate_checked(uint tag, uint payload)
{
    if (tag == 0u || tag == 0xffffffffu) return RT_NONE;
    return translate_ref(ct_ref(tag, payload));
}

// Arguments of a canonical record, translated into rt_x_args at the
// record's own canonical arg base.
public struct RtJobArgs : IRtArgs
{
    public uint base;
    public uint arg(uint index) { return rt_x_args[base + index]; }
}

// ---------------------------------------------------------------------------
// Relative references inside a body. A body is the subtree of function row
// F: rows [F, F + count) and tokens [first token, end token].
public static const uint RT_REL_FOREIGN = 0xc0000000u;

public struct BodySpan
{
    public uint function;
    public uint count;
    public uint token;
    public uint token_end;
}

public uint rel_row(BodySpan span, uint row, inout uint foreign)
{
    if (row == 0xffffffffu) return row;
    if (row >= span.function && row - span.function < span.count) return row - span.function;
    foreign++;
    return RT_REL_FOREIGN;
}

// A subtree boundary may be one past the last row.
public uint rel_boundary(BodySpan span, uint row, inout uint foreign)
{
    if (row == 0xffffffffu) return row;
    if (row >= span.function && row - span.function <= span.count) return row - span.function;
    foreign++;
    return RT_REL_FOREIGN;
}

// A token of the body, or its end boundary (the first token after it).
public uint rel_token(BodySpan span, uint token, inout uint foreign)
{
    if (token == 0xffffffffu) return token;
    if (token >= span.token && token <= span.token_end) return token - span.token;
    foreign++;
    return RT_REL_FOREIGN;
}

public void stat_add(uint function, uint stat, uint amount)
{
    stat_add_at(function, function, stat, amount);
}

// Adds to `function`'s statistic and records `row` as the fault's row.
public void stat_add_at(uint function, uint row, uint stat, uint amount)
{
    if (amount == 0u) return;
    InterlockedAdd(rt_x_stats[function * 4u + stat], amount);
    rt_fault(row, RT_FAULT_STAT + stat);
}

// The function whose body contains `row`, or INVALID.
public uint body_function(uint row)
{
    if (!valid_row(row)) return 0xffffffffu;
    if (compact_hir_core[row].kind == HIR_FN) return row;
    uint function = compact_hir_nearest_fn[row];
    if (!valid_row(function) || compact_hir_core[function].kind != HIR_FN) return 0xffffffffu;
    return row > function && row < compact_hir_links[function].subtree_end ? function : 0xffffffffu;
}

// Whether function row `row` has a body generic in its binder chain: its
// own parameters or its impl's. Required trait members and externs have no
// body; a nongeneric body lowers in its own job and keeps no segment.
public bool retained_body(uint row)
{
    if (!valid_row(row) || compact_hir_core[row].kind != HIR_FN) return false;
    if (compact_hir_payload[row].a == HIR_ITEM_KIND_EXTERN_FN) return false;
    uint container = container_of(row);
    if (is_trait_row(container)) return false;
    if (compact_generic_param_ranges[row].count != 0u) return true;
    return valid_row(container) && compact_hir_core[container].kind == HIR_IMPL &&
        compact_generic_param_ranges[container].count != 0u;
}

// Whether a term reference is owned by the binder chain (decl, parent).
// Uses the store's owner summaries, so the check is O(1) per root.
public bool owned_by(uint ref, uint decl, uint parent)
{
    if (!rt_is_resolved(ref)) return true;
    if ((rt_term_flags(ref) & RTF_SLOT) != 0u) return false;
    uint2 owners = rt_term_owners(ref);
    if (owners.y == RT_OWNERS_MANY) return false;
    bool a = owners.x == 0u || owners.x == decl || (parent != 0u && owners.x == parent);
    bool b = owners.y == 0u || owners.y == decl || (parent != 0u && owners.y == parent);
    return a && b;
}

// The scan's exclusive prefix at `index`; one past the last row is the total.
public uint4 scan_at(uint index)
{
    if (index < rt_x_counts[RT_X_SCAN_N]) return rt_x_scan[index];
    return uint4(rt_x_counts[RT_X_SCAN_TOTAL], rt_x_counts[RT_X_SCAN_TOTAL + 1u],
        rt_x_counts[RT_X_SCAN_TOTAL + 2u], rt_x_counts[RT_X_SCAN_TOTAL + 3u]);
}

// ---------------------------------------------------------------------------
// Value bindings. A checked binding is a declaration token
// (semantic_value_decl_by_hir). Inside a body it becomes
// (kind, value, aux) of retained_row_classes.slang: a generic parameter leaf, a
// declaration identity, an enum variant, or a token of the body itself.
// `span` is the containing body; a binding outside it that names no
// declaration is FOREIGN.
public uint4 resolve_binding(BodySpan span, uint token)
{
    if (token == 0xffffffffu) return uint4(RT_BIND_NONE, 0xffffffffu, 0xffffffffu, 0u);
    uint param = param_map_find(token);
    if (param != RT_INVALID) return uint4(RT_BIND_PARAM, rt_param_leaf(param), 0xffffffffu, 0u);
    uint count; uint stride;
    rt_x_decl_by_token.GetDimensions(count, stride);
    uint entry = token < count ? rt_x_decl_by_token[token] : 0u;
    if ((entry & RT_X_VARIANT_BIT) != 0u)
    {
        uint variant = entry & ~RT_X_VARIANT_BIT;
        uint enum_row = compact_variants[variant].owner;
        uint decl = valid_row(enum_row) ? rt_x_row[enum_row].x : RT_INVALID;
        if (decl != RT_INVALID) return uint4(RT_BIND_VARIANT, decl, compact_variants[variant].ordinal, 0u);
        return uint4(RT_BIND_FOREIGN, 0xffffffffu, 0xffffffffu, 1u);
    }
    if (entry != 0u && valid_row(entry - 1u))
    {
        uint decl = rt_x_row[entry - 1u].x;
        if (decl != RT_INVALID) return uint4(RT_BIND_DECL, decl, 0xffffffffu, 0u);
        return uint4(RT_BIND_FOREIGN, 0xffffffffu, 0xffffffffu, 1u);
    }
    if (token >= span.token && token < span.token_end)
        return uint4(RT_BIND_LOCAL, token - span.token, 0xffffffffu, 0u);
    return uint4(RT_BIND_FOREIGN, 0xffffffffu, 0xffffffffu, 1u);
}

// Whether `row` is the callee of its parent call (callable-only syntax).
public bool callee_position(uint row)
{
    uint count; uint stride;
    rt_x_callee.GetDimensions(count, stride);
    return row < count && (rt_x_callee[row] & RT_X_MARK_CALLEE) != 0u;
}

// Whether `row` is a match pattern: an arm's pattern or a payload pattern.
public bool pattern_position(uint row)
{
    uint count; uint stride;
    rt_x_callee.GetDimensions(count, stride);
    return row < count && (rt_x_callee[row] & RT_X_MARK_PATTERN) != 0u;
}

// Whether pattern row `row` names an enum variant (`Ok(_)`, `None`,
// `Error::Busy`): constructor syntax that matches a value and constructs
// none. `decl_token` and `present` are the row's checked value binding and
// constant presence words. A binder (`inner`, `_`) or literal pattern is
// not one; it keeps its value role and type.
public bool variant_pattern(uint row, uint decl_token, uint present)
{
    if (!pattern_position(row)) return false;
    if ((present & RT_CONST_VARIANT) != 0u) return true;
    return (binding_target(decl_token) & RT_X_VARIANT_BIT) != 0u;
}

// The declaration row (+ 1) or RT_X_VARIANT_BIT | variant a binding token
// names, 0 when it names neither. Reads only step 01b's map.
public uint binding_target(uint token)
{
    uint count; uint stride;
    rt_x_decl_by_token.GetDimensions(count, stride);
    return token < count ? rt_x_decl_by_token[token] : 0u;
}
