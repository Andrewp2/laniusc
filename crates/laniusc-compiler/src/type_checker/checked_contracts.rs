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
};
use crate::gpu::readback::{PagedReadback, ReadbackRegion};
use crate::parser::passes::hir::item::fields::{HIR_ITEM_KIND_ENUM, HIR_ITEM_KIND_STRUCT};

const INVALID: u32 = u32::MAX;
const TRAIT_KIND: u32 = 10;
const TYPE_HIR_KIND: u32 = 5;
/// semantic/artifact/00_project: a predicate subject column value with this
/// bit is a scalar subject's type code, not a parameter declaration token.
const SCALAR_SUBJECT_BIT: u32 = 0x8000_0000;

#[derive(Clone, Debug, Default)]
pub(crate) struct CheckedUnitFacts {
    pub generic_calls: Vec<CheckedGenericCall>,
    pub contracts: CheckedUnitContracts,
    pub call_owners: Vec<CheckedCallOwner>,
    /// Full checked callable occurrence ownership before generic-only pruning.
    pub native_call_owners: Vec<CheckedCallOwner>,
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
    /// Definition-owned payload graphs, independent of instantiated types and
    /// native layout availability. Private declarations remain source-scoped.
    pub nominal_recipes: Vec<CheckedNominalRecipe>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CheckedNominalRecipeKind {
    Record,
    Enum,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedNominalRecipe {
    pub identity: CheckedNominalIdentity,
    pub source_hir: u32,
    /// Index into this exact snapshot's binders, including nongeneric owners.
    pub owner: u32,
    pub kind: CheckedNominalRecipeKind,
    /// A record has one group in field order. Enum group indexes are variant
    /// ordinals, retaining empty variants and zero groups for an empty enum.
    pub groups: Vec<Vec<CheckedGenericType>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CheckedContractOwner {
    pub source_hir: u32,
    pub binder: CheckedBinderIdentity,
    /// Accepted executable callable identity in this immutable source unit.
    /// Trait requirements and non-callable owners have no native target.
    pub callable: Option<CheckedCallableOwner>,
    /// Index into the same unit's owner table, independent of public identity.
    pub enclosing_owner: Option<u32>,
    pub parameters: Vec<CheckedGenericParameter>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedCallableOwner {
    /// Shares the native definition policy, independently of lexical scope.
    pub native_symbol: u32,
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
    /// INVALID is the checked producer's explicit absence of a lexical function.
    /// A missing call-owner row never carries this meaning.
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
        for recipe in &mut self.nominal_recipes {
            recipe.identity.scope(source_unit);
            for group in &mut recipe.groups {
                for payload in group {
                    payload.scope(source_unit);
                }
            }
        }
    }

    /// Owned vector/graph storage only. An Arc owner must separately account
    /// for this inner struct, in addition to its own Arc handle.
    pub(crate) fn resident_byte_len(&self) -> usize {
        let mut bytes = vector_bytes(&self.binders)
            .saturating_add(vector_bytes(&self.predicates))
            .saturating_add(vector_bytes(&self.implementations))
            .saturating_add(vector_bytes(&self.nominal_recipes));
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
        for recipe in &self.nominal_recipes {
            bytes = bytes.saturating_add(vector_bytes(&recipe.groups));
            for group in &recipe.groups {
                bytes = bytes.saturating_add(vector_bytes(group));
                for payload in group {
                    bytes = bytes.saturating_add(payload.owned_edge_bytes());
                }
            }
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

/// Compact declaration rows copied with the original unit's readback batch.
/// Field rows also contain struct literal entries, which are not type recipes.
pub(super) struct NominalRecipeSourceRows<'a> {
    pub headers: &'a [(u32, u32, u32, u32)],
    pub fields: &'a [u32],
    pub variants: &'a [u32],
    pub payloads: &'a [u32],
    pub payload_starts: &'a [u32],
    pub payload_counts: &'a [u32],
}

/// Copy accepted declaration shape and reuse the shared semantic decoder.
/// This boundary does not substitute arguments or compute native layouts.
#[allow(clippy::too_many_arguments)]
pub(super) fn read_nominal_recipes(
    readback: &PagedReadback,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    inputs: &RetainedGenericCallInputs,
    types: &mut CheckedTypeReadback,
    source: NominalRecipeSourceRows<'_>,
) -> Result<Vec<CheckedNominalRecipe>> {
    ensure!(source.fields.len() % 4 == 0 && source.variants.len() % 4 == 0
        && source.payloads.len() % 4 == 0,
        "nominal recipe source rows are truncated");
    let variant_count = source.variants.len() / 4;
    let payload_count = source.payloads.len() / 4;
    ensure!(source.payload_starts.len() == variant_count
        && source.payload_counts.len() == variant_count,
        "nominal recipe variant ranges are incomplete");
    let mut declarations = BTreeMap::new();
    let mut record_fields = BTreeMap::<u32, BTreeMap<u32, u32>>::new();
    let mut enum_variants = BTreeMap::<u32, BTreeMap<u32, u32>>::new();
    for &(_, hir, token, kind) in source.headers {
        if !matches!(kind, HIR_ITEM_KIND_STRUCT | HIR_ITEM_KIND_ENUM) {
            continue;
        }
        ensure!(declarations.insert(hir, (token, kind)).is_none(),
            "nominal recipe has duplicate declaration HIR {hir}");
        if kind == HIR_ITEM_KIND_STRUCT {
            record_fields.insert(hir, BTreeMap::new());
        } else {
            enum_variants.insert(hir, BTreeMap::new());
        }
    }
    for field in source.fields.chunks_exact(4) {
        // Canonical fields include literals. Only declaration owners have
        // checked type roots; literal field values must never be decoded here.
        let Some(fields) = record_fields.get_mut(&field[0]) else {
            ensure!(!enum_variants.contains_key(&field[0]),
                "enum declaration unexpectedly owns a record field");
            continue;
        };
        ensure!(field[2] != INVALID && fields.insert(field[3], field[2]).is_none(),
            "record {} has a missing type or duplicate field ordinal", field[0]);
    }
    let mut variant_groups = Vec::with_capacity(variant_count);
    for (row, variant) in source.variants.chunks_exact(4).enumerate() {
        let variants = enum_variants.get_mut(&variant[0])
            .ok_or_else(|| anyhow!("variant {row} has no retained enum declaration"))?;
        ensure!(variants.insert(variant[2], row as u32).is_none(),
            "enum {} has duplicate variant ordinals", variant[0]);
        let start = source.payload_starts[row];
        let count = source.payload_counts[row] as usize;
        ensure!((count == 0 && start == INVALID)
            || (count != 0 && (start as usize) <= payload_count
                && count <= payload_count - start as usize),
            "variant {row} has an invalid payload range");
        // Allocate from actual rows below, not the sum of unvalidated ranges.
        variant_groups.push(Vec::new());
    }
    for (row, payload) in source.payloads.chunks_exact(4).enumerate() {
        let variant = payload[0] as usize;
        ensure!(variant < variant_count && payload[1] != INVALID,
            "variant payload {row} has no retained variant or type");
        let start = source.payload_starts[variant];
        let count = source.payload_counts[variant];
        ensure!(start != INVALID && payload[2] < count
            && start.checked_add(payload[2]) == Some(row as u32)
            && variant_groups[variant].len() == payload[2] as usize,
            "variant payload {row} has different ownership or order");
        variant_groups[variant].push(payload[1]);
    }
    for (row, group) in variant_groups.iter().enumerate() {
        ensure!(group.len() == source.payload_counts[row] as usize,
            "variant {row} has an incomplete payload group");
    }
    let mut plans = Vec::with_capacity(declarations.len());
    let mut root_hirs = BTreeSet::new();
    for (&hir, &(token, kind)) in &declarations {
        let (kind, groups) = if kind == HIR_ITEM_KIND_STRUCT {
            let fields = &record_fields[&hir];
            let mut group = Vec::with_capacity(fields.len());
            for (ordinal, (&actual, &root)) in fields.iter().enumerate() {
                ensure!(actual == ordinal as u32,
                    "record {hir} has a noncontiguous field ordinal");
                group.push(root);
            }
            (CheckedNominalRecipeKind::Record, vec![group])
        } else {
            let variants = &enum_variants[&hir];
            let mut groups = Vec::with_capacity(variants.len());
            for (ordinal, (&actual, &row)) in variants.iter().enumerate() {
                ensure!(actual == ordinal as u32,
                    "enum {hir} has a noncontiguous variant ordinal");
                groups.push(std::mem::take(&mut variant_groups[row as usize]));
            }
            (CheckedNominalRecipeKind::Enum, groups)
        };
        root_hirs.extend(groups.iter().flatten().copied());
        plans.push((types.nominal_identity(token)?, hir, types.owner_index(hir)?, kind, groups));
    }
    let mut requests = Vec::with_capacity(root_hirs.len() * 3);
    for &hir in &root_hirs {
        requests.push(("compact_hir_core", hir.checked_mul(4)
            .ok_or_else(|| anyhow!("nominal recipe type HIR offset overflows"))?));
        requests.push(("semantic_type_ref_tag_by_hir", hir));
        requests.push(("semantic_type_ref_payload_by_hir", hir));
    }
    let rows = if requests.is_empty() {
        Vec::new()
    } else {
        read_scalars(readback, device, queue, inputs, &requests)?
    };
    ensure!(rows.chunks_exact(3).all(|row| row[0] == TYPE_HIR_KIND),
        "nominal recipe payload is not a checked type root");
    let references = rows.chunks_exact(3).map(|row| (row[1], row[2])).collect::<Vec<_>>();
    types.prefetch_types(readback, device, queue, inputs, &references)?;
    let mut roots = BTreeMap::new();
    for (&hir, reference) in root_hirs.iter().zip(rows.chunks_exact(3)) {
        let ty = read_type(readback, device, queue, inputs, reference[1], reference[2], types)?;
        ensure!(ty.has_semantic_identity(),
            "nominal recipe type root {hir} has no complete semantic identity");
        roots.insert(hir, ty);
    }
    Ok(plans.into_iter().map(|(identity, source_hir, owner, kind, groups)| {
        CheckedNominalRecipe {
            identity, source_hir, owner, kind,
            groups: groups.into_iter().map(|group| {
                group.into_iter().map(|root| roots[&root].clone()).collect()
            }).collect(),
        }
    }).collect())
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
    readback.read_regions_words(device, queue, &regions, "checked contract facts")
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
    metadata: Option<&[u32]>,
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
        metadata[..requests.len()].to_vec()
    } else {
        read_scalars(readback, device, queue, inputs, &requests)?
    };
    let ranges_requests = range_requests(source.predicates)?;
    let ranges = if let Some(metadata) = metadata {
        metadata[requests.len()..].to_vec()
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
            let subject = if fact[4] != INVALID && fact[4] & SCALAR_SUBJECT_BIT != 0 {
                // semantic/artifact/00_project: `where bool: Inner<..>`.
                let code = fact[4] & !SCALAR_SUBJECT_BIT;
                ensure!(
                    crate::primitive_types::is_known(code),
                    "predicate {index} has an unknown scalar subject"
                );
                CheckedGenericType::Scalar(code)
            } else {
                let parameter = types.parameter(fact[4]).ok_or_else(|| {
                    anyhow!("predicate {index} has no canonical subject parameter")
                })?;
                ensure!(
                    parameter.identity.domain
                        == super::generic_calls::CheckedParameterDomain::Type,
                    "predicate {index} has a non-type subject parameter"
                );
                CheckedGenericType::Parameter(parameter)
            };
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
                subject,
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
