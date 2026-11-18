/// Links struct field rows to parent struct declarations.
pub mod link_struct_fields;
/// Scatters compact struct rank records.
pub mod list_struct_fields;
pub mod mark_canonical_fields;
/// Scatters ranked struct field rows into compact storage.
pub mod publish_struct_fields;
/// Ranks struct field rows within each struct declaration.
pub mod rank_struct_fields;
pub mod scatter_canonical_fields;
/// Uniform parameters for the struct field passes.
pub mod struct_pass_params;
