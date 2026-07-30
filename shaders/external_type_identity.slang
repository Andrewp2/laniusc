StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;

static const uint EXTERNAL_TYPE_IDENTITY_INVALID = 0xffffffffu;

bool external_type_identity_valid(uint token)
{
    return external_type_library_id[token] != EXTERNAL_TYPE_IDENTITY_INVALID &&
           external_type_unit_id[token] != EXTERNAL_TYPE_IDENTITY_INVALID &&
           external_type_local_index[token] != EXTERNAL_TYPE_IDENTITY_INVALID;
}

bool external_type_identity_equal(uint lhs, uint rhs)
{
    return external_type_identity_valid(lhs) &&
           external_type_library_id[lhs] == external_type_library_id[rhs] &&
           external_type_unit_id[lhs] == external_type_unit_id[rhs] &&
           external_type_local_index[lhs] == external_type_local_index[rhs];
}
