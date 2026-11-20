public struct RetentionLaunch
{
    public uint groups;
    public uint slot;
    public uint options;
    public uint reserved;
};

public ConstantBuffer<RetentionLaunch> program_launch;
