// The ICtSlots adapter of kernels that bind the source parameter tables
// through the mutable checked graph.
import type_checker.substitution.ct_spare;
import type_checker.mutable_checked_type_graph;
import type_checker.constant_parameter_slots;
import constant_value;

public struct SourceSlots : ICtSlots
{
    public uint type_slot(uint token)
    {
        uint count; uint stride;
        type_generic_param_slot_by_token.GetDimensions(count, stride);
        return token < count ? type_generic_param_slot_by_token[token] : CT_SLOT_NONE;
    }
    public uint const_slot(uint token)
    {
        uint count; uint stride;
        type_const_param_slot_by_token.GetDimensions(count, stride);
        return token < count ? type_const_param_slot_by_token[token] : CT_SLOT_NONE;
    }
    public uint const_scalar(uint token)
    {
        uint count; uint stride;
        type_const_param_scalar_by_token.GetDimensions(count, stride);
        uint scalar = token < count ? type_const_param_scalar_by_token[token] : 0u;
        return constant_scalar_is_supported(scalar) ? scalar : 0u;
    }
}
