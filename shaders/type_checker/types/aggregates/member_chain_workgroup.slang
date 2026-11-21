// Space the chains within a workgroup because their substitutions diverge.
static const uint MEMBER_CHAIN_WORKGROUP_LANES = 32u;
static const uint MEMBER_CHAIN_LANES = 4u;
static const uint MEMBER_CHAINS_PER_WORKGROUP = MEMBER_CHAIN_WORKGROUP_LANES / MEMBER_CHAIN_LANES;
