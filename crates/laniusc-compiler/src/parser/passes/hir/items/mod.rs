/// Item field extraction pass.
pub mod extract_item_records;
/// Method declaration field extraction pass.
pub mod extract_method_records;
pub mod finish_canonical_generic_params;
pub mod finish_canonical_predicates;
pub mod mark_canonical_methods;
pub mod mark_generic_param_candidates;
/// Method signature status flag pass.
pub mod mark_method_signatures;
pub mod scatter_canonical_generic_params;
pub mod scatter_canonical_methods;
pub mod scatter_canonical_predicates;
