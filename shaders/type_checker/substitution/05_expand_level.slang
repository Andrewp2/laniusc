// One level round of the field closure (ct_expand.slang). Each lane takes
// one queued ID, queues its type arguments (or element type), substitutes
// every declaration field and enum payload pattern with the ID itself as
// the environment, realizes each result's row and queues the result. Local
// declarations read their fields from the HIR; imported ones from the
// resident dependency page, or wait in the deferred list for their page.
import hir_records;
import status;
import dependency_interface;
import semantic_interface_layout;
import type_checker.local_struct_layout;
import type_checker.mutable_checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;
import type_checker.substitution.ct_expand;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint CHILD_LIMIT = 65536u;
// Failures, as the materializer reported them: 1 capacity, 2 limits, 3 a
// missing binding, 4 an unsupported type.
static const uint FAILURE_CAPACITY = 1u;
static const uint FAILURE_LIMIT = 2u;
static const uint FAILURE_UNBOUND = 3u;
static const uint FAILURE_INVALID = 4u;

static const uint FIELDS_NONE = 0u;
static const uint FIELDS_LOCAL_STRUCT = 1u;
static const uint FIELDS_LOCAL_ENUM = 2u;
static const uint FIELDS_IMPORTED_STRUCT = 3u;
static const uint FIELDS_IMPORTED_ENUM = 4u;
static const uint FIELDS_DEFERRED = 5u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

// Rows [row, end) of a declaration's fields; for an imported enum, the
// payload edges [edge, edge_end) of the variant being read.
struct FieldCursor
{
    uint kind;
    uint owner;
    uint row;
    uint end;
    uint edge;
    uint edge_end;
}

uint type_token(uint node)
{
    if (node >= hir_count()) return INVALID;
    uint head = compact_hir_core[node].token_start;
    if (head < gParams.n_tokens && type_expr_ref_tag[head] != 0u) return head;
    uint path = path_id_by_owner_hir[node];
    if (path < min(path_count_out[0u], gParams.n_hir_nodes))
    {
        uint count = path_segment_count[path];
        uint row = count != 0u ? path_segment_base[path] + count - 1u : INVALID;
        if (row < gParams.n_tokens) return path_segment_token[row];
    }
    return INVALID;
}

// The canonical pattern of a source type node, in its declaration's
// parameters.
uint source_pattern(uint node)
{
    uint token = type_token(node);
    return token < gParams.n_tokens ? ct_ref(type_expr_ref_tag[token], type_expr_ref_payload[token]) : CT_UNKNOWN;
}

// The canonical type of dependency node `t` of the resident page (its alias
// root's), or CT_UNKNOWN.
uint dependency_type(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? ct_dependency_state(root) : CT_UNKNOWN;
}

// The first payload row of local enum `owner`.
uint first_variant_payload(uint owner, uint total, uint variants)
{
    uint lo = 0u; uint hi = total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint variant = compact_variant_payloads[mid].variant;
        uint payload_owner = variant < variants ? compact_variants[variant].owner : INVALID;
        if (payload_owner < owner) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

FieldCursor fields_begin(uint id)
{
    FieldCursor cursor;
    cursor.kind = FIELDS_NONE; cursor.owner = INVALID;
    cursor.row = 0u; cursor.end = 0u; cursor.edge = 0u; cursor.edge_end = 0u;
    if (ct_kind(id) != CT_KIND_NAMED) return cursor;
    uint declaration = ct_named_decl_token(id);
    if (declaration < gParams.n_tokens)
    {
        uint owner = type_decl_hir_node_by_token[declaration];
        if (owner >= hir_count()) return cursor;
        uint kind = compact_hir_core[owner].kind;
        cursor.owner = owner;
        if (kind == 27u)
        {
            uint total = min(compact_field_count[0u], gParams.n_hir_nodes);
            cursor.kind = FIELDS_LOCAL_STRUCT;
            cursor.row = first_local_struct_field(compact_hir_core[owner].token_start, total, compact_fields);
            cursor.end = total;
        }
        else if (kind == 26u)
        {
            uint total = min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes);
            cursor.kind = FIELDS_LOCAL_ENUM;
            cursor.row = first_variant_payload(owner, total, min(compact_variant_count[0u], gParams.n_hir_nodes));
            cursor.end = total;
        }
        return cursor;
    }
    uint3 words = ct_words(id);
    uint found = dependency_find_declaration(words.x, words.y, words.z);
    if (found >= dependency_declaration_count()) { cursor.kind = FIELDS_DEFERRED; return cursor; }
    uint kind = dependency_declaration_word(found * 14u + 6u);
    uint start = dependency_declaration_word(found * 14u + 8u);
    uint count = dependency_declaration_word(found * 14u + 9u);
    if ((kind != 6u && kind != 7u) || start > dependency_member_count() ||
        count > dependency_member_count() - start) return cursor;
    cursor.kind = kind == 6u ? FIELDS_IMPORTED_STRUCT : FIELDS_IMPORTED_ENUM;
    cursor.row = start;
    cursor.end = start + count;
    return cursor;
}

// The next field or payload pattern, CT_NONE after the last one, or
// CT_UNKNOWN for a declaration the closure cannot read.
uint next_pattern(inout FieldCursor cursor)
{
    for (uint step = 0u; step < CHILD_LIMIT; step++)
    {
        if (cursor.edge < cursor.edge_end)
            return dependency_type(dependency_type_edge_word(cursor.edge++));
        if (cursor.row >= cursor.end) return CT_NONE;
        uint row = cursor.row++;
        if (cursor.kind == FIELDS_LOCAL_STRUCT)
            return compact_fields[row].owner == cursor.owner ? source_pattern(compact_fields[row].value) : CT_NONE;
        if (cursor.kind == FIELDS_LOCAL_ENUM)
        {
            HirVariantPayload field = compact_variant_payloads[row];
            uint variants = min(compact_variant_count[0u], gParams.n_hir_nodes);
            return field.variant < variants && compact_variants[field.variant].owner == cursor.owner
                ? source_pattern(field.type_node) : CT_NONE;
        }
        if (cursor.kind != FIELDS_IMPORTED_STRUCT && cursor.kind != FIELDS_IMPORTED_ENUM) return CT_NONE;
        uint member_kind = dependency_member_word(row * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u);
        uint type = dependency_member_word(row * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u);
        if (cursor.kind == FIELDS_IMPORTED_STRUCT)
        {
            if (member_kind == 4u) return dependency_type(type);
            continue;
        }
        if (member_kind != 5u) continue;
        // A variant's payloads are its constructor signature's parameters.
        // Layout depends on every variant, so all of them are expanded.
        uint count = dependency_type_count();
        uint signature = type < count ? canonical_type_roots[type] : INVALID;
        if (signature >= count || dependency_type_word(signature * 9u) != 7u) return CT_UNKNOWN;
        uint edge = dependency_type_word(signature * 9u + 3u);
        uint edges = dependency_type_word(signature * 9u + 4u);
        if (edges == 0u || edge > dependency_count(5u) || edges > dependency_count(5u) - edge) return CT_UNKNOWN;
        cursor.edge = edge;
        cursor.edge_end = edge + edges - 1u;
    }
    return CT_UNKNOWN;
}

uint subst_failure()
{
    uint overflow = ct_subst_counts[CT_SUBST_COUNT_OVERFLOW];
    if ((overflow & (CT_SUBST_OVERFLOW_MEMO | CT_SUBST_OVERFLOW_ROWS | CT_SUBST_OVERFLOW_CONSTANTS)) != 0u ||
        ct_counts[CT_COUNT_OVERFLOW] != 0u) return FAILURE_CAPACITY;
    return (overflow & CT_SUBST_OVERFLOW_WORK) != 0u ? FAILURE_LIMIT : FAILURE_UNBOUND;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = ct_expand_counts[CT_EXPAND_START] + dtid.x + dtid.y * 16776960u;
    if (index >= ct_expand_counts[CT_EXPAND_END]) return;
    uint2 entry = ct_expand_queue[index];
    uint id = entry.x;
    uint word = entry.y;
    uint depth = ct_expand_depth(word);
    bool fields_only = (word & CT_EXPAND_FIELDS_ONLY) != 0u;
    uint kind = ct_kind(id);
    // Type children: a named type's operands (constants are skipped below),
    // or the element of an array, slice or reference.
    uint children = fields_only ? 0u : kind == CT_KIND_NAMED ? ct_arity(id) : 1u;
    FieldCursor cursor = fields_begin(id);
    uint failure = 0u;
    if (cursor.kind == FIELDS_DEFERRED && !fields_only && !ct_expand_defer(id, word))
        failure = FAILURE_CAPACITY;
    uint child_word = (word & ~(CT_EXPAND_FIELDS_ONLY | (0x7fu << CT_EXPAND_DEPTH_SHIFT))) |
        ((depth + 1u) << CT_EXPAND_DEPTH_SHIFT);
    bool retry = false;
    CtSpare spare = ct_spare_none();
    for (uint ordinal = 0u; ordinal < CHILD_LIMIT && failure == 0u; ordinal++)
    {
        uint child = CT_NONE;
        if (ordinal < children) child = ct_arg(id, ordinal);
        else
        {
            uint pattern = next_pattern(cursor);
            if (pattern == CT_NONE) break;
            child = ct_is_resolved(pattern) ? ct_subst(SourceSlots(), id, pattern, true, spare) : CT_UNKNOWN;
            uint realized = ct_is_resolved(pattern) ? subst_failure() : FAILURE_INVALID;
            if (ct_is_resolved(child)) ct_realize(child, realized);
            // Another lane is writing a row this child needs: expand this
            // ID again in the next level round.
            if (realized == CT_REALIZE_BUSY) { retry = true; realized = 0u; }
            failure = realized;
        }
        if (failure != 0u || ct_is_constant(child) || !ct_expandable(child)) continue;
        if (depth + 1u >= CT_EXPAND_DEPTH_LIMIT) failure = FAILURE_LIMIT;
        else if (!ct_expand_push(child, child_word)) failure = FAILURE_CAPACITY;
    }
    if (retry && failure == 0u && !ct_expand_append(id, word)) failure = FAILURE_CAPACITY;
    if (failure != 0u && ((word & CT_EXPAND_LENIENT) == 0u || failure <= FAILURE_LIMIT))
        record_min_token_error(status, ct_expand_token(word), 6u, 0x474e0000u | failure);
}
