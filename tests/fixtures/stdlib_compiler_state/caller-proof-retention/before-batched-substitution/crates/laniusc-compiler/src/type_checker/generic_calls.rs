//! Owned generic call facts for compiled source units.
//!
//! The GPU checker owns inference. This reader copies its accepted relations
//! before workspace reuse and decodes their scalar/descriptor identities. It
//! neither infers types on the host nor emits a specialized function body.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Result, anyhow, ensure};

use super::{OwnedGpuSemanticArtifact, compiler_graph};
use crate::{
    compiler::{
        GpuSemanticInterfaceArtifact,
        GpuSemanticInterfaceMemberKind,
        GpuSemanticInterfaceTypeKind,
    },
    gpu::{
        buffers::{LaniusBuffer, TrackedBufferView},
        compiler_graph::{CompilerGraph, CompilerGraphBuilder, ResourceClass},
        readback::{PagedReadback, ReadbackRegion},
    },
};

const INVALID: u32 = u32::MAX;
const CALL_WORDS: usize = 14;
const MAX_RETAINED_TYPE_DEPTH: usize = 256;

/// These inputs cross the checker/backend boundary only for source-unit jobs
/// requesting an interface. Fresh non-interface graphs do not add this
/// retention; cached interface-capable workspaces may keep that capacity.
/// Ordinary executable compilation does not read these tables back.
pub(super) const RETAINED_INPUTS: &[&str] = &[
    "retained_callable_count",
    "retained_callable_hir",
    "call_generic_claim_count_out",
    "call_const_claim_callee",
    "call_const_claim_slot",
    "call_const_claim_count_out",
    "call_const_claim_ref_kind",
    "call_const_claim_ref_payload",
    "call_const_claim_arg_row",
    "type_decl_const_param_count_by_owner_token",
    "type_const_param_value_by_token",
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
    "interface_public_decl_index_by_hir",
    "type_decl_generic_param_count",
    "type_decl_generic_param_count_by_owner_token",
    "method_decl_method_row",
    "compact_method_cores",
    "compact_method_signatures",
    "compact_hir_payload",
    "compact_hir_core",
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
];

/// These facts are produced by the separate interface-export graph. The
/// binding name used by this reader is deliberately paired with the actual
/// owner resource; it is not a checker allocation or a checker-side alias.
const RETAINED_INTERFACE_INPUTS: &[(&str, &str)] = &[(
    "interface_generic_scope_owner_by_hir",
    "semantic_interface.members.scope_owner_by_hir",
)];

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
}

impl RetainedGenericCallInputs {
    pub(super) fn new(
        graph: &compiler_graph::TypeCheckCompilerGraph,
        hir: &crate::parser::buffers::GpuHirView,
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
        Ok(Self { buffers })
    }

    pub(super) fn retained_buffers(&self) -> impl Iterator<Item = TrackedBufferView<'_>> {
        self.buffers.values().map(Into::into)
    }

    fn buffer(&self, name: &str) -> &LaniusBuffer<u32> {
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

    fn scope(&mut self, source_unit: [u32; 2]) {
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
}

impl CheckedGenericParameter {
    fn scope(&mut self, unit: [u32; 2]) {
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

    fn owned_edge_bytes(&self) -> usize {
        match self {
            Self::Slice(element) | Self::Reference(element) | Self::Array { element, .. } => {
                std::mem::size_of::<Self>().saturating_add(element.owned_edge_bytes())
            }
            Self::Nominal { arguments, .. } => arguments
                .capacity()
                .saturating_mul(std::mem::size_of::<CheckedGenericApplicationArgument>())
                .saturating_add(
                    arguments
                        .iter()
                        .map(|argument| match argument {
                            CheckedGenericApplicationArgument::Type(ty) => ty.owned_edge_bytes(),
                            CheckedGenericApplicationArgument::Constant(_) => 0,
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CheckedGenericConstantValue {
    Literal(u32),
    Parameter(CheckedGenericParameter),
    /// Missing declaration ownership stays an explicit failed reference.
    Unresolved {
        kind: u32,
        payload: u32,
    },
}

impl CheckedGenericConstantValue {
    pub(crate) fn literal(self) -> Option<u32> {
        match self {
            Self::Literal(value) if value != INVALID => Some(value),
            _ => None,
        }
    }

    fn is_bound(self) -> bool {
        match self {
            Self::Literal(value) => value != INVALID,
            Self::Parameter(value) => value.binding_slot != INVALID,
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
            value: CheckedGenericConstantValue::Literal(value),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedGenericCall {
    /// Dense call identity belongs to this compiled unit's retained source.
    /// Different calls to one declaration always have different environments.
    pub call_hir: u32,
    pub target: CheckedGenericTarget,
    pub arguments: Vec<CheckedGenericArgument>,
    pub constants: Vec<CheckedGenericConstant>,
    pub required_constant_parameters: Option<u32>,
    /// Checked receiver instance arguments in their declaration order. They
    /// are copied before scratch reuse, then mapped to method parameter slots
    /// using the persisted receiver signature.
    pub receiver_arguments: Vec<CheckedGenericApplicationArgument>,
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
                self.receiver_arguments
                    .capacity()
                    .saturating_mul(std::mem::size_of::<CheckedGenericApplicationArgument>()),
            )
            .saturating_add(
                self.arguments
                    .iter()
                    .map(|arg| arg.ty.owned_edge_bytes())
                    .sum::<usize>(),
            )
            .saturating_add(
                self.receiver_arguments
                    .iter()
                    .map(|argument| match argument {
                        CheckedGenericApplicationArgument::Type(ty) => ty.owned_edge_bytes(),
                        CheckedGenericApplicationArgument::Constant(_) => 0,
                    })
                    .sum::<usize>(),
            )
    }
}

/// Add declaration-owned generic counts using the already persisted canonical
/// interfaces. Missing metadata remains incomplete. This does not inspect or
/// infer from argument expressions.
pub(crate) fn resolve_generic_requirements(
    calls: &mut Vec<CheckedGenericCall>,
    dependency_pages: &[Vec<GpuSemanticInterfaceArtifact>],
) {
    for call in calls.iter_mut() {
        let identity = match call.target {
            CheckedGenericTarget::Dependency {
                library_id,
                unit_id,
                ..
            }
            | CheckedGenericTarget::DependencyMethod {
                library_id,
                unit_id,
                ..
            } => Some((library_id, unit_id)),
            CheckedGenericTarget::Local { .. } => None,
        };
        if let Some((library_id, unit_id)) = identity {
            call.required_constant_parameters = dependency_pages
                .iter()
                .flatten()
                .find(|interface| {
                    interface.library_id == library_id && interface.unit_id == unit_id
                })
                .and_then(|interface| {
                    let owner = match call.target {
                        CheckedGenericTarget::Dependency {
                            declaration_index, ..
                        } => declaration_index,
                        CheckedGenericTarget::DependencyMethod { method_symbol, .. } => {
                            let method = interface.members.iter().find(|member| {
                                member.kind
                                    == GpuSemanticInterfaceMemberKind::AssociatedMethod as u32
                                    && member.value_hi == method_symbol
                            })?;
                            return Some(method.method_constant_parameter_count());
                        }
                        _ => unreachable!(),
                    };
                    let declaration = interface.declarations.get(owner as usize)?;
                    let start = declaration.first_member as usize;
                    let members = interface
                        .members
                        .get(start..start.checked_add(declaration.member_count as usize)?)?;
                    Some(
                        members
                            .iter()
                            .filter(|member| {
                                member.kind
                                    == GpuSemanticInterfaceMemberKind::GenericConstParameter as u32
                                    && member.value_hi == 0
                            })
                            .count() as u32,
                    )
                });
            call.required_generic_parameters = dependency_pages
                .iter()
                .flatten()
                .find(|interface| {
                    interface.library_id == library_id && interface.unit_id == unit_id
                })
                .and_then(|interface| match call.target {
                    CheckedGenericTarget::Dependency {
                        declaration_index, ..
                    } => {
                        let declaration = interface.declarations.get(declaration_index as usize)?;
                        let members = interface.members.get(
                            declaration.first_member as usize
                                ..(declaration.first_member as usize)
                                    .checked_add(declaration.member_count as usize)?,
                        )?;
                        Some(
                            members
                                .iter()
                                .filter(|member| {
                                    member.kind
                                        == GpuSemanticInterfaceMemberKind::GenericTypeParameter
                                            as u32
                                        && member.value_hi == 0
                                })
                                .count() as u32,
                        )
                    }
                    CheckedGenericTarget::DependencyMethod { method_symbol, .. } => {
                        let (count, receiver_slots) =
                            method_type_parameters(interface, method_symbol)?;
                        for (slot, ordinal) in receiver_slots {
                            let Some(CheckedGenericApplicationArgument::Type(ty)) =
                                call.receiver_arguments.get(ordinal as usize)
                            else {
                                continue;
                            };
                            if !call.arguments.iter().any(|argument| argument.slot == slot) {
                                // Imported method replay uses the portable identity.
                                call.arguments.push(CheckedGenericArgument {
                                    slot,
                                    ty: ty.clone(),
                                });
                            }
                        }
                        call.arguments.sort_by_key(|argument| argument.slot);
                        Some(count)
                    }
                    CheckedGenericTarget::Local { .. } => unreachable!(),
                });
        }
    }
    calls.retain(|call| {
        !call.arguments.is_empty()
            || !call.constants.is_empty()
            || call.required_generic_parameters != Some(0)
            || call.required_constant_parameters != Some(0)
    });
}

/// A concrete `impl Maybe<bool>` has no inherited T even though Maybe's
/// declaration owns T. Follow the exact method receiver/signature forest;
/// counting the owner's members would create a spurious required slot.
fn method_type_parameters(
    interface: &GpuSemanticInterfaceArtifact,
    method_symbol: u32,
) -> Option<(u32, Vec<(u32, u32)>)> {
    let method = interface.members.iter().find(|member| {
        member.kind == GpuSemanticInterfaceMemberKind::AssociatedMethod as u32
            && member.value_hi == method_symbol
    })?;
    let mut pending = vec![method.receiver_type_index, method.type_index];
    pending.extend(interface.members.iter().filter_map(|member| {
        (member.owner_ref == method.owner_ref
            && member.kind == GpuSemanticInterfaceMemberKind::Parameter as u32
            && member.value_hi == method_symbol)
            .then_some(member.type_index)
    }));
    let mut visited = BTreeSet::new();
    let mut slots = BTreeSet::new();
    while let Some(index) = pending.pop() {
        if !visited.insert(index) {
            continue;
        }
        let ty = interface.types.get(index as usize)?;
        if ty.kind == GpuSemanticInterfaceTypeKind::GenericParameter as u32 {
            slots.insert(canonical_generic_slot(
                interface,
                ty.payload_lo,
                method.owner_ref,
            )?);
        }
        let edges = interface.type_edges.get(
            ty.first_edge as usize..(ty.first_edge as usize).checked_add(ty.edge_count as usize)?,
        )?;
        pending.extend(edges.iter().map(|edge| edge.type_index));
    }
    let mut receiver_index = method.receiver_type_index;
    let mut receiver = interface.types.get(receiver_index as usize)?;
    while receiver.kind == GpuSemanticInterfaceTypeKind::Reference as u32 {
        if receiver.edge_count != 1 {
            return None;
        }
        receiver_index = interface
            .type_edges
            .get(receiver.first_edge as usize)?
            .type_index;
        receiver = interface.types.get(receiver_index as usize)?;
    }
    let mut receiver_slots = Vec::new();
    if receiver.kind == GpuSemanticInterfaceTypeKind::Declaration as u32 {
        for ordinal in 0..receiver.edge_count {
            let index = interface
                .type_edges
                .get((receiver.first_edge + ordinal) as usize)?
                .type_index;
            let argument = interface.types.get(index as usize)?;
            if argument.kind == GpuSemanticInterfaceTypeKind::GenericParameter as u32 {
                receiver_slots.push((
                    canonical_generic_slot(interface, argument.payload_lo, method.owner_ref)?,
                    ordinal,
                ));
            }
        }
    }
    // Nested structural patterns require an explicit checked substitution
    // relation. Direct generic receiver arguments need only this slot map.
    let count = method.method_type_parameter_count();
    (count <= 32 && slots.iter().all(|&slot| slot < count)).then_some((count, receiver_slots))
}

/// Canonical type records name a persisted generic member, not its local
/// substitution slot. Earlier declarations can place that member anywhere
/// in the unit's member table.
fn canonical_generic_slot(
    interface: &GpuSemanticInterfaceArtifact,
    member_index: u32,
    owner_ref: u32,
) -> Option<u32> {
    let member = interface.members.get(member_index as usize)?;
    (member.kind == GpuSemanticInterfaceMemberKind::GenericTypeParameter as u32
        && member.owner_ref == owner_ref)
        .then_some(member.type_binding_slot())
}

fn words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

fn rows<T>(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &LaniusBuffer<T>,
    indices: &[u32],
    stride_words: usize,
) -> Result<Vec<Vec<u32>>> {
    let regions = indices
        .iter()
        .map(|&index| {
            ReadbackRegion::from_buffer(
                buffer,
                u64::from(index) * stride_words as u64 * 4,
                stride_words * 4,
                "generic call rows",
            )
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(readback
        .read_regions(device, queue, &regions, "generic call rows")?
        .iter()
        .map(|bytes| words(bytes))
        .collect())
}

/// Source metadata is read once while the immutable caller snapshot is resident.
/// The GPU has already assigned declaration ownership, source ordinals, and
/// composed substitution slots; this reader only copies that correspondence.
#[derive(Default)]
struct CheckedTypeReadback {
    types: BTreeMap<(u32, u32), CheckedGenericType>,
    parameters: BTreeMap<u32, CheckedGenericParameter>,
    constants: BTreeMap<u32, u32>,
    nominals: BTreeMap<u32, CheckedNominalIdentity>,
    visiting: BTreeSet<(u32, u32)>,
}

impl CheckedTypeReadback {
    fn get(&self, key: &(u32, u32)) -> Option<&CheckedGenericType> {
        self.types.get(key)
    }
    fn insert(&mut self, key: (u32, u32), value: CheckedGenericType) {
        self.types.insert(key, value);
    }

    fn constant(&self, kind: u32, payload: u32) -> CheckedGenericConstantValue {
        if kind == 1 {
            return CheckedGenericConstantValue::Literal(payload);
        }
        if kind == 2 {
            if let Some(&value) = self
                .constants
                .get(&payload)
                .filter(|&&value| value != INVALID)
            {
                return CheckedGenericConstantValue::Literal(value);
            }
            if let Some(&parameter) = self
                .parameters
                .get(&payload)
                .filter(|parameter| parameter.identity.domain == CheckedParameterDomain::Constant)
            {
                return CheckedGenericConstantValue::Parameter(parameter);
            }
        }
        CheckedGenericConstantValue::Unresolved { kind, payload }
    }

    fn new(
        readback: &PagedReadback,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        semantic: &OwnedGpuSemanticArtifact,
        inputs: &RetainedGenericCallInputs,
        count: usize,
    ) -> Result<Self> {
        if count == 0 {
            return Ok(Self::default());
        }
        let raw = readback.read_regions(
            device,
            queue,
            &[ReadbackRegion::from_buffer(
                inputs.buffer("compact_generic_params"),
                0,
                count * 16,
                "retained generic parameters",
            )?],
            "retained generic declarations",
        )?;
        let parameters = words(&raw[0]);
        let owners = parameters
            .chunks_exact(4)
            .map(|row| row[0])
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        // These columns depend only on the compact rows above. Copy them in
        // one batch instead of introducing a fence for every metadata table.
        let mut regions = Vec::new();
        for &owner in &owners {
            for (name, width) in [
                ("compact_hir_core", 4),
                ("compact_generic_param_ranges", 2),
                ("interface_public_decl_index_by_hir", 1),
                ("interface_generic_scope_owner_by_hir", 1),
            ] {
                regions.push(ReadbackRegion::from_buffer(
                    inputs.buffer(name),
                    u64::from(owner) * width * 4,
                    width as usize * 4,
                    "retained generic owner metadata",
                )?);
            }
        }
        for row in parameters.chunks_exact(4) {
            for buffer in [
                &semantic.type_generic_param_slot,
                &semantic.type_const_param_slot,
                inputs.buffer("type_const_param_value_by_token"),
            ] {
                regions.push(ReadbackRegion::from_buffer(
                    buffer,
                    u64::from(row[1]) * 4,
                    4,
                    "retained generic parameter metadata",
                )?);
            }
        }
        let metadata = readback
            .read_regions(
                device,
                queue,
                &regions,
                "retained generic ownership and substitution",
            )?
            .iter()
            .map(|bytes| words(bytes))
            .collect::<Vec<_>>();
        let mut result = Self::default();
        for (ordinal, row) in parameters.chunks_exact(4).enumerate() {
            let owner = owners
                .binary_search(&row[0])
                .expect("retained parameter owner");
            let core = &metadata[owner * 4];
            let range = &metadata[owner * 4 + 1];
            let public = metadata[owner * 4 + 2][0];
            let scope_owner = metadata[owner * 4 + 3][0];
            let parameter_metadata = owners.len() * 4 + ordinal * 3;
            ensure!(
                range[0] != INVALID
                    && ordinal as u32 >= range[0]
                    && (ordinal as u32) - range[0] < range[1],
                "generic parameter has no declaration-owned source ordinal"
            );
            let (domain, binding_slot) = match row[2] {
                1 => (
                    CheckedParameterDomain::Type,
                    metadata[parameter_metadata][0],
                ),
                2 => (
                    CheckedParameterDomain::Constant,
                    metadata[parameter_metadata + 1][0],
                ),
                _ => continue,
            };
            // Invalid producer metadata cannot create an accepted-looking leaf.
            if binding_slot == INVALID {
                continue;
            }
            let binder = if public != INVALID {
                CheckedBinderIdentity::Public {
                    owner: public,
                    scope: 0,
                }
            } else if scope_owner != INVALID {
                CheckedBinderIdentity::Public {
                    owner: scope_owner,
                    scope: if core[0] == 3 {
                        0x8000_0000
                    } else {
                        0xc000_0000
                    } | row[0],
                }
            } else {
                CheckedBinderIdentity::SourceLocal {
                    owner_kind: core[0],
                    declaration_start_token: core[2],
                }
            };
            let parameter = CheckedGenericParameter {
                identity: CheckedParameterIdentity {
                    unit: [INVALID, INVALID],
                    binder,
                    domain,
                    source_ordinal: ordinal as u32 - range[0],
                },
                binding_slot,
            };
            ensure!(
                result.parameters.insert(row[1], parameter).is_none(),
                "generic parameter declaration token is not unique"
            );
            if domain == CheckedParameterDomain::Constant {
                result
                    .constants
                    .insert(row[1], metadata[parameter_metadata + 2][0]);
            }
        }
        Ok(result)
    }
}

/// Decode accepted GPU facts while the calling compilation still owns the
/// resident pipeline lock. Returned rows contain no borrowed GPU buffers.
pub(super) fn read_generic_calls(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    semantic: &OwnedGpuSemanticArtifact,
) -> Result<Vec<CheckedGenericCall>> {
    let Some(inputs) = semantic.generic_call_inputs.as_ref() else {
        return Ok(Vec::new());
    };
    let readback = PagedReadback::new(device, "generic call snapshot", 64 * 1024);
    let counts = readback.read_regions(
        device,
        queue,
        &[
            ReadbackRegion::from_buffer(
                inputs.buffer("call_generic_claim_count_out"),
                0,
                4,
                "claim count",
            )?,
            ReadbackRegion::from_buffer(
                inputs.buffer("call_arg_row_count_out"),
                0,
                4,
                "argument count",
            )?,
            ReadbackRegion::from_buffer(
                inputs.buffer("retained_callable_count"),
                0,
                4,
                "callable count",
            )?,
            ReadbackRegion::from_buffer(
                inputs.buffer("call_const_claim_count_out"),
                0,
                4,
                "constant claim count",
            )?,
            ReadbackRegion::from_buffer(
                inputs.buffer("compact_generic_param_count"),
                0,
                4,
                "generic parameter count",
            )?,
        ],
        "generic call counts",
    )?;
    let claim_count = words(&counts[0])[0] as usize;
    let argument_count = words(&counts[1])[0] as usize;
    let callable_count = words(&counts[2])[0] as usize;
    let constant_claim_count = words(&counts[3])[0] as usize;
    let generic_parameter_count = words(&counts[4])[0] as usize;
    let column_names = [
        "call_generic_claim_callee",
        "call_generic_claim_slot",
        "call_generic_claim_ref_tag",
        "call_generic_claim_ref_payload",
        "call_generic_claim_arg_row",
    ];
    let mut regions = column_names
        .iter()
        .map(|name| {
            ReadbackRegion::from_buffer(inputs.buffer(name), 0, claim_count * 4, "claim column")
        })
        .collect::<Result<Vec<_>>>()?;
    regions.push(ReadbackRegion::from_buffer(
        inputs.buffer("call_arg_row_call_node"),
        0,
        argument_count * 4,
        "argument calls",
    )?);
    regions.push(ReadbackRegion::from_buffer(
        inputs.buffer("retained_callable_hir"),
        0,
        callable_count * 4,
        "callable rows",
    )?);
    for name in [
        "call_const_claim_callee",
        "call_const_claim_slot",
        "call_const_claim_ref_kind",
        "call_const_claim_ref_payload",
        "call_const_claim_arg_row",
    ] {
        regions.push(ReadbackRegion::from_buffer(
            inputs.buffer(name),
            0,
            constant_claim_count * 4,
            "constant claim column",
        )?);
    }
    let columns = readback
        .read_regions(device, queue, &regions, "generic call claims")?
        .iter()
        .map(|bytes| words(bytes))
        .collect::<Vec<_>>();
    let call_ids = columns[6]
        .iter()
        .copied()
        .filter(|&id| id != INVALID)
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    if call_ids.is_empty() {
        return Ok(Vec::new());
    }
    let calls_with_claims = (0..claim_count)
        .filter(|&claim| columns[0][claim] != INVALID && columns[1][claim] != INVALID)
        .filter_map(|claim| columns[5].get(columns[4][claim] as usize).copied())
        .collect::<BTreeSet<_>>();
    let call_records = rows(
        &readback,
        device,
        queue,
        &semantic.calls_by_hir,
        &call_ids,
        CALL_WORDS,
    )?;
    // Both result domains share one sparse mask readback. Masks own validity;
    // unpublished context payload cells need no initialization or readback.
    let mut context_masks = vec![0; call_ids.len()];
    let mut constant_context_masks = vec![0; call_ids.len()];
    if inputs.buffer("call_context_arg_mask").byte_size > 4 {
        let mut mask_regions = Vec::with_capacity(call_ids.len() * 2);
        for &call in &call_ids {
            for name in ["call_context_arg_mask", "call_context_constant_mask"] {
                mask_regions.push(ReadbackRegion::from_buffer(
                    inputs.buffer(name),
                    u64::from(call) * 4,
                    4,
                    "result context mask",
                )?);
            }
        }
        if !mask_regions.is_empty() {
            let masks =
                readback.read_regions(device, queue, &mask_regions, "result context masks")?;
            for (index, pair) in masks.chunks_exact(2).enumerate() {
                context_masks[index] = words(&pair[0])[0];
                constant_context_masks[index] = words(&pair[1])[0];
            }
        }
    }
    let local_tokens = call_records
        .iter()
        .filter(|record| record[11] == 1)
        .map(|record| record[0])
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let local_names = rows(
        &readback,
        device,
        queue,
        inputs.buffer("call_fn_index"),
        &local_tokens,
        1,
    )?
    .iter()
    .map(|row| row[0])
    .collect::<Vec<_>>();
    ensure!(
        local_names.iter().all(|&name| name != INVALID),
        "local generic call has no declaration-name token"
    );
    let local_counts = rows(
        &readback,
        device,
        queue,
        inputs.buffer("type_decl_generic_param_count_by_owner_token"),
        &local_names,
        1,
    )?;
    let local_constant_rows = rows(
        &readback,
        device,
        queue,
        inputs.buffer("type_decl_const_param_count_by_owner_token"),
        &local_names,
        1,
    )?;
    let mut local_constant_counts = local_tokens
        .iter()
        .copied()
        .zip(local_constant_rows.iter().map(|row| row[0]))
        .collect::<BTreeMap<_, _>>();
    let mut local_counts = local_tokens
        .iter()
        .copied()
        .zip(local_counts.iter().map(|row| row[0]))
        .collect::<BTreeMap<_, _>>();
    // Methods inherit the impl's parameters even when their own signature
    // declares none. Read declaration-owned metadata; receiver constraints
    // have already been solved by the GPU into the call context relation.
    let method_rows = rows(
        &readback,
        device,
        queue,
        inputs.buffer("method_decl_method_row"),
        &local_names,
        1,
    )?;
    let method_ids: Vec<_> = method_rows
        .iter()
        .filter_map(|row| (row[0] != INVALID).then_some(row[0]))
        .collect();
    let method_cores = rows(
        &readback,
        device,
        queue,
        inputs.buffer("compact_method_cores"),
        &method_ids,
        4,
    )?;
    let method_signatures = rows(
        &readback,
        device,
        queue,
        inputs.buffer("compact_method_signatures"),
        &method_ids,
        4,
    )?;
    let impl_ids: Vec<_> = method_cores.iter().map(|row| row[2]).collect();
    let impl_payloads = rows(
        &readback,
        device,
        queue,
        inputs.buffer("compact_hir_payload"),
        &impl_ids,
        4,
    )?;
    let impl_cores = rows(
        &readback,
        device,
        queue,
        inputs.buffer("compact_hir_core"),
        &impl_ids,
        4,
    )?;
    let token_capacity = inputs
        .buffer("type_decl_generic_param_count_by_owner_token")
        .byte_size
        / 4;
    let impl_tokens: Vec<_> = impl_payloads
        .iter()
        .zip(&impl_cores)
        .map(|(payload, core)| {
            if (payload[1] as usize) < token_capacity {
                payload[1]
            } else {
                core[2]
            }
        })
        .collect();
    let impl_counts = rows(
        &readback,
        device,
        queue,
        inputs.buffer("type_decl_generic_param_count_by_owner_token"),
        &impl_tokens,
        1,
    )?;
    let impl_constant_counts = rows(
        &readback,
        device,
        queue,
        inputs.buffer("type_decl_const_param_count_by_owner_token"),
        &impl_tokens,
        1,
    )?;
    let methods: BTreeMap<_, _> = method_ids
        .iter()
        .copied()
        .zip(
            method_cores
                .iter()
                .zip(&method_signatures)
                .zip(&impl_counts)
                .zip(&impl_constant_counts),
        )
        .map(|(row, (((core, signature), count), constants))| {
            (row, (core[0], signature[3], count[0], constants[0]))
        })
        .collect();
    let mut local_method_symbols = BTreeMap::new();
    let mut specialization_symbols = BTreeMap::new();
    for (&token, method) in local_tokens.iter().zip(&method_rows) {
        if let Some(&(hir, metadata, count, constants)) = methods.get(&method[0]) {
            let types = local_counts[&token] + count;
            let constants = local_constant_counts[&token] + constants;
            if types != 0 || constants != 0 {
                local_counts.insert(token, types);
                local_constant_counts.insert(token, constants);
                local_method_symbols.insert(
                    token,
                    if metadata & 0xffff == 1 {
                        0x8000_0000 | hir
                    } else {
                        0x4000_0000 | token
                    },
                );
                specialization_symbols.insert(token, 0x8000_0000 | hir);
            }
        }
    }
    // Only free functions use the public declaration table. Private method
    // identities are still their existing function-start-token symbols.
    let (local_tokens, local_names): (Vec<_>, Vec<_>) = local_tokens
        .into_iter()
        .zip(local_names)
        .filter(|(token, _)| {
            (local_counts[token] != 0 || local_constant_counts[token] != 0)
                && !local_method_symbols.contains_key(token)
        })
        .unzip();
    let local_decls = rows(
        &readback,
        device,
        queue,
        inputs.buffer("decl_id_by_name_token"),
        &local_names,
        1,
    )?
    .iter()
    .map(|row| row[0])
    .collect::<Vec<_>>();
    ensure!(
        local_decls.iter().all(|&decl| decl != INVALID),
        "local generic call has no declaration identity"
    );
    let local_hirs = rows(
        &readback,
        device,
        queue,
        inputs.buffer("decl_hir_node"),
        &local_decls,
        1,
    )?
    .iter()
    .map(|row| row[0])
    .collect::<Vec<_>>();
    ensure!(
        local_hirs.iter().all(|&hir| hir != INVALID),
        "local generic call has no declaration HIR"
    );
    let local_symbols = rows(
        &readback,
        device,
        queue,
        inputs.buffer("interface_public_decl_index_by_hir"),
        &local_hirs,
        1,
    )?;
    let mut local_symbols = local_tokens
        .iter()
        .copied()
        .zip(local_symbols.iter())
        .map(|(token, row)| {
            (
                token,
                if row[0] == INVALID {
                    0x4000_0000 | token
                } else {
                    row[0]
                },
            )
        })
        .collect::<BTreeMap<_, _>>();
    local_symbols.extend(local_method_symbols);
    for &token in &local_tokens {
        specialization_symbols.insert(token, 0x4000_0000 | token);
    }
    let receiver_ids = call_records
        .iter()
        .filter(|record| {
            record[11] == 3
                && record[4] == INVALID
                && record[3] & 0x8000_0000 != 0
                && record[7] != INVALID
        })
        .map(|record| record[7])
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let mut types = CheckedTypeReadback::new(
        &readback,
        device,
        queue,
        semantic,
        inputs,
        generic_parameter_count,
    )?;
    let receivers = read_receiver_arguments(
        &readback,
        device,
        queue,
        semantic,
        inputs,
        &receiver_ids,
        &mut types,
    )?;
    let mut calls = BTreeMap::new();
    for (&call_hir, record) in call_ids.iter().zip(call_records) {
        let target = match record[11] {
            1 => {
                let function_start_token = record[0];
                let generic_parameter_count = local_counts[&function_start_token];
                if generic_parameter_count == 0 && local_constant_counts[&function_start_token] == 0
                {
                    ensure!(
                        !calls_with_claims.contains(&call_hir),
                        "local callable {function_start_token} at call {call_hir} has generic claims but no generic parameter metadata"
                    );
                    continue;
                }
                CheckedGenericTarget::Local {
                    function_start_token,
                    generic_parameter_count,
                    native_symbol: local_symbols[&function_start_token],
                    specialization_symbol: specialization_symbols[&function_start_token],
                }
            }
            3 if record[4] == INVALID && record[3] & 0x8000_0000 != 0 => {
                CheckedGenericTarget::DependencyMethod {
                    library_id: record[1],
                    unit_id: record[2],
                    method_symbol: record[3],
                }
            }
            3 if record[4] == INVALID => CheckedGenericTarget::Dependency {
                library_id: record[1],
                unit_id: record[2],
                declaration_index: record[3],
            },
            _ => continue,
        };
        let required_generic_parameters = match target {
            CheckedGenericTarget::Local {
                generic_parameter_count,
                ..
            } => Some(generic_parameter_count),
            CheckedGenericTarget::Dependency { .. }
            | CheckedGenericTarget::DependencyMethod { .. } => None,
        };
        calls.insert(
            call_hir,
            CheckedGenericCall {
                call_hir,
                target,
                arguments: Vec::new(),
                constants: Vec::new(),
                required_constant_parameters: if matches!(
                    target,
                    CheckedGenericTarget::Local { .. }
                ) {
                    Some(local_constant_counts[&record[0]])
                } else {
                    None
                },
                receiver_arguments: receivers.get(&record[7]).cloned().unwrap_or_default(),
                required_generic_parameters,
            },
        );
    }
    // Argument and result rows are GPU-owned accepted facts. Copy both into
    // one relation before resolving each published caller parameter once.
    let mut constant_bindings = Vec::new();
    for row in 0..constant_claim_count {
        if columns[7][row] == INVALID
            || columns[8][row] >= 32
            || columns[10][row] == INVALID
            || !matches!(columns[9][row], 1 | 2)
        {
            continue;
        }
        let argument = columns[11][row] as usize;
        ensure!(
            argument < argument_count,
            "constant claim points outside its argument rows"
        );
        constant_bindings.push((
            columns[5][argument],
            columns[8][row],
            columns[9][row],
            columns[10][row],
        ));
    }
    let constant_context_ids = call_ids
        .iter()
        .zip(&constant_context_masks)
        .filter_map(|(&call, &mask)| (mask != 0 && calls.contains_key(&call)).then_some(call))
        .collect::<Vec<_>>();
    let mut constant_regions = Vec::with_capacity(constant_context_ids.len() * 2);
    for &call in &constant_context_ids {
        for name in [
            "call_context_constant_kind",
            "call_context_constant_payload",
        ] {
            constant_regions.push(ReadbackRegion::from_buffer(
                inputs.buffer(name),
                u64::from(call) * 32 * 4,
                32 * 4,
                "checked result constant row",
            )?);
        }
    }
    if !constant_regions.is_empty() {
        let buffers =
            readback.read_regions(device, queue, &constant_regions, "checked result constants")?;
        for (&call, pair) in constant_context_ids.iter().zip(buffers.chunks_exact(2)) {
            let mask =
                constant_context_masks[call_ids.binary_search(&call).expect("contextual call row")];
            let kinds = words(&pair[0]);
            let payloads = words(&pair[1]);
            for slot in 0..32u32 {
                if mask & (1u32 << slot) == 0 {
                    continue;
                }
                let kind = kinds[slot as usize];
                let payload = payloads[slot as usize];
                ensure!(
                    matches!(kind, 1 | 2) && payload != INVALID,
                    "published result constant has no checked reference"
                );
                constant_bindings.push((call, slot, kind, payload));
            }
        }
    }
    for (call_id, slot, kind, payload) in constant_bindings {
        let Some(call) = calls.get_mut(&call_id) else {
            continue;
        };
        let value = types.constant(kind, payload);
        if let Some(prior) = call.constants.iter().find(|arg| arg.slot == slot) {
            ensure!(
                prior.value == value,
                "retained argument/result constants disagree"
            );
        } else {
            call.constants.push(CheckedGenericConstant { slot, value });
        }
    }
    for call in calls.values_mut() {
        call.constants.sort_by_key(|arg| arg.slot);
    }
    for claim in 0..claim_count {
        if columns[0][claim] == INVALID || columns[1][claim] == INVALID {
            continue;
        }
        let argument = columns[4][claim] as usize;
        ensure!(
            argument < argument_count,
            "generic claim points outside its argument rows"
        );
        let Some(call) = calls.get_mut(&columns[5][argument]) else {
            continue;
        };
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
    for call in calls.values_mut() {
        call.arguments.sort_by_key(|arg| arg.slot);
    }
    let context_ids = call_ids
        .iter()
        .zip(&context_masks)
        .filter_map(|(&call, &mask)| (mask != 0 && calls.contains_key(&call)).then_some(call))
        .collect::<Vec<_>>();
    let mut context_regions = Vec::with_capacity(context_ids.len() * 2);
    for &call in &context_ids {
        for name in ["call_context_ref_tag", "call_context_ref_payload"] {
            context_regions.push(ReadbackRegion::from_buffer(
                inputs.buffer(name),
                u64::from(call) * 32 * 4,
                32 * 4,
                "checked contextual argument row",
            )?);
        }
    }
    if !context_regions.is_empty() {
        let buffers = readback.read_regions(
            device,
            queue,
            &context_regions,
            "checked contextual arguments",
        )?;
        for (&call_id, buffers) in context_ids.iter().zip(buffers.chunks_exact(2)) {
            let mask = context_masks[call_ids
                .binary_search(&call_id)
                .expect("contextual call row")];
            let tags = words(&buffers[0]);
            let payloads = words(&buffers[1]);
            let call = calls.get_mut(&call_id).expect("retained contextual call");
            for slot in 0..32u32 {
                if mask & (1u32 << slot) == 0
                    || call
                        .arguments
                        .iter()
                        .any(|arg| arg.slot == slot && arg.ty.is_native_ready())
                {
                    continue;
                }
                let tag = tags[slot as usize];
                let payload = payloads[slot as usize];
                let ty = read_type(&readback, device, queue, inputs, tag, payload, &mut types)?;
                let argument = CheckedGenericArgument { slot, ty };
                if let Some(prior) = call.arguments.iter_mut().find(|arg| arg.slot == slot) {
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
    Ok(calls.into_values().collect())
}

impl super::GpuTypeChecker {
    pub(crate) fn retained_generic_calls(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Vec<CheckedGenericCall>> {
        let semantic = self
            .semantic_artifact()
            .ok_or_else(|| anyhow!("checked semantic artifact is unavailable"))?;
        read_generic_calls(device, queue, &semantic)
    }
}

/// Batch sparse receiver rows and argument columns; repeated calls do not
/// add one GPU synchronization per receiver or parameter.
#[allow(clippy::too_many_arguments)]
fn read_receiver_arguments(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    semantic: &OwnedGpuSemanticArtifact,
    inputs: &RetainedGenericCallInputs,
    receiver_ids: &[u32],
    types: &mut CheckedTypeReadback,
) -> Result<BTreeMap<u32, Vec<CheckedGenericApplicationArgument>>> {
    let mut regions = Vec::new();
    for &hir in receiver_ids {
        regions.push(ReadbackRegion::from_buffer(
            &semantic.expr_ref_tag_by_hir,
            u64::from(hir) * 4,
            4,
            "receiver tag",
        )?);
        regions.push(ReadbackRegion::from_buffer(
            &semantic.expr_ref_payload_by_hir,
            u64::from(hir) * 4,
            4,
            "receiver type",
        )?);
    }
    let receiver_rows =
        readback.read_regions(device, queue, &regions, "checked generic receivers")?;
    let receiver_instances = receiver_ids
        .iter()
        .copied()
        .zip(receiver_rows.chunks_exact(2))
        .filter_map(|(hir, row)| {
            let tag = words(&row[0])[0];
            let instance = words(&row[1])[0];
            (tag == 3 && instance != INVALID).then_some((hir, instance))
        })
        .collect::<BTreeMap<_, _>>();
    let instance_ids = receiver_instances
        .values()
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let mut regions = Vec::new();
    for &instance in &instance_ids {
        regions.push(ReadbackRegion::from_buffer(
            &semantic.type_instance_arg_count,
            u64::from(instance) * 4,
            4,
            "receiver argument count",
        )?);
        regions.push(ReadbackRegion::from_buffer(
            &semantic.type_instance_arg_row_start,
            u64::from(instance) * 4,
            4,
            "receiver argument rows",
        )?);
        regions.push(ReadbackRegion::from_buffer(
            inputs.buffer("type_instance_arg_start"),
            u64::from(instance) * 4,
            4,
            "receiver fixed argument rows",
        )?);
    }
    let layout_rows =
        readback.read_regions(device, queue, &regions, "checked receiver argument layouts")?;
    let layouts = instance_ids
        .into_iter()
        .zip(layout_rows.chunks_exact(3))
        .map(|(instance, row)| {
            (
                instance,
                (
                    words(&row[0])[0] as usize,
                    words(&row[1])[0],
                    words(&row[2])[0],
                ),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let mut regions = Vec::new();
    let mut read_instances = Vec::new();
    let mut arguments_by_instance = BTreeMap::new();
    let source_capacity = inputs.buffer("type_expr_ref_tag").byte_size / 4;
    for (&instance, &(count, start, fixed_start)) in &layouts {
        ensure!(
            count <= semantic.type_instance_arg_row_ref_tag.byte_size / 4,
            "receiver argument count exceeds its checked relation"
        );
        if count == 0 {
            arguments_by_instance.insert(instance, Vec::new());
        } else if start == INVALID
            && (fixed_start == INVALID
                || count
                    > if instance as usize >= source_capacity {
                        super::generic_body::MAX_BODY_TYPE_ARGUMENTS
                    } else {
                        4
                    })
        {
            arguments_by_instance.insert(
                instance,
                vec![
                    CheckedGenericApplicationArgument::Type(CheckedGenericType::Unresolved {
                        reference_tag: 3,
                        instance_kind: 1,
                    });
                    count
                ],
            );
        } else {
            // Source factory results use four fallback slots. Generated
            // applications use the private 32-slot relation after the whole
            // workspace source capacity and the replay graph arena.
            let (tag_buffer, payload_buffer, argument_start) = if start == INVALID {
                (
                    inputs.buffer("type_instance_arg_ref_tag"),
                    inputs.buffer("type_instance_arg_ref_payload"),
                    fixed_start,
                )
            } else {
                (
                    &semantic.type_instance_arg_row_ref_tag,
                    &semantic.type_instance_arg_row_ref_payload,
                    start,
                )
            };
            regions.push(ReadbackRegion::from_buffer(
                tag_buffer,
                u64::from(argument_start) * 4,
                count * 4,
                "receiver argument tags",
            )?);
            regions.push(ReadbackRegion::from_buffer(
                payload_buffer,
                u64::from(argument_start) * 4,
                count * 4,
                "receiver argument types",
            )?);
            read_instances.push(instance);
        }
    }
    let argument_rows = readback.read_regions(
        device,
        queue,
        &regions,
        "checked receiver argument references",
    )?;
    for (instance, row) in read_instances
        .into_iter()
        .zip(argument_rows.chunks_exact(2))
    {
        let mut arguments = Vec::new();
        for (tag, payload) in words(&row[0]).into_iter().zip(words(&row[1])) {
            let constant = match tag {
                0x8000_0001 => Some(CheckedGenericConstantValue::Literal(payload)),
                0x8000_0002 => Some(types.constant(2, payload)),
                _ => None,
            };
            if let Some(value) = constant {
                arguments.push(CheckedGenericApplicationArgument::Constant(value));
                continue;
            }
            let ty = if let Some(ty) = types.get(&(tag, payload)) {
                ty.clone()
            } else {
                read_type(readback, device, queue, inputs, tag, payload, types)?
            };
            arguments.push(CheckedGenericApplicationArgument::Type(ty));
        }
        arguments_by_instance.insert(instance, arguments);
    }
    Ok(receiver_instances
        .into_iter()
        .map(|(hir, instance)| (hir, arguments_by_instance[&instance].clone()))
        .collect())
}

/// Normalize a local declaration through the authoritative exported-owner map.
/// The token remains a private replay anchor even when the semantic ID is public.
fn read_nominal_identity(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    token: u32,
    types: &mut CheckedTypeReadback,
) -> Result<CheckedNominalIdentity> {
    if let Some(&identity) = types.nominals.get(&token) {
        return Ok(identity);
    }
    let declaration = rows(
        readback,
        device,
        queue,
        inputs.buffer("decl_id_by_name_token"),
        &[token],
        1,
    )?[0][0];
    ensure!(
        declaration != INVALID,
        "retained nominal token {token} has no declaration owner"
    );
    let hir = rows(
        readback,
        device,
        queue,
        inputs.buffer("decl_hir_node"),
        &[declaration],
        1,
    )?[0][0];
    ensure!(
        hir != INVALID,
        "retained nominal declaration {declaration} has no HIR owner"
    );
    let metadata = readback.read_regions(
        device,
        queue,
        &[
            ReadbackRegion::from_buffer(
                inputs.buffer("compact_hir_core"),
                u64::from(hir) * 16,
                16,
                "nominal declaration kind",
            )?,
            ReadbackRegion::from_buffer(
                inputs.buffer("compact_hir_payload"),
                u64::from(hir) * 16,
                16,
                "nominal declaration token",
            )?,
            ReadbackRegion::from_buffer(
                inputs.buffer("interface_public_decl_index_by_hir"),
                u64::from(hir) * 4,
                4,
                "nominal export owner",
            )?,
        ],
        "retained nominal declaration ownership",
    )?;
    let core = words(&metadata[0]);
    let payload = words(&metadata[1]);
    ensure!(
        payload[1] == token && (matches!(core[0], 26 | 27) || (core[0] == 2 && payload[0] == 8)),
        "retained nominal token {token} does not name its record, enum, or alias declaration"
    );
    let public = words(&metadata[2])[0];
    let identity = if public != INVALID {
        CheckedNominalIdentity::Public([INVALID, INVALID, public])
    } else {
        CheckedNominalIdentity::SourceLocal {
            unit: [INVALID, INVALID],
            declaration_token: token,
        }
    };
    types.nominals.insert(token, identity);
    Ok(identity)
}

fn read_type(
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
        let resolved = readback.read_regions(
            device,
            queue,
            &[
                ReadbackRegion::from_buffer(
                    inputs.buffer("type_expr_ref_tag"),
                    u64::from(payload) * 4,
                    4,
                    "parameter reference tag",
                )?,
                ReadbackRegion::from_buffer(
                    inputs.buffer("type_expr_ref_payload"),
                    u64::from(payload) * 4,
                    4,
                    "parameter reference payload",
                )?,
            ],
            "retained parameter substitution",
        )?;
        let resolved_tag = words(&resolved[0])[0];
        let resolved_payload = words(&resolved[1])[0];
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
    if tag == 1 && payload > 0 && payload < 128 {
        return Ok(CheckedGenericType::Scalar(payload));
    }
    if tag == 1 && payload >= 4096 {
        // Bare records and enums both retain a GPU-checked nominal identity
        // and layout. Read both possible legacy rows; never derive a native
        // width or resolve an ambiguous code on the host.
        let capacity = inputs.buffer("type_native_scalar_identity").byte_size as u32 / 4;
        let candidates = [4096, 6144]
            .into_iter()
            .filter_map(|base| payload.checked_sub(base).filter(|&row| row < capacity))
            .collect::<Vec<_>>();
        let identities = rows(
            readback,
            device,
            queue,
            inputs.buffer("type_native_scalar_identity"),
            &candidates,
            1,
        )?;
        let matching = candidates
            .iter()
            .zip(&identities)
            .filter_map(|(&row, identity)| (identity[0] == payload).then_some(row))
            .collect::<Vec<_>>();
        if matching.len() == 1 {
            let width = rows(
                readback,
                device,
                queue,
                inputs.buffer("type_native_word_count"),
                &matching,
                1,
            )?[0][0];
            return Ok(CheckedGenericType::Nominal {
                identity: read_nominal_identity(
                    readback,
                    device,
                    queue,
                    inputs,
                    matching[0],
                    types,
                )?,
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
    let names = [
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
    let regions = names
        .iter()
        .map(|name| {
            ReadbackRegion::from_buffer(
                inputs.buffer(name),
                u64::from(payload) * 4,
                4,
                "generic argument type",
            )
        })
        .collect::<Result<Vec<_>>>()?;
    let values = readback
        .read_regions(device, queue, &regions, "generic argument type")?
        .iter()
        .map(|bytes| words(bytes)[0])
        .collect::<Vec<_>>();
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
            read_nominal_identity(readback, device, queue, inputs, values[10], types)?
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
        let count = values[1] as usize;
        ensure!(
            count <= super::generic_body::MAX_BODY_TYPE_ARGUMENTS,
            "generic type exceeds {} checked arguments",
            super::generic_body::MAX_BODY_TYPE_ARGUMENTS
        );
        let total = rows(
            readback,
            device,
            queue,
            inputs.buffer("type_instance_arg_row_count_out"),
            &[0],
            1,
        )?[0][0];
        let row_start = values[12];
        let source_capacity = inputs.buffer("type_expr_ref_tag").byte_size / 4;
        let (tags, payloads, start) = if row_start < total && count as u32 <= total - row_start {
            (
                "type_instance_arg_row_ref_tag",
                "type_instance_arg_row_ref_payload",
                row_start,
            )
        } else if values[11] != INVALID && (payload as usize >= source_capacity || count <= 4) {
            (
                "type_instance_arg_ref_tag",
                "type_instance_arg_ref_payload",
                values[11],
            )
        } else {
            return Ok(CheckedGenericType::Unresolved {
                reference_tag: tag,
                instance_kind: values[0],
            });
        };
        let argument_rows = readback.read_regions(
            device,
            queue,
            &[
                ReadbackRegion::from_buffer(
                    inputs.buffer(tags),
                    u64::from(start) * 4,
                    count * 4,
                    "nominal argument tags",
                )?,
                ReadbackRegion::from_buffer(
                    inputs.buffer(payloads),
                    u64::from(start) * 4,
                    count * 4,
                    "nominal argument types",
                )?,
            ],
            "checked nominal arguments",
        )?;
        let mut arguments = Vec::with_capacity(count);
        for (child_tag, child_payload) in words(&argument_rows[0])
            .into_iter()
            .zip(words(&argument_rows[1]))
        {
            arguments.push(match child_tag {
                0x8000_0001 => CheckedGenericApplicationArgument::Constant(
                    CheckedGenericConstantValue::Literal(child_payload),
                ),
                0x8000_0002 => {
                    CheckedGenericApplicationArgument::Constant(types.constant(2, child_payload))
                }
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
    fn constant(value: &mut CheckedGenericConstantValue, unit: [u32; 2]) {
        if let CheckedGenericConstantValue::Parameter(parameter) = value {
            parameter.scope(unit);
        }
    }
    fn argument(value: &mut CheckedGenericApplicationArgument, unit: [u32; 2]) {
        match value {
            CheckedGenericApplicationArgument::Type(ty) => scope(ty, unit),
            CheckedGenericApplicationArgument::Constant(value) => constant(value, unit),
        }
    }
    fn scope(ty: &mut CheckedGenericType, unit: [u32; 2]) {
        match ty {
            CheckedGenericType::Parameter(parameter) => parameter.scope(unit),
            CheckedGenericType::Nominal {
                identity,
                arguments,
                ..
            } => {
                identity.scope(unit);
                for value in arguments {
                    argument(value, unit);
                }
            }
            CheckedGenericType::Array {
                element, length, ..
            } => {
                scope(element, unit);
                constant(length, unit);
            }
            CheckedGenericType::Slice(element) | CheckedGenericType::Reference(element) => {
                scope(element, unit)
            }
            _ => {}
        }
    }
    let unit = [library, unit];
    for call in calls {
        for value in &mut call.arguments {
            scope(&mut value.ty, unit);
        }
        for value in &mut call.constants {
            constant(&mut value.value, unit);
        }
        for value in &mut call.receiver_arguments {
            argument(value, unit);
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
        }
    }

    fn call(ty: CheckedGenericType, value: CheckedGenericConstantValue) -> CheckedGenericCall {
        CheckedGenericCall {
            call_hir: 7,
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
            receiver_arguments: vec![CheckedGenericApplicationArgument::Constant(value)],
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
        assert_eq!(
            call.receiver_arguments[0],
            CheckedGenericApplicationArgument::Constant(call.constants[0].value)
        );
        assert_eq!(arguments[1], call.receiver_arguments[0]);
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
            CheckedGenericConstantValue::Literal(2),
            None,
        );
        let native = shape(
            CheckedGenericType::Scalar(3),
            CheckedGenericConstantValue::Literal(2),
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
        let call = call(closed, CheckedGenericConstantValue::Literal(2));
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
        assert_eq!(
            reader.constant(2, 23),
            CheckedGenericConstantValue::Literal(0)
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
}
