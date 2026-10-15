//! Owned generic call facts for compiled source units.
//!
//! The GPU checker owns inference. This reader copies its accepted relations
//! before workspace reuse and decodes their scalar/descriptor identities. It
//! neither infers types on the host nor emits a specialized function body.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Result, anyhow, ensure};

use crate::constant_value::{CheckedConstantValue, constant_scalar_is_supported};

use super::{
    OwnedGpuSemanticArtifact,
    checked_contracts::{
        self,
        CheckedCallOwner,
        CheckedCallableOwner,
        CheckedContractOwner,
        CheckedUnitContracts,
        CheckedUnitFacts,
    },
    compiler_graph,
};
use crate::{
    compiler::{
        GpuSemanticInterfaceArtifact,
        GpuSemanticInterfaceMemberKind,
    },
    gpu::{
        buffers::{LaniusBuffer, TrackedBufferView},
        compiler_graph::{CompilerGraph, CompilerGraphBuilder, ResourceClass},
        readback::{PagedReadback, ReadbackRegion},
    },
    parser::passes::hir::{
        item::fields::{
            HIR_ITEM_KIND_ENUM,
            HIR_ITEM_KIND_EXTERN_FN,
            HIR_ITEM_KIND_FN,
            HIR_ITEM_KIND_STRUCT,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_KIND_TYPE_ALIAS,
        },
        nodes::{
            HIR_NODE_ENUM_ITEM,
            HIR_NODE_FN,
            HIR_NODE_IMPL,
            HIR_NODE_ITEM,
            HIR_NODE_STRUCT_ITEM,
            HIR_NODE_TYPE_ALIAS_ITEM,
        },
    },
};

const INVALID: u32 = u32::MAX;
const CALL_WORDS: usize = std::mem::size_of::<super::GpuCheckedCallArtifact>() / 4;
const RETAINED_CALLABLE_WORDS: usize = 3;
/// Words of a checked call record the unit snapshot reads: target token
/// through callable kind.
const CALL_RECORD_READ_WORDS: usize = 12;
const _: () = assert!(CALL_RECORD_READ_WORDS <= CALL_WORDS);
const MAX_RETAINED_TYPE_DEPTH: usize = 256;
const TYPE_INSTANCE_COLUMNS: [&str; 13] = [
    "type_instance_kind",
    "type_instance_arg_count",
    "type_instance_elem_ref_tag",
    "type_instance_elem_ref_payload",
    "external_type_library_id",
    "external_type_unit_id",
    "external_type_local_index",
    "type_native_word_count",
    "type_instance_len_kind",
    "type_instance_len_payload",
    "type_instance_decl_token",
    "type_instance_arg_start",
    "type_instance_arg_row_start",
];

/// These inputs cross the checker/backend boundary only for source-unit jobs
/// requesting an interface. Fresh non-interface graphs do not add this
/// retention; cached interface-capable workspaces may keep that capacity.
/// Ordinary executable compilation does not read these tables back.
pub(super) const RETAINED_INPUTS: &[&str] = &[
    "retained_callable_count",
    "retained_callable_records",
    "call_generic_claim_count_out",
    "call_const_claim_callee",
    "call_const_claim_slot",
    "call_const_claim_count_out",
    "call_const_claim_ref_kind",
    "call_const_claim_ref_payload",
    "call_const_claim_selected",
    "call_const_claim_arg_row",
    "type_decl_const_param_count_by_owner_token",
    "type_const_param_value_by_token",
    "type_const_param_scalar_by_token",
    "checked_constant_atoms",
    "checked_constant_projections",
    "call_generic_claim_callee",
    "call_generic_claim_slot",
    "call_generic_claim_ref_tag",
    "call_generic_claim_ref_payload",
    "call_generic_claim_arg_row",
    "call_context_arg_mask",
    "call_context_ref_tag",
    "call_context_ref_payload",
    "call_context_constant_mask",
    "call_context_constant_kind",
    "call_context_constant_payload",
    "call_arg_row_count_out",
    "call_arg_row_call_node",
    "call_fn_index",
    "type_native_word_count",
    "type_native_scalar_identity",
    "type_expr_ref_tag",
    "type_expr_ref_payload",
    "decl_id_by_name_token",
    "decl_hir_node",
    "decl_count_out",
    "decl_kind",
    "decl_name_token",
    "interface_public_decl_index_by_hir",
    "type_decl_generic_param_count",
    "type_decl_generic_param_count_by_owner_token",
    "method_decl_method_row",
    "compact_method_cores",
    "compact_method_signatures",
    "compact_hir_payload",
    "compact_hir_core",
    "compact_hir_count",
    "compact_field_count",
    "compact_fields",
    "compact_variant_count",
    "compact_variants",
    "compact_variant_payload_row_count",
    "compact_variant_payloads",
    "compact_variant_payload_start",
    "compact_variant_payload_count",
    "generic_decl_owner_by_node_a",
    "compact_generic_param_count",
    "compact_generic_params",
    "compact_generic_param_ranges",
    "type_instance_arg_count",
    "type_instance_arg_start",
    "type_instance_arg_ref_tag",
    "type_instance_arg_ref_payload",
    "type_instance_arg_row_start",
    "type_instance_arg_row_count_out",
    "type_instance_arg_row_ref_tag",
    "type_instance_arg_row_ref_payload",
    "type_instance_kind",
    "type_instance_decl_token",
    "type_instance_elem_ref_tag",
    "type_instance_elem_ref_payload",
    "type_instance_len_kind",
    "type_instance_len_payload",
    "external_type_library_id",
    "external_type_unit_id",
    "external_type_local_index",
    "compact_predicate_count",
    "compact_predicates",
    "compact_type_arg_count",
    "compact_type_args",
    "compact_type_arg_ranges",
    "compact_method_count",
    "predicate_owner_node",
    "predicate_subject_token",
    "predicate_bound_reference",
    "predicate_bound_arg_count",
    "predicate_status",
    "predicate_trait_impl_trait_type_node",
    "predicate_method_contract_owner_count",
    "predicate_method_validation_status",
    "predicate_method_validation_required_symbol",
    "resolved_dependency_library_id",
    "resolved_dependency_unit_id",
    "resolved_dependency_local_index",
    "resolved_dependency_trait_header",
    "semantic_type_ref_tag_by_hir",
    "semantic_type_ref_payload_by_hir",
    "semantic_function_native_symbol_by_hir",
    "semantic_predicate_subject_parameter_token_by_hir",
];

/// These facts are produced by the separate interface-export graph. The
/// binding name used by this reader is deliberately paired with the actual
/// owner resource; it is not a checker allocation or a checker-side alias.
const RETAINED_INTERFACE_INPUTS: &[(&str, &str)] = &[
    (
        "interface_generic_scope_owner_by_hir",
        "semantic_interface.members.scope_owner_by_hir",
    ),
    (
        "interface_predicate_flag",
        "semantic_interface.predicates.flag",
    ),
    (
        "interface_predicate_prefix",
        "semantic_interface.predicates.output",
    ),
    (
        "interface_implementation_index_by_hir",
        "semantic_interface.implementations.index_by_hir",
    ),
];

/// A readback consumer contract, composed before the producer is allocated.
/// This promotes only its imported tables, preventing later checker or native
/// lowering scratch from overwriting a relation before it is copied.
pub(super) fn retention_graph(producer: &CompilerGraph) -> Result<CompilerGraph> {
    retention_graph_inputs(producer, RETAINED_INPUTS.iter().copied())
}

pub(super) fn interface_retention_graph(producer: &CompilerGraph) -> Result<CompilerGraph> {
    retention_graph_inputs(
        producer,
        RETAINED_INTERFACE_INPUTS
            .iter()
            .map(|&(_, resource)| resource),
    )
}

fn retention_graph_inputs(
    producer: &CompilerGraph,
    inputs: impl IntoIterator<Item = &'static str>,
) -> Result<CompilerGraph> {
    let mut reader = CompilerGraphBuilder::new();
    for name in inputs {
        let id = producer
            .resource_id(name)
            .ok_or_else(|| anyhow!("missing generic call input {name}"))?;
        let resource = producer
            .resource(id)
            .ok_or_else(|| anyhow!("missing resource {name}"))?;
        reader
            .add_storage(
                name,
                resource.domain,
                ResourceClass::External,
                resource.bytes,
            )
            .map_err(anyhow::Error::msg)?;
    }
    reader.build().map_err(anyhow::Error::msg)
}

#[derive(Clone)]
pub(super) struct RetainedGenericCallInputs {
    buffers: BTreeMap<&'static str, LaniusBuffer<u32>>,
    call_facts_active: bool,
    contract_facts_active: bool,
    method_facts_active: bool,
}

impl RetainedGenericCallInputs {
    pub(super) fn new(
        graph: &compiler_graph::TypeCheckCompilerGraph,
        hir: &crate::parser::buffers::GpuHirView,
        parser_feature_flags: u32,
        dependency_interfaces_present: bool,
    ) -> Result<Self> {
        let mut buffers = RETAINED_INPUTS
            .iter()
            .map(|&name| {
                let buffer = match name {
                    "compact_method_cores" => {
                        hir.method_cores.alias(hir.method_cores.byte_size / 4)
                    }
                    "compact_method_signatures" => hir
                        .method_signatures
                        .alias(hir.method_signatures.byte_size / 4),
                    "compact_hir_payload" => hir.payload.alias(hir.payload.byte_size / 4),
                    "compact_hir_core" => hir.core.alias(hir.core.byte_size / 4),
                    "compact_hir_count" => hir.count.clone(),
                    "compact_field_count" => hir.field_count.clone(),
                    "compact_fields" => hir.fields.alias(hir.fields.byte_size / 4),
                    "compact_variant_count" => hir.variant_count.clone(),
                    "compact_variants" => hir.variants.alias(hir.variants.byte_size / 4),
                    "compact_variant_payload_row_count" => hir.variant_payload_row_count.clone(),
                    "compact_variant_payloads" => hir.variant_payloads.alias(hir.variant_payloads.byte_size / 4),
                    "compact_variant_payload_start" => hir.variant_payload_start.clone(),
                    "compact_variant_payload_count" => hir.variant_payload_count.clone(),
                    "compact_predicate_count" => hir.predicate_count.clone(),
                    "compact_predicates" => hir.predicates.alias(hir.predicates.byte_size / 4),
                    "compact_type_arg_count" => hir.type_arg_count.clone(),
                    "compact_type_args" => hir.type_args.alias(hir.type_args.byte_size / 4),
                    "compact_type_arg_ranges" => {
                        hir.type_arg_ranges.alias(hir.type_arg_ranges.byte_size / 4)
                    }
                    "compact_method_count" => hir.method_count.clone(),
                    "compact_generic_param_count" => hir.generic_param_count.clone(),
                    "compact_generic_params" => {
                        hir.generic_params.alias(hir.generic_params.byte_size / 4)
                    }
                    "compact_generic_param_ranges" => hir
                        .generic_param_ranges
                        .alias(hir.generic_param_ranges.byte_size / 4),
                    _ => graph.buffer(name)?,
                };
                Ok((name, buffer))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        for &(binding, resource) in RETAINED_INTERFACE_INPUTS {
            buffers.insert(binding, graph.semantic_interface_buffer(resource)?);
        }
        Ok(Self {
            buffers,
            call_facts_active: super::generic_call_claim_passes_required(parser_feature_flags)
                || dependency_interfaces_present,
            method_facts_active: super::method_passes_required(parser_feature_flags),
            contract_facts_active: parser_feature_flags
                & crate::lexer::features::PARSER_FEATURE_PREDICATES
                != 0,
        })
    }

    pub(super) fn retained_buffers(&self) -> impl Iterator<Item = TrackedBufferView<'_>> {
        self.buffers.values().map(Into::into)
    }

    pub(super) fn buffer(&self, name: &str) -> &LaniusBuffer<u32> {
        &self.buffers[name]
    }
}

/// Identities are meaningful in the retained immutable source-unit context.
/// Source-local tokens are anchors into that snapshot, never exported IDs.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum CheckedNominalIdentity {
    Public([u32; 3]),
    SourceLocal {
        unit: [u32; 2],
        declaration_token: u32,
    },
}

impl CheckedNominalIdentity {
    pub(crate) fn unit(self) -> [u32; 2] {
        match self {
            Self::Public([library, unit, _]) => [library, unit],
            Self::SourceLocal { unit, .. } => unit,
        }
    }

    pub(super) fn scope(&mut self, source_unit: [u32; 2]) {
        match self {
            Self::Public(identity) if identity[..2] == [INVALID, INVALID] => {
                identity[..2].copy_from_slice(&source_unit);
            }
            Self::SourceLocal { unit, .. } if *unit == [INVALID, INVALID] => *unit = source_unit,
            _ => {}
        }
    }

    /// Private packet encoding only; callers must not treat this as an export.
    pub(super) fn packet_identity(self) -> Result<[u32; 3]> {
        let identity = match self {
            Self::Public(identity) => {
                ensure!(
                    identity[2] < 0x2000_0000,
                    "invalid public nominal declaration"
                );
                identity
            }
            Self::SourceLocal {
                unit,
                declaration_token,
            } => {
                ensure!(
                    declaration_token < 0x2000_0000,
                    "invalid source-local nominal token"
                );
                [unit[0], unit[1], 0x2000_0000 | declaration_token]
            }
        };
        ensure!(
            identity.iter().all(|&word| word != INVALID),
            "nominal identity has no retained unit"
        );
        Ok(identity)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum CheckedBinderIdentity {
    /// Exact exported owner and the interface's lexical scope symbol.
    Public { owner: u32, scope: u32 },
    SourceLocal {
        owner_kind: u32,
        declaration_start_token: u32,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum CheckedParameterDomain {
    Type,
    Constant,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct CheckedParameterIdentity {
    /// Bound at the retention boundary to the immutable source unit. Reusing
    /// library/unit numbers with different snapshots does not authorize replay.
    pub unit: [u32; 2],
    pub binder: CheckedBinderIdentity,
    pub domain: CheckedParameterDomain,
    /// Position in this binder's own mixed type/constant parameter header.
    pub source_ordinal: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedGenericParameter {
    pub identity: CheckedParameterIdentity,
    /// Composed domain slot for GPU substitution; this is not binder identity.
    pub binding_slot: u32,
    /// Declared value scalar; absent exactly for the type parameter domain.
    /// This is a checked contract, not another component of binder identity.
    pub constant_scalar: Option<u32>,
}

impl CheckedGenericParameter {
    pub(super) fn scope(&mut self, unit: [u32; 2]) {
        if self.identity.unit == [INVALID, INVALID] {
            self.identity.unit = unit;
        }
    }
}

/// A semantic graph survives independently of native layout availability.
/// No GPU-local type-instance row is kept as a semantic type identity.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum CheckedGenericType {
    Scalar(u32),
    Parameter(CheckedGenericParameter),
    Slice(Box<CheckedGenericType>),
    Reference(Box<CheckedGenericType>),
    Array {
        element: Box<CheckedGenericType>,
        length: CheckedGenericConstantValue,
        words: Option<u32>,
    },
    Nominal {
        identity: CheckedNominalIdentity,
        arguments: Vec<CheckedGenericApplicationArgument>,
        words: Option<u32>,
        /// Optional private packet anchor in this exact source snapshot. It
        /// is separate from the public declaration's semantic identity.
        local_replay: Option<u32>,
    },
    /// Invalid, unsupported, cyclic, or unavailable semantic identity.
    Unresolved {
        reference_tag: u32,
        instance_kind: u32,
    },
}

impl CheckedGenericType {
    pub(super) fn scope(&mut self, unit: [u32; 2]) {
        match self {
            CheckedGenericType::Parameter(parameter) => parameter.scope(unit),
            CheckedGenericType::Nominal {
                identity,
                arguments,
                ..
            } => {
                identity.scope(unit);
                for value in arguments {
                    value.scope(unit);
                }
            }
            CheckedGenericType::Array {
                element, length, ..
            } => {
                element.scope(unit);
                length.scope(unit);
            }
            CheckedGenericType::Slice(element) | CheckedGenericType::Reference(element) => {
                element.scope(unit)
            }
            _ => {}
        }
    }

    pub(crate) fn has_semantic_identity(&self) -> bool {
        match self {
            Self::Unresolved { .. } => false,
            Self::Slice(element) | Self::Reference(element) => element.has_semantic_identity(),
            Self::Array {
                element, length, ..
            } => element.has_semantic_identity() && length.is_bound(),
            Self::Nominal { arguments, .. } => arguments.iter().all(|argument| match argument {
                CheckedGenericApplicationArgument::Type(ty) => ty.has_semantic_identity(),
                CheckedGenericApplicationArgument::Constant(value) => value.is_bound(),
            }),
            _ => true,
        }
    }

    pub(crate) fn is_closed(&self) -> bool {
        match self {
            Self::Unresolved { .. } | Self::Parameter(_) => false,
            Self::Slice(element) | Self::Reference(element) => element.is_closed(),
            Self::Array {
                element, length, ..
            } => element.is_closed() && length.literal().is_some(),
            Self::Nominal { arguments, .. } => arguments.iter().all(|argument| match argument {
                CheckedGenericApplicationArgument::Type(ty) => ty.is_closed(),
                CheckedGenericApplicationArgument::Constant(value) => value.literal().is_some(),
            }),
            Self::Scalar(_) => true,
        }
    }

    pub(crate) fn is_native_ready(&self) -> bool {
        self.is_closed()
            && match self {
                Self::Slice(element) | Self::Reference(element) => element.is_native_ready(),
                Self::Array { element, words, .. } => words.is_some() && element.is_native_ready(),
                Self::Nominal {
                    arguments, words, ..
                } => {
                    words.is_some()
                        && arguments.iter().all(|argument| match argument {
                            CheckedGenericApplicationArgument::Type(ty) => ty.is_native_ready(),
                            CheckedGenericApplicationArgument::Constant(value) => {
                                value.literal().is_some()
                            }
                        })
                }
                Self::Scalar(_) => true,
                _ => false,
            }
    }

    fn retention_rank(&self) -> u8 {
        if self.is_native_ready() {
            3
        } else if self.is_closed() {
            2
        } else if self.has_semantic_identity() {
            1
        } else {
            0
        }
    }

    pub(super) fn owned_edge_bytes(&self) -> usize {
        match self {
            Self::Slice(element) | Self::Reference(element) => {
                std::mem::size_of::<Self>().saturating_add(element.owned_edge_bytes())
            }
            Self::Array { element, length, .. } => std::mem::size_of::<Self>()
                .saturating_add(element.owned_edge_bytes()).saturating_add(length.owned_edge_bytes()),
            Self::Nominal { arguments, .. } => arguments
                .capacity()
                .saturating_mul(std::mem::size_of::<CheckedGenericApplicationArgument>())
                .saturating_add(
                    arguments
                        .iter()
                        .map(|argument| match argument {
                            CheckedGenericApplicationArgument::Type(ty) => ty.owned_edge_bytes(),
                            CheckedGenericApplicationArgument::Constant(value) => value.owned_edge_bytes(),
                        })
                        .sum::<usize>(),
                ),
            _ => 0,
        }
    }
}

/// Nominal operands keep their declaration-owned parameter domain during
/// readback and body replay. Constants never manufacture value type identities.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum CheckedGenericApplicationArgument {
    Type(CheckedGenericType),
    Constant(CheckedGenericConstantValue),
}

impl CheckedGenericApplicationArgument {
    pub(super) fn scope(&mut self, unit: [u32; 2]) {
        match self {
            Self::Type(ty) => ty.scope(unit),
            Self::Constant(value) => value.scope(unit),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CheckedGenericTarget {
    /// Function start token is scoped to the retained ordered source snapshot.
    Local {
        function_start_token: u32,
        generic_parameter_count: u32,
        native_symbol: u32,
        /// Private replay scope: function token or enclosing-impl method HIR.
        specialization_symbol: u32,
    },
    Dependency {
        library_id: u32,
        unit_id: u32,
        declaration_index: u32,
    },
    /// Associated methods use the persisted member's symbol identity rather
    /// than a declaration index. Its high bit separates the two namespaces.
    DependencyMethod {
        library_id: u32,
        unit_id: u32,
        method_symbol: u32,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedGenericArgument {
    pub slot: u32,
    pub ty: CheckedGenericType,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum CheckedGenericConstantValue {
    Literal(CheckedConstantValue),
    Parameter(CheckedGenericParameter),
    /// GPU-owned checked count conversion. Symbolic fit obligations survive
    /// retention; concrete native replay requires GPU normalization to Literal.
    CountProjection {
        target_scalar: u32,
        source: Box<CheckedGenericConstantValue>,
    },
    /// Missing declaration ownership stays an explicit failed reference.
    Unresolved {
        kind: u32,
        payload: u32,
    },
}

impl CheckedGenericConstantValue {
    pub(super) fn scope(&mut self, unit: [u32; 2]) {
        match self {
            Self::Parameter(parameter) => parameter.scope(unit),
            Self::CountProjection { source, .. } => source.scope(unit),
            _ => {}
        }
    }
    pub(crate) fn literal(&self) -> Option<CheckedConstantValue> {
        match self {
            Self::Literal(value) => Some(*value),
            _ => None,
        }
    }

    #[cfg(test)]
    pub(crate) fn count_literal(value: u32) -> Self {
        Self::Literal(CheckedConstantValue::from_words(crate::primitive_types::SCALAR_U32, [value, 0])
            .expect("all u32 count values are valid"))
    }

    pub(super) fn owned_edge_bytes(&self) -> usize {
        match self {
            Self::CountProjection { source, .. } => std::mem::size_of::<Self>()
                .saturating_add(source.owned_edge_bytes()),
            _ => 0,
        }
    }

    fn is_bound(&self) -> bool {
        match self {
            Self::Literal(_) => true,
            Self::Parameter(value) => value.binding_slot != INVALID
                && value.identity.domain == CheckedParameterDomain::Constant
                && value.constant_scalar.is_some_and(constant_scalar_is_supported),
            Self::CountProjection { target_scalar, source } =>
                crate::primitive_types::integer_bits(*target_scalar) != 0 && source.is_bound(),
            Self::Unresolved { .. } => false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedGenericConstant {
    pub slot: u32,
    pub value: CheckedGenericConstantValue,
}

impl CheckedGenericConstant {
    #[cfg(test)]
    pub(crate) fn literal(slot: u32, value: u32) -> Self {
        Self {
            slot,
            value: CheckedGenericConstantValue::count_literal(value),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedGenericCall {
    /// Dense call identity belongs to this compiled unit's retained source.
    /// Different calls to one declaration always have different environments.
    pub call_hir: u32,
    /// Exact token span in the immutable concatenated source-pack bytes.
    /// Copied while the producing HIR/token buffers are alive; never recovered
    /// from a later workspace or inferred from source syntax.
    pub source_span: [u32; 2],
    pub target: CheckedGenericTarget,
    pub arguments: Vec<CheckedGenericArgument>,
    pub constants: Vec<CheckedGenericConstant>,
    pub required_constant_parameters: Option<u32>,
    pub required_generic_parameters: Option<u32>,
}

impl CheckedGenericCall {
    pub(crate) fn has_all_parameter_slots(&self) -> bool {
        let Some(count) = self.required_generic_parameters else {
            return false;
        };
        let Some(constant_count) = self.required_constant_parameters else {
            return false;
        };
        self.constants.len() == constant_count as usize
            && self
                .constants
                .iter()
                .enumerate()
                .all(|(slot, arg)| arg.slot == slot as u32 && arg.value.is_bound())
            && self.arguments.len() == count as usize
            && self
                .arguments
                .iter()
                .enumerate()
                .all(|(slot, arg)| arg.slot == slot as u32)
    }

    pub(crate) fn has_closed_arguments(&self) -> bool {
        self.has_all_parameter_slots()
            && self
                .constants
                .iter()
                .all(|arg| arg.value.literal().is_some())
            && self.arguments.iter().all(|arg| arg.ty.is_closed())
    }

    pub(crate) fn has_complete_arguments(&self) -> bool {
        self.has_all_parameter_slots()
            && self
                .constants
                .iter()
                .all(|arg| arg.value.literal().is_some())
            && self.arguments.iter().all(|arg| arg.ty.is_native_ready())
    }

    pub(crate) fn resident_argument_bytes(&self) -> usize {
        self.arguments
            .capacity()
            .saturating_mul(std::mem::size_of::<CheckedGenericArgument>())
            .saturating_add(
                self.constants
                    .capacity()
                    .saturating_mul(std::mem::size_of::<CheckedGenericConstant>()),
            )
            .saturating_add(
                self.arguments
                    .iter()
                    .map(|arg| arg.ty.owned_edge_bytes())
                    .sum::<usize>(),
            )
            .saturating_add(self.constants.iter().map(|arg| arg.value.owned_edge_bytes()).sum::<usize>())
    }
}

/// Add declaration-owned requirements from the admitted portable interface.
/// The GPU has already solved the receiver's complete structural pattern and
/// published its accepted substitution. Do not reconstruct bindings from a
/// nominal receiver's positional arguments here.
pub(crate) fn resolve_generic_requirements(
    calls: &mut Vec<CheckedGenericCall>,
    dependency_pages: &[Vec<GpuSemanticInterfaceArtifact>],
) {
    for call in calls.iter_mut() {
        let (library_id, unit_id) = match call.target {
            CheckedGenericTarget::Dependency { library_id, unit_id, .. }
            | CheckedGenericTarget::DependencyMethod { library_id, unit_id, .. } =>
                (library_id, unit_id),
            CheckedGenericTarget::Local { .. } => continue,
        };
        let requirements = dependency_pages.iter().flatten()
            .find(|interface| interface.library_id == library_id && interface.unit_id == unit_id)
            .and_then(|interface| match call.target {
                CheckedGenericTarget::Dependency { declaration_index, .. } => {
                    let declaration = interface.declarations.get(declaration_index as usize)?;
                    let start = declaration.first_member as usize;
                    let end = start.checked_add(declaration.member_count as usize)?;
                    let members = interface.members.get(start..end)?;
                    let count = |kind: GpuSemanticInterfaceMemberKind| members.iter()
                        .filter(|member| member.kind == kind as u32 && member.value_hi == 0)
                        .count() as u32;
                    Some((count(GpuSemanticInterfaceMemberKind::GenericTypeParameter),
                          count(GpuSemanticInterfaceMemberKind::GenericConstParameter)))
                }
                CheckedGenericTarget::DependencyMethod { method_symbol, .. } =>
                    dependency_method_requirements(interface, method_symbol),
                CheckedGenericTarget::Local { .. } => unreachable!(),
            });
        call.required_generic_parameters = requirements.map(|counts| counts.0);
        call.required_constant_parameters = requirements.map(|counts| counts.1);
    }
    calls.retain(|call| {
        !call.arguments.is_empty()
            || !call.constants.is_empty()
            || call.required_generic_parameters != Some(0)
            || call.required_constant_parameters != Some(0)
    });
}

/// Callable header counts include the exact impl and method domains, even for
/// parameters absent from the signature. The owner may be structural and must
/// never be interpreted as a nominal declaration index.
pub(crate) fn dependency_method_requirements(
    interface: &GpuSemanticInterfaceArtifact,
    method_symbol: u32,
) -> Option<(u32, u32)> {
    let identity = [interface.library_id, interface.unit_id, method_symbol];
    let mut matches = interface.members.iter().enumerate().filter_map(|(index, member)| {
        (member.kind == GpuSemanticInterfaceMemberKind::ImplementationMethod as u32
            && interface.implementation_method_target(index as u32).ok() == Some(identity))
            .then_some(member)
    });
    let method = matches.next()?;
    if matches.next().is_some() { return None; }
    let types = method.method_type_parameter_count();
    let constants = method.method_constant_parameter_count();
    (types <= 32 && constants <= 32).then_some((types, constants))
}

/// Trace spans for the unit snapshot's stages, so the host work between its
/// readbacks shows up in a profile. Each span includes its stage's readback.
struct UnitFactsHostTimer(Option<std::time::Instant>);

impl UnitFactsHostTimer {
    fn new() -> Self {
        Self(crate::gpu::trace::enabled().then(std::time::Instant::now))
    }

    fn stamp(&mut self, stage: &str) {
        if let Some(last) = self.0 {
            let now = std::time::Instant::now();
            let name = format!("generic_calls.unit_facts.{stage}");
            crate::gpu::trace::record_host_span("host.compiler", &name, last, now);
            self.0 = Some(now);
        }
    }
}

pub(super) fn words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

/// The regions of one batched readback, read back as one flat vector of
/// words. Each `push` returns where its words start in that vector.
#[derive(Default)]
pub(super) struct WordBatch<'a> {
    regions: Vec<ReadbackRegion<'a>>,
    words: usize,
}

impl<'a> WordBatch<'a> {
    /// Queues `words` words of `buffer` from word `first`.
    pub(super) fn push<T>(
        &mut self,
        buffer: &'a LaniusBuffer<T>,
        first: u64,
        words: usize,
        label: &str,
    ) -> Result<usize> {
        let region = ReadbackRegion::from_buffer(buffer, first * 4, words * 4, label)?;
        Ok(self.push_region(region))
    }

    /// Queues the first `words` words of `buffer` and returns their range.
    pub(super) fn column<T>(
        &mut self,
        buffer: &'a LaniusBuffer<T>,
        words: usize,
        label: &str,
    ) -> Result<std::ops::Range<usize>> {
        let start = self.push(buffer, 0, words, label)?;
        Ok(start..start + words)
    }

    /// Queues the first `width` words of row `index` of a table of
    /// `stride`-word rows, for each index.
    pub(super) fn rows<T>(
        &mut self,
        buffer: &'a LaniusBuffer<T>,
        indices: &[u32],
        stride: usize,
        width: usize,
        label: &str,
    ) -> Result<usize> {
        let start = self.words;
        self.regions.reserve(indices.len());
        for &index in indices {
            self.push(buffer, u64::from(index) * stride as u64, width, label)?;
        }
        Ok(start)
    }

    /// Queues a planned region of whole words.
    pub(super) fn push_region(&mut self, region: ReadbackRegion<'a>) -> usize {
        let start = self.words;
        self.words += region.byte_len().div_ceil(4);
        self.regions.push(region);
        start
    }

    pub(super) fn extend(&mut self, regions: impl IntoIterator<Item = ReadbackRegion<'a>>) {
        for region in regions {
            self.push_region(region);
        }
    }

    /// Words queued so far: where the next push starts.
    pub(super) fn len(&self) -> usize {
        self.words
    }

    /// Reads every queued region in one round trip; an empty batch reads
    /// nothing.
    pub(super) fn read(
        self,
        readback: &PagedReadback,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
    ) -> Result<Vec<u32>> {
        if self.regions.is_empty() {
            return Ok(Vec::new());
        }
        let words = readback.read_regions_words(device, queue, &self.regions, label)?;
        debug_assert_eq!(words.len(), self.words);
        Ok(words)
    }
}

/// Rows `indices` of a table of `stride`-word rows, in one round trip.
pub(super) fn rows<T>(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &LaniusBuffer<T>,
    indices: &[u32],
    stride_words: usize,
) -> Result<Vec<u32>> {
    let mut batch = WordBatch::default();
    batch.rows(buffer, indices, stride_words, stride_words, "generic call rows")?;
    batch.read(readback, device, queue, "generic call rows")
}

/// Rows `indices` of a table of `width`-word rows already on the host.
fn table_rows(table: &[u32], indices: &[u32], width: usize) -> Vec<u32> {
    let mut rows = Vec::with_capacity(indices.len() * width);
    for &index in indices {
        rows.extend_from_slice(&table[index as usize * width..][..width]);
    }
    rows
}

fn sorted_unique(mut values: Vec<u32>) -> Vec<u32> {
    values.sort_unstable();
    values.dedup();
    values
}

/// The distinct valid rows of a one-word table among `values`: lookups a later
/// filter may need, read early so they share an earlier round trip.
fn in_table_rows(values: impl Iterator<Item = u32>, table: &LaniusBuffer<u32>) -> Vec<u32> {
    let rows = table.byte_size / 4;
    values
        .filter(|&value| value != INVALID && (value as usize) < rows)
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

/// Source metadata is read once while the immutable caller snapshot is resident.
/// The GPU has already assigned declaration ownership, source ordinals, and
/// composed substitution slots; this reader only copies that correspondence.
#[derive(Default)]
pub(super) struct CheckedTypeReadback {
    owners: BTreeMap<u32, CheckedContractOwner>,
    /// The keys of `owners`, sorted: an owner's index is its position.
    owner_keys: Vec<u32>,
    /// Each owner's lexical parent HIR, in owner order.
    owner_parents: Vec<(u32, u32)>,
    types: BTreeMap<(u32, u32), CheckedGenericType>,
    parameters: BTreeMap<u32, CheckedGenericParameter>,
    /// GPU-published substitutions for those exact declaration tokens, copied
    /// in the same batch as their ownership/slot metadata.
    parameter_references: BTreeMap<u32, (u32, u32)>,
    /// Published parameter substitution references index the same atom table.
    constants: BTreeMap<u32, u32>,
    constant_atoms: BTreeMap<u32, CheckedConstantValue>,
    constant_projections: BTreeMap<u32, [u32; 3]>,
    nominals: BTreeMap<u32, CheckedNominalIdentity>,
    visiting: BTreeSet<(u32, u32)>,
    /// Immutable raw rows share the same lifetime as the decoded cache. A
    /// contract frontier can fetch many roots without decoding them twice.
    instance_headers: BTreeMap<u32, [u32; TYPE_INSTANCE_COLUMNS.len()]>,
    instance_arguments: BTreeMap<u32, Option<Vec<(u32, u32)>>>,
    legacy_nominal_rows: BTreeMap<u32, (u32, u32)>,
    argument_row_count: Option<u32>,
}

impl CheckedTypeReadback {
    fn legacy_nominal_candidates(inputs: &RetainedGenericCallInputs, scalar: u32) -> Vec<u32> {
        let capacity = inputs.buffer("type_native_scalar_identity").byte_size / 4;
        [4096, 6144]
            .into_iter()
            .filter_map(|base| {
                scalar
                    .checked_sub(base)
                    .filter(|&row| (row as usize) < capacity)
            })
            .collect()
    }

    fn read_type_rows(
        &mut self,
        readback: &PagedReadback,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        inputs: &RetainedGenericCallInputs,
        instances: &[u32],
        legacy_rows: &[u32],
    ) -> Result<()> {
        let instances = instances
            .iter()
            .copied()
            .filter(|row| !self.instance_headers.contains_key(row))
            .collect::<Vec<_>>();
        let legacy_rows = legacy_rows
            .iter()
            .copied()
            .filter(|row| !self.legacy_nominal_rows.contains_key(row))
            .collect::<Vec<_>>();
        if instances.is_empty() && legacy_rows.is_empty() {
            return Ok(());
        }
        // Column-major, so each column's rows are one gather run.
        let mut batch = WordBatch::default();
        for name in TYPE_INSTANCE_COLUMNS {
            let buffer = inputs.buffer(name);
            for &instance in &instances {
                batch.push(buffer, u64::from(instance), 1, "generic argument type")?;
            }
        }
        let legacy_start = batch.len();
        for name in ["type_native_scalar_identity", "type_native_word_count"] {
            let buffer = inputs.buffer(name);
            for &row in &legacy_rows {
                batch.push(buffer, u64::from(row), 1, "legacy nominal type")?;
            }
        }
        let values = batch.read(readback, device, queue, "checked type frontier")?;
        for (index, &instance) in instances.iter().enumerate() {
            let header = std::array::from_fn(|column| values[column * instances.len() + index]);
            self.instance_headers.insert(instance, header);
        }
        let legacy = &values[legacy_start..];
        for (index, &row) in legacy_rows.iter().enumerate() {
            self.legacy_nominal_rows
                .insert(row, (legacy[index], legacy[legacy_rows.len() + index]));
        }
        Ok(())
    }

    fn read_argument_rows(
        &mut self,
        readback: &PagedReadback,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        inputs: &RetainedGenericCallInputs,
        instances: &[u32],
        speculative: bool,
    ) -> Result<()> {
        let mut batch = WordBatch::default();
        let mut requested = Vec::new();
        for &instance in instances {
            if self.instance_arguments.contains_key(&instance) {
                continue;
            }
            let values = self
                .instance_headers
                .get(&instance)
                .ok_or_else(|| anyhow!("nominal {instance} has no retained header"))?;
            ensure!(
                values[0] == 1,
                "operand read requested for a non-nominal type"
            );
            let count = values[1] as usize;
            ensure!(
                count <= super::generic_body::MAX_BODY_TYPE_ARGUMENTS,
                "generic type exceeds {} checked arguments",
                super::generic_body::MAX_BODY_TYPE_ARGUMENTS
            );
            if count == 0 {
                self.instance_arguments.insert(instance, Some(Vec::new()));
                continue;
            }
            let total = match self.argument_row_count {
                Some(total) => total,
                None => {
                    let total = rows(
                        readback,
                        device,
                        queue,
                        inputs.buffer("type_instance_arg_row_count_out"),
                        &[0],
                        1,
                    )?[0];
                    self.argument_row_count = Some(total);
                    total
                }
            };
            let row_start = values[12];
            let source_capacity = inputs.buffer("type_expr_ref_tag").byte_size / 4;
            let (tags, payloads, start) = if row_start < total && count as u32 <= total - row_start
            {
                (
                    "type_instance_arg_row_ref_tag",
                    "type_instance_arg_row_ref_payload",
                    row_start,
                )
            } else if values[11] != INVALID && (instance as usize >= source_capacity || count <= 4)
            {
                (
                    "type_instance_arg_ref_tag",
                    "type_instance_arg_ref_payload",
                    values[11],
                )
            } else {
                self.instance_arguments.insert(instance, None);
                continue;
            };
            let pair = [
                (tags, "nominal argument tags"),
                (payloads, "nominal argument types"),
            ]
            .map(|(name, label)| {
                ReadbackRegion::from_buffer(
                    inputs.buffer(name),
                    u64::from(start) * 4,
                    count * 4,
                    label,
                )
            });
            // A speculative frontier must not replace the decoder's error
            // order with a failure from a later or unreachable root.
            if speculative && pair.iter().any(|region| region.is_err()) {
                continue;
            }
            let [tags, payloads] = pair;
            let start = batch.push_region(tags?);
            batch.push_region(payloads?);
            requested.push((instance, start, count));
        }
        let values = batch.read(readback, device, queue, "checked nominal frontier")?;
        for (instance, start, count) in requested {
            let tags = &values[start..start + count];
            let payloads = &values[start + count..start + 2 * count];
            self.instance_arguments.insert(
                instance,
                Some(tags.iter().copied().zip(payloads.iter().copied()).collect()),
            );
        }
        Ok(())
    }

    /// Copy only rows reachable from these roots, in breadth-first batches.
    /// This discovers storage edges; `read_type_at_depth` remains the sole
    /// decoder and keeps its ownership, layout, depth, and cycle checks.
    pub(super) fn prefetch_types(
        &mut self,
        readback: &PagedReadback,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        inputs: &RetainedGenericCallInputs,
        roots: &[(u32, u32)],
    ) -> Result<()> {
        let mut frontier = roots.iter().copied().collect::<BTreeSet<_>>();
        let mut visited = BTreeSet::new();
        for _ in 0..MAX_RETAINED_TYPE_DEPTH {
            if frontier.is_empty() {
                break;
            }
            let mut next = BTreeSet::new();
            let mut instances = BTreeSet::new();
            let mut legacy_rows = BTreeSet::new();
            let mut constants = Vec::new();
            for (tag, payload) in frontier {
                if self.types.contains_key(&(tag, payload)) || !visited.insert((tag, payload)) {
                    continue;
                }
                match tag {
                    0x8000_0001 | 0x8000_0002 | 0x8000_0003 => constants.push((tag & 0x7fff_ffff, payload)),
                    3 if payload != INVALID => {
                        if TYPE_INSTANCE_COLUMNS.iter().all(|name| {
                            u64::from(payload) * 4 + 4 <= inputs.buffer(name).byte_size as u64
                        }) {
                            instances.insert(payload);
                        }
                    }
                    1 if payload >= 4096 => {
                        legacy_rows.extend(
                            Self::legacy_nominal_candidates(inputs, payload)
                                .into_iter()
                                .filter(|&row| {
                                    u64::from(row) * 4 + 4
                                        <= inputs.buffer("type_native_word_count").byte_size as u64
                                }),
                        );
                    }
                    2 if self.parameters.get(&payload).is_some_and(|parameter| {
                        parameter.identity.domain == CheckedParameterDomain::Type
                    }) =>
                    {
                        if let Some(&reference) = self
                            .parameter_references
                            .get(&payload)
                            .filter(|&&(tag, _)| matches!(tag, 1 | 3))
                        {
                            next.insert(reference);
                        }
                    }
                    _ => {}
                }
            }
            let instances = instances.into_iter().collect::<Vec<_>>();
            self.read_type_rows(
                readback,
                device,
                queue,
                inputs,
                &instances,
                &legacy_rows.into_iter().collect::<Vec<_>>(),
            )?;
            let mut nominals = Vec::new();
            for &instance in &instances {
                let values = self.instance_headers[&instance];
                match values[0] {
                    1 if values[1] as usize <= super::generic_body::MAX_BODY_TYPE_ARGUMENTS
                        && (values[4..7].iter().all(|&value| value != INVALID)
                            || self.nominals.contains_key(&values[10])) =>
                    {
                        nominals.push(instance)
                    }
                    2 | 3 | 4 => {
                        next.insert((values[2], values[3]));
                        if values[0] == 2 { constants.push((values[8], values[9])); }
                    }
                    _ => {}
                }
            }
            self.read_argument_rows(readback, device, queue, inputs, &nominals, true)?;
            for instance in nominals {
                if let Some(Some(arguments)) = self.instance_arguments.get(&instance) {
                    next.extend(arguments.iter().copied());
                }
            }
            self.prefetch_constants(readback, device, queue, inputs, &constants)?;
            frontier = next;
        }
        Ok(())
    }

    pub(super) fn owner_index(&self, hir: u32) -> Result<u32> {
        self.owner_keys
            .binary_search(&hir)
            .map(|index| index as u32)
            .map_err(|_| anyhow!("contract owner {hir} has no retained declaration"))
    }
    pub(super) fn parameter(&self, token: u32) -> Option<CheckedGenericParameter> {
        self.parameters.get(&token).copied()
    }
    pub(super) fn nominal_identity(&self, token: u32) -> Result<CheckedNominalIdentity> {
        self.nominals
            .get(&token)
            .copied()
            .ok_or_else(|| anyhow!("contract declaration {token} has no retained ownership"))
    }
    fn get(&self, key: &(u32, u32)) -> Option<&CheckedGenericType> {
        self.types.get(key)
    }
    fn insert(&mut self, key: (u32, u32), value: CheckedGenericType) {
        self.types.insert(key, value);
    }

    fn constant_atom_row(&self, kind: u32, payload: u32) -> Option<u32> {
        match kind {
            1 => (payload != INVALID).then_some(payload),
            2 if self.parameters.get(&payload).is_some_and(|parameter|
                parameter.identity.domain == CheckedParameterDomain::Constant) =>
                self.constants.get(&payload).copied().filter(|&row| row != INVALID),
            _ => None,
        }
    }

    /// Copy only reachable atoms, in one batch. Row numbers never become value
    /// identity, and this boundary performs no evaluation or substitution.
    pub(super) fn prefetch_constants(
        &mut self,
        readback: &PagedReadback,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        inputs: &RetainedGenericCallInputs,
        references: &[(u32, u32)],
    ) -> Result<()> {
        let mut frontier = references.iter().copied().collect::<BTreeSet<_>>();
        let mut visited = BTreeSet::new();
        for _ in 0..MAX_RETAINED_TYPE_DEPTH {
            if frontier.is_empty() { return Ok(()); }
            let mut atoms = BTreeSet::new();
            let mut projections = BTreeSet::new();
            let mut next = BTreeSet::new();
            for (kind, payload) in frontier {
                if !visited.insert((kind, payload)) { continue; }
                if let Some(row) = self.constant_atom_row(kind, payload) {
                    if !self.constant_atoms.contains_key(&row) { atoms.insert(row); }
                } else if kind == 3 && payload != INVALID {
                    if let Some(&[_, child_kind, child_payload]) = self.constant_projections.get(&payload) {
                        next.insert((child_kind, child_payload));
                    } else { projections.insert(payload); }
                }
            }
            let atoms = atoms.into_iter().collect::<Vec<_>>();
            let projections = projections.into_iter().collect::<Vec<_>>();
            let mut batch = WordBatch::default();
            for (rows, name) in [(&atoms, "checked_constant_atoms"),
                (&projections, "checked_constant_projections")] {
                batch.rows(inputs.buffer(name), rows, 4, 4, "retained constant frontier")?;
            }
            let values = batch.read(readback, device, queue, "retained constant frontier")?;
            for (&row, words) in atoms.iter().zip(values.chunks_exact(4)) {
                self.retain_constant_atom(row, words)?;
            }
            for (&row, words) in projections.iter().zip(values[atoms.len() * 4..].chunks_exact(4)) {
                self.retain_constant_projection(row, words)?;
                let [_, child_kind, child_payload] = self.constant_projections[&row];
                next.insert((child_kind, child_payload));
            }
            frontier = next;
        }
        ensure!(frontier.is_empty(), "retained constant graph exceeds {MAX_RETAINED_TYPE_DEPTH} levels");
        Ok(())
    }

    fn retain_constant_projection(&mut self, row: u32, words: &[u32]) -> Result<()> {
        ensure!(row != INVALID && words.len() == 4 && words[3] == 0 &&
            crate::primitive_types::integer_bits(words[0]) != 0 &&
            matches!(words[1], 1 | 2 | 3) && words[2] != INVALID,
            "retained count projection has an invalid row or wire shape");
        let value = [words[0], words[1], words[2]];
        ensure!(self.constant_projections.get(&row).is_none_or(|&prior| prior == value),
            "one retained count projection changed within its source snapshot");
        self.constant_projections.insert(row, value);
        Ok(())
    }

    fn retain_constant_atom(&mut self, row: u32, words: &[u32]) -> Result<()> {
        ensure!(row != INVALID && words.len() == 4 && words[3] == 0,
            "retained constant atom has an invalid row or wire shape");
        let value = CheckedConstantValue::from_words(words[0], [words[1], words[2]])
            .ok_or_else(|| anyhow!("retained constant atom has invalid scalar bits"))?;
        ensure!(self.constant_atoms.get(&row).is_none_or(|&prior| prior == value),
            "one retained constant atom changed value within its source snapshot");
        self.constant_atoms.insert(row, value);
        Ok(())
    }

    fn constant(&self, kind: u32, payload: u32) -> CheckedGenericConstantValue {
        self.constant_at_depth(kind, payload, 0, &mut BTreeSet::new())
    }

    fn constant_at_depth(&self, kind: u32, payload: u32, depth: usize,
        visiting: &mut BTreeSet<u32>) -> CheckedGenericConstantValue {
        if depth >= MAX_RETAINED_TYPE_DEPTH {
            return CheckedGenericConstantValue::Unresolved { kind, payload };
        }
        if kind == 3 {
            let Some(&[target_scalar, child_kind, child_payload]) = self.constant_projections.get(&payload)
                .filter(|_| !visiting.contains(&payload)) else {
                    return CheckedGenericConstantValue::Unresolved { kind, payload };
                };
            visiting.insert(payload);
            let source = self.constant_at_depth(child_kind, child_payload, depth + 1, visiting);
            visiting.remove(&payload);
            return CheckedGenericConstantValue::CountProjection { target_scalar, source: Box::new(source) };
        }
        if let Some(row) = self.constant_atom_row(kind, payload) {
            if let Some(&value) = self.constant_atoms.get(&row) {
                let matches_parameter = kind != 2 || self.parameters.get(&payload)
                    .is_some_and(|parameter| parameter.constant_scalar == Some(value.scalar()));
                if matches_parameter { return CheckedGenericConstantValue::Literal(value); }
            }
            // A published substitution must not fall back to its symbolic
            // binder when the referenced atom is unavailable or ill-typed.
            return CheckedGenericConstantValue::Unresolved { kind, payload };
        }
        if kind == 2 {
            if let Some(&parameter) = self.parameters.get(&payload).filter(|parameter|
                parameter.identity.domain == CheckedParameterDomain::Constant &&
                parameter.constant_scalar.is_some_and(constant_scalar_is_supported))
            {
                return CheckedGenericConstantValue::Parameter(parameter);
            }
        }
        CheckedGenericConstantValue::Unresolved { kind, payload }
    }

    /// Words of one owner's metadata row: HIR core (4), generic parameter
    /// range (2), public declaration index, and with an exported interface
    /// the generic scope owner.
    fn owner_metadata_words(interface_exported: bool) -> usize {
        if interface_exported { 8 } else { 7 }
    }

    /// Queues the owner rows, then six words per parameter: type slot,
    /// constant slot, constant value, constant scalar, and the substitution
    /// reference tag and payload.
    fn push_parameter_metadata<'a>(
        batch: &mut WordBatch<'a>,
        semantic: &'a OwnedGpuSemanticArtifact,
        inputs: &'a RetainedGenericCallInputs,
        parameters: &[u32],
        owners: &[u32],
        interface_exported: bool,
    ) -> Result<()> {
        // These columns depend only on the compact rows above. Copy them in
        // one batch instead of introducing a fence for every metadata table.
        let mut owner_columns = vec![
            (inputs.buffer("compact_hir_core"), 4),
            (inputs.buffer("compact_generic_param_ranges"), 2),
            (inputs.buffer("interface_public_decl_index_by_hir"), 1),
        ];
        if interface_exported {
            owner_columns.push((inputs.buffer("interface_generic_scope_owner_by_hir"), 1));
        }
        for &owner in owners {
            for &(buffer, width) in &owner_columns {
                batch.push(
                    buffer,
                    u64::from(owner) * width as u64,
                    width,
                    "retained generic owner metadata",
                )?;
            }
        }
        let parameter_columns = [
            &semantic.type_generic_param_slot,
            &semantic.type_const_param_slot,
            inputs.buffer("type_const_param_value_by_token"),
            inputs.buffer("type_const_param_scalar_by_token"),
            inputs.buffer("type_expr_ref_tag"),
            inputs.buffer("type_expr_ref_payload"),
        ];
        for row in parameters.chunks_exact(4) {
            for buffer in parameter_columns {
                batch.push(buffer, u64::from(row[1]), 1, "retained generic parameter metadata")?;
            }
        }
        Ok(())
    }

    /// Decodes the rows [`Self::push_parameter_metadata`] queued.
    fn from_parameter_metadata(
        parameters: &[u32],
        owners: &[u32],
        metadata: &[u32],
        interface_exported: bool,
        template_contracts: Option<&CheckedUnitContracts>,
    ) -> Result<Self> {
        let owner_words = Self::owner_metadata_words(interface_exported);
        ensure!(
            parameters.len() % 4 == 0
                && metadata.len() == owners.len() * owner_words + parameters.len() / 4 * 6,
            "retained generic parameter metadata is incomplete"
        );
        let (owner_rows, parameter_rows) = metadata.split_at(owners.len() * owner_words);
        // The first template binder of each source HIR.
        let mut template_binders = BTreeMap::new();
        for owner in template_contracts.iter().flat_map(|contracts| &contracts.binders) {
            template_binders.entry(owner.source_hir).or_insert(owner);
        }
        let mut result = Self {
            owner_keys: owners.to_vec(),
            owner_parents: Vec::with_capacity(owners.len()),
            ..Self::default()
        };
        for (&hir, row) in owners.iter().zip(owner_rows.chunks_exact(owner_words)) {
            let core = &row[..4];
            let public = row[6];
            let scope_owner = if interface_exported { row[7] } else { INVALID };
            let template_owner = template_binders.get(&hir).copied();
            ensure!(
                interface_exported || template_owner.is_some(),
                "replayed generic owner {hir} has no immutable template identity"
            );
            let binder = if let Some(owner) = template_owner {
                owner.binder
            } else if public != INVALID {
                CheckedBinderIdentity::Public {
                    owner: public,
                    scope: 0,
                }
            } else if scope_owner != INVALID {
                CheckedBinderIdentity::Public {
                    owner: scope_owner,
                    scope: if core[0] == HIR_NODE_FN {
                        0x8000_0000
                    } else {
                        0xc000_0000
                    } | hir,
                }
            } else {
                CheckedBinderIdentity::SourceLocal {
                    owner_kind: core[0],
                    declaration_start_token: core[2],
                }
            };
            result.owners.insert(
                hir,
                CheckedContractOwner {
                    source_hir: hir,
                    binder,
                    callable: template_owner.and_then(|owner| owner.callable),
                    parameters: Vec::new(),
                    // Indices belong to the immutable definition table. A
                    // replay publishes that original table, not its sparse
                    // decoder cache; an export reads its links later.
                    enclosing_owner: if interface_exported {
                        None
                    } else {
                        template_owner.and_then(|owner| owner.enclosing_owner)
                    },
                },
            );
            result.owner_parents.push((hir, core[1]));
        }
        for (ordinal, (row, parameter_metadata)) in parameters
            .chunks_exact(4)
            .zip(parameter_rows.chunks_exact(6))
            .enumerate()
        {
            let owner = owners
                .binary_search(&row[0])
                .expect("retained parameter owner");
            let range = &owner_rows[owner * owner_words + 4..][..2];
            ensure!(
                range[0] != INVALID
                    && ordinal as u32 >= range[0]
                    && (ordinal as u32) - range[0] < range[1],
                "generic parameter has no declaration-owned source ordinal"
            );
            let (domain, binding_slot) = match row[2] {
                1 => (CheckedParameterDomain::Type, parameter_metadata[0]),
                2 => (CheckedParameterDomain::Constant, parameter_metadata[1]),
                _ => continue,
            };
            if binding_slot == INVALID {
                continue;
            }
            let constant_scalar = if domain == CheckedParameterDomain::Constant {
                let scalar = parameter_metadata[3];
                ensure!(constant_scalar_is_supported(scalar),
                    "retained constant parameter has no admitted declared scalar");
                Some(scalar)
            } else { None };
            let binder = result.owners[&row[0]].binder;
            let mut parameter = CheckedGenericParameter {
                identity: CheckedParameterIdentity {
                    unit: [INVALID, INVALID],
                    binder,
                    domain,
                    source_ordinal: ordinal as u32 - range[0],
                },
                binding_slot,
                constant_scalar,
            };
            if !interface_exported {
                let template = template_binders
                    .get(&row[0])
                    .and_then(|owner| {
                        owner.parameters.iter().find(|parameter| {
                            parameter.identity.domain == domain
                                && parameter.identity.source_ordinal == ordinal as u32 - range[0]
                        })
                    })
                    .ok_or_else(|| {
                        anyhow!("replayed parameter has no exact immutable template binder")
                    })?;
                ensure!(
                    template.binding_slot == binding_slot && template.constant_scalar == constant_scalar,
                    "replayed parameter changed its checked slot or declared scalar"
                );
                parameter = *template;
            }
            ensure!(
                result.parameters.insert(row[1], parameter).is_none(),
                "generic parameter declaration token is not unique"
            );
            result
                .owners
                .get_mut(&row[0])
                .expect("retained parameter owner")
                .parameters
                .push(parameter);
            if domain == CheckedParameterDomain::Constant {
                result.constants.insert(row[1], parameter_metadata[2]);
            } else {
                result
                    .parameter_references
                    .insert(row[1], (parameter_metadata[4], parameter_metadata[5]));
            }
        }
        Ok(result)
    }

    /// Words of one nominal header's metadata: declaration by name token,
    /// HIR core (4), HIR payload (4), and public declaration index.
    const NOMINAL_METADATA_WORDS: usize = 10;

    fn read_nominal_metadata(
        &mut self,
        headers: &[(u32, u32, u32, u32)],
        metadata: &[u32],
    ) -> Result<()> {
        ensure!(
            metadata.len() == headers.len() * Self::NOMINAL_METADATA_WORDS,
            "retained nominal ownership metadata is incomplete"
        );
        for (&(declaration, _hir, token, kind), metadata) in
            headers.iter().zip(metadata.chunks_exact(Self::NOMINAL_METADATA_WORDS))
        {
            ensure!(
                metadata[0] == declaration,
                "retained nominal token {token} does not map back to declaration {declaration}"
            );
            let core = &metadata[1..5];
            let payload = &metadata[5..9];
            // Declaration item kinds and canonical HIR node kinds are
            // separate namespaces (parser/hir/nodes.slang).
            let expected_kind = match kind {
                HIR_ITEM_KIND_STRUCT => HIR_NODE_STRUCT_ITEM,
                HIR_ITEM_KIND_ENUM => HIR_NODE_ENUM_ITEM,
                HIR_ITEM_KIND_TYPE_ALIAS => HIR_NODE_TYPE_ALIAS_ITEM,
                HIR_ITEM_KIND_TRAIT => HIR_NODE_ITEM,
                _ => unreachable!("nominal header kinds"),
            };
            ensure!(
                core[0] == expected_kind
                    && payload[1] == token
                    && (!matches!(kind, HIR_ITEM_KIND_TYPE_ALIAS | HIR_ITEM_KIND_TRAIT)
                        || payload[0] == kind),
                "retained nominal token {token} has declaration kind {kind}, HIR kind {}, and name token {}; expected HIR kind {expected_kind} with the same name token",
                core[0],
                payload[1]
            );
            let public = metadata[9];
            let identity = if public != INVALID {
                CheckedNominalIdentity::Public([INVALID, INVALID, public])
            } else {
                CheckedNominalIdentity::SourceLocal {
                    unit: [INVALID, INVALID],
                    declaration_token: token,
                }
            };
            ensure!(
                self.nominals.insert(token, identity).is_none(),
                "retained nominal declaration token is not unique"
            );
        }
        Ok(())
    }
}


/// Decode accepted GPU facts while the calling compilation still owns the
/// resident pipeline lock. Returned rows contain no borrowed GPU buffers.
///
/// Every batch is read as one flat word vector and decoded by offset, and
/// every lookup table is a sorted vector: a replay of a 1 MB program decodes
/// ~8k calls, so per-row allocations and tree lookups dominated its time.
pub(super) fn read_unit_facts(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    readback_buffers: &crate::gpu::buffers::CapacityBufferCache,
    semantic: &OwnedGpuSemanticArtifact,
    interface_exported: bool,
    template_contracts: Option<&CheckedUnitContracts>,
) -> Result<CheckedUnitFacts> {
    // Ordinary object-only jobs do not publish a definition contract snapshot.
    // Body replay is explicit and supplies the immutable template instead.
    if !interface_exported && template_contracts.is_none() {
        return Ok(CheckedUnitFacts::default());
    }
    let Some(inputs) = semantic.generic_call_inputs.as_ref() else {
        return Ok(CheckedUnitFacts::default());
    };
    let mut timer = UnitFactsHostTimer::new();
    // This page is physical staging only. Each read copies the current accepted
    // rows while the caller holds the resident pipeline lock; no facts survive
    // here between jobs. Resident workspace trim clears the owning cache.
    // Every page is one round trip: a 1 MB program's call metadata is 131 KB,
    // and a generic program's contextual argument rows are a few hundred KB.
    const SNAPSHOT_PAGE_BYTES: usize = 1 << 20;
    let readback = PagedReadback::from_staging(readback_buffers.buffer(
        device,
        "generic call snapshot",
        SNAPSHOT_PAGE_BYTES,
        SNAPSHOT_PAGE_BYTES,
        wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
    ));
    let mut batch = WordBatch::default();
    for name in [
        "call_generic_claim_count_out",
        "call_arg_row_count_out",
        "retained_callable_count",
        "call_const_claim_count_out",
        "compact_generic_param_count",
        "decl_count_out",
        "compact_predicate_count",
        "compact_type_arg_count",
        "compact_method_count",
        "compact_field_count",
        "compact_variant_count",
        "compact_variant_payload_row_count",
    ] {
        batch.push(inputs.buffer(name), 0, 1, name)?;
    }
    let counts = batch.read(&readback, device, queue, "generic call counts")?;
    timer.stamp("counts");
    // Inactive producer families may share reused scratch. Current job flags,
    // not previous buffer contents, determine whether those counts are valid.
    let count = |index: usize, valid: bool| if valid { counts[index] as usize } else { 0 };
    let claim_count = count(0, inputs.call_facts_active);
    let argument_count = count(1, inputs.call_facts_active);
    let callable_count = count(2, inputs.call_facts_active);
    let constant_claim_count = count(3, inputs.call_facts_active);
    let generic_parameter_count = count(4, true);
    let declaration_count = count(5, true);
    let predicate_count = count(6, interface_exported && inputs.contract_facts_active);
    let type_argument_count = count(7, predicate_count != 0);
    let method_count = count(
        8,
        inputs.method_facts_active || predicate_count != 0 || generic_parameter_count != 0,
    );
    // Recipes are definition facts. A replay reuses the original contract Arc
    // and must not replace symbolic fields with the selected body's bindings.
    let field_count = count(9, interface_exported);
    let variant_count = count(10, interface_exported);
    let variant_payload_count = count(11, interface_exported);
    // A provider can own callable definitions without calls or generics.
    if callable_count == 0
        && predicate_count == 0
        && generic_parameter_count == 0
        && declaration_count == 0
        && method_count == 0
    {
        return Ok(CheckedUnitFacts::default());
    }
    for name in ["decl_kind", "decl_name_token", "decl_hir_node"] {
        ensure!(
            declaration_count <= inputs.buffer(name).byte_size / 4,
            "retained declaration count exceeds its checked {name} table"
        );
    }
    let callable_bytes = callable_count
        .checked_mul(RETAINED_CALLABLE_WORDS * 4)
        .ok_or_else(|| anyhow!("retained callable record size overflow"))?;
    ensure!(
        callable_bytes <= inputs.buffer("retained_callable_records").byte_size,
        "retained callable count exceeds its record table"
    );
    let mut batch = WordBatch::default();
    let mut columns = Vec::new();
    for name in [
        "call_generic_claim_callee",
        "call_generic_claim_slot",
        "call_generic_claim_ref_tag",
        "call_generic_claim_ref_payload",
        "call_generic_claim_arg_row",
    ] {
        columns.push(batch.column(inputs.buffer(name), claim_count, "claim column")?);
    }
    columns.push(batch.column(
        inputs.buffer("call_arg_row_call_node"),
        argument_count,
        "argument calls",
    )?);
    columns.push(batch.column(
        inputs.buffer("retained_callable_records"),
        callable_bytes / 4,
        "callable records with source spans",
    )?);
    for name in [
        "call_const_claim_callee",
        "call_const_claim_slot",
        "call_const_claim_ref_kind",
        "call_const_claim_ref_payload",
        "call_const_claim_arg_row",
    ] {
        columns.push(batch.column(inputs.buffer(name), constant_claim_count,
            "constant claim column")?);
    }
    columns.push(batch.column(
        inputs.buffer("compact_generic_params"),
        generic_parameter_count * 4,
        "retained generic parameters",
    )?);
    for name in ["decl_kind", "decl_name_token", "decl_hir_node"] {
        columns.push(batch.column(inputs.buffer(name), declaration_count,
            "retained declaration headers")?);
    }
    for (name, count, width) in [
        ("compact_predicates", predicate_count, 4),
        ("compact_type_args", type_argument_count, 5),
        ("compact_method_cores", method_count, 4),
        ("compact_method_signatures", method_count, 4),
        ("compact_fields", field_count, 4),
        ("compact_variants", variant_count, 4),
        ("compact_variant_payloads", variant_payload_count, 4),
        ("compact_variant_payload_start", variant_count, 1),
        ("compact_variant_payload_count", variant_count, 1),
    ] {
        ensure!(
            count <= inputs.buffer(name).byte_size / (width * 4),
            "retained {name} count exceeds its checked table"
        );
        columns.push(batch.column(inputs.buffer(name), count * width,
            "retained contract source rows")?);
    }
    let selected_constant_column = columns.len();
    columns.push(batch.column(
        inputs.buffer("call_const_claim_selected"),
        constant_claim_count,
        "GPU-selected constant claims",
    )?);
    let claims = batch.read(&readback, device, queue, "generic call claims")?;
    let columns = columns.into_iter().map(|range| &claims[range]).collect::<Vec<_>>();
    timer.stamp("claims");
    // The compact producer owns all three columns. Invalid spans must fail
    // retention rather than silently remove a call from program obligations.
    ensure!(columns[6].len() % RETAINED_CALLABLE_WORDS == 0,
        "retained callable record table is truncated");
    let mut call_spans = columns[6]
        .chunks_exact(RETAINED_CALLABLE_WORDS)
        .map(|record| {
            ensure!(record[0] != INVALID && record[1] != INVALID && record[2] != 0
                && record[1].checked_add(record[2]).is_some(),
                "retained call {} has no valid checked source span", record[0]);
            Ok((record[0], [record[1], record[2]]))
        })
        .collect::<Result<Vec<_>>>()?;
    call_spans.sort_unstable_by_key(|&(call, _)| call);
    if let Some(pair) = call_spans.windows(2).find(|pair| pair[0].0 == pair[1].0) {
        return Err(anyhow!("retained call {} has duplicate source records", pair[0].0));
    }
    let call_ids = call_spans.iter().map(|&(call, _)| call).collect::<Vec<_>>();
    let calls_with_claims = sorted_unique(
        (0..claim_count)
            .filter(|&claim| columns[0][claim] != INVALID && columns[1][claim] != INVALID)
            .filter_map(|claim| columns[5].get(columns[4][claim] as usize).copied())
            .collect(),
    );
    let parameters = columns[12];
    // Reuse accepted compact declaration/method rows already in this batch.
    // Trait requirements own contracts but have no executable native target.
    let requirement_hirs = sorted_unique(
        columns[18]
            .chunks_exact(4)
            .filter(|method| method[2] == INVALID)
            .map(|method| method[0])
            .collect(),
    );
    let method_impls = columns[18]
        .chunks_exact(4)
        .filter(|method| method[2] != INVALID)
        .map(|method| (method[0], method[2]))
        .collect::<Vec<_>>();
    let callable_hirs = sorted_unique(
        (0..declaration_count)
            .filter(|&declaration| {
                matches!(
                    columns[13][declaration],
                    HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN
                )
            })
            .map(|declaration| columns[15][declaration])
            .filter(|hir| requirement_hirs.binary_search(hir).is_err())
            .chain(method_impls.iter().map(|&(method, _)| method))
            .collect(),
    );
    ensure!(
        callable_hirs.last() != Some(&INVALID),
        "retained callable declaration has no HIR"
    );
    let parameter_owners = sorted_unique(
        parameters
            .chunks_exact(4)
            .map(|row| row[0])
            .chain(
                columns[16]
                    .chunks_exact(4)
                    .filter(|row| matches!(row[3] & 255, 1 | 2))
                    .map(|row| row[0]),
            )
            .chain(columns[18].chunks_exact(4).map(|row| row[0]))
            .chain(method_impls.iter().map(|&(_, implementation)| implementation))
            .chain(callable_hirs.iter().copied())
            // Layout recipes also own nongeneric declaration scopes. Keep the
            // same inventory during replay so template binder identities match.
            .chain((0..declaration_count)
                .filter(|&declaration| matches!(columns[13][declaration],
                    HIR_ITEM_KIND_STRUCT | HIR_ITEM_KIND_ENUM))
                .map(|declaration| columns[15][declaration]))
            .collect(),
    );
    let nominal_headers = (0..declaration_count)
        .filter(|&declaration| {
            matches!(
                columns[13][declaration],
                HIR_ITEM_KIND_STRUCT | HIR_ITEM_KIND_ENUM | HIR_ITEM_KIND_TYPE_ALIAS
            ) || (predicate_count != 0 && columns[13][declaration] == HIR_ITEM_KIND_TRAIT)
        })
        .map(|declaration| {
            (
                declaration as u32,
                columns[15][declaration],
                columns[14][declaration],
                columns[13][declaration],
            )
        })
        .collect::<Vec<_>>();
    // Everything below depends only on the rows above: call records, owner
    // and parameter metadata, nominal ownership, callers, result context
    // masks, callable native identities, and contract scalars share one
    // round trip.
    let mut batch = WordBatch::default();
    batch.rows(
        &semantic.calls_by_hir,
        &call_ids,
        CALL_WORDS,
        CALL_RECORD_READ_WORDS,
        "generic call record",
    )?;
    let parameter_metadata_start = batch.len();
    CheckedTypeReadback::push_parameter_metadata(
        &mut batch,
        semantic,
        inputs,
        parameters,
        &parameter_owners,
        interface_exported,
    )?;
    let nominal_metadata_start = batch.len();
    let nominal_columns = [
        inputs.buffer("decl_id_by_name_token"),
        inputs.buffer("compact_hir_core"),
        inputs.buffer("compact_hir_payload"),
        inputs.buffer("interface_public_decl_index_by_hir"),
    ];
    for &(declaration, hir, token, _) in &nominal_headers {
        ensure!(
            hir != INVALID && token != INVALID,
            "retained nominal declaration {declaration} has no HIR or name token"
        );
        for (buffer, row, width) in [
            (nominal_columns[0], token, 1),
            (nominal_columns[1], hir, 4),
            (nominal_columns[2], hir, 4),
            (nominal_columns[3], hir, 1),
        ] {
            batch.push(
                buffer,
                u64::from(row) * width as u64,
                width,
                "retained nominal ownership",
            )?;
        }
    }
    let caller_metadata_start = batch.len();
    batch.rows(&semantic.enclosing_fn_by_hir, &call_ids, 1, 1, "retained actual caller")?;
    // Both result domains share this batch. Masks own validity; unpublished
    // context payload cells need no initialization or readback.
    let masks_available = inputs.buffer("call_context_arg_mask").byte_size > 4;
    let mask_start = batch.len();
    if masks_available {
        for name in ["call_context_arg_mask", "call_context_constant_mask"] {
            batch.rows(inputs.buffer(name), &call_ids, 1, 1, "result context mask")?;
        }
    }
    let callable_metadata_start = batch.len();
    if interface_exported {
        batch.rows(
            inputs.buffer("semantic_function_native_symbol_by_hir"),
            &callable_hirs,
            1,
            1,
            "retained callable native identity",
        )?;
    }
    let contract_source = checked_contracts::ContractSourceRows {
        predicates: columns[16],
        type_arguments: columns[17],
        methods: columns[18],
        method_signatures: columns[19],
        declaration_kinds: columns[13],
        declaration_tokens: columns[14],
    };
    let contract_metadata_start = batch.len();
    // Only gather valid sparse regions here. Defer any planning failure to
    // read_contracts, after parameter, nominal, and enclosing-owner checks.
    let contract_metadata = if interface_exported && predicate_count != 0 {
        checked_contracts::metadata_regions(inputs, contract_source).ok()
    } else {
        None
    };
    let contract_metadata_available = contract_metadata.is_some();
    if let Some(regions) = contract_metadata {
        batch.extend(regions);
    }
    timer.stamp("plan_rows");
    let metadata = batch.read(&readback, device, queue, "generic call rows")?;
    timer.stamp("rows_read");
    let call_records = &metadata[..parameter_metadata_start];
    let owner_words = CheckedTypeReadback::owner_metadata_words(interface_exported);
    let owner_metadata =
        &metadata[parameter_metadata_start..][..parameter_owners.len() * owner_words];
    let mut types = CheckedTypeReadback::from_parameter_metadata(
        parameters,
        &parameter_owners,
        &metadata[parameter_metadata_start..nominal_metadata_start],
        interface_exported,
        template_contracts,
    )?;
    types.read_nominal_metadata(
        &nominal_headers,
        &metadata[nominal_metadata_start..caller_metadata_start],
    )?;
    timer.stamp("rows");
    let callers = &metadata[caller_metadata_start..mask_start];
    let no_masks;
    let (context_masks, constant_context_masks): (&[u32], &[u32]) = if masks_available {
        let masks = &metadata[mask_start..callable_metadata_start];
        masks.split_at(call_ids.len())
    } else {
        no_masks = vec![0; call_ids.len()];
        (&no_masks, &no_masks)
    };
    let enclosing_owners = if interface_exported && generic_parameter_count != 0 {
        types
            .owner_parents
            .iter()
            .filter_map(|&(owner, parent)| (parent != INVALID).then_some((owner, parent)))
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };
    if !enclosing_owners.is_empty() {
        let mut batch = WordBatch::default();
        let links = inputs.buffer("generic_decl_owner_by_node_a");
        for &(_, parent) in &enclosing_owners {
            batch.push(links, u64::from(parent), 1, "retained enclosing binder")?;
        }
        let parents = batch.read(&readback, device, queue, "retained binder links")?;
        for (&(owner, _), &parent) in enclosing_owners.iter().zip(&parents) {
            let enclosing = if parent == INVALID {
                None
            } else {
                Some(types.owner_index(parent)?)
            };
            ensure!(
                parent != owner,
                "retained binder has a self-owning enclosing link"
            );
            types
                .owners
                .get_mut(&owner)
                .expect("retained owner")
                .enclosing_owner = enclosing;
        }
    }
    if interface_exported {
        // The nearest-generic map intentionally skips nongeneric binders.
        // Method scope instead has an exact lexical impl parent, already
        // checked and retained in the compact method record. Keep the map for
        // other ancestor links and type decoding; do not replace its meaning.
        for &(method, implementation) in &method_impls {
            let parent = types.owner_index(implementation)?;
            let core = &owner_metadata[parent as usize * owner_words..][..4];
            ensure!(
                core[0] == HIR_NODE_IMPL && method != implementation,
                "retained method {method} has no checked lexical impl owner"
            );
            types.owners.get_mut(&method).expect("retained method owner")
                .enclosing_owner = Some(parent);
        }
        let natives = &metadata[callable_metadata_start..contract_metadata_start];
        for (&hir, &native) in callable_hirs.iter().zip(natives) {
            let owner_index = parameter_owners
                .binary_search(&hir)
                .expect("retained callable owner");
            let core = &owner_metadata[owner_index * owner_words..][..4];
            ensure!(
                core[0] == HIR_NODE_FN,
                "retained callable {hir} is not a checked function owner"
            );
            ensure!(
                native != INVALID,
                "retained callable {hir} has no checked native identity"
            );
            let owner = types.owners.get_mut(&hir).expect("retained callable owner");
            owner.callable = Some(CheckedCallableOwner {
                native_symbol: native,
            });
        }
    }
    timer.stamp("masks_and_owners");
    let mut contracts = if interface_exported {
        checked_contracts::read_contracts(
            &readback,
            device,
            queue,
            inputs,
            &mut types,
            contract_source,
            contract_metadata_available.then_some(&metadata[contract_metadata_start..]),
        )?
    } else {
        // The compiled replay retains its template Arc; do not deep-copy
        // immutable definition graphs just to discard them at that boundary.
        CheckedUnitContracts::default()
    };
    if interface_exported {
        contracts.binders = types.owners.values().cloned().collect();
        contracts.nominal_recipes = checked_contracts::read_nominal_recipes(
            &readback, device, queue, inputs, &mut types,
            checked_contracts::NominalRecipeSourceRows {
                headers: &nominal_headers,
                fields: columns[20],
                variants: columns[21],
                payloads: columns[22],
                payload_starts: columns[23],
                payload_counts: columns[24],
            },
        )?;
    }
    timer.stamp("contracts");
    if call_ids.is_empty() {
        return Ok(CheckedUnitFacts {
            generic_calls: Vec::new(),
            contracts,
            call_owners: Vec::new(),
            native_call_owners: Vec::new(),
        });
    }
    let local_tokens = sorted_unique(
        call_records
            .chunks_exact(CALL_RECORD_READ_WORDS)
            .filter(|record| record[11] == 1)
            .map(|record| record[0])
            .collect(),
    );
    let local_names = rows(
        &readback,
        device,
        queue,
        inputs.buffer("call_fn_index"),
        &local_tokens,
        1,
    )?;
    ensure!(
        local_names.iter().all(|&name| name != INVALID),
        "local generic call has no declaration-name token"
    );
    // Each level of this lookup chain is one readback. The method chain needs
    // the method's impl and then the impl's counts; the free functions that
    // stay generic need their declaration, then its HIR, then its public
    // index. Method rows, impl cores, and declaration HIRs are already in the
    // batches above, and the declarations of every local name are read with
    // the counts, so the lookups take three round trips instead of five.
    let generic_counts_by_token = inputs.buffer("type_decl_generic_param_count_by_owner_token");
    let constant_counts_by_token = inputs.buffer("type_decl_const_param_count_by_owner_token");
    let decl_by_name_token = inputs.buffer("decl_id_by_name_token");
    let decl_hir_node = inputs.buffer("decl_hir_node");
    let public_decl_by_hir = inputs.buffer("interface_public_decl_index_by_hir");
    let name_rows = in_table_rows(local_names.iter().copied(), decl_by_name_token);
    let mut batch = WordBatch::default();
    let local_count_start = batch.rows(generic_counts_by_token, &local_names, 1, 1, "local counts")?;
    let local_constant_start =
        batch.rows(constant_counts_by_token, &local_names, 1, 1, "local constant counts")?;
    let method_row_start =
        batch.rows(inputs.buffer("method_decl_method_row"), &local_names, 1, 1, "local methods")?;
    let name_decl_start = batch.rows(decl_by_name_token, &name_rows, 1, 1, "local declarations")?;
    let level = batch.read(&readback, device, queue, "generic call rows")?;
    let local_count = local_tokens.len();
    let local_type_counts = &level[local_count_start..][..local_count];
    let local_constant_counts = &level[local_constant_start..][..local_count];
    let method_rows = &level[method_row_start..][..local_count];
    let name_decl_rows = &level[name_decl_start..][..name_rows.len()];
    let generic_functions = (0..local_count)
        .filter(|&index| {
            method_rows[index] == INVALID
                && (local_type_counts[index] != 0 || local_constant_counts[index] != 0)
        })
        .map(|index| local_tokens[index])
        .collect::<Vec<_>>();
    let candidate_names = in_table_rows(
        (0..local_count)
            .filter(|&index| generic_functions.binary_search(&local_tokens[index]).is_ok())
            .map(|index| local_names[index]),
        decl_by_name_token,
    );
    let name_decls = candidate_names
        .iter()
        .map(|&name| {
            let row = name_rows.binary_search(&name).expect("candidate name was read");
            (name, name_decl_rows[row])
        })
        .collect::<BTreeMap<_, _>>();
    let candidate_decls = in_table_rows(name_decls.values().copied(), decl_hir_node);
    // Methods inherit the impl's parameters even when their own signature
    // declares none. Read declaration-owned metadata; receiver constraints
    // have already been solved by the GPU into the call context relation.
    let method_ids: Vec<_> = method_rows.iter().copied().filter(|&row| row != INVALID).collect();
    let method_table_rows = columns[18].len() / 4;
    let mut batch = WordBatch::default();
    let method_rows_read = if method_ids.iter().all(|&row| (row as usize) < method_table_rows) {
        None
    } else {
        let cores = batch.rows(inputs.buffer("compact_method_cores"), &method_ids, 4, 4,
            "method cores")?;
        let signatures = batch.rows(inputs.buffer("compact_method_signatures"), &method_ids, 4, 4,
            "method signatures")?;
        Some((cores, signatures))
    };
    let decl_hirs_read = if candidate_decls.iter().all(|&decl| (decl as usize) < declaration_count) {
        None
    } else {
        Some(batch.rows(decl_hir_node, &candidate_decls, 1, 1, "declaration HIRs")?)
    };
    let fallback = batch.read(&readback, device, queue, "generic call rows")?;
    let (method_cores, method_signatures) = match method_rows_read {
        None => (
            table_rows(columns[18], &method_ids, 4),
            table_rows(columns[19], &method_ids, 4),
        ),
        Some((cores, signatures)) => (
            fallback[cores..signatures].to_vec(),
            fallback[signatures..signatures + method_ids.len() * 4].to_vec(),
        ),
    };
    let decl_hir_rows = match decl_hirs_read {
        None => table_rows(columns[15], &candidate_decls, 1),
        Some(start) => fallback[start..start + candidate_decls.len()].to_vec(),
    };
    let decl_hirs = candidate_decls
        .iter()
        .copied()
        .zip(decl_hir_rows)
        .collect::<BTreeMap<_, _>>();
    let candidate_hirs = in_table_rows(decl_hirs.values().copied(), public_decl_by_hir);
    let impl_ids: Vec<_> = method_cores.chunks_exact(4).map(|row| row[2]).collect();
    // An impl owns its methods' scope, so its core is in the owner metadata.
    let impl_cores = match impl_ids
        .iter()
        .map(|implementation| {
            parameter_owners
                .binary_search(implementation)
                .ok()
                .map(|owner| &owner_metadata[owner * owner_words..][..4])
        })
        .collect::<Option<Vec<_>>>()
    {
        Some(cores) => cores.concat(),
        None => rows(&readback, device, queue, inputs.buffer("compact_hir_core"), &impl_ids, 4)?,
    };
    let token_capacity = generic_counts_by_token.byte_size / 4;
    // Implementation owners are unnamed. Their payload.b stores a dense
    // trait-bound HIR row, so only the core's source anchor keys owner counts.
    let impl_tokens = impl_cores
        .chunks_exact(4)
        .map(|core| {
            ensure!(core[0] == HIR_NODE_IMPL && (core[2] as usize) < token_capacity,
                "retained method implementation has no source owner anchor");
            Ok(core[2])
        })
        .collect::<Result<Vec<_>>>()?;
    let mut batch = WordBatch::default();
    let impl_count_start = batch.rows(generic_counts_by_token, &impl_tokens, 1, 1, "impl counts")?;
    let impl_constant_start =
        batch.rows(constant_counts_by_token, &impl_tokens, 1, 1, "impl constant counts")?;
    let public_start =
        batch.rows(public_decl_by_hir, &candidate_hirs, 1, 1, "public declarations")?;
    let level = batch.read(&readback, device, queue, "generic call rows")?;
    let hir_symbols = candidate_hirs
        .iter()
        .copied()
        .zip(level[public_start..].iter().copied())
        .collect::<BTreeMap<_, _>>();
    let methods: BTreeMap<_, _> = method_ids
        .iter()
        .enumerate()
        .map(|(index, &row)| {
            (row, (
                method_cores[index * 4],
                method_signatures[index * 4 + 3],
                level[impl_count_start + index],
                level[impl_constant_start + index],
            ))
        })
        .collect();
    /// What a local call target needs: its type and constant parameter
    /// counts and, when it is generic, its native and specialization symbols.
    #[derive(Clone, Copy)]
    struct LocalCallee {
        types: u32,
        constants: u32,
        method: bool,
        native_symbol: u32,
        specialization_symbol: u32,
    }
    let mut callees = (0..local_count)
        .map(|index| LocalCallee {
            types: local_type_counts[index],
            constants: local_constant_counts[index],
            method: false,
            native_symbol: INVALID,
            specialization_symbol: INVALID,
        })
        .collect::<Vec<_>>();
    for (index, callee) in callees.iter_mut().enumerate() {
        if let Some(&(hir, metadata, count, constants)) = methods.get(&method_rows[index]) {
            let types = callee.types + count;
            let constants = callee.constants + constants;
            if types != 0 || constants != 0 {
                *callee = LocalCallee {
                    types,
                    constants,
                    method: true,
                    native_symbol: if metadata & 0xffff == 1 {
                        0x8000_0000 | hir
                    } else {
                        0x4000_0000 | local_tokens[index]
                    },
                    specialization_symbol: 0x8000_0000 | hir,
                };
            }
        }
    }
    // Only free functions use the public declaration table. Private method
    // identities are still their existing function-start-token symbols.
    let free_functions = (0..local_count)
        .filter(|&index| {
            let callee = callees[index];
            (callee.types != 0 || callee.constants != 0) && !callee.method
        })
        .collect::<Vec<_>>();
    ensure!(
        free_functions.len() == generic_functions.len()
            && free_functions
                .iter()
                .all(|&index| generic_functions.binary_search(&local_tokens[index]).is_ok()),
        "local generic functions differ from their count-only prediction"
    );
    let local_decls = free_functions
        .iter()
        .map(|&index| {
            let name = local_names[index];
            name_decls.get(&name).copied().ok_or_else(|| {
                anyhow!("local generic call name {name} exceeds its declaration table")
            })
        })
        .collect::<Result<Vec<_>>>()?;
    ensure!(
        local_decls.iter().all(|&decl| decl != INVALID),
        "local generic call has no declaration identity"
    );
    let local_hirs = local_decls
        .iter()
        .map(|decl| {
            decl_hirs
                .get(decl)
                .copied()
                .ok_or_else(|| anyhow!("local generic call declaration {decl} exceeds its HIR table"))
        })
        .collect::<Result<Vec<_>>>()?;
    ensure!(
        local_hirs.iter().all(|&hir| hir != INVALID),
        "local generic call has no declaration HIR"
    );
    for (&index, hir) in free_functions.iter().zip(&local_hirs) {
        let symbol = hir_symbols.get(hir).copied().ok_or_else(|| {
            anyhow!("local generic call HIR {hir} exceeds its public declaration table")
        })?;
        let token = local_tokens[index];
        callees[index].native_symbol = if symbol == INVALID {
            0x4000_0000 | token
        } else {
            symbol
        };
        callees[index].specialization_symbol = 0x4000_0000 | token;
    }
    timer.stamp("local_lookups");
    // Calls by their index in `call_ids`; `None` is not a generic call.
    let mut calls = Vec::with_capacity(call_ids.len());
    for ((&call_hir, &(_, source_span)), record) in call_ids
        .iter()
        .zip(&call_spans)
        .zip(call_records.chunks_exact(CALL_RECORD_READ_WORDS))
    {
        let (target, required_constant_parameters) = match record[11] {
            1 => {
                let function_start_token = record[0];
                let callee = callees[local_tokens
                    .binary_search(&function_start_token)
                    .expect("local callee token was read")];
                if callee.types == 0 && callee.constants == 0 {
                    ensure!(
                        calls_with_claims.binary_search(&call_hir).is_err(),
                        "local callable {function_start_token} at call {call_hir} has generic claims but no generic parameter metadata"
                    );
                    calls.push(None);
                    continue;
                }
                assert!(
                    callee.native_symbol != INVALID && callee.specialization_symbol != INVALID,
                    "generic local callee {function_start_token} has no symbol"
                );
                (
                    CheckedGenericTarget::Local {
                        function_start_token,
                        generic_parameter_count: callee.types,
                        native_symbol: callee.native_symbol,
                        specialization_symbol: callee.specialization_symbol,
                    },
                    Some(callee.constants),
                )
            }
            3 if record[4] == INVALID && record[3] & 0x8000_0000 != 0 => (
                CheckedGenericTarget::DependencyMethod {
                    library_id: record[1],
                    unit_id: record[2],
                    method_symbol: record[3],
                },
                None,
            ),
            3 if record[4] == INVALID => (
                CheckedGenericTarget::Dependency {
                    library_id: record[1],
                    unit_id: record[2],
                    declaration_index: record[3],
                },
                None,
            ),
            _ => {
                calls.push(None);
                continue;
            }
        };
        let required_generic_parameters = match target {
            CheckedGenericTarget::Local {
                generic_parameter_count,
                ..
            } => Some(generic_parameter_count),
            CheckedGenericTarget::Dependency { .. }
            | CheckedGenericTarget::DependencyMethod { .. } => None,
        };
        calls.push(Some(CheckedGenericCall {
            call_hir,
            source_span,
            target,
            arguments: Vec::new(),
            constants: Vec::new(),
            required_constant_parameters,
            required_generic_parameters,
        }));
    }
    timer.stamp("targets");
    let call_index = |call: u32| call_ids.binary_search(&call).ok();
    // The final GPU validator selects the exact argument row, including
    // precedence between typed and array-count evidence. Host retention copies
    // that selection; it does not solve count equations or compare recipes.
    let mut constant_bindings = Vec::new();
    // Selected slots of each retained call; other calls' keys in the set.
    let mut selected_slots = vec![0u32; call_ids.len()];
    let mut other_selected_keys = BTreeSet::new();
    for row in 0..constant_claim_count {
        let selected = columns[selected_constant_column][row];
        ensure!(selected <= 1, "invalid GPU constant selection marker");
        if selected == 0 { continue; }
        ensure!(columns[7][row] != INVALID && columns[8][row] < 32 &&
            columns[10][row] != INVALID && matches!(columns[9][row], 1 | 2 | 3),
            "selected constant claim has no checked reference");
        let argument = columns[11][row] as usize;
        ensure!(
            argument < argument_count,
            "constant claim points outside its argument rows"
        );
        let (call, slot) = (columns[5][argument], columns[8][row]);
        let fresh = match call_index(call) {
            Some(index) => {
                let fresh = selected_slots[index] & (1 << slot) == 0;
                selected_slots[index] |= 1 << slot;
                fresh
            }
            None => other_selected_keys.insert((call, slot)),
        };
        ensure!(fresh, "GPU selected more than one constant claim for the same call slot");
        constant_bindings.push((call, slot, columns[9][row], columns[10][row]));
    }
    // Context rows are read through their highest published slot.
    let mask_words = |mask: u32| 32 - mask.leading_zeros() as usize;
    let constant_context = (0..call_ids.len())
        .filter(|&index| constant_context_masks[index] != 0 && calls[index].is_some())
        .collect::<Vec<_>>();
    if !constant_context.is_empty() {
        let mut batch = WordBatch::default();
        let mut starts = Vec::with_capacity(constant_context.len() * 2);
        for name in ["call_context_constant_kind", "call_context_constant_payload"] {
            let buffer = inputs.buffer(name);
            for &index in &constant_context {
                starts.push(batch.push(
                    buffer,
                    u64::from(call_ids[index]) * 32,
                    mask_words(constant_context_masks[index]),
                    "checked result constant row",
                )?);
            }
        }
        let rows = batch.read(&readback, device, queue, "checked result constants")?;
        let (kind_starts, payload_starts) = starts.split_at(constant_context.len());
        for ((&index, &kinds), &payloads) in
            constant_context.iter().zip(kind_starts).zip(payload_starts)
        {
            let mask = constant_context_masks[index];
            for slot in 0..mask_words(mask) {
                if mask & (1u32 << slot) == 0 || selected_slots[index] & (1u32 << slot) != 0 {
                    continue;
                }
                let kind = rows[kinds + slot];
                let payload = rows[payloads + slot];
                ensure!(
                    matches!(kind, 1 | 2 | 3) && payload != INVALID,
                    "published result constant has no checked reference"
                );
                constant_bindings.push((call_ids[index], slot as u32, kind, payload));
            }
        }
    }
    let retained = |calls: &[Option<CheckedGenericCall>], call: u32| {
        call_index(call).filter(|&index| calls[index].is_some())
    };
    types.prefetch_constants(&readback, device, queue, inputs,
        &constant_bindings.iter().filter(|&&(call, ..)| retained(&calls, call).is_some())
            .map(|&(_, _, kind, payload)| (kind, payload)).collect::<Vec<_>>())?;
    for (call_id, slot, kind, payload) in constant_bindings {
        let Some(index) = retained(&calls, call_id) else {
            continue;
        };
        let call = calls[index].as_mut().expect("retained call");
        let value = types.constant(kind, payload);
        ensure!(!call.constants.iter().any(|arg| arg.slot == slot),
            "duplicate GPU-selected constant binding");
        call.constants.push(CheckedGenericConstant { slot, value });
    }
    for call in calls.iter_mut().flatten() {
        call.constants.sort_by_key(|arg| arg.slot);
    }
    timer.stamp("constants");
    let claim_call = |claim: usize| {
        let argument = columns[4][claim] as usize;
        (argument < argument_count).then(|| columns[5][argument])
    };
    let claim_roots = (0..claim_count).filter(|&claim|
        columns[0][claim] != INVALID && columns[1][claim] != INVALID &&
        claim_call(claim).is_some_and(|call| retained(&calls, call).is_some()))
        .map(|claim| (columns[2][claim], columns[3][claim])).collect::<Vec<_>>();
    types.prefetch_types(&readback, device, queue, inputs, &claim_roots)?;
    for claim in 0..claim_count {
        if columns[0][claim] == INVALID || columns[1][claim] == INVALID {
            continue;
        }
        let Some(call_hir) = claim_call(claim) else {
            return Err(anyhow!("generic claim points outside its argument rows"));
        };
        let Some(index) = retained(&calls, call_hir) else {
            continue;
        };
        let call = calls[index].as_mut().expect("retained call");
        let slot = columns[1][claim];
        // The GPU has already compared every repeated claim structurally.
        // Separate annotations can name the same type through different local
        // instance rows. Keep the first complete accepted reference rather
        // than comparing those source-local row identities on the host.
        if call
            .arguments
            .iter()
            .any(|arg| arg.slot == slot && arg.ty.is_native_ready())
        {
            continue;
        }
        let tag = columns[2][claim];
        let payload = columns[3][claim];
        let ty = if let Some(ty) = types.get(&(tag, payload)) {
            ty.clone()
        } else {
            read_type(&readback, device, queue, inputs, tag, payload, &mut types)?
        };
        // Repeated arguments are checked by the GPU before this reader runs.
        // Retain one fact per slot without merging separate call identities.
        if let Some(prior) = call.arguments.iter_mut().find(|arg| arg.slot == slot) {
            if ty.retention_rank() > prior.ty.retention_rank() {
                prior.ty = ty;
            }
        } else {
            call.arguments.push(CheckedGenericArgument { slot, ty });
        }
    }
    for call in calls.iter_mut().flatten() {
        call.arguments.sort_by_key(|arg| arg.slot);
    }
    timer.stamp("claim_types");
    let context = (0..call_ids.len())
        .filter(|&index| context_masks[index] != 0 && calls[index].is_some())
        .collect::<Vec<_>>();
    if !context.is_empty() {
        let mut batch = WordBatch::default();
        let mut starts = Vec::with_capacity(context.len() * 2);
        for name in ["call_context_ref_tag", "call_context_ref_payload"] {
            let buffer = inputs.buffer(name);
            for &index in &context {
                starts.push(batch.push(
                    buffer,
                    u64::from(call_ids[index]) * 32,
                    mask_words(context_masks[index]),
                    "checked contextual argument row",
                )?);
            }
        }
        let rows = batch.read(&readback, device, queue, "checked contextual arguments")?;
        let (tag_starts, payload_starts) = starts.split_at(context.len());
        for ((&index, &tags), &payloads) in context.iter().zip(tag_starts).zip(payload_starts) {
            let mask = context_masks[index];
            let call = calls[index].as_mut().expect("retained contextual call");
            for slot in 0..mask_words(mask) {
                if mask & (1u32 << slot) == 0
                    || call
                        .arguments
                        .iter()
                        .any(|arg| arg.slot == slot as u32 && arg.ty.is_native_ready())
                {
                    continue;
                }
                let tag = rows[tags + slot];
                let payload = rows[payloads + slot];
                let ty = read_type(&readback, device, queue, inputs, tag, payload, &mut types)?;
                let argument = CheckedGenericArgument { slot: slot as u32, ty };
                if let Some(prior) = call.arguments.iter_mut().find(|arg| arg.slot == slot as u32) {
                    if argument.ty.retention_rank() > prior.ty.retention_rank() {
                        *prior = argument;
                    }
                } else {
                    call.arguments.push(argument);
                }
            }
            call.arguments.sort_by_key(|arg| arg.slot);
        }
    }
    timer.stamp("calls");
    let native_call_owners: Vec<_> = call_ids
        .iter()
        .zip(callers)
        .map(|(&call_hir, &function)| {
            // Zero is the checked producer's explicit absence of a lexical function
            // (for example a constant initializer), never a nearby generic owner.
            CheckedCallOwner {
                call_hir,
                function_hir: function.wrapping_sub(1),
            }
        })
        .collect();
    // A function's calls are adjacent in HIR order; check each owner once.
    let mut accepted_owner = INVALID;
    for call in &native_call_owners {
        if call.function_hir == INVALID || call.function_hir == accepted_owner {
            continue;
        }
        ensure!(
            types
                .owners
                .get(&call.function_hir)
                .is_some_and(|owner| owner.callable.is_some()),
            "retained call {} has no accepted executable owner {}",
            call.call_hir,
            call.function_hir
        );
        accepted_owner = call.function_hir;
    }
    let call_owners = native_call_owners
        .iter()
        .zip(&calls)
        .filter(|(_, call)| call.is_some())
        .map(|(owner, _)| *owner)
        .collect();
    timer.stamp("owners");
    Ok(CheckedUnitFacts {
        generic_calls: calls.into_iter().flatten().collect(),
        contracts,
        call_owners,
        native_call_owners,
    })
}

impl super::GpuTypeChecker {
    pub(crate) fn retained_unit_facts(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        interface_exported: bool,
        template_contracts: Option<&CheckedUnitContracts>,
    ) -> Result<CheckedUnitFacts> {
        let semantic = self
            .semantic_artifact()
            .ok_or_else(|| anyhow!("checked semantic artifact is unavailable"))?;
        read_unit_facts(
            device,
            queue,
            &self.semantic_interface_buffers,
            &semantic,
            interface_exported,
            template_contracts,
        )
    }
}

/// Batch sparse receiver rows and argument columns; repeated calls do not
/// add one GPU synchronization per receiver or parameter.
#[allow(clippy::too_many_arguments)]
/// Normalize a local declaration through the authoritative exported-owner map.
/// The token remains a private replay anchor even when the semantic ID is public.
fn read_nominal_identity(
    token: u32,
    types: &CheckedTypeReadback,
) -> Result<CheckedNominalIdentity> {
    types
        .nominals
        .get(&token)
        .copied()
        .ok_or_else(|| anyhow!("retained nominal token {token} has no validated declaration owner"))
}

pub(super) fn read_type(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    tag: u32,
    payload: u32,
    types: &mut CheckedTypeReadback,
) -> Result<CheckedGenericType> {
    read_type_at_depth(readback, device, queue, inputs, tag, payload, 0, types)
}

fn read_type_at_depth(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    tag: u32,
    payload: u32,
    depth: usize,
    types: &mut CheckedTypeReadback,
) -> Result<CheckedGenericType> {
    ensure!(
        depth < MAX_RETAINED_TYPE_DEPTH,
        "retained semantic type graph exceeds {MAX_RETAINED_TYPE_DEPTH} levels"
    );
    if let Some(ty) = types.get(&(tag, payload)) {
        return Ok(ty.clone());
    }
    if !types.visiting.insert((tag, payload)) {
        return Ok(CheckedGenericType::Unresolved {
            reference_tag: tag,
            instance_kind: 0,
        });
    }
    let result =
        read_uncached_type_at_depth(readback, device, queue, inputs, tag, payload, depth, types);
    types.visiting.remove(&(tag, payload));
    let ty = result?;
    if ty.has_semantic_identity() {
        types.insert((tag, payload), ty.clone());
    }
    Ok(ty)
}

#[allow(clippy::too_many_arguments)]
fn read_uncached_type_at_depth(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    tag: u32,
    payload: u32,
    depth: usize,
    types: &mut CheckedTypeReadback,
) -> Result<CheckedGenericType> {
    if tag == 2 && payload != INVALID {
        let Some(&parameter) = types
            .parameters
            .get(&payload)
            .filter(|parameter| parameter.identity.domain == CheckedParameterDomain::Type)
        else {
            return Ok(CheckedGenericType::Unresolved {
                reference_tag: tag,
                instance_kind: 0,
            });
        };
        let &(resolved_tag, resolved_payload) =
            types.parameter_references.get(&payload).ok_or_else(|| {
                anyhow!("retained type parameter {payload} has no checked substitution row")
            })?;
        if matches!(resolved_tag, 1 | 3) {
            return read_type_at_depth(
                readback,
                device,
                queue,
                inputs,
                resolved_tag,
                resolved_payload,
                depth + 1,
                types,
            );
        }
        return Ok(CheckedGenericType::Parameter(parameter));
    }
    if tag == 1 && crate::primitive_types::is_known(payload) {
        return Ok(CheckedGenericType::Scalar(payload));
    }
    if tag == 1 && payload >= 4096 {
        // Bare records and enums both retain a GPU-checked nominal identity
        // and layout. Read both possible legacy rows; never derive a native
        // width or resolve an ambiguous code on the host.
        let candidates = CheckedTypeReadback::legacy_nominal_candidates(inputs, payload);
        let identities = if candidates
            .iter()
            .all(|row| types.legacy_nominal_rows.contains_key(row))
        {
            candidates
                .iter()
                .map(|row| types.legacy_nominal_rows[row].0)
                .collect()
        } else {
            rows(
                readback,
                device,
                queue,
                inputs.buffer("type_native_scalar_identity"),
                &candidates,
                1,
            )?
        };
        let matching = candidates
            .iter()
            .zip(&identities)
            .filter_map(|(&row, &identity)| (identity == payload).then_some(row))
            .collect::<Vec<_>>();
        if matching.len() == 1 {
            let width = if let Some(&(_, width)) = types.legacy_nominal_rows.get(&matching[0]) {
                width
            } else {
                rows(
                    readback,
                    device,
                    queue,
                    inputs.buffer("type_native_word_count"),
                    &matching,
                    1,
                )?[0]
            };
            return Ok(CheckedGenericType::Nominal {
                identity: read_nominal_identity(matching[0], types)?,
                arguments: Vec::new(),
                words: (width != INVALID).then_some(width),
                local_replay: Some(0x4000_0000 | payload),
            });
        }
    }
    if tag != 3 || payload == INVALID {
        return Ok(CheckedGenericType::Unresolved {
            reference_tag: tag,
            instance_kind: 0,
        });
    }
    types.read_type_rows(readback, device, queue, inputs, &[payload], &[])?;
    let values = types.instance_headers[&payload];
    if matches!(values[0], 2 | 3 | 4) {
        let element = Box::new(read_type_at_depth(
            readback,
            device,
            queue,
            inputs,
            values[2],
            values[3],
            depth + 1,
            types,
        )?);
        if values[0] == 4 && (values[7] == 1 || values[7] == INVALID) {
            return Ok(CheckedGenericType::Reference(element));
        }
        if values[0] == 3 && (values[7] == 3 || values[7] == INVALID) {
            return Ok(CheckedGenericType::Slice(element));
        }
        if values[0] == 2 {
            types.prefetch_constants(readback, device, queue, inputs, &[(values[8], values[9])])?;
            return Ok(CheckedGenericType::Array {
                element,
                length: types.constant(values[8], values[9]),
                words: (values[7] != INVALID).then_some(values[7]),
            });
        }
    }
    if values[0] == 1 {
        let identity = if values[4..7].iter().all(|&v| v != INVALID) {
            if values[6] & 0xe000_0000 == 0x2000_0000 {
                CheckedNominalIdentity::SourceLocal {
                    unit: [values[4], values[5]],
                    declaration_token: values[6] & 0x1fff_ffff,
                }
            } else {
                CheckedNominalIdentity::Public([values[4], values[5], values[6]])
            }
        } else if values[10] != INVALID {
            read_nominal_identity(values[10], types)?
        } else {
            return Ok(CheckedGenericType::Unresolved {
                reference_tag: tag,
                instance_kind: values[0],
            });
        };
        let local_replay = match identity {
            CheckedNominalIdentity::SourceLocal {
                declaration_token, ..
            } => Some(0x2000_0000 | declaration_token),
            _ => (values[10] != INVALID).then_some(0x2000_0000 | values[10]),
        };
        let native_words = (values[7] != INVALID).then_some(values[7]);
        if values[1] == 0 {
            return Ok(CheckedGenericType::Nominal {
                identity,
                arguments: Vec::new(),
                words: native_words,
                local_replay,
            });
        }
        types.read_argument_rows(readback, device, queue, inputs, &[payload], false)?;
        let Some(argument_rows) = types.instance_arguments[&payload].clone() else {
            return Ok(CheckedGenericType::Unresolved {
                reference_tag: tag,
                instance_kind: values[0],
            });
        };
        types.prefetch_constants(readback, device, queue, inputs,
            &argument_rows.iter().filter(|(tag, _)| matches!(*tag, 0x8000_0001 | 0x8000_0002 | 0x8000_0003))
                .map(|&(tag, payload)| (tag & 0x7fff_ffff, payload)).collect::<Vec<_>>())?;
        let mut arguments = Vec::with_capacity(argument_rows.len());
        for (child_tag, child_payload) in argument_rows {
            arguments.push(match child_tag {
                0x8000_0001 | 0x8000_0002 | 0x8000_0003 => CheckedGenericApplicationArgument::Constant(
                    types.constant(child_tag & 0x7fff_ffff, child_payload),
                ),
                _ => CheckedGenericApplicationArgument::Type(read_type_at_depth(
                    readback,
                    device,
                    queue,
                    inputs,
                    child_tag,
                    child_payload,
                    depth + 1,
                    types,
                )?),
            });
        }
        let ty = CheckedGenericType::Nominal {
            identity,
            arguments,
            words: native_words,
            local_replay,
        };
        if ty.has_semantic_identity() {
            types.insert((tag, payload), ty.clone());
        }
        return Ok(ty);
    }
    Ok(CheckedGenericType::Unresolved {
        reference_tag: tag,
        instance_kind: values[0],
    })
}

/// Bind retained identities to the immutable source unit that owns their tokens.
/// This operation does not make private tokens portable across source snapshots.
pub(crate) fn scope_generic_type_identities(
    calls: &mut [CheckedGenericCall],
    library: u32,
    unit: u32,
) {
    let unit = [library, unit];
    for call in calls {
        for value in &mut call.arguments {
            value.ty.scope(unit);
        }
        for value in &mut call.constants {
            value.value.scope(unit);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parameter(domain: CheckedParameterDomain, source_ordinal: u32) -> CheckedGenericParameter {
        CheckedGenericParameter {
            identity: CheckedParameterIdentity {
                unit: [INVALID, INVALID],
                binder: CheckedBinderIdentity::SourceLocal {
                    owner_kind: 3,
                    declaration_start_token: 41,
                },
                domain,
                source_ordinal,
            },
            binding_slot: 0,
            constant_scalar: (domain == CheckedParameterDomain::Constant).then_some(crate::primitive_types::SCALAR_U32),
        }
    }

    fn call(ty: CheckedGenericType, value: CheckedGenericConstantValue) -> CheckedGenericCall {
        CheckedGenericCall {
            call_hir: 7,
            source_span: [0, 1],
            target: CheckedGenericTarget::Local {
                function_start_token: 11,
                generic_parameter_count: 1,
                native_symbol: 0x4000_000b,
                specialization_symbol: 0x4000_000b,
            },
            arguments: vec![CheckedGenericArgument { slot: 0, ty }],
            constants: vec![CheckedGenericConstant { slot: 0, value }],
            required_generic_parameters: Some(1),
            required_constant_parameters: Some(1),
        }
    }

    #[test]
    fn symbolic_graph_scoping_preserves_every_parameter_domain_and_owner() {
        let ty = parameter(CheckedParameterDomain::Type, 0);
        let length = parameter(CheckedParameterDomain::Constant, 1);
        let mut foreign = ty;
        foreign.identity.unit = [8, 9];
        let graph = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::SourceLocal {
                unit: [INVALID, INVALID],
                declaration_token: 3,
            },
            arguments: vec![
                CheckedGenericApplicationArgument::Type(CheckedGenericType::Reference(Box::new(
                    CheckedGenericType::Slice(Box::new(CheckedGenericType::Array {
                        element: Box::new(CheckedGenericType::Parameter(ty)),
                        length: CheckedGenericConstantValue::Parameter(length),
                        words: None,
                    })),
                ))),
                CheckedGenericApplicationArgument::Constant(
                    CheckedGenericConstantValue::Parameter(length),
                ),
                CheckedGenericApplicationArgument::Type(CheckedGenericType::Parameter(foreign)),
            ],
            words: None,
            local_replay: Some(0x2000_0003),
        };
        let mut calls = vec![call(graph, CheckedGenericConstantValue::Parameter(length))];
        scope_generic_type_identities(&mut calls, 7, 4);
        let call = &calls[0];
        assert!(call.has_all_parameter_slots());
        assert!(!call.has_closed_arguments());
        assert!(!call.has_complete_arguments());
        assert!(call.arguments[0].ty.has_semantic_identity());
        let CheckedGenericType::Nominal {
            identity,
            arguments,
            words,
            ..
        } = &call.arguments[0].ty
        else {
            panic!("nominal graph")
        };
        assert_eq!(
            *identity,
            CheckedNominalIdentity::SourceLocal {
                unit: [7, 4],
                declaration_token: 3
            }
        );
        assert_eq!(*words, None);
        let mut scoped_length = length;
        scoped_length.identity.unit = [7, 4];
        assert_eq!(
            call.constants[0].value,
            CheckedGenericConstantValue::Parameter(scoped_length)
        );
        assert_eq!(arguments[1], CheckedGenericApplicationArgument::Constant(call.constants[0].value.clone()));
        assert_eq!(
            arguments[2],
            CheckedGenericApplicationArgument::Type(CheckedGenericType::Parameter(foreign)),
            "an already owned foreign parameter must not be rebound to the reader"
        );
        let CheckedGenericApplicationArgument::Type(CheckedGenericType::Reference(reference)) =
            &arguments[0]
        else {
            panic!("reference graph")
        };
        let CheckedGenericType::Slice(slice) = reference.as_ref() else {
            panic!("slice graph")
        };
        let CheckedGenericType::Array {
            element,
            length: array_length,
            ..
        } = slice.as_ref()
        else {
            panic!("array graph")
        };
        let CheckedGenericType::Parameter(element) = element.as_ref() else {
            panic!("parameter graph")
        };
        assert_eq!(element.identity.unit, [7, 4]);
        assert_eq!(element.identity.binder, scoped_length.identity.binder);
        assert_ne!(
            element.identity, scoped_length.identity,
            "type and constant domain/ordinal distinguish the same binding slot"
        );
        assert_eq!(element.binding_slot, scoped_length.binding_slot);
        assert_eq!(*array_length, call.constants[0].value);
        let mut other_owner = *element;
        other_owner.identity.binder = CheckedBinderIdentity::SourceLocal {
            owner_kind: 3,
            declaration_start_token: 99,
        };
        assert_ne!(element.identity, other_owner.identity);
    }

    #[test]
    fn semantic_closure_is_independent_of_native_layout_and_claim_preference() {
        let shape = |element, length, words| CheckedGenericType::Array {
            element: Box::new(element),
            length,
            words,
        };
        let symbolic = shape(
            CheckedGenericType::Parameter(parameter(CheckedParameterDomain::Type, 0)),
            CheckedGenericConstantValue::Parameter(parameter(CheckedParameterDomain::Constant, 1)),
            None,
        );
        let closed = shape(
            CheckedGenericType::Scalar(3),
            CheckedGenericConstantValue::count_literal(2),
            None,
        );
        let native = shape(
            CheckedGenericType::Scalar(3),
            CheckedGenericConstantValue::count_literal(2),
            Some(2),
        );
        let unresolved = CheckedGenericType::Unresolved {
            reference_tag: 3,
            instance_kind: 2,
        };
        assert!(symbolic.has_semantic_identity());
        assert!(!symbolic.is_closed());
        assert!(closed.is_closed());
        assert!(!closed.is_native_ready());
        assert!(native.is_native_ready());
        assert!(native.retention_rank() > closed.retention_rank());
        assert!(closed.retention_rank() > symbolic.retention_rank());
        assert!(symbolic.retention_rank() > unresolved.retention_rank());
        let call = call(closed, CheckedGenericConstantValue::count_literal(2));
        assert!(call.has_closed_arguments());
        assert!(!call.has_complete_arguments());
    }

    #[test]
    fn constant_readback_preserves_binders_until_the_gpu_publishes_a_value() {
        let constant = parameter(CheckedParameterDomain::Constant, 1);
        let mut reader = CheckedTypeReadback::default();
        reader.parameters.insert(23, constant);
        reader.constants.insert(23, INVALID);
        assert_eq!(
            reader.constant(2, 23),
            CheckedGenericConstantValue::Parameter(constant)
        );
        reader.constants.insert(23, 0);
        reader.retain_constant_atom(0, &[crate::primitive_types::SCALAR_U32, 0, 0, 0]).unwrap();
        assert_eq!(
            reader.constant(2, 23),
            CheckedGenericConstantValue::count_literal(0)
        );
        assert!(matches!(
            reader.constant(2, 24),
            CheckedGenericConstantValue::Unresolved { .. }
        ));
        reader
            .parameters
            .insert(24, parameter(CheckedParameterDomain::Type, 0));
        assert!(
            matches!(
                reader.constant(2, 24),
                CheckedGenericConstantValue::Unresolved { .. }
            ),
            "a type parameter is never a constant parameter just because its slot matches"
        );
    }
    #[test]
    fn nominal_header_cache_preserves_export_identity_and_rejects_broken_ownership() {
        let headers = [(3, 7, 13, 6), (4, 11, 17, 7), (5, 12, 19, 8)];
        let metadata = vec![
            vec![3],
            vec![27, INVALID, 10, 20],
            vec![6, 13, 0, 0],
            vec![9],
            vec![4],
            vec![26, INVALID, 21, 30],
            vec![7, 17, 0, 0],
            vec![INVALID],
            vec![5],
            vec![29, INVALID, 31, 40],
            vec![8, 19, 0, 0],
            vec![12],
        ];
        let mut reader = CheckedTypeReadback::default();
        reader.read_nominal_metadata(&headers, &metadata.concat()).unwrap();
        assert_eq!(
            read_nominal_identity(13, &reader).unwrap(),
            CheckedNominalIdentity::Public([INVALID, INVALID, 9]),
            "export index is not the source declaration index or token"
        );
        assert_eq!(
            read_nominal_identity(17, &reader).unwrap(),
            CheckedNominalIdentity::SourceLocal {
                unit: [INVALID, INVALID],
                declaration_token: 17
            }
        );
        assert_eq!(
            read_nominal_identity(19, &reader).unwrap(),
            CheckedNominalIdentity::Public([INVALID, INVALID, 12]),
            "canonical alias HIR rows retain their exported declaration identity"
        );
        assert!(
            read_nominal_identity(99, &reader).is_err(),
            "an absent declaration cannot manufacture a private identity"
        );
        for (column, word, corrupt) in [(0, 0, INVALID), (0, 0, 4), (1, 0, 26), (2, 1, 17)] {
            let mut invalid = metadata[..4].to_vec();
            invalid[column][word] = corrupt;
            assert!(
                CheckedTypeReadback::default()
                    .read_nominal_metadata(&headers[..1], &invalid.concat())
                    .is_err(),
                "reverse owner, HIR kind, and declaration name must agree: {invalid:?}"
            );
        }
    }

    #[test]
    fn retained_constant_atoms_preserve_typed_full_width_identity() {
        use crate::primitive_types::*;
        let mut reader = CheckedTypeReadback::default();
        let values = [
            [SCALAR_U64, u32::MAX, u32::MAX, 0],
            [SCALAR_U64, u32::MAX, 0, 0],
            [SCALAR_I64, u32::MAX, 0, 0],
            [SCALAR_F64, 0, 0, 0],
            [SCALAR_F64, 0, 0x8000_0000, 0],
            [SCALAR_F64, 7, 0x7ff8_0000, 0],
            [SCALAR_F64, 8, 0x7ff8_0000, 0],
        ];
        for (row, words) in values.iter().enumerate() {
            reader.retain_constant_atom(row as u32, words).unwrap();
            assert_eq!(reader.constant(1, row as u32).literal().unwrap().words(), words[..3]);
        }
        for left in 0..values.len() {
            for right in left + 1..values.len() {
                assert_ne!(reader.constant(1, left as u32), reader.constant(1, right as u32));
            }
        }
        reader.retain_constant_atom(99, &values[0]).unwrap();
        assert_eq!(reader.constant(1, 0), reader.constant(1, 99),
            "storage row is not constant identity");
        for words in [[SCALAR_U64, 0, 0, 1], [SCALAR_U32, 0, 1, 0], [SCALAR_BOOL, 2, 0, 0]] {
            assert!(reader.retain_constant_atom(100, &words).is_err());
        }
        let mut declared = parameter(CheckedParameterDomain::Constant, 1);
        declared.constant_scalar = Some(SCALAR_I64);
        reader.parameters.insert(17, declared);
        reader.constants.insert(17, 1);
        assert!(!reader.constant(2, 17).is_bound(), "published atom must match declared scalar");
        reader.constants.insert(17, 2);
        assert_eq!(reader.constant(2, 17), reader.constant(1, 2));
    }

    #[test]
    fn retained_count_projections_preserve_scopes_and_pending_gpu_fit() {
        use crate::primitive_types::*;
        let mut reader = CheckedTypeReadback::default();
        let mut declared = parameter(CheckedParameterDomain::Constant, 1);
        declared.constant_scalar = Some(SCALAR_U64);
        reader.parameters.insert(23, declared);
        reader.constants.insert(23, INVALID);
        reader.retain_constant_projection(0, &[SCALAR_U32, 2, 23, 0]).unwrap();
        reader.retain_constant_projection(1, &[SCALAR_U64, 3, 0, 0]).unwrap();
        let mut value = reader.constant(3, 1);
        assert!(value.is_bound());
        assert!(value.literal().is_none());
        value.scope([7, 9]);
        declared.scope([7, 9]);
        assert_eq!(value, CheckedGenericConstantValue::CountProjection {
            target_scalar: SCALAR_U64,
            source: Box::new(CheckedGenericConstantValue::CountProjection {
                target_scalar: SCALAR_U32,
                source: Box::new(CheckedGenericConstantValue::Parameter(declared)),
            }),
        });
        reader.retain_constant_atom(7, &[SCALAR_U64, 3, 0, 0]).unwrap();
        reader.constants.insert(23, 7);
        assert!(reader.constant(3, 1).literal().is_none(),
            "retention must not evaluate a now-concrete fit obligation on the host");
        reader.retain_constant_projection(2, &[SCALAR_U32, 3, 2, 0]).unwrap();
        assert!(!reader.constant(3, 2).is_bound(), "cycles fail closed");
        for row in 10..10 + MAX_RETAINED_TYPE_DEPTH as u32 {
            reader.retain_constant_projection(row, &[SCALAR_U32, 3, row + 1, 0]).unwrap();
        }
        assert!(!reader.constant(3, 10).is_bound(), "depth is bounded");
        for words in [[SCALAR_F32, 2, 23, 0], [SCALAR_U32, 0, 23, 0],
            [SCALAR_U32, 3, INVALID, 0], [SCALAR_U32, 2, 23, 1]] {
            assert!(reader.retain_constant_projection(99, &words).is_err());
        }
    }

    #[test]
    fn retained_constant_scalar_is_contract_metadata_not_binder_identity() {
        use crate::primitive_types::*;
        let mut left = parameter(CheckedParameterDomain::Constant, 3);
        let mut right = left;
        left.constant_scalar = Some(SCALAR_U64);
        right.constant_scalar = Some(SCALAR_I64);
        assert_eq!(left.identity, right.identity);
        assert_ne!(left, right);
        assert!(CheckedGenericConstantValue::Parameter(left).is_bound());
        left.constant_scalar = None;
        assert!(!CheckedGenericConstantValue::Parameter(left).is_bound());
        left.constant_scalar = Some(SCALAR_U64);
        left.identity.domain = CheckedParameterDomain::Type;
        assert!(!CheckedGenericConstantValue::Parameter(left).is_bound());
    }

    #[test]
    fn retained_parameter_metadata_requires_the_same_declared_scalar_on_replay() {
        use crate::primitive_types::*;
        let parameters = [7, 10, 1, INVALID, 7, 11, 2, 15];
        let mut metadata = vec![
            vec![3, INVALID, 41, 80], vec![0, 2], vec![9], vec![INVALID],
            vec![0], vec![INVALID], vec![INVALID], vec![0], vec![2], vec![10],
            vec![INVALID], vec![0], vec![INVALID], vec![SCALAR_U64], vec![0], vec![INVALID],
        ];
        let original = CheckedTypeReadback::from_parameter_metadata(
            &parameters, &[7], &metadata.concat(), true, None).unwrap();
        assert_eq!(original.parameters[&10].constant_scalar, None);
        assert_eq!(original.parameters[&11].constant_scalar, Some(SCALAR_U64));
        let contracts = CheckedUnitContracts {
            binders: original.owners.values().cloned().collect(), ..CheckedUnitContracts::default()
        };
        metadata.remove(3); // Replay inherits the immutable template's public scope.
        assert!(CheckedTypeReadback::from_parameter_metadata(
            &parameters, &[7], &metadata.concat(), false, Some(&contracts)).is_ok());
        metadata[12][0] = SCALAR_I64;
        assert!(CheckedTypeReadback::from_parameter_metadata(
            &parameters, &[7], &metadata.concat(), false, Some(&contracts)).is_err(),
            "same binder and slot cannot silently change scalar");
        metadata[12][0] = SCALAR_UNIT;
        assert!(CheckedTypeReadback::from_parameter_metadata(
            &parameters, &[7], &metadata.concat(), false, Some(&contracts)).is_err());
    }

}
