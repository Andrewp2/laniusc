// The armed round: lo, hi, field base, request count and armed flag.
public RWStructuredBuffer<uint> ps_round;
public uint ps_round_lo() { return ps_round[0]; }
public uint ps_round_terms() { return ps_round[1] - ps_round[0]; }
public uint ps_round_base() { return ps_round[2]; }
public uint ps_round_count() { return ps_round[3]; }
