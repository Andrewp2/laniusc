import constant_value;
import type_checker.constant_atoms;
import type_checker.constant_atoms_identity;
import type_checker.constant_publication;

// Install the selected body's checked constant values after generic signature
// validation and aggregate rebuilding. Constants retain declaration identity:
// 00f publishes a value only for a parameter owned by the selected body.
// Every checked constant edge uses this contract: array lengths and nominal
// arguments, including generated nodes produced by alias normalization.
// A generated node holds a count projection instead of a bare parameter
// (alias normalization retains `[T; N]` as CountProjection(u32, N)). The
// source constant reader substitutes the body's constants and replays the
// projection's fit, as 00g2 does for call claims, and a closed value is
// published as an atom. Native replay schedules only literal edges.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint4> body_specialization_inputs;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_arg_row_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;

// A bare parameter takes its published atom when the atom has the
// parameter's declared scalar. A projection takes a new atom of its closed
// value. Anything else, or a reference that is not closed, is left as it is.
bool specialize_constant(uint kind, inout uint payload, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    if (kind == 2u)
    {
        uint parameter = payload;
        if (parameter >= gParams.n_tokens) return false;
        uint atom = type_const_param_value_by_token[parameter];
        if (!checked_constant_atom_value(atom, value) ||
            value.x != checked_constant_parameter_scalar(parameter)) return false;
        payload = atom;
        return true;
    }
    uint atom; uint2 reference;
    if (kind != 3u || !checked_source_constant_value(kind, payload, gParams.n_tokens, value) ||
        !reserve_checked_constant_row(atom) ||
        !publish_checked_constant_atom_at(atom, value, reference)) return false;
    payload = reference.y;
    return true;
}

static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    // Entry 0's constant count, or any extra entries (which may bind constants).
    if (body_specialization_inputs[705u].x == 0u && body_specialization_inputs[705u].y == 0u) return;
    uint instance = dtid.x + dtid.y * 65535u * 256u;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity) return;
    // A nominal row's edges are its argument rows (even) and its source
    // argument words (odd); an array row's only edge is its length. One
    // specialization site serves them all.
    bool named = type_instance_kind[instance] == 1u;
    uint edges = 0u;
    uint row_start = 0u; uint total = 0u; uint fallback = 0u; uint words = 0u;
    bool source_words = false;
    if (named)
    {
        uint arguments = type_instance_arg_count[instance];
        if (arguments > 32u) return;
        edges = arguments * 2u;
        row_start = type_instance_arg_row_start[instance];
        type_instance_arg_row_ref_tag.GetDimensions(capacity, stride);
        total = min(type_instance_arg_row_count_out[0u], capacity);
        fallback = type_instance_arg_start[instance];
        type_instance_arg_ref_tag.GetDimensions(words, stride);
        uint source_capacity;
        type_const_param_value_by_token.GetDimensions(source_capacity, stride);
        source_words = instance >= source_capacity;
    }
    else if (type_instance_kind[instance] == 2u &&
        (type_instance_len_kind[instance] == 2u || type_instance_len_kind[instance] == 3u))
        edges = 1u;
    for (uint edge = 0u; edge < edges; edge++)
    {
        uint slot = edge >> 1u;
        bool argument_row = (edge & 1u) == 0u;
        uint row = INVALID;
        if (!named) row = instance;
        else if (argument_row) { if (row_start < total && slot < total - row_start) row = row_start + slot; }
        else if ((source_words || slot < 4u) && fallback < words && slot < words - fallback)
            row = fallback + slot;
        if (row == INVALID) continue;
        uint kind = !named ? type_instance_len_kind[row]
            : argument_row ? type_instance_arg_row_ref_tag[row] : type_instance_arg_ref_tag[row];
        uint payload = !named ? type_instance_len_payload[row]
            : argument_row ? type_instance_arg_row_ref_payload[row] : type_instance_arg_ref_payload[row];
        if (named)
        {
            if (kind != 0x80000002u && kind != 0x80000003u) continue;
            kind &= 0x7fffffffu;
        }
        uint3 value;
        if (!specialize_constant(kind, payload, value)) continue;
        if (!named)
        {
            // This remains a typed atom reference. Array layout performs the
            // explicit nonnegative count projection rather than treating its
            // storage row as a count.
            uint count_value;
            if (!constant_value_to_count(value, count_value)) continue;
            type_instance_len_kind[row] = 1u;
            type_instance_len_payload[row] = payload;
        }
        else if (argument_row)
        {
            type_instance_arg_row_ref_payload[row] = payload;
            type_instance_arg_row_ref_tag[row] = 0x80000001u;
        }
        else
        {
            type_instance_arg_ref_payload[row] = payload;
            type_instance_arg_ref_tag[row] = 0x80000001u;
        }
    }
}
