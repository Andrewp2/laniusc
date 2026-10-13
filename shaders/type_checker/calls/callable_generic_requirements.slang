// Declaration-owned requirements are independent of signature uses. Imported
// calls retain both domains while their interface page is resident; local calls
// compose the declaration and enclosing impl through the same counts view.
#include "callable_constant_parameters.slang"
StructuredBuffer<uint> call_dependency_generic_requirements;

uint2 required_callable_generic_counts(uint callee)
{
    if (!valid_token(callee)) return uint2(0u, 0u);
    if (call_dependency_library_id[callee] != INVALID)
    {
        uint packed = call_dependency_generic_requirements[callee];
        return uint2(packed & 0xffffu, packed >> 16u);
    }
    uint function = call_fn_index[callee];
    uint header = callable_header_token(function);
    return valid_token(header)
        ? uint2(type_decl_generic_param_count[header], required_callable_constant_count(function))
        : uint2(0u, 0u);
}
