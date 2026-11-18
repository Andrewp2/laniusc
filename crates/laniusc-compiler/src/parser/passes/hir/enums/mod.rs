use encase::ShaderType;

/// Links enum variant rows to parent enum declarations.
pub mod link_enum_variants;
/// Scatters ranked enum declaration rows into compact ranges.
pub mod list_enum_rows;
pub mod mark_canonical_variants;
/// Computes local enum declaration ranks.
pub mod mark_enum_rows;
pub mod number_canonical_variant_payloads;
/// Scatters ranked enum variant rows into compact storage.
pub mod publish_enum_variants;
/// Ranks enum variant and payload rows.
pub mod rank_enum_variants;
pub mod scatter_canonical_variant_payloads;
pub mod scatter_canonical_variants;
pub mod seed_variant_payload_owners;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters shared by enum and match lowering passes.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
    /// Bit 0: enum records are present. Bit 1: match records are present.
    pub family_flags: u32,
    pub retain_debug_rows: u32,
}
