// Visibility has already selected the qualifier. Its checked target identity
// owns members, including when an alias exposes a type from another module.
import dependency_interface;
struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};
ConstantBuffer<Params> gParams;
static const uint INVALID = 0xffffffffu;
uint normalized_member_hash(uint parent, uint lo, uint hi)
{
    uint hash = (2166136261u ^ parent) * 16777619u;
    hash = (hash ^ lo) * 16777619u;
    return (hash ^ hi) * 16777619u;
}
