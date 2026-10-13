//! Immutable checked contracts retained beside a source unit's public interface.
//!
//! Source rows and HIR anchors belong to that exact retained unit. They are not
//! public declaration identifiers. This boundary copies accepted GPU facts; it
//! does not select implementations or discharge obligations on the host.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Result, anyhow, ensure};

use super::generic_calls::{
    CheckedBinderIdentity,
    CheckedGenericApplicationArgument,
    CheckedGenericCall,
    CheckedGenericParameter,
    CheckedGenericType,
    CheckedNominalIdentity,
    CheckedTypeReadback,
    RetainedGenericCallInputs,
    read_type,
    words,
};
use crate::gpu::readback::{PagedReadback, ReadbackRegion};

const INVALID: u32 = u32::MAX;
const TRAIT_KIND: u32 = 10;
const TYPE_HIR_KIND: u32 = 5;

#[derive(Clone, Debug, Default)]
pub(crate) struct CheckedUnitFacts {
    pub generic_calls: Vec<CheckedGenericCall>,
    pub contracts: CheckedUnitContracts,
    pub call_owners: Vec<CheckedCallOwner>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct CheckedUnitContracts {
    /// Scoping preserves the immutable source context; it does not grant a
    /// different snapshot authority merely because its unit numbers match.
    pub source_unit: Option<[u32; 2]>,
    /// One owner table, including nongeneric owners and enclosing scopes.
    /// Replay normalizes parameters against this definition-owned relation.
    pub binders: Vec<CheckedContractOwner>,
    pub predicates: Vec<CheckedPredicateContract>,
    pub implementations: Vec<CheckedImplementationContract>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedContractOwner {
    pub source_hir: u32,
    pub binder: CheckedBinderIdentity,
    /// Index into the same unit's owner table, independent of public identity.
    pub enclosing_owner: Option<u32>,
    pub parameters: Vec<CheckedGenericParameter>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedPredicateContract {
    pub source_row: u32,
    pub bound_hir: u32,
    /// Index into `CheckedUnitContracts::binders`.
    pub owner: u32,
    /// An alias from the actual public exporter, never a private surrogate.
    pub public_index: Option<u32>,
    pub trait_identity: CheckedNominalIdentity,
    pub subject: CheckedGenericType,
    pub arguments: Vec<CheckedGenericApplicationArgument>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedImplementationContract {
    pub source_row: u32,
    /// Index into `CheckedUnitContracts::binders`.
    pub owner: u32,
    pub public_index: Option<u32>,
    pub trait_identity: CheckedNominalIdentity,
    pub subject: CheckedGenericType,
    pub arguments: Vec<CheckedGenericApplicationArgument>,
    pub method_bindings: Vec<CheckedImplementationMethodBinding>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedImplementationMethodBinding {
    pub method_hir: u32,
    /// Scoped by the containing implementation's exact trait identity.
    pub required_symbol: u32,
    pub receiver_mode: u32,
    pub target: [u32; 3],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedCallOwner {
    pub call_hir: u32,
    pub function_hir: u32,
}

impl CheckedUnitContracts {
    pub(crate) fn scope_source_unit(&mut self, library: u32, unit: u32) {
        let source_unit = [library, unit];
        if let Some(previous) = self.source_unit {
            assert_eq!(
                previous, source_unit,
                "checked contracts cannot change source unit"
            );
        }
        self.source_unit = Some(source_unit);
        for binder in &mut self.binders {
            scope_owner(binder, source_unit);
        }
        for predicate in &mut self.predicates {
            predicate.trait_identity.scope(source_unit);
            predicate.subject.scope(source_unit);
            for argument in &mut predicate.arguments {
                argument.scope(source_unit);
            }
        }
        for implementation in &mut self.implementations {
            implementation.trait_identity.scope(source_unit);
            implementation.subject.scope(source_unit);
            for argument in &mut implementation.arguments {
                argument.scope(source_unit);
            }
            for binding in &mut implementation.method_bindings {
                if binding.target[..2] == [INVALID, INVALID] {
                    binding.target[..2].copy_from_slice(&source_unit);
                }
            }
        }
    }

    /// Owned vector/graph storage only. An Arc owner must separately account
    /// for this inner struct, in addition to its own Arc handle.
    pub(crate) fn resident_byte_len(&self) -> usize {
        let mut bytes = vector_bytes(&self.binders)
            .saturating_add(vector_bytes(&self.predicates))
            .saturating_add(vector_bytes(&self.implementations));
        for binder in &self.binders {
            bytes = bytes.saturating_add(vector_bytes(&binder.parameters));
        }
        for predicate in &self.predicates {
            bytes = bytes
                .saturating_add(predicate.subject.owned_edge_bytes())
                .saturating_add(argument_bytes(&predicate.arguments));
        }
        for implementation in &self.implementations {
            bytes = bytes
                .saturating_add(implementation.subject.owned_edge_bytes())
                .saturating_add(argument_bytes(&implementation.arguments))
                .saturating_add(vector_bytes(&implementation.method_bindings));
        }
        bytes
    }
}

fn scope_owner(owner: &mut CheckedContractOwner, unit: [u32; 2]) {
    for parameter in &mut owner.parameters {
        parameter.scope(unit);
    }
}

fn vector_bytes<T>(values: &Vec<T>) -> usize {
    values.capacity().saturating_mul(std::mem::size_of::<T>())
}

fn argument_bytes(arguments: &Vec<CheckedGenericApplicationArgument>) -> usize {
    arguments
        .iter()
        .fold(vector_bytes(arguments), |bytes, argument| {
            bytes.saturating_add(match argument {
                CheckedGenericApplicationArgument::Type(ty) => ty.owned_edge_bytes(),
                CheckedGenericApplicationArgument::Constant(_) => 0,
            })
        })
}

/// These are active compact rows already copied with the generic-call batch.
#[derive(Clone, Copy)]
pub(super) struct ContractSourceRows<'a> {
    pub predicates: &'a [u32],
    pub type_arguments: &'a [u32],
    pub methods: &'a [u32],
    pub method_signatures: &'a [u32],
    pub declaration_kinds: &'a [u32],
    pub declaration_tokens: &'a [u32],
}

fn scalar_regions<'a>(
    inputs: &'a RetainedGenericCallInputs,
    requests: &[(&str, u32)],
) -> Result<Vec<ReadbackRegion<'a>>> {
    requests
        .iter()
        .map(|&(name, row)| {
            ReadbackRegion::from_buffer(inputs.buffer(name), u64::from(row) * 4, 4, name)
        })
        .collect()
}

fn scalar_values(rows: &[Vec<u32>]) -> Result<Vec<u32>> {
    rows.iter()
        .map(|row| {
            ensure!(row.len() == 1, "checked contract scalar has invalid width");
            Ok(row[0])
        })
        .collect()
}

fn read_scalars(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    requests: &[(&str, u32)],
) -> Result<Vec<u32>> {
    if requests.is_empty() {
        return Ok(Vec::new());
    }
    let regions = scalar_regions(inputs, requests)?;
    readback
        .read_regions(device, queue, &regions, "checked contract facts")?
        .iter()
        .map(|bytes| {
            let row = words(bytes);
            ensure!(row.len() == 1, "checked contract scalar has invalid width");
            Ok(row[0])
        })
        .collect()
}

fn validate_source_rows(source: ContractSourceRows<'_>) -> Result<()> {
    ensure!(
        source.predicates.len() % 4 == 0,
        "checked predicate table has invalid width"
    );
    if source.predicates.is_empty() {
        return Ok(());
    }
    ensure!(
        source.type_arguments.len() % 5 == 0,
        "checked type argument table has invalid width"
    );
    ensure!(
        source.methods.len() % 4 == 0 && source.methods.len() == source.method_signatures.len(),
        "checked method tables have inconsistent widths"
    );
    ensure!(
        source.declaration_kinds.len() == source.declaration_tokens.len(),
        "checked declaration columns have inconsistent lengths"
    );
    Ok(())
}

fn fact_requests(predicates: &[u32]) -> Result<Vec<(&'static str, u32)>> {
    let mut requests = Vec::with_capacity(predicates.len() * 2);
    for (index, row) in predicates.chunks_exact(4).enumerate() {
        let kind = row[3] & 255;
        ensure!(
            matches!(kind, 1 | 2),
            "checked predicate {index} has unsupported kind {kind}"
        );
        let node = if kind == 1 { row[2] } else { row[0] };
        for name in [
            "predicate_status",
            "predicate_owner_node",
            "predicate_bound_reference",
            "predicate_bound_arg_count",
        ] {
            requests.push((name, node));
        }
        if kind == 1 {
            requests.push(("semantic_predicate_subject_parameter_token_by_hir", node));
            requests.push(("interface_predicate_flag", index as u32));
            requests.push(("interface_predicate_prefix", index as u32));
            requests.push(("predicate_subject_token", node));
        } else {
            requests.push(("predicate_method_contract_owner_count", node));
            requests.push(("interface_implementation_index_by_hir", node));
            requests.push(("predicate_method_validation_status", node));
            requests.push(("predicate_trait_impl_trait_type_node", node));
        }
    }
    Ok(requests)
}

fn range_requests(predicates: &[u32]) -> Result<Vec<(&'static str, u32)>> {
    let mut range_requests = Vec::with_capacity(predicates.len() / 2);
    for row in predicates.chunks_exact(4) {
        range_requests.push((
            "compact_type_arg_ranges",
            row[2]
                .checked_mul(2)
                .ok_or_else(|| anyhow!("contract type argument range offset overflows"))?,
        ));
        range_requests.push(("compact_type_arg_ranges", row[2] * 2 + 1));
    }
    Ok(range_requests)
}

/// Plan only sparse, active scalar rows. A caller may defer planning failures
/// and let `read_contracts` report them in its original validation order.
pub(super) fn metadata_regions<'a>(
    inputs: &'a RetainedGenericCallInputs,
    source: ContractSourceRows<'_>,
) -> Result<Vec<ReadbackRegion<'a>>> {
    validate_source_rows(source)?;
    let mut regions = scalar_regions(inputs, &fact_requests(source.predicates)?)?;
    regions.extend(scalar_regions(inputs, &range_requests(source.predicates)?)?);
    Ok(regions)
}

#[allow(clippy::too_many_arguments)]
pub(super) fn read_contracts(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    types: &mut CheckedTypeReadback,
    source: ContractSourceRows<'_>,
    metadata: Option<&[Vec<u32>]>,
) -> Result<CheckedUnitContracts> {
    validate_source_rows(source)?;
    if source.predicates.is_empty() {
        return Ok(CheckedUnitContracts::default());
    }

    // The usual path shares the generic-call metadata transfer. A planning
    // failure falls back here so earlier owner errors retain precedence.
    let requests = fact_requests(source.predicates)?;
    let facts = if let Some(metadata) = metadata {
        ensure!(
            metadata.len() == source.predicates.len() / 4 * 10,
            "checked contract metadata has invalid width"
        );
        scalar_values(&metadata[..requests.len()])?
    } else {
        read_scalars(readback, device, queue, inputs, &requests)?
    };
    let ranges_requests = range_requests(source.predicates)?;
    let ranges = if let Some(metadata) = metadata {
        scalar_values(&metadata[requests.len()..])?
    } else {
        read_scalars(readback, device, queue, inputs, &ranges_requests)?
    };
    let mut root_hirs = BTreeSet::new();
    let mut implementation_owners = BTreeSet::new();
    for (index, row) in source.predicates.chunks_exact(4).enumerate() {
        let fact = &facts[index * 8..index * 8 + 8];
        ensure!(
            fact[0] == 0 && fact[1] == row[0],
            "predicate {index} has no accepted owner contract"
        );
        ensure!(
            fact[2] != INVALID && fact[3] <= 32,
            "predicate {index} has invalid trait operands"
        );
        let first = ranges[index * 2] as usize;
        let count = ranges[index * 2 + 1] as usize;
        ensure!(
            count == fact[3] as usize
                && (count == 0
                    || (first <= source.type_arguments.len() / 5
                        && count <= source.type_arguments.len() / 5 - first)),
            "predicate {index} has an invalid ordered operand range"
        );
        if row[3] & 255 == 2 {
            ensure!(
                fact[6] == 0 || fact[6] == INVALID,
                "implementation {index} has a rejected method contract"
            );
            ensure!(
                fact[7] == row[2],
                "implementation {index} has a different checked trait root"
            );
            ensure!(
                implementation_owners.insert(row[0]),
                "implementation owner has duplicate source rows"
            );
            root_hirs.insert(row[1]);
        }
        for ordinal in 0..count {
            let argument = &source.type_arguments[(first + ordinal) * 5..(first + ordinal + 1) * 5];
            ensure!(
                argument[0] == row[2] && argument[2] == ordinal as u32,
                "predicate {index} has an operand with different ownership or order"
            );
            root_hirs.insert(argument[1]);
        }
    }

    let mut root_requests = Vec::with_capacity(root_hirs.len() * 3);
    for &hir in &root_hirs {
        root_requests.push((
            "compact_hir_core",
            hir.checked_mul(4)
                .ok_or_else(|| anyhow!("contract type HIR offset overflows"))?,
        ));
        root_requests.push(("semantic_type_ref_tag_by_hir", hir));
        root_requests.push(("semantic_type_ref_payload_by_hir", hir));
    }
    let root_rows = read_scalars(readback, device, queue, inputs, &root_requests)?;
    let references = root_rows
        .chunks_exact(3)
        .filter(|reference| reference[0] == TYPE_HIR_KIND)
        .map(|reference| (reference[1], reference[2]))
        .collect::<Vec<_>>();
    types.prefetch_types(readback, device, queue, inputs, &references)?;
    let mut roots = BTreeMap::new();
    for (&hir, reference) in root_hirs.iter().zip(root_rows.chunks_exact(3)) {
        ensure!(
            reference[0] == TYPE_HIR_KIND,
            "contract operand {hir} is not a checked type root"
        );
        let ty = read_type(
            readback,
            device,
            queue,
            inputs,
            reference[1],
            reference[2],
            types,
        )?;
        ensure!(
            ty.has_semantic_identity(),
            "contract type root {hir} has no complete semantic identity"
        );
        roots.insert(hir, ty);
    }

    let mut binding_requests = Vec::new();
    let mut method_rows = Vec::new();
    for (index, method) in source.methods.chunks_exact(4).enumerate() {
        if !implementation_owners.contains(&method[2]) {
            continue;
        }
        ensure!(
            method[1] == method[2],
            "implementation method has a different checked owner"
        );
        method_rows.push(index);
        for name in [
            "predicate_method_validation_status",
            "predicate_method_validation_required_symbol",
            "semantic_function_native_symbol_by_hir",
        ] {
            binding_requests.push((name, method[0]));
        }
    }
    let binding_facts = read_scalars(readback, device, queue, inputs, &binding_requests)?;
    let mut bindings = BTreeMap::<u32, Vec<CheckedImplementationMethodBinding>>::new();
    let mut required_symbols = BTreeSet::new();
    let mut method_hirs = BTreeSet::new();
    for (&index, binding) in method_rows.iter().zip(binding_facts.chunks_exact(3)) {
        let method = &source.methods[index * 4..index * 4 + 4];
        let signature = &source.method_signatures[index * 4..index * 4 + 4];
        ensure!(
            binding[0] == 0
                && binding[1] != INVALID
                && binding[1] & 0xc000_0000 == 0x8000_0000
                && matches!(binding[2] & 0xc000_0000, 0x4000_0000 | 0x8000_0000)
                && binding[2] != INVALID
                && signature[2] <= 3,
            "implementation method {} has no accepted complete binding",
            method[0]
        );
        ensure!(
            method_hirs.insert(method[0]) && required_symbols.insert((method[2], binding[1])),
            "implementation method binding is duplicated"
        );
        bindings
            .entry(method[2])
            .or_default()
            .push(CheckedImplementationMethodBinding {
                method_hir: method[0],
                required_symbol: binding[1],
                receiver_mode: signature[2],
                target: [INVALID, INVALID, binding[2]],
            });
    }

    let mut result = CheckedUnitContracts::default();
    let mut trait_identities = BTreeMap::new();
    for (index, row) in source.predicates.chunks_exact(4).enumerate() {
        let fact = &facts[index * 8..index * 8 + 8];
        let reference = fact[2];
        let trait_identity = if let Some(&identity) = trait_identities.get(&reference) {
            identity
        } else {
            let identity = if reference & 0x8000_0000 != 0 {
                let path = reference & 0x7fff_ffff;
                let identity = read_scalars(
                    readback,
                    device,
                    queue,
                    inputs,
                    &[
                        ("resolved_dependency_library_id", path),
                        ("resolved_dependency_unit_id", path),
                        ("resolved_dependency_local_index", path),
                        (
                            "resolved_dependency_trait_header",
                            path.checked_mul(4).ok_or_else(|| {
                                anyhow!("dependency trait header offset overflows")
                            })?,
                        ),
                    ],
                )?;
                ensure!(
                    identity[..3].iter().all(|&word| word != INVALID) && identity[3] == TRAIT_KIND,
                    "predicate {index} has no resolved dependency trait identity"
                );
                CheckedNominalIdentity::Public([identity[0], identity[1], identity[2]])
            } else {
                let declaration = reference as usize;
                ensure!(
                    source.declaration_kinds.get(declaration) == Some(&TRAIT_KIND),
                    "predicate {index} does not reference a checked trait declaration"
                );
                types.nominal_identity(source.declaration_tokens[declaration])?
            };
            trait_identities.insert(reference, identity);
            identity
        };
        let first = ranges[index * 2] as usize;
        let arguments = (0..fact[3] as usize)
            .map(|ordinal| {
                let hir = source.type_arguments[(first + ordinal) * 5 + 1];
                CheckedGenericApplicationArgument::Type(roots[&hir].clone())
            })
            .collect();
        let owner = types.owner_index(row[0])?;
        if row[3] & 255 == 1 {
            ensure!(
                fact[7] == row[1] && matches!(fact[5], 0 | 1),
                "predicate {index} has inconsistent subject or public alias metadata"
            );
            let parameter = types
                .parameter(fact[4])
                .ok_or_else(|| anyhow!("predicate {index} has no canonical subject parameter"))?;
            ensure!(
                parameter.identity.domain == super::generic_calls::CheckedParameterDomain::Type,
                "predicate {index} has a non-type subject parameter"
            );
            ensure!(
                fact[5] == 0 || fact[6] != INVALID,
                "predicate {index} has an invalid public row alias"
            );
            result.predicates.push(CheckedPredicateContract {
                source_row: index as u32,
                bound_hir: row[2],
                owner,
                public_index: (fact[5] == 1).then_some(fact[6]),
                trait_identity,
                subject: CheckedGenericType::Parameter(parameter),
                arguments,
            });
        } else {
            let method_bindings = bindings.remove(&row[0]).unwrap_or_default();
            ensure!(
                method_bindings.len() == fact[4] as usize,
                "implementation {index} has incomplete accepted method bindings"
            );
            ensure!(
                fact[5] != INVALID,
                "implementation {index} has an invalid public row alias"
            );
            result.implementations.push(CheckedImplementationContract {
                source_row: index as u32,
                owner,
                public_index: fact[5].checked_sub(1),
                trait_identity,
                subject: roots[&row[1]].clone(),
                arguments,
                method_bindings,
            });
        }
    }
    ensure!(
        bindings.is_empty(),
        "checked method bindings have no implementation owner"
    );
    Ok(result)
}
