/// Links match arm rows to parent match expressions.
pub mod link_match_arms;
/// Scatters compact match rank records.
pub mod list_match_rows;
pub mod mark_canonical_match_arms;
pub mod mark_canonical_match_payloads;
/// Computes local match rank prefixes.
pub mod mark_match_rows;
/// Scatters ranked match arm rows into compact storage.
pub mod publish_match_arms;
/// Ranks match arm and payload rows.
pub mod rank_match_arms;
pub mod scatter_canonical_match_arms;
pub mod scatter_canonical_match_payloads;
/// Seeds nearest match-arm ownership for arbitrarily nested patterns.
pub mod seed_match_arm_owners;
