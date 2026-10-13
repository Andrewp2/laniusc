// Immutable allocation addresses shared by every page replay and source job.
// The host plans storage only; this packet contains no semantic constant value.
public struct ConstantStoragePlan
{
    public uint imported_base;
    public uint dynamic_base;
    public uint dynamic_limit;
    public uint total_rows;
}
public ConstantBuffer<ConstantStoragePlan> gConstantStoragePlan;
