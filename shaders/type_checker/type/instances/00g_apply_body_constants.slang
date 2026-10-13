import constant_value;
import type_checker.constant_atoms;

// Install the selected body's checked constant values after generic signature
// validation and aggregate rebuilding. Constants retain declaration identity:
// 00f publishes a value only for a parameter owned by the selected body.
// Every checked constant edge uses this contract: array lengths and nominal
// arguments, including generated nodes produced by alias normalization.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint4> body_specialization_inputs;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_const_param_value_by_token;
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

void specialize_argument(RWStructuredBuffer<uint> tags, RWStructuredBuffer<uint> payloads, uint row)
{
    if (tags[row] != 0x80000002u) return;
    uint parameter = payloads[row];
    if (parameter >= gParams.n_tokens) return;
    uint atom = type_const_param_value_by_token[parameter];
    uint3 value;
    if (!checked_constant_atom_value(atom, value) ||
        value.x != checked_constant_parameter_scalar(parameter)) return;
    payloads[row] = atom;
    tags[row] = 0x80000001u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint count = min(body_specialization_inputs[705u].x, 32u);
    if (count == 0u) return;
    uint instance = dtid.x + dtid.y * 65535u * 256u;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity) return;
    if (type_instance_kind[instance] == 1u)
    {
        uint arguments = type_instance_arg_count[instance];
        if (arguments > 32u) return;
        uint row_start = type_instance_arg_row_start[instance];
        type_instance_arg_row_ref_tag.GetDimensions(capacity, stride);
        uint total = min(type_instance_arg_row_count_out[0u], capacity);
        uint fallback = type_instance_arg_start[instance];
        type_instance_arg_ref_tag.GetDimensions(capacity, stride);
        uint source_capacity; uint source_stride;
        type_const_param_value_by_token.GetDimensions(source_capacity, source_stride);
        for (uint slot = 0u; slot < arguments; slot++)
        {
            if (row_start < total && slot < total - row_start)
                specialize_argument(type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload,
                    row_start + slot);
            if ((instance >= source_capacity || slot < 4u) &&
                fallback < capacity && slot < capacity - fallback)
                specialize_argument(type_instance_arg_ref_tag, type_instance_arg_ref_payload,
                    fallback + slot);
        }
        return;
    }
    if (type_instance_kind[instance] != 2u ||
        type_instance_len_kind[instance] != 2u) return;
    uint parameter = type_instance_len_payload[instance];
    if (parameter >= gParams.n_tokens) return;
    uint atom = type_const_param_value_by_token[parameter];
    uint3 value;
    if (!checked_constant_atom_value(atom, value) ||
        value.x != checked_constant_parameter_scalar(parameter)) return;
    uint count_value;
    if (!constant_value_to_count(value, count_value)) return;
    // This remains a typed atom reference. Array layout performs the explicit
    // nonnegative count projection rather than treating its storage row as a count.
    type_instance_len_kind[instance] = 1u;
    type_instance_len_payload[instance] = atom;
}
