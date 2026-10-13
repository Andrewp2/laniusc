import type_checker.constant_atoms;
// Resolve source operands against the selected declaration's exact scalar contract.
// Scoped names use the same lexical lookup and shadowing policy as declaration
// uses and body replay. Concrete replay values replace symbolic parameters.
import hir_records;
import primitive_types;
import constant_value;
import type_checker.argument_context;
import type_checker.float_literal_selection;
import type_checker.constant_publication;
import type_checker.type.instances.generic_param_lookup;

StructuredBuffer<uint> explicit_operand_hir_count;
StructuredBuffer<HirCore> explicit_operand_hir_core;
StructuredBuffer<HirPayload> explicit_operand_hir_payload;
StructuredBuffer<HirSemanticFacts> explicit_operand_hir_semantic_facts;
StructuredBuffer<HirRange> explicit_operand_argument_ranges;
StructuredBuffer<uint> explicit_operand_path_id;
StructuredBuffer<uint> explicit_operand_path_count;
StructuredBuffer<HirPath> explicit_operand_paths;
StructuredBuffer<HirPathSegment> explicit_operand_path_segments;
StructuredBuffer<uint> explicit_operand_generic_owner;
StructuredBuffer<uint> explicit_operand_name_ids;
StructuredBuffer<uint> explicit_operand_parameter_count;
StructuredBuffer<uint> explicit_operand_parameter_owner;
StructuredBuffer<uint> explicit_operand_parameter_name;
StructuredBuffer<uint> explicit_operand_parameter_kind;
StructuredBuffer<uint> explicit_operand_parameter_token;
StructuredBuffer<uint> explicit_operand_parameter_lookup;
StructuredBuffer<uint> explicit_operand_parameter_value;
StructuredBuffer<uint> explicit_operand_resolved_value_decl;
StructuredBuffer<uint> explicit_operand_resolved_value_status;
StructuredBuffer<uint> explicit_operand_dependency_value_metadata;
StructuredBuffer<uint> explicit_operand_decl_count;
StructuredBuffer<uint> explicit_operand_decl_kind;
StructuredBuffer<uint> explicit_operand_decl_hir;
StructuredBuffer<uint> explicit_operand_const_type;
StructuredBuffer<uint> explicit_operand_const_value;
StructuredBuffer<uint> explicit_operand_type_ref_tag;
StructuredBuffer<uint> explicit_operand_type_ref_payload;

// Lookup hash capacities are logical producer inputs. Workspace buffers can
// be larger when reused by a smaller job; their physical extent cannot select
// the lookup modulus. Bind this alias to the same packet as the producer even
// in dependency kernels whose gParams packet has another layout.
struct ExplicitOperandParams { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<ExplicitOperandParams> gExplicitOperandParams;
uint explicit_operand_hir_capacity() { return gExplicitOperandParams.n_hir_nodes; }
uint explicit_operand_token_capacity() { return gExplicitOperandParams.n_tokens; }

// Binding aliases reuse existing immutable lexical facts. The include owns
// scope traversal and name lookup; this adapter adds no competing lookup rule.
#define LEXICAL_HIR_CAPACITY explicit_operand_hir_capacity()
#define LEXICAL_TOKEN_CAPACITY explicit_operand_token_capacity()
#define compact_hir_count explicit_operand_hir_count
#define compact_hir_core explicit_operand_hir_core
#define compact_hir_payload explicit_operand_hir_payload
#define generic_decl_owner_by_node_a explicit_operand_generic_owner
#define name_id_by_token explicit_operand_name_ids
#define generic_param_count_out explicit_operand_parameter_count
#define generic_param_owner_token explicit_operand_parameter_owner
#define generic_param_name_id explicit_operand_parameter_name
#define generic_param_kind explicit_operand_parameter_kind
#define generic_param_lookup_state explicit_operand_parameter_lookup
#include "../type/instances/lexical_parameter_lookup.slang"
#undef LEXICAL_HIR_CAPACITY
#undef LEXICAL_TOKEN_CAPACITY
#undef compact_hir_count
#undef compact_hir_core
#undef compact_hir_payload
#undef generic_decl_owner_by_node_a
#undef name_id_by_token
#undef generic_param_count_out
#undef generic_param_owner_token
#undef generic_param_name_id
#undef generic_param_kind
#undef generic_param_lookup_state

// One source application lane owns this operand row. A repeated inference
// dispatch may republish the same immutable value, but simultaneous lanes must
// not invoke this publisher for the same operand.
bool publish_explicit_constant_atom(uint node, uint3 value, out uint kind, out uint atom)
{
    kind = 0u; atom = 0xffffffffu;
    uint2 reference;
    if (node >= explicit_operand_hir_capacity() ||
        !publish_checked_constant_atom_at(node, value, reference)) return false;
    kind = reference.x; atom = reference.y;
    return true;
}

// Numeric literal syntax takes the selected declaration scalar. Bool, char,
// resolved named values, and forwarded parameters keep their exact own type.
public bool checked_source_literal_value(uint node, uint scalar, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    if (!constant_scalar_is_supported(scalar)) return false;
    uint count = min(explicit_operand_hir_count[0u], explicit_operand_hir_capacity());
    uint literal; bool negative;
    if (integer_literal_magnitude(node, count, explicit_operand_hir_core,
        explicit_operand_hir_payload, literal, negative))
    {
        HirPayload magnitude = explicit_operand_hir_payload[literal];
        return constant_value_from_integer_magnitude(scalar, uint2(magnitude.b, magnitude.c),
            negative, value);
    }
    node = argument_context_root(node, count, explicit_operand_hir_core, explicit_operand_hir_payload);
    if (node >= count) return false;
    negative = explicit_operand_hir_core[node].kind == 17u &&
        explicit_operand_hir_payload[node].a == 13u;
    if (negative)
        node = argument_context_root(explicit_operand_hir_payload[node].b, count,
            explicit_operand_hir_core, explicit_operand_hir_payload);
    if (node >= count || explicit_operand_hir_core[node].kind != 23u) return false;
    HirPayload literal_value = explicit_operand_hir_payload[node];
    if (!negative && scalar == SCALAR_BOOL && (literal_value.a == 4u || literal_value.a == 5u))
        value = uint3(SCALAR_BOOL, literal_value.a == 4u ? 1u : 0u, 0u);
    else if (!negative && scalar == SCALAR_CHAR && literal_value.a == 29u)
        value = uint3(SCALAR_CHAR, literal_value.b, literal_value.c);
    else if (literal_value.a == 27u)
        return selected_float_literal_value(literal_value,
            explicit_operand_hir_semantic_facts[node].literal_status, scalar, negative, value);
    else return false;
    return constant_value_is_valid(value);
}

bool explicit_operand_inside_body(uint node)
{
    uint count = min(explicit_operand_hir_count[0u], explicit_operand_hir_capacity());
    for (uint step = 0u; step < count && node < count; step++)
    {
        if (explicit_operand_hir_core[node].kind == 6u) return true;
        uint parent = explicit_operand_hir_core[node].parent;
        if (parent == node) return true;
        node = parent;
    }
    return node < count; // A malformed parent cycle is not module scope.
}

// expected_scalar=0 is reserved for callers that preserve a named operand's
// own type (array-count projection). Generic binding always supplies a scalar.
public bool checked_named_constant_operand(uint node, uint expected_scalar,
    out uint kind, out uint value)
{
    kind = 0u; value = 0xffffffffu;
    if (expected_scalar != 0u && !constant_scalar_is_supported(expected_scalar)) return false;
    uint count = min(explicit_operand_hir_count[0u], explicit_operand_hir_capacity());
    if (node >= count) return false;
    HirCore core = explicit_operand_hir_core[node];
    HirPayload payload = explicit_operand_hir_payload[node];
    if (core.kind != 5u || payload.a != 1u || core.token_start >= explicit_operand_token_capacity() ||
        explicit_operand_argument_ranges[core.token_start].count != 0u) return false;
    uint path = explicit_operand_path_id[node];
    uint capacity; uint stride;
    explicit_operand_paths.GetDimensions(capacity, stride);
    if (path >= min(explicit_operand_path_count[0u], capacity)) return false;
    HirPath source_path = explicit_operand_paths[path];
    explicit_operand_path_segments.GetDimensions(capacity, stride);
    if (source_path.segment_count == 0u || source_path.segment_start > capacity ||
        source_path.segment_count > capacity - source_path.segment_start) return false;
    if (source_path.segment_count == 1u)
    {
        uint name = explicit_operand_path_segments[source_path.segment_start].name_token;
        if (name >= explicit_operand_token_capacity()) return false;
        uint row = lexical_parameter_row(node, name, 2u);
        uint parameters = min(explicit_operand_parameter_count[0u], explicit_operand_token_capacity());
        if (row < parameters)
        {
            uint token = explicit_operand_parameter_token[row];
            if (token >= explicit_operand_token_capacity()) return false;
            uint scalar = checked_constant_parameter_scalar(token);
            if (scalar == 0u || (expected_scalar != 0u && scalar != expected_scalar)) return false;
            uint atom = explicit_operand_parameter_value[token];
            if (atom != 0xffffffffu)
            {
                uint3 concrete;
                if (!checked_constant_atom_value(atom, concrete) || concrete.x != scalar) return false;
                kind = 1u; value = atom;
            }
            else { kind = 2u; value = token; }
            return true;
        }
        // A nearer type parameter shadows an ordinary declaration too.
        if (lexical_parameter_row(node, name, 1u) < parameters) return false;
        // Early nominal checking precedes canonical lexical value resolution.
        // Do not accidentally bind a module constant shadowed by a body local.
        if (explicit_operand_inside_body(node)) return false;
    }
    if (explicit_operand_resolved_value_status[path] != 0u) return false;
    uint3 concrete;
    uint imported = path * 4u;
    explicit_operand_dependency_value_metadata.GetDimensions(capacity, stride);
    if (imported <= capacity && 4u <= capacity - imported &&
        explicit_operand_dependency_value_metadata[imported] == 3u)
    {
        concrete = uint3(explicit_operand_dependency_value_metadata[imported + 1u],
            explicit_operand_dependency_value_metadata[imported + 2u],
            explicit_operand_dependency_value_metadata[imported + 3u]);
    }
    else
    {
        uint declaration = explicit_operand_resolved_value_decl[path];
        if (declaration >= min(explicit_operand_decl_count[0u], explicit_operand_token_capacity()) ||
            explicit_operand_decl_kind[declaration] != 3u) return false;
        uint owner = explicit_operand_decl_hir[declaration];
        if (owner >= count || explicit_operand_hir_core[owner].kind != 25u) return false;
        uint annotation = explicit_operand_const_type[owner];
        if (annotation >= count) return false;
        uint anchor = explicit_operand_hir_core[annotation].token_start;
        if (anchor >= explicit_operand_token_capacity() || explicit_operand_type_ref_tag[anchor] != 1u)
            return false;
        uint scalar = explicit_operand_type_ref_payload[anchor];
        // Ordinary computed constants have no checked value at this stage.
        // Only a literal initializer can use this source adapter.
        if (!checked_source_literal_value(explicit_operand_const_value[owner], scalar, concrete)) return false;
    }
    if (!constant_value_is_valid(concrete) ||
        (expected_scalar != 0u && concrete.x != expected_scalar)) return false;
    return publish_explicit_constant_atom(node, concrete, kind, value);
}

public bool checked_explicit_constant_operand(uint node, uint expected_scalar,
    out uint kind, out uint value)
{
    kind = 0u; value = 0xffffffffu;
    if (!constant_scalar_is_supported(expected_scalar)) return false;
    uint3 literal;
    if (checked_source_literal_value(node, expected_scalar, literal))
        return publish_explicit_constant_atom(node, literal, kind, value);
    return checked_named_constant_operand(node, expected_scalar, kind, value);
}
