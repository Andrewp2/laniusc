//! Copy accepted proof terms and their GPU-computed value layouts. These values
//! grant no implementation/call authority; the routed-member capability must
//! still select the exact proof, binding, target, and original call occurrence.
use std::sync::Arc;

use anyhow::{Result, anyhow, ensure};

use super::super::{
    abi::{INVALID, ROOT_DEPTH, ROOT_VISITS},
    catalog::FrozenCatalog,
    native_layout_work::{
        NATIVE_LAYOUT_WORK_FIXED_WORDS, NativeLayoutSource, NativeLayoutWorkLimits,
        NativeLayoutWorkPlan,
    },
};
use super::{Arena, GpuPacket, GpuProgramEvidence, kernels, one_status, words};
use crate::{
    constant_value::CheckedConstantValue,
    gpu::{passes_core, readback::ReadbackRegion},
    type_checker::{
        CheckedGenericApplicationArgument, CheckedGenericConstantValue, CheckedGenericType,
        CheckedNominalIdentity,
    },
};

/// Owns the immutable source snapshots behind private identities. A type and
/// native width are data, not proof that a method is callable for this type.
pub(in crate::compiler::gpu_compiler::program_evidence) struct MaterializedProofType {
    catalog: Arc<FrozenCatalog>,
    source: NativeLayoutSource,
    ty: CheckedGenericType,
    words: u32,
}
impl MaterializedProofType {
    /// Exact row provenance, not host structural equality. Routing must ask for
    /// the very binding term selected by the GPU, in the same retained packet.
    pub fn type_for(
        &self,
        catalog: &Arc<FrozenCatalog>,
        source: NativeLayoutSource,
    ) -> Result<&CheckedGenericType> {
        ensure!(
            Arc::ptr_eq(catalog, &self.catalog) && self.source == source,
            "materialized native type belongs to a different owned term"
        );
        Ok(&self.ty)
    }
    pub fn words(&self) -> u32 {
        self.words
    }
}

#[derive(Debug)]
pub(in crate::compiler::gpu_compiler::program_evidence) struct NativeLayoutFailure {
    pub source: NativeLayoutSource,
    pub status: [u32; 8],
}
impl std::fmt::Display for NativeLayoutFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "GPU native layout failed for term {:?}: {:?}",
            self.source.reference, self.status
        )
    }
}
impl std::error::Error for NativeLayoutFailure {}

impl GpuProgramEvidence {
    /// One command submission and at most two batched readback API calls. The
    /// shared readback layer may page large batches. Each root owns an
    /// independent expansion/work budget. No source graph is downloaded to
    /// estimate layout or select an implementation.
    pub(in crate::compiler::gpu_compiler::program_evidence) fn materialize_proof_terms(
        &mut self,
        packet: &GpuPacket,
        sources: &[[u32; 2]],
        limits: NativeLayoutWorkLimits,
    ) -> Result<Vec<MaterializedProofType>> {
        ensure!(
            !packet.poisoned
                && Arc::ptr_eq(&self.gpu_owner, &packet.gpu_owner)
                && Arc::ptr_eq(&self.catalog, &packet.packet.catalog),
            "native layout uses a foreign/failed GPU packet"
        );
        let arena_id = packet
            .arena_id
            .ok_or_else(|| anyhow!("native layout packet has no admitted proof arena"))?;
        let serial = packet.completed_serial;
        ensure!(
            serial != 0,
            "native layout requires an accepted proof submission"
        );
        packet
            .packet
            .proof_store
            .check_submission(self.catalog.epoch, arena_id, serial)?;
        if sources.is_empty() {
            return Ok(Vec::new());
        }
        let device_limits = self.device.limits();
        ensure!(
            device_limits.max_storage_buffers_per_shader_stage >= 6
                && device_limits.max_uniform_buffers_per_shader_stage >= 2
                && device_limits.max_bindings_per_bind_group >= 8,
            "device cannot bind native layout/proof arenas"
        );
        if self.layout_kernel.is_none() {
            self.layout_kernel = Some(kernels::NativeLayoutKernel::load(&self.device)?);
            crate::gpu::device::persist_compiled_pipelines_for_device(&self.device);
        }
        let kernel = self.layout_kernel.as_ref().expect("loaded layout kernel");
        let plans = sources
            .iter()
            .map(|&reference| {
                NativeLayoutWorkPlan::new(
                    NativeLayoutSource {
                        epoch: self.catalog.epoch,
                        arena_id,
                        serial,
                        reference,
                    },
                    limits,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let arenas = plans
            .iter()
            .map(|plan| {
                Arena::from_words(
                    &self.workspace,
                    "program_evidence.native_layout_job",
                    &plan.words,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("program_evidence.materialize_native_types"),
            });
        for arena in &arenas {
            kernel.record(
                &self.device,
                &mut encoder,
                &self.storage,
                &packet.input,
                &packet.output,
                kernels::ProofResources {
                    storage: &packet.proof,
                    epoch: self.catalog.epoch,
                    arena_id,
                    serial,
                },
                &self.native_recipes,
                arena,
            )?;
        }
        passes_core::flush_deferred_compute(&mut encoder);
        self.queue.submit(Some(encoder.finish()));
        let mut regions = Vec::with_capacity(plans.len() * 3);
        for (plan, arena) in plans.iter().zip(&arenas) {
            regions.push(ReadbackRegion::from_buffer(
                &arena.buffer,
                0,
                NATIVE_LAYOUT_WORK_FIXED_WORDS as usize * 4,
                "native layout header",
            )?);
            regions.push(ReadbackRegion::from_buffer(
                &arena.buffer,
                u64::from(plan.dirs[5].offset) * 4,
                32,
                "native layout receipt",
            )?);
            regions.push(ReadbackRegion::from_buffer(
                &arena.buffer,
                u64::from(plan.dirs[6].offset) * 4,
                16,
                "native layout result",
            )?);
        }
        let first = self.readback.read_regions(
            &self.device,
            &self.queue,
            &regions,
            "native layout completions",
        )?;
        let mut prefixes = Vec::with_capacity(plans.len());
        for (i, plan) in plans.iter().enumerate() {
            let header = words(&first[i * 3])?;
            let status = one_status(&first[i * 3 + 1])?;
            if status[0] != 1 {
                return Err(NativeLayoutFailure {
                    source: plan.source,
                    status,
                }
                .into());
            }
            ensure!(
                header.len() == NATIVE_LAYOUT_WORK_FIXED_WORDS as usize,
                "native layout header width differs"
            );
            // Only GPU output counters may differ from the fresh uploaded plan.
            for (column, (&actual, &expected)) in header.iter().zip(plan.words.iter()).enumerate() {
                if matches!(column, 13..=16 | 18..=20) {
                    continue;
                }
                ensure!(
                    actual == expected,
                    "native layout readback belongs to a different job at column {column}"
                );
            }
            for table in 0..4 {
                ensure!(
                    header[13 + table] <= plan.dirs[table].capacity,
                    "native layout used rows exceed the owned allocation"
                );
            }
            ensure!(
                header[18] <= limits.visits && header[19] <= header[13] && header[20] <= header[14],
                "native layout returned an invalid semantic prefix"
            );
            let result = words(&first[i * 3 + 2])?;
            ensure!(
                result.len() == 4 && result[3] == 1 && result[2] != INVALID,
                "native layout omitted a completed result"
            );
            prefixes.push((header[19], header[20], [result[0], result[1]], result[2]));
        }
        // Only the copied requested semantic graph is read back. Definition
        // payload expansion rows remain private GPU work; allocated capacity
        // and unused arenas are never downloaded.
        let mut payload_regions = Vec::new();
        let mut region_indices = Vec::with_capacity(plans.len());
        for ((plan, arena), &(nodes, edges, _, _)) in plans.iter().zip(&arenas).zip(&prefixes) {
            let mut indexes = [None; 3];
            for (part, table, count) in [(0, 0, nodes), (1, 1, edges), (2, 4, nodes)] {
                if count == 0 {
                    continue;
                }
                indexes[part] = Some(payload_regions.len());
                let size = u64::from(count) * u64::from(plan.dirs[table].width) * 4;
                payload_regions.push(ReadbackRegion::from_buffer(
                    &arena.buffer,
                    u64::from(plan.dirs[table].offset) * 4,
                    usize::try_from(size)?,
                    "native semantic prefix",
                )?);
            }
            region_indices.push(indexes);
        }
        let payloads = if payload_regions.is_empty() {
            Vec::new()
        } else {
            self.readback.read_regions(
                &self.device,
                &self.queue,
                &payload_regions,
                "native semantic graph prefixes",
            )?
        };
        let mut results = Vec::with_capacity(plans.len());
        for ((plan, &(_, _, root, native_words)), indexes) in
            plans.iter().zip(&prefixes).zip(&region_indices)
        {
            let region = |part: usize| -> Result<Vec<u32>> {
                match indexes[part] {
                    Some(index) => words(&payloads[index]),
                    None => Ok(Vec::new()),
                }
            };
            let nodes = region(0)?;
            let edges = region(1)?;
            let layouts = region(2)?;
            let mut reader = ClosedLayoutReadback {
                packet,
                nodes: &nodes,
                edges: &edges,
                layouts: &layouts,
                visits: 0,
            };
            let ty = reader.ty(root, 0)?;
            ensure!(ty.is_closed(), "native readback returned a symbolic type");
            results.push(MaterializedProofType {
                catalog: self.catalog.clone(),
                source: plan.source,
                ty,
                words: native_words,
            });
        }
        Ok(results)
    }
}

/// Lossless decoding only. All graph normalization and layout arithmetic were
/// executed and accepted on the GPU. Exact fixed atom tuples recover immutable
/// public/private identities without host unification or implementation lookup.
struct ClosedLayoutReadback<'a> {
    packet: &'a GpuPacket,
    nodes: &'a [u32],
    edges: &'a [u32],
    layouts: &'a [u32],
    visits: usize,
}

fn closed_layout_node(nodes: &[u32], row: u32) -> Result<[u32; 8]> {
    ensure!(row != INVALID, "native graph contains an absent reference");
    let start = (row as usize)
        .checked_mul(8)
        .ok_or_else(|| anyhow!("native node offset overflow"))?;
    let words = nodes
        .get(start..)
        .and_then(|tail| tail.get(..8))
        .ok_or_else(|| anyhow!("native value escapes the requested semantic prefix"))?;
    Ok(words.try_into().expect("eight-word node"))
}

fn closed_layout_type_node(nodes: &[u32], row: u32) -> Result<[u32; 8]> {
    let node = closed_layout_node(nodes, row)?;
    ensure!(
        (1..=4).contains(&node[0]),
        "native type reference names a constant or invalid node"
    );
    Ok(node)
}

fn closed_layout_constant(nodes: &[u32], reference: [u32; 2]) -> Result<CheckedConstantValue> {
    ensure!(
        reference[0] == 0x8000_0001,
        "native constant is symbolic or has an invalid reference tag"
    );
    let row = closed_layout_node(nodes, reference[1])?;
    ensure!(
        row[0] == 6 && row[4..] == [0; 4],
        "native constant reference does not name an owned literal"
    );
    CheckedConstantValue::from_words(row[1], [row[2], row[3]])
        .ok_or_else(|| anyhow!("native literal has an invalid scalar or value representation"))
}

impl ClosedLayoutReadback<'_> {
    fn constant(
        &mut self,
        reference: [u32; 2],
        depth: usize,
    ) -> Result<CheckedGenericConstantValue> {
        self.visits = self
            .visits
            .checked_add(1)
            .ok_or_else(|| anyhow!("native graph visit overflow"))?;
        ensure!(
            depth <= ROOT_DEPTH && self.visits <= ROOT_VISITS,
            "native constant exceeds graph limits"
        );
        // This copies exact GPU-produced bits. Array count fitting and native
        // multiplication already ran on GPU; no host evaluation is performed.
        Ok(CheckedGenericConstantValue::Literal(
            closed_layout_constant(self.nodes, reference)?,
        ))
    }

    fn ty(&mut self, reference: [u32; 2], depth: usize) -> Result<CheckedGenericType> {
        self.visits = self
            .visits
            .checked_add(1)
            .ok_or_else(|| anyhow!("native graph visit overflow"))?;
        ensure!(
            depth <= ROOT_DEPTH && self.visits <= ROOT_VISITS,
            "native graph readback exceeds retained graph limits"
        );
        ensure!(
            reference[1] != INVALID,
            "native graph contains an absent reference"
        );
        if reference[0] == 1 {
            ensure!(
                crate::primitive_types::is_known(reference[1]),
                "native graph scalar is invalid"
            );
            return Ok(CheckedGenericType::Scalar(reference[1]));
        }
        ensure!(
            reference[0] == 3,
            "native graph is symbolic or has an invalid type tag"
        );
        let node = reference[1] as usize;
        let row = closed_layout_type_node(self.nodes, reference[1])?;
        let width = *self
            .layouts
            .get(
                node.checked_mul(4)
                    .and_then(|n| n.checked_add(3))
                    .ok_or_else(|| anyhow!("native width offset overflow"))?,
            )
            .ok_or_else(|| anyhow!("native type has no layout column"))?;
        let width = (width != INVALID).then_some(width);
        Ok(match row[0] {
            1 => {
                ensure!(
                    row[3] <= 32,
                    "native nominal arity exceeds the admitted application limit"
                );
                let key = self.packet.packet.retained_atom_key(row[1])?;
                let (identity, local_replay) = match key {
                    [1, library, unit, declaration, 0, 0, 0, 0] => (
                        CheckedNominalIdentity::Public([library, unit, declaration]),
                        None,
                    ),
                    [2, snapshot, declaration_token, 0, 0, 0, 0, 0] => {
                        let snapshot = self
                            .packet
                            .packet
                            .catalog
                            .snapshots
                            .get(snapshot as usize)
                            .ok_or_else(|| {
                                anyhow!("native private type has no immutable source snapshot")
                            })?;
                        ensure!(
                            declaration_token < 0x2000_0000,
                            "private native type anchor exceeds packet domain"
                        );
                        (
                            CheckedNominalIdentity::SourceLocal {
                                unit: snapshot.unit,
                                declaration_token,
                            },
                            Some(0x2000_0000 | declaration_token),
                        )
                    }
                    _ => {
                        return Err(anyhow!(
                            "native nominal atom is not an accepted nominal identity"
                        ));
                    }
                };
                let mut arguments = Vec::with_capacity(row[3] as usize);
                for ordinal in 0..row[3] {
                    let edge = row[2]
                        .checked_add(ordinal)
                        .ok_or_else(|| anyhow!("native argument edge overflow"))?
                        as usize;
                    let start = edge
                        .checked_mul(2)
                        .ok_or_else(|| anyhow!("native edge offset overflow"))?;
                    let pair = self
                        .edges
                        .get(start..)
                        .and_then(|tail| tail.get(..2))
                        .ok_or_else(|| anyhow!("native argument escapes semantic edge prefix"))?;
                    let pair = [pair[0], pair[1]];
                    if pair[0] == 0x8000_0001 {
                        arguments.push(CheckedGenericApplicationArgument::Constant(
                            self.constant(pair, depth + 1)?,
                        ));
                    } else {
                        arguments.push(CheckedGenericApplicationArgument::Type(
                            self.ty(pair, depth + 1)?,
                        ));
                    }
                }
                CheckedGenericType::Nominal {
                    identity,
                    arguments,
                    words: width,
                    local_replay,
                }
            }
            2 => {
                let length = self.constant([row[6], row[7]], depth + 1)?;
                CheckedGenericType::Array {
                    element: Box::new(self.ty([row[4], row[5]], depth + 1)?),
                    length,
                    words: width,
                }
            }
            3 => CheckedGenericType::Slice(Box::new(self.ty([row[4], row[5]], depth + 1)?)),
            4 => CheckedGenericType::Reference(Box::new(self.ty([row[4], row[5]], depth + 1)?)),
            _ => return Err(anyhow!("native graph contains an invalid node kind")),
        })
    }
}

#[cfg(test)]
mod typed_constant_tests {
    use super::{closed_layout_constant, closed_layout_type_node};
    use crate::primitive_types::{SCALAR_I64, SCALAR_U64};

    #[test]
    fn layout_readback_preserves_typed_constant_bits_and_namespace() {
        let nodes = [
            [6, SCALAR_U64, 7, 1, 0, 0, 0, 0],
            [6, SCALAR_U64, 7, 2, 0, 0, 0, 0],
            [6, SCALAR_I64, 7, 1, 0, 0, 0, 0],
            [6, SCALAR_U64, u32::MAX, u32::MAX, 0, 0, 0, 0],
        ]
        .concat();
        let values: Vec<_> = (0..4)
            .map(|row| closed_layout_constant(&nodes, [0x8000_0001, row]).unwrap())
            .collect();
        assert_ne!(values[0], values[1]);
        assert_ne!(values[0], values[2]);
        assert_eq!(values[3].words(), [SCALAR_U64, u32::MAX, u32::MAX]);
        for row in 0..4 {
            assert!(closed_layout_type_node(&nodes, row).is_err());
        }
    }

    #[test]
    fn layout_readback_rejects_unclosed_or_malformed_constant_nodes() {
        let nodes = [
            [5, SCALAR_U64, 0, 0, 0x8000_0002, 1, 0, 0],
            [4, 0, 0, 0, 1, SCALAR_U64, 0, 0],
            [6, SCALAR_U64, 1, 0, 1, 0, 0, 0],
        ]
        .concat();
        for row in 0..3 {
            assert!(closed_layout_constant(&nodes, [0x8000_0001, row]).is_err());
        }
        assert!(closed_layout_constant(&nodes, [0x8000_0003, 0]).is_err());
        assert!(closed_layout_constant(&nodes, [0x8000_0001, 3]).is_err());
        assert!(closed_layout_constant(&nodes, [0x8000_0001, u32::MAX]).is_err());
    }
}
