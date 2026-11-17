// The armed round, read by the wide kernels of a round.
public StructuredBuffer<uint> ps_round;
public uint ps_round_lo() { return ps_round[0]; }
public uint ps_round_terms() { return ps_round[1] - ps_round[0]; }
public uint ps_round_base() { return ps_round[2]; }
public uint ps_round_count() { return ps_round[3]; }
