// Record literal contexts. A literal with a receiving type takes that type's
// declaration and instance. A literal without one infers its declaration's
// parameters from its fields over canonical IDs: the declared field types
// are matched jointly against the field values (ct_match_roots), as one
// pattern, and the bindings become the literal's context. A slice field
// accepts an array value (the root coercion, per field).
import hir_records;
import hir_expr_semantics;
import type_checker.mutable_checked_type_graph;
import type_checker.constant_atoms_identity;
import type_checker.concrete_type_closure;
import type_checker.checked_index_reference;
import type_checker.argument_context;
import type_checker.calls.contextual_call_environment;
import type_checker.type.instances.struct_field_lookup;
import semantic_interface_layout;
import dependency_interface;
import status;
import type_checker.local_struct_layout;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.source_slots;
import type_checker.match.ct_match;
import type_checker.match.ct_context_publish;
import type_checker.match.field_expected;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;

StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
[ForceInline]
bool valid_hir(uint node) { return node < active_hir_count(); }
[ForceInline]
bool valid_token(uint token) { return token < gParams.n_tokens; }
uint checked_type_capacity() { return mutable_type_capacity(); }
bool valid_instance(uint instance) { return instance < checked_type_capacity(); }
bool checked_instance_is_closed(uint instance)
{
    return concrete_instance_is_closed<MutableCheckedTypeGraph, CheckedSourceConstantGraph,
        CheckedSourceConstantEnvironment>(instance, checked_type_capacity(),
        checked_source_constant_parameter_capacity());
}

StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> struct_field_lookup_state;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> resolved_type_decl;
// decl_name_token is the canonical candidates binding.
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;

RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

#define CANONICAL_FIELD_EXPECTATION
#define INFERENCE_INDEX_GRAPH MutableCheckedTypeGraph
#include "../checked_record_constructor_reference.slang"
#include "../result_expression_context.slang"
#include "../inference_expression_reference.slang"

uint record_field_type_token(uint node)
{
    if (!valid_hir(node)) return INVALID;
    uint token = compact_hir_core[node].token_start;
    return valid_token(token) && type_expr_ref_tag[token] != 0u ? token : INVALID;
}

uint imported_record_field_pattern(uint declaration, uint token)
{
    uint name = name_id_by_token[token];
    if (name >= gParams.n_tokens) return INVALID;
    uint start = dependency_declaration_word(declaration * 14u + 8u);
    uint count = dependency_declaration_word(declaration * 14u + 9u);
    if (start > dependency_member_count() || count > dependency_member_count() - start) return INVALID;
    for (uint member = start; member < start + count; member++)
    {
        uint base = member * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(base + 1u) == 4u &&
            dependency_member_word(base + 3u) == name_hash_lo[name] &&
            dependency_member_word(base + 4u) == name_hash_hi[name])
            return dependency_member_word(base + 7u);
    }
    return INVALID;
}

// The declared type of field row `row` of literal `node`: a checked operand,
// or (5, dependency node) for an imported declaration. Records the field's
// lookup error and returns false when the field or its declaration is not
// well formed; `silent` is set for the malformed rows that report nothing.
bool record_field_pattern(uint node, uint row, bool imported, uint dependency, uint owner,
    uint fields, out uint2 pattern, out bool silent)
{
    pattern = uint2(0u, INVALID);
    silent = true;
    HirField field = compact_fields[row];
    if (field.owner != node || !valid_token(field.name_token)) return false;
    silent = false;
    if (struct_field_lookup_find(node, name_id_by_token[field.name_token], fields,
        gParams.n_tokens, compact_fields, name_id_by_token, struct_field_lookup_state) != row)
    {
        record_min_token_error(status, field.name_token, 8u, 4u);
        return false;
    }
    if (imported)
    {
        pattern = uint2(TYPE_REF_EXTERNAL_CANONICAL, imported_record_field_pattern(dependency, field.name_token));
    }
    else
    {
        uint field_row = struct_field_lookup_find(owner, name_id_by_token[field.name_token],
            fields, gParams.n_tokens, compact_fields, name_id_by_token, struct_field_lookup_state);
        if (field_row >= fields)
        {
            record_min_token_error(status, field.name_token, 8u, 0u);
            return false;
        }
        uint pattern_token = record_field_type_token(compact_fields[field_row].value);
        silent = true;
        if (!valid_token(pattern_token)) return false;
        silent = false;
        pattern = uint2(type_expr_ref_tag[pattern_token], type_expr_ref_payload[pattern_token]);
    }
    if (pattern.y == INVALID)
    {
        record_min_token_error(status, field.name_token, 8u, 0u);
        return false;
    }
    return true;
}

// The canonical ID of a checked operand, or (5, t) for dependency node `t`
// (its alias root's); CT_PENDING or CT_NONE when a row is not interned yet.
uint operand_id(uint2 operand)
{
    if (operand.x != TYPE_REF_EXTERNAL_CANONICAL) return ct_ref(operand.x, operand.y);
    uint roots; uint stride;
    canonical_type_roots.GetDimensions(roots, stride);
    return operand.y < roots ? ct_dependency_state(canonical_type_roots[operand.y]) : CT_UNKNOWN;
}

// The first `limit` fields of a literal as match roots: the declared field
// type against the value's checked type. A field whose value has no type yet
// is no root. An operand without an ID ends the match and is `request`.
struct RecordFieldRoots : ICtRoots
{
    uint node;
    uint first;
    uint limit;
    bool imported;
    uint dependency;
    uint owner;
    uint fields;
    uint2 request;
    uint count() { return limit; }
    [mutating] bool root(uint index, out uint pattern, out uint actual, out bool slice)
    {
        pattern = CT_NONE;
        actual = CT_NONE;
        slice = true;
        uint row = first + index;
        uint2 declared; bool silent;
        if (!record_field_pattern(node, row, imported, dependency, owner, fields, declared, silent))
            return false;
        uint tag; uint payload;
        if (!inference_value_reference(compact_fields[row].value, tag, payload)) return true;
        for (uint side = 0u; side < 2u; side++)
        {
            uint2 operand = side == 0u ? declared : uint2(tag, payload);
            uint id = operand_id(operand);
            if (id == CT_PENDING || id == CT_NONE)
            {
                request = operand;
                return false;
            }
            if (side == 0u) pattern = id;
            else actual = id;
        }
        return true;
    }
}

void infer_record_field_constraints(uint node, uint declaration)
{
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token) || valid_instance(struct_lit_context_instance[node])) return;
    bool imported = external_type_library_id[token] != INVALID;
    uint owner = INVALID; uint dependency = INVALID;
    if (imported)
    {
        dependency = dependency_find_declaration(external_type_library_id[token],
            external_type_unit_id[token], external_type_local_index[token]);
        if (dependency >= dependency_declaration_count() ||
            dependency_declaration_word(dependency * 14u + 6u) != 6u) return;
    }
    else
    {
        if (!valid_token(declaration) || type_instance_kind[declaration] != 1u) return;
        owner = type_decl_hir_node_by_token[declaration];
        if (!valid_hir(owner) || compact_hir_core[owner].kind != 27u) return;
    }
    HirPayload literal = compact_hir_payload[node];
    uint fields = min(compact_field_count[0u], gParams.n_tokens);
    if (literal.c != 0u && (literal.b >= fields || literal.c > fields - literal.b)) return;
    // Every field is well formed before any is matched; the first malformed
    // one reports its lookup error.
    for (uint row = literal.b; row < literal.b + literal.c; row++)
    {
        uint2 pattern; bool silent;
        if (!record_field_pattern(node, row, imported, dependency, owner, fields, pattern, silent)) return;
    }
    RecordFieldRoots roots;
    roots.node = node;
    roots.first = literal.b;
    roots.limit = literal.c;
    roots.imported = imported;
    roots.dependency = dependency;
    roots.owner = owner;
    roots.fields = fields;
    SourceSlots slots;
    CtSpare spare = ct_spare_none();
    // One interning site serves the roots' operands and the publisher's
    // priors; one matcher serves the joint match and, after a mismatch in
    // the final round, the prefixes that find the first conflicting field.
    uint2 request = uint2(0u, INVALID);
    uint3 interned = uint3(0u, INVALID, CT_NONE);
    bool blaming = false;
    bool matched = false;
    uint environment = CT_MATCH_FAILED;
    uint count_mask = 0u;
    [loop]
    for (uint work = 0u; work < 8u + 4u * literal.c + CT_PUBLISH_REQUEST_LIMIT; work++)
    {
        if (request.x != 0u)
        {
            uint id = ct_intern_checked<CtMutableRows>(request.x, request.y, spare.record);
            // An operand that does not intern yet is retried next round.
            if (!ct_is_resolved(id)) return;
            interned = uint3(request, id);
            request = uint2(0u, INVALID);
        }
        if (!matched)
        {
            roots.request = uint2(0u, INVALID);
            count_mask = 0u;
            environment = ct_match_roots<SourceSlots, RecordFieldRoots>(slots, roots, CT_NONE, !blaming,
                spare, count_mask);
            if (roots.request.x != 0u)
            {
                request = roots.request;
                continue;
            }
            if (environment == CT_MATCH_OVERFLOW) return;
            if (blaming)
            {
                // The shortest failing prefix ends at the conflicting field.
                if (environment == CT_MATCH_FAILED)
                {
                    record_min_token_error(status, compact_fields[literal.b + roots.limit - 1u].name_token, 3u, 0u);
                    return;
                }
                roots.limit++;
                if (roots.limit > literal.c) return;
                continue;
            }
            if (environment == CT_MATCH_FAILED)
            {
                if (call_inference_state[0u] != 0u || literal.c == 0u) return;
                blaming = true;
                roots.limit = 1u;
                continue;
            }
            matched = true;
            uint required_fields = 0u;
            if (imported)
            {
                uint start = dependency_declaration_word(dependency * 14u + 8u);
                uint count = dependency_declaration_word(dependency * 14u + 9u);
                if (start > dependency_member_count() || count > dependency_member_count() - start) return;
                for (uint member = start; member < start + count; member++)
                    if (dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u) == 4u) required_fields++;
            }
            else
            {
                uint first = first_local_struct_field(compact_hir_core[owner].token_start, fields, compact_fields);
                for (uint row = first; row < fields && compact_fields[row].owner == owner; row++) required_fields++;
            }
            if (literal.c != required_fields)
            {
                record_min_token_error(status, token, 8u, 3u);
                return;
            }
        }
        // One literal owns these cells. No field lane or materializer reads
        // them until the next dispatch; unknown fields can settle in a later
        // round. Constants merge with the literal's prior claims.
        uint3 words = ct_words(environment);
        uint outcome = ct_publish_context<CtNoClaims>(node, token, environment, words.y, words.z,
            count_mask, 0u, interned, request);
        if (outcome == CT_PUBLISH_INTERN) continue;
        if (outcome == CT_PUBLISH_BUSY) return;
        if (outcome != CT_PUBLISHED)
        {
            record_min_token_error(status, token, 6u, 0x474e0001u);
            return;
        }
        call_context_arg_mask[node] = words.y;
        call_context_constant_mask[node] = words.z;
        call_context_owner_by_token[token] = node;
        struct_lit_context_decl_token[node] = imported ? INVALID : declaration;
        return;
    }
}

// One literal lane publishes its complete receiving type. Field/semantic
// projection runs in later dispatches and never reads a sibling lane's output.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    if (!valid_hir(node) || compact_hir_core[node].kind != 28u) return;
    uint source_tag; uint source_payload; uint source_decl;
    bool explicit_type = checked_record_constructor_reference(node, source_tag, source_payload, source_decl);
    // An explicit application already owns its ordered arguments, even when
    // they contain lexical parameters. Receiving context validates that actual
    // type elsewhere. Replacing it with an equivalent indexed instance would
    // oscillate with declaration field projection and prevent convergence.
    if (explicit_type && source_tag == 3u) return;
    uint2 expected;
    if (!result_expression_context<MutableCheckedTypeGraph>(node, checked_type_capacity(), expected))
    {
        // Field evidence supplies the same ordered application environment as
        // callable arguments. Materialization runs after this dispatch.
        infer_record_field_constraints(node, source_decl);
        return;
    }
    uint declaration = expected.x == 3u && valid_instance(expected.y)
        ? type_instance_decl_token[expected.y]
        : expected.x == 1u && expected.y >= 4096u && expected.y < 6144u
        ? expected.y - 4096u : INVALID;
    uint instance = expected.x == 3u ? expected.y : INVALID;
    if (valid_token(source_decl))
    {
        if (declaration != source_decl)
        {
            // A receiving application cannot change nominal identity. Keep
            // provisional contexts deferred, but diagnose before codegen.
            if (call_inference_state[0u] == 0u)
                record_min_token_error(status, compact_hir_core[node].token_start, 3u, 0u);
            return;
        }
    }
    else
    {
        uint token = compact_hir_core[node].token_start;
        if (!valid_instance(instance) || !valid_token(token) ||
            external_type_library_id[instance] == INVALID ||
            external_type_library_id[instance] != external_type_library_id[token] ||
            external_type_unit_id[instance] != external_type_unit_id[token] ||
            external_type_local_index[instance] != external_type_local_index[token])
        {
            if (call_inference_state[0u] == 0u) record_min_token_error(status, token, 3u, 0u);
            return;
        }
    }
    if (struct_lit_context_decl_token[node] == declaration && struct_lit_context_instance[node] == instance) return;
    struct_lit_context_decl_token[node] = declaration;
    struct_lit_context_instance[node] = instance;
    uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored);
}
