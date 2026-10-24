//! Bounded projection of an already admitted implementation proof. Only this
//! dispatcher can construct the opaque successful result. Wire plans are data.
use std::sync::Arc;

use anyhow::{Result, anyhow, ensure};

use super::{
    super::{
        abi::ROOT_VISITS,
        catalog::FrozenCatalog,
        native_layout_work::NativeLayoutWorkLimits,
        packet::{ImplApplicationRequest, ProgramPacket},
    },
    Arena,
    GpuPacket,
    GpuProgramEvidence,
    kernels,
    one_status,
    words,
};
use crate::gpu::{passes_core, readback::ReadbackRegion};

const MAGIC: u32 = 0x4941_5031;
const VERSION: u32 = 1;
const MAX_REQUESTS: usize = 64;
const MAX_ROWS: usize = 4096;
const REQUEST_ROW: usize = 6;
const APP_ROW: usize = REQUEST_ROW + MAX_REQUESTS * 2;
const BINDING_ROW: usize = APP_ROW + MAX_REQUESTS * 3;
const PREREQ_ROW: usize = BINDING_ROW + MAX_ROWS * 3;
const HOP_ROW: usize = PREREQ_ROW + MAX_ROWS;
const STATUS_ROW: usize = HOP_ROW + MAX_ROWS;
const TOTAL_ROWS: usize = STATUS_ROW + 2;

#[derive(Clone, Copy, Debug)]
pub(in crate::compiler::gpu_compiler::program_evidence) struct ImplProjectionLimits {
    bindings: u32,
    prerequisites: u32,
    hops: u32,
}
impl ImplProjectionLimits {
    pub fn production() -> Self {
        Self {
            bindings: 4096,
            prerequisites: 4096,
            hops: 4096,
        }
    }
    pub fn new(bindings: u32, prerequisites: u32, hops: u32) -> Result<Self> {
        ensure!(
            [bindings, prerequisites, hops]
                .iter()
                .all(|&count| count <= MAX_ROWS as u32),
            "implementation projection policy exceeds fixed capacity"
        );
        Ok(Self {
            bindings,
            prerequisites,
            hops,
        })
    }
    pub fn type_layout_limits() -> NativeLayoutWorkLimits {
        NativeLayoutWorkLimits {
            nodes: 1024,
            edges: 16384,
            groups: 1024,
            payload_roots: 16384,
            visits: ROOT_VISITS as u32,
        }
    }
}

struct ProjectionPlan {
    words: Vec<u32>,
    requests: Vec<[u32; 8]>,
}
impl ProjectionPlan {
    fn new(
        epoch: u64,
        arena: u64,
        serial: u32,
        requests: Vec<[u32; 8]>,
        limits: ImplProjectionLimits,
    ) -> Result<Self> {
        ensure!(
            epoch != 0 && arena != 0 && serial != 0 && serial != u32::MAX,
            "implementation projection has a reserved lineage"
        );
        ensure!(
            requests.len() <= MAX_REQUESTS,
            "implementation projection exceeds 64 requests"
        );
        ImplProjectionLimits::new(limits.bindings, limits.prerequisites, limits.hops)?;
        let mut words = Vec::new();
        words.try_reserve_exact(TOTAL_ROWS * 4)?;
        words.resize(TOTAL_ROWS * 4, 0);
        words[..20].copy_from_slice(&[
            MAGIC,
            VERSION,
            epoch as u32,
            (epoch >> 32) as u32,
            arena as u32,
            (arena >> 32) as u32,
            serial,
            requests.len() as u32,
            limits.bindings,
            limits.prerequisites,
            limits.hops,
            0,
            REQUEST_ROW as u32,
            APP_ROW as u32,
            BINDING_ROW as u32,
            PREREQ_ROW as u32,
            HOP_ROW as u32,
            STATUS_ROW as u32,
            TOTAL_ROWS as u32,
            0,
        ]);
        for (index, request) in requests.iter().enumerate() {
            let at = (REQUEST_ROW + index * 2) * 4;
            words[at..at + 8].copy_from_slice(request);
        }
        Ok(Self { words, requests })
    }
    fn completion(&self, header: &[u32], status: [u32; 8]) -> Result<[usize; 3]> {
        ensure!(
            header.len() == 24 && header[..20] == self.words[..20],
            "implementation projection receipt belongs to another work request"
        );
        ensure!(
            status[0] == 1,
            "GPU implementation projection failed: {status:?}"
        );
        ensure!(
            header[23] as usize == self.requests.len(),
            "implementation projection is incomplete"
        );
        let mut used = [0; 3];
        for index in 0..3 {
            ensure!(
                header[20 + index] <= self.words[8 + index],
                "implementation projection output exceeds its policy"
            );
            used[index] = header[20 + index] as usize;
        }
        Ok(used)
    }
}

/// Opaque successful query receipt. It retains only selected binding references,
/// prerequisite/hop provenance, and constant data, never the whole proof graph.
pub(in crate::compiler::gpu_compiler::program_evidence) struct ProjectedImplApplication {
    catalog: Arc<FrozenCatalog>,
    epoch: u64,
    arena: u64,
    serial: u32,
    request_identity: Arc<()>,
    request_rows: [u32; 8],
    application: [u32; 12],
    bindings: Box<[[u32; 12]]>,
    prerequisites: Box<[[u32; 4]]>,
    hops: Box<[[u32; 4]]>,
}
impl ProjectedImplApplication {
    pub fn implementation(&self) -> u32 {
        self.application[2]
    }
    pub fn owner(&self) -> u32 {
        self.application[10]
    }
    pub fn serial(&self) -> u32 {
        self.serial
    }
    pub fn bindings(&self) -> &[[u32; 12]] {
        &self.bindings
    }
    pub fn prerequisites(&self) -> &[[u32; 4]] {
        &self.prerequisites
    }
    pub fn assumption_hops(&self) -> &[[u32; 4]] {
        &self.hops
    }
    pub fn type_sources(&self) -> Vec<[u32; 2]> {
        self.bindings
            .iter()
            .filter(|binding| binding[1] == 0)
            .map(|binding| [binding[4], binding[5]])
            .collect()
    }
    pub fn validate_retained_source(
        &self,
        request: &ImplApplicationRequest,
        packet: &ProgramPacket,
    ) -> Result<()> {
        packet.check_implementation_projection_owner(self.epoch, self.arena, None)?;
        ensure!(
            Arc::ptr_eq(&self.catalog, &packet.catalog)
                && Arc::ptr_eq(&self.request_identity, &request.identity())
                && self.request_rows == request.checked_rows(packet)?,
            "implementation projection lost its exact request or source"
        );
        Ok(())
    }
    pub fn validate_current(
        &self,
        request: &ImplApplicationRequest,
        packet: &ProgramPacket,
    ) -> Result<()> {
        self.validate_retained_source(request, packet)?;
        packet.check_implementation_projection_owner(self.epoch, self.arena, Some(self.serial))
    }
}

fn records<const N: usize>(words: &[u32]) -> Result<Vec<[u32; N]>> {
    ensure!(
        words.len() % N == 0,
        "implementation projection has a partial output row"
    );
    words
        .chunks_exact(N)
        .map(|row| row.try_into().map_err(anyhow::Error::from))
        .collect()
}
fn span<'a, T>(values: &'a [T], first: u32, count: u32) -> Result<&'a [T]> {
    let end = first
        .checked_add(count)
        .ok_or_else(|| anyhow!("implementation projection span overflow"))?;
    values
        .get(first as usize..end as usize)
        .ok_or_else(|| anyhow!("implementation projection span is incomplete"))
}

impl GpuProgramEvidence {
    pub fn project_implementation_applications(
        &mut self,
        packet: &GpuPacket,
        requests: &[ImplApplicationRequest],
        limits: ImplProjectionLimits,
    ) -> Result<Vec<ProjectedImplApplication>> {
        ensure!(
            !self.query_scratch_poisoned,
            "a prior query did not complete its scratch readbacks"
        );
        ensure!(
            !packet.poisoned
                && Arc::ptr_eq(&self.gpu_owner, &packet.gpu_owner)
                && Arc::ptr_eq(&self.catalog, &packet.packet.catalog),
            "implementation projection uses a foreign/failed GPU packet"
        );
        let arena = packet
            .arena_id
            .ok_or_else(|| anyhow!("implementation projection has no accepted arena"))?;
        let serial = packet.completed_serial;
        packet.packet.check_implementation_projection_owner(
            self.catalog.epoch,
            arena,
            Some(serial),
        )?;
        if requests.is_empty() {
            return Ok(Vec::new());
        }
        let descriptors = requests
            .iter()
            .map(|request| request.checked_rows(&packet.packet))
            .collect::<Result<Vec<_>>>()?;
        let plan = ProjectionPlan::new(self.catalog.epoch, arena, serial, descriptors, limits)?;
        if self.implementation_application_kernel.is_none() {
            self.implementation_application_kernel = Some(
                kernels::ImplementationApplicationKernel::load(&self.device)?,
            );
            crate::gpu::device::persist_created_pipelines_for_device(&self.device);
        }
        if self.implementation_query_slot.is_none() {
            self.implementation_query_slot = Some(
                self.workspace
                    .reserve("program_evidence.implementation_application")?,
            );
        }
        let work = Arena::from_slot_words(
            self.implementation_query_slot
                .as_ref()
                .expect("reserved projection query role"),
            &plan.words,
        )?;
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("program_evidence.project_implementation_applications"),
            });
        self.implementation_application_kernel
            .as_ref()
            .expect("loaded implementation projector")
            .record(
                &self.device,
                &mut encoder,
                &self.storage,
                &packet.input,
                &packet.output,
                kernels::ProofResources {
                    storage: &packet.proof,
                    epoch: self.catalog.epoch,
                    arena_id: arena,
                    serial,
                },
                &work,
            )?;
        passes_core::flush_deferred_compute(&mut encoder);
        self.query_scratch_poisoned = true;
        self.queue.submit(Some(encoder.finish()));
        let first = self.readback.read_regions(
            &self.device,
            &self.queue,
            &[
                ReadbackRegion::from_buffer(
                    &work.buffer,
                    0,
                    24 * 4,
                    "implementation projection header",
                )?,
                ReadbackRegion::from_buffer(
                    &work.buffer,
                    (STATUS_ROW * 16) as u64,
                    32,
                    "implementation projection receipt",
                )?,
            ],
            "implementation projection receipt",
        )?;
        let header = words(&first[0])?;
        let used = match plan.completion(&header, one_status(&first[1])?) {
            Ok(used) => used,
            Err(error) => {
                self.query_scratch_poisoned = false;
                return Err(error);
            }
        };
        let regions = [
            (APP_ROW, requests.len() * 12),
            (BINDING_ROW, used[0] * 12),
            (PREREQ_ROW, used[1] * 4),
            (HOP_ROW, used[2] * 4),
        ]
        .into_iter()
        .filter(|(_, count)| *count != 0)
        .map(|(row, count)| {
            ReadbackRegion::from_buffer(
                &work.buffer,
                (row * 16) as u64,
                count * 4,
                "implementation projection selected rows",
            )
        })
        .collect::<Result<Vec<_>>>()?;
        let raw = self.readback.read_regions(
            &self.device,
            &self.queue,
            &regions,
            "implementation application rows",
        )?;
        self.query_scratch_poisoned = false;
        let mut raw = raw.iter();
        let apps = records::<12>(&words(
            raw.next()
                .ok_or_else(|| anyhow!("missing implementation applications"))?,
        )?)?;
        let mut pool = |count: usize| -> Result<Vec<u32>> {
            if count == 0 {
                Ok(Vec::new())
            } else {
                words(
                    raw.next()
                        .ok_or_else(|| anyhow!("missing implementation projection pool"))?,
                )
            }
        };
        let bindings = records::<12>(&pool(used[0])?)?;
        let prerequisites = records::<4>(&pool(used[1])?)?;
        let hops = records::<4>(&pool(used[2])?)?;
        ensure!(
            apps.len() == requests.len()
                && bindings.len() == used[0]
                && prerequisites.len() == used[1]
                && hops.len() == used[2]
                && raw.next().is_none(),
            "implementation projection readback lengths differ"
        );
        let mut result = Vec::new();
        let mut covered = [0u32; 3];
        for (index, (application, request)) in apps.into_iter().zip(requests).enumerate() {
            ensure!(
                application[0] == index as u32
                    && application[11] == plan.requests[index][1]
                    && application[4] == covered[0]
                    && application[6] == covered[1]
                    && application[8] == covered[2]
                    && application[5] <= 64
                    && application[9] <= 64,
                "implementation application ownership or span coverage differs"
            );
            let selected_bindings = span(&bindings, application[4], application[5])?;
            let selected_prerequisites = span(&prerequisites, application[6], application[7])?;
            let selected_hops = span(&hops, application[8], application[9])?;
            covered = [
                application[4] + application[5],
                application[6] + application[7],
                application[8] + application[9],
            ];
            result.push(ProjectedImplApplication {
                catalog: self.catalog.clone(),
                epoch: self.catalog.epoch,
                arena,
                serial,
                request_identity: request.identity(),
                request_rows: plan.requests[index],
                application,
                bindings: selected_bindings.into(),
                prerequisites: selected_prerequisites.into(),
                hops: selected_hops.into(),
            });
        }
        ensure!(
            covered == used.map(|count| count as u32),
            "implementation projection has unowned trailing output rows"
        );
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn projection_protocol_has_exact_bounded_layout_and_no_authority_constructor() {
        assert_eq!(
            (
                APP_ROW,
                BINDING_ROW,
                PREREQ_ROW,
                HOP_ROW,
                STATUS_ROW,
                TOTAL_ROWS
            ),
            (134, 326, 12614, 16710, 20806, 20808)
        );
        assert_eq!(TOTAL_ROWS * 16, 332_928);
        let plan = ProjectionPlan::new(
            1,
            2,
            3,
            vec![[0; 8]; 64],
            ImplProjectionLimits::production(),
        )
        .unwrap();
        assert_eq!(plan.words.len(), TOTAL_ROWS * 4);
        assert!(
            ProjectionPlan::new(
                1,
                2,
                3,
                vec![[0; 8]; 65],
                ImplProjectionLimits::production()
            )
            .is_err()
        );
        assert!(ImplProjectionLimits::new(4097, 0, 0).is_err());
        assert!(ImplProjectionLimits::new(0, 4097, 0).is_err());
        assert!(ImplProjectionLimits::new(0, 0, 4097).is_err());
    }
    #[test]
    fn projection_completion_rejects_stale_headers_partial_and_oversized_outputs() {
        let plan =
            ProjectionPlan::new(1, 2, 3, vec![[0; 8]], ImplProjectionLimits::production()).unwrap();
        let mut header = plan.words[..24].to_vec();
        let mut status = [0; 8];
        status[0] = 1;
        assert!(plan.completion(&header, status).is_err());
        header[23] = 1;
        assert_eq!(plan.completion(&header, status).unwrap(), [0; 3]);
        for column in 0..20 {
            let mut stale = header.clone();
            stale[column] ^= 1;
            assert!(plan.completion(&stale, status).is_err(), "column {column}");
        }
        for column in 20..23 {
            let mut oversized = header.clone();
            oversized[column] = 4097;
            assert!(plan.completion(&oversized, status).is_err());
        }
        status[0] = 2;
        assert!(plan.completion(&header, status).is_err());
        assert!(span(&[1, 2], u32::MAX, 1).is_err());
        assert!(records::<12>(&[0; 11]).is_err());
    }
}
