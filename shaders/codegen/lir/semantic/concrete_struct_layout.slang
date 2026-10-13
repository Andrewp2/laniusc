// Field ranges belong to an instantiated record, not its declaration. Both
// record construction and member access use this checked width relation.
public interface IConcreteStructFields
{
    static uint field_words(uint instance, uint owner, uint ordinal);
}

public uint2 concrete_struct_field_range<Fields : IConcreteStructFields>(
    uint instance, uint owner, uint ordinal, uint field_capacity)
{
    static const uint INVALID = 0xffffffffu;
    if (ordinal >= field_capacity) return uint2(INVALID, INVALID);
    uint offset = 0u;
    for (uint prior = 0u; prior <= ordinal; prior++)
    {
        uint words = Fields.field_words(instance, owner, prior);
        if (words == INVALID || offset >= INVALID - words)
            return uint2(INVALID, INVALID);
        if (prior == ordinal) return uint2(offset, words);
        offset += words;
    }
    return uint2(INVALID, INVALID);
}
