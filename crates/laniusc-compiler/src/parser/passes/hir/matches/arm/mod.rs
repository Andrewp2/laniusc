/// Links match arm rows to parent match expressions.
pub mod links;
/// Seeds nearest match-arm ownership for arbitrarily nested patterns.
pub mod owner_init;
/// Ranks match arm and payload rows.
pub mod rank_step;
/// Scatters ranked match arm rows into compact storage.
pub mod scatter;
