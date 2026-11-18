// Shared by the trait-fact steps (14b, 14c, 14d): the accepted predicate,
// impl-header and impl-method producer facts of the job, and the trait-fact
// scan. These steps export what the frontend's predicate and method
// validators accepted (shaders/type_checker/predicates); they select no
// implementation and resolve no names.
//
// The trait-fact scan is a second run of the 08 scan kernels over HIR rows,
// with rt_x_tflags/rt_x_tscan bound in place of rt_x_flags/rt_x_scan:
//   x: the row is the bound node of a generic-bound predicate (record rank)
//   y: the row is a method of a trait impl            (binding rank)
//   z: predicates the row owns                         (predicate block base)
//   w: bindings the row (a trait impl) owns           (binding block base)
// Step 14c copies its totals to rt_x_counts[RT_X_TRAIT_TOTAL + 0..3].
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.type_rows;
import type_checker.retention.export.source_tables;

public StructuredBuffer<uint> compact_predicate_count;
public StructuredBuffer<HirPredicate> compact_predicates;
public StructuredBuffer<uint> compact_type_arg_count;
public StructuredBuffer<HirTypeArg> compact_type_args;
public StructuredBuffer<HirRange> compact_type_arg_ranges;
public StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
public StructuredBuffer<uint> predicate_status;
public StructuredBuffer<uint> predicate_owner_node;
public StructuredBuffer<uint> predicate_bound_reference;
public StructuredBuffer<uint> predicate_bound_arg_count;
public StructuredBuffer<uint> predicate_bound_token;
public StructuredBuffer<uint> predicate_method_contract_owner_count;
public StructuredBuffer<uint> predicate_method_validation_status;
public StructuredBuffer<uint> predicate_method_validation_required_symbol;
public StructuredBuffer<uint> semantic_function_native_symbol_by_hir;
public StructuredBuffer<uint> semantic_predicate_subject_parameter_token_by_hir;
public StructuredBuffer<uint> decl_hir_node;
public StructuredBuffer<uint> resolved_dependency_library_id;
public StructuredBuffer<uint> resolved_dependency_unit_id;
public StructuredBuffer<uint> resolved_dependency_local_index;
public StructuredBuffer<uint> resolved_dependency_trait_header; // 4 words per path

public globallycoherent RWStructuredBuffer<uint4> rt_x_tflags;
public globallycoherent RWStructuredBuffer<uint4> rt_x_tscan;
// For each bound or impl trait node, 14b stages its immutable key and keeps
// the claimed slot plus one. 14d reads the term from the slot's second word.
public globallycoherent RWStructuredBuffer<uint4> rt_x_trait_key;
public globallycoherent RWStructuredBuffer<uint2> rt_x_trait_terms;
public RWStructuredBuffer<uint> rt_x_trait_term_slot;

public static const uint PREDICATE_GENERIC_BOUND = 1u;
public static const uint PREDICATE_TRAIT_IMPL = 2u;
public static const uint PREDICATE_STATUS_OK = 0u;
public static const uint HIR_IMPL_TRAIT_PAYLOAD = 2u; // compact_hir_payload.a of a trait impl
public static const uint TRAIT_REFERENCE_DEPENDENCY = 0x80000000u;
public static const uint SUBJECT_SCALAR_BIT = 0x80000000u; // semantic/artifact/00_project
public static const uint TRAIT_DECL_KIND = 10u;
public static const uint MAX_TRAIT_ARGUMENTS = 32u;

public uint predicate_rows()
{
    uint rows; uint stride;
    compact_predicates.GetDimensions(rows, stride);
    return min(min(compact_predicate_count[0u], rows), hir_count());
}

public uint method_rows()
{
    uint rows; uint stride;
    compact_method_cores.GetDimensions(rows, stride);
    return min(min(compact_method_count[0u], rows), hir_count());
}

uint column(StructuredBuffer<uint> table, uint index)
{
    uint count; uint stride;
    table.GetDimensions(count, stride);
    return index < count ? table[index] : 0xffffffffu;
}

public uint predicate_fact(uint which, uint row)
{
    if (which == 0u) return column(predicate_status, row);
    if (which == 1u) return column(predicate_owner_node, row);
    if (which == 2u) return column(predicate_bound_reference, row);
    if (which == 3u) return column(predicate_bound_arg_count, row);
    if (which == 4u) return column(predicate_bound_token, row);
    if (which == 5u) return column(predicate_method_contract_owner_count, row);
    if (which == 6u) return column(predicate_method_validation_status, row);
    if (which == 7u) return column(predicate_method_validation_required_symbol, row);
    if (which == 8u) return column(semantic_function_native_symbol_by_hir, row);
    return column(semantic_predicate_subject_parameter_token_by_hir, row);
}
public static const uint F_STATUS = 0u;
public static const uint F_OWNER = 1u;
public static const uint F_REFERENCE = 2u;
public static const uint F_ARG_COUNT = 3u;
public static const uint F_BOUND_TOKEN = 4u;
public static const uint F_CONTRACT_COUNT = 5u;
public static const uint F_METHOD_STATUS = 6u;
public static const uint F_REQUIRED_SYMBOL = 7u;
public static const uint F_NATIVE_SYMBOL = 8u;
public static const uint F_SUBJECT = 9u;

// A trait impl row: an impl whose header names a trait.
public bool trait_impl_row(uint row)
{
    return valid_row(row) && compact_hir_core[row].kind == HIR_IMPL &&
        compact_hir_payload[row].a == HIR_IMPL_TRAIT_PAYLOAD && valid_row(compact_hir_payload[row].b);
}

public bool accepted_trait_impl(uint row, uint node)
{
    uint method_status = predicate_fact(F_METHOD_STATUS, row);
    return predicate_fact(F_STATUS, row) == PREDICATE_STATUS_OK &&
        compact_hir_semantic_facts[row].semantic_kind == HIR_SEMANTIC_IMPL_TRAIT &&
        compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_TYPE_PATH &&
        compact_hir_core[node].parent == row &&
        (method_status == PREDICATE_STATUS_OK || method_status == 0xffffffffu);
}

// An exported generic-bound predicate's owner row: a callable or an impl
// with a staged directory entry. INVALID otherwise.
public uint predicate_owner_row(HirPredicate predicate)
{
    if ((predicate.metadata & 0xffu) != PREDICATE_GENERIC_BOUND || !valid_row(predicate.bound)) return 0xffffffffu;
    uint owner = predicate.owner;
    if (!valid_row(owner)) return 0xffffffffu;
    uint kind = compact_hir_core[owner].kind;
    if (kind != HIR_FN && kind != HIR_IMPL) return 0xffffffffu;
    return rt_x_row[owner].y != RT_INVALID ? owner : 0xffffffffu;
}

// The trait impl that method core `index` belongs to, or INVALID.
public uint binding_impl_row(uint index)
{
    HirMethodCore method = compact_method_cores[index];
    if (!valid_row(method.node) || compact_hir_core[method.node].kind != HIR_FN) return 0xffffffffu;
    if (!trait_impl_row(method.impl_node) || rt_x_row[method.impl_node].y == RT_INVALID) return 0xffffffffu;
    return method.impl_node;
}

public uint4 tscan_at(uint index)
{
    if (index < hir_count()) return rt_x_tscan[index];
    return uint4(rt_x_counts[RT_X_TRAIT_TOTAL], rt_x_counts[RT_X_TRAIT_TOTAL + 1u],
        rt_x_counts[RT_X_TRAIT_TOTAL + 2u], rt_x_counts[RT_X_TRAIT_TOTAL + 3u]);
}

// The DeclId of a checked trait reference (predicates/trait_reference.slang):
// a local declaration index or TRAIT_REFERENCE_DEPENDENCY | resolved path.
// A local trait is the declaration row's own DeclId (step 02); a dependency
// trait is the defining unit's nominal identity, the key its own export
// gives the trait. RT_INVALID when the reference names no trait.
public uint trait_reference_decl(uint reference)
{
    if (reference == 0xffffffffu) return RT_INVALID;
    if ((reference & TRAIT_REFERENCE_DEPENDENCY) != 0u)
    {
        uint path = reference & ~TRAIT_REFERENCE_DEPENDENCY;
        if (column(resolved_dependency_trait_header, path * 4u) != TRAIT_DECL_KIND) return RT_INVALID;
        uint4 key = uint4(column(resolved_dependency_library_id, path), column(resolved_dependency_unit_id, path),
            RT_NS_NOMINAL, column(resolved_dependency_local_index, path));
        if (key.x == 0xffffffffu || key.y == 0xffffffffu || key.w == 0xffffffffu) return RT_INVALID;
        return rt_intern_decl(key);
    }
    uint row = column(decl_hir_node, reference);
    if (!is_trait_row(row)) return RT_INVALID;
    return rt_x_row[row].x;
}

// The local trait row of a reference, or INVALID for a dependency trait.
public uint trait_reference_row(uint reference)
{
    if (reference == 0xffffffffu || (reference & TRAIT_REFERENCE_DEPENDENCY) != 0u) return 0xffffffffu;
    uint row = column(decl_hir_node, reference);
    return is_trait_row(row) ? row : 0xffffffffu;
}

// (library, unit) of the unit that defines a trait reference.
public uint2 trait_reference_unit(uint reference)
{
    if (reference != 0xffffffffu && (reference & TRAIT_REFERENCE_DEPENDENCY) != 0u)
    {
        uint path = reference & ~TRAIT_REFERENCE_DEPENDENCY;
        return uint2(column(resolved_dependency_library_id, path), column(resolved_dependency_unit_id, path));
    }
    return uint2(job_library(), job_unit());
}

// Required members of a trait reference: the trait's own method contracts,
// or the dependency header's method count.
public uint trait_reference_required_count(uint reference)
{
    if (reference == 0xffffffffu) return 0xffffffffu;
    if ((reference & TRAIT_REFERENCE_DEPENDENCY) != 0u)
        return column(resolved_dependency_trait_header, (reference & ~TRAIT_REFERENCE_DEPENDENCY) * 4u + 3u);
    uint row = trait_reference_row(reference);
    return valid_row(row) ? column(predicate_method_contract_owner_count, row) : 0xffffffffu;
}

// A constant operand of a NAMED term: a constant parameter or slot leaf, or
// a constant term (canonical_candidates.slang marks constant operands by
// their checked tag; their translations are exactly these references).
public bool constant_operand(uint ref)
{
    if (rt_is_leaf(ref)) return (ref & RT_CONST_BIT) != 0u;
    uint kind = rt_term_kind(ref);
    return kind == RT_KIND_CC_VALUE || kind == RT_KIND_CC_CAST || kind == RT_KIND_CC_COUNT;
}

// Bound argument `ordinal` of bound node `bound`: its checked type root.
public struct BoundArgs : IRtArgs
{
    public uint start;
    public uint arg(uint index) { return type_row_term(compact_type_args[start + index].value); }
}

public uint exported_trait_decl(uint node)
{
    uint decl = rt_x_trait_key[node].y;
    return decl == 0u ? RT_INVALID : decl;
}

public uint exported_trait_term(uint node)
{
    uint slot = rt_x_trait_term_slot[node];
    if (slot == 0u) return RT_UNKNOWN;
    uint term = rt_x_trait_terms[slot - 1u].y;
    return rt_is_stored_term(term) ? term : RT_UNKNOWN;
}

// (file-relative byte start, byte length) of tokens [first, end).
public uint2 token_bytes(uint first, uint end, uint file)
{
    if (first == 0xffffffffu || end == 0xffffffffu || end <= first) return uint2(0xffffffffu, 0u);
    RtJobToken a = job_token(first);
    RtJobToken b = job_token(end - 1u);
    uint start = a.start;
    uint stop = max(b.start + b.len, start);
    uint base = job_file_start(file);
    return uint2(start >= base ? start - base : 0xffffffffu, stop - start);
}
