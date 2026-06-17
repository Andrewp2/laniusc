use super::{build_manifest::*, *};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackBuildPlan {
    pub schedule: SourcePackJobSchedule,
    pub artifacts: Vec<SourcePackArtifactPlan>,
    pub link: SourcePackLinkPlan,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackBuildArtifactEstimateSummary {
    pub artifact_manifest: SourcePackArtifactManifestSummary,
    pub artifact_lifetimes: SourcePackArtifactLifetimeSummary,
    pub job_artifacts: SourcePackJobArtifactIoSummary,
    pub job_artifact_manifest: SourcePackJobArtifactManifestSummary,
    pub link_interface_batches: SourcePackLinkInterfaceBatchSummary,
    pub link_object_batches: SourcePackLinkObjectBatchSummary,
    pub total_artifacts: usize,
    pub interface_artifacts: usize,
    pub object_artifacts: usize,
    pub linked_output_artifacts: usize,
    pub link_interface_inputs: usize,
    pub link_object_inputs: usize,
    pub artifact_use_count: usize,
}
impl SourcePackBuildPlan {
    pub fn interface_artifact_count(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::LibraryInterface)
            .count()
    }

    pub fn object_artifact_count(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::CodegenObject)
            .count()
    }

    pub fn linked_output_artifact_count(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::LinkedOutput)
            .count()
    }

    pub fn build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(batch_limits, target)
    }

    pub fn try_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn retained_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.retained_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn retained_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.try_retained_build_artifact_manifest_for_target(batch_limits, target)
            .expect("source-pack retained build artifact manifest schedule should be acyclic")
    }

    pub fn try_retained_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_retained_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.try_compact_build_artifact_manifest_for_target(batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    pub fn try_compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn try_compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let job_batch_count = self.schedule.try_for_each_execution_batch(
            batch_limits,
            |err| err,
            |_| Ok::<(), SourcePackScheduleError>(()),
        )?;
        let link_interface_batch_count = self
            .try_for_each_link_interface_batch(batch_limits, |_| {
                Ok::<(), SourcePackScheduleError>(())
            })?;
        let link_object_batch_count = self.try_for_each_link_object_batch(batch_limits, |_| {
            Ok::<(), SourcePackScheduleError>(())
        })?;
        Ok(SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: self.schedule.jobs.len(),
            job_batch_count,
            batch_dependency_count: job_batch_count,
            artifact_count: self.artifacts.len(),
            job_artifact_count: self.schedule.jobs.len(),
            job_artifact_io_count: self.schedule.jobs.len(),
            artifact_use_count: self.artifacts.len(),
            link_interface_batch_count,
            link_object_batch_count,
            job_schedule: Default::default(),
            job_batches: Default::default(),
            batch_dependencies: Default::default(),
            artifacts: Default::default(),
            job_artifacts: Default::default(),
            job_artifact_io: Default::default(),
            artifact_uses: Default::default(),
            link_interface_batches: Default::default(),
            link_object_batches: Default::default(),
        })
    }

    pub fn try_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(batch_limits, target)
    }

    pub fn try_retained_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let job_batches = self.schedule.try_execution_batches(batch_limits)?;
        let batch_dependencies = self.schedule.try_batch_dependency_plan(&job_batches)?;
        let artifacts = self.artifact_manifest_for_target(target);
        let job_artifacts = self.job_artifact_manifest_plan_for_target(target);
        let job_artifact_io = self.job_artifact_io_plan();
        let artifact_uses = self.artifact_use_plan();
        let link_interface_batches = self.link_interface_batches(batch_limits);
        let link_object_batches = self.link_object_batches(batch_limits);
        Ok(SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: self.schedule.jobs.len(),
            job_batch_count: job_batches.batches.len(),
            batch_dependency_count: batch_dependencies.batches.len(),
            artifact_count: artifacts.artifacts.len(),
            job_artifact_count: job_artifacts.jobs.len(),
            job_artifact_io_count: job_artifact_io.jobs.len(),
            artifact_use_count: artifact_uses.uses.len(),
            link_interface_batch_count: link_interface_batches.batches.len(),
            link_object_batch_count: link_object_batches.batches.len(),
            job_schedule: self.schedule.clone(),
            job_batches,
            batch_dependencies,
            artifacts,
            job_artifacts,
            job_artifact_io,
            artifact_uses,
            link_interface_batches,
            link_object_batches,
        })
    }

    pub fn artifact_use_plan(&self) -> SourcePackArtifactUsePlan {
        let mut uses = self
            .artifacts
            .iter()
            .map(|artifact| SourcePackArtifactUse {
                artifact_index: artifact.artifact_index,
                producing_job_index: artifact.producing_job_index,
                consumer_job_indices: Vec::new(),
                last_consumer_job_index: None,
            })
            .collect::<Vec<_>>();
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();

        for job in &self.schedule.jobs {
            for &dependency_job_index in &job.dependency_job_indices {
                let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                else {
                    continue;
                };
                for &artifact_index in artifact_indices {
                    if let Some(artifact_use) = uses.get_mut(artifact_index) {
                        push_unique(&mut artifact_use.consumer_job_indices, job.job_index);
                    }
                }
            }
            for dependency_job_range in self.schedule.dependency_job_ranges_for_job(job) {
                if let Some(artifact_range) = interface_artifact_range_for_job_range(
                    &artifact_indices_by_job_and_kind,
                    dependency_job_range,
                ) {
                    if let Some(artifact_indices) = artifact_range.iter() {
                        for artifact_index in artifact_indices {
                            if let Some(artifact_use) = uses.get_mut(artifact_index) {
                                push_unique(&mut artifact_use.consumer_job_indices, job.job_index);
                            }
                        }
                    }
                    continue;
                }
                let Some(dependency_job_indices) = dependency_job_range.iter() else {
                    continue;
                };
                for dependency_job_index in dependency_job_indices {
                    let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                    else {
                        continue;
                    };
                    for &artifact_index in artifact_indices {
                        if let Some(artifact_use) = uses.get_mut(artifact_index) {
                            push_unique(&mut artifact_use.consumer_job_indices, job.job_index);
                        }
                    }
                }
            }
        }

        self.link
            .try_for_each_input_interface_artifact_index(|artifact_index| {
                if let Some(artifact_use) = uses.get_mut(artifact_index) {
                    push_unique(
                        &mut artifact_use.consumer_job_indices,
                        self.link.link_job_index,
                    );
                }
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| unreachable!("infallible interface artifact use visit failed"));
        self.link
            .try_for_each_input_object_artifact_index(|artifact_index| {
                if let Some(artifact_use) = uses.get_mut(artifact_index) {
                    push_unique(
                        &mut artifact_use.consumer_job_indices,
                        self.link.link_job_index,
                    );
                }
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| unreachable!("infallible object artifact use visit failed"));

        for artifact_use in &mut uses {
            artifact_use.consumer_job_indices.sort_unstable();
            artifact_use.last_consumer_job_index =
                artifact_use.consumer_job_indices.iter().copied().max();
        }

        SourcePackArtifactUsePlan { uses }
    }

    pub fn artifact_last_use_plan(&self) -> SourcePackArtifactLastUsePlan {
        let index = self.artifact_last_use_index();
        let artifacts = self
            .artifacts
            .iter()
            .map(|artifact| SourcePackArtifactLastUse {
                artifact_index: artifact.artifact_index,
                producing_job_index: artifact.producing_job_index,
                last_consumer_job_index: index
                    .last_consumer_job_indices
                    .get(artifact.artifact_index)
                    .copied()
                    .flatten(),
            })
            .collect();
        SourcePackArtifactLastUsePlan { artifacts }
    }

    pub fn artifact_last_use_index(&self) -> SourcePackArtifactLastUseIndex {
        let mut last_consumer_job_indices = vec![None; self.artifacts.len()];
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();

        for job in &self.schedule.jobs {
            for &dependency_job_index in &job.dependency_job_indices {
                let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                else {
                    continue;
                };
                for &artifact_index in artifact_indices {
                    record_artifact_last_consumer(
                        &mut last_consumer_job_indices,
                        artifact_index,
                        job.job_index,
                    );
                }
            }
            for dependency_job_range in self.schedule.dependency_job_ranges_for_job(job) {
                if let Some(artifact_range) = interface_artifact_range_for_job_range(
                    &artifact_indices_by_job_and_kind,
                    dependency_job_range,
                ) {
                    if let Some(artifact_indices) = artifact_range.iter() {
                        for artifact_index in artifact_indices {
                            record_artifact_last_consumer(
                                &mut last_consumer_job_indices,
                                artifact_index,
                                job.job_index,
                            );
                        }
                    }
                    continue;
                }
                let Some(dependency_job_indices) = dependency_job_range.iter() else {
                    continue;
                };
                for dependency_job_index in dependency_job_indices {
                    let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                    else {
                        continue;
                    };
                    for &artifact_index in artifact_indices {
                        record_artifact_last_consumer(
                            &mut last_consumer_job_indices,
                            artifact_index,
                            job.job_index,
                        );
                    }
                }
            }
        }

        self.link
            .try_for_each_input_interface_artifact_index(|artifact_index| {
                record_artifact_last_consumer(
                    &mut last_consumer_job_indices,
                    artifact_index,
                    self.link.link_job_index,
                );
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| {
                unreachable!("infallible interface artifact last-use visit failed")
            });
        self.link
            .try_for_each_input_object_artifact_index(|artifact_index| {
                record_artifact_last_consumer(
                    &mut last_consumer_job_indices,
                    artifact_index,
                    self.link.link_job_index,
                );
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| unreachable!("infallible object artifact last-use visit failed"));

        SourcePackArtifactLastUseIndex {
            last_consumer_job_indices,
        }
    }

    pub fn artifact_lifetime_summary(&self) -> SourcePackArtifactLifetimeSummary {
        SourcePackArtifactLifetimeSummary {
            artifact_count: self.artifacts.len(),
            artifacts_without_consumers: self.artifacts.len().saturating_sub(
                self.link
                    .input_interface_artifact_count()
                    .saturating_add(self.link.input_object_artifact_count()),
            ),
        }
    }

    pub fn artifact_manifest(&self) -> SourcePackArtifactManifest {
        self.artifact_manifest_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_manifest_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> SourcePackArtifactManifest {
        SourcePackArtifactManifest {
            artifacts: self
                .artifacts
                .iter()
                .map(|artifact| SourcePackArtifactManifestEntry {
                    artifact_index: artifact.artifact_index,
                    key: artifact_key_for_target(artifact, target),
                    producing_job_index: artifact.producing_job_index,
                    kind: artifact.kind,
                    library_id: artifact.library_id,
                    first_source_index: artifact.first_source_index,
                    source_file_count: artifact.source_file_count,
                    source_bytes: artifact.source_bytes,
                    source_lines: artifact.source_lines,
                })
                .collect(),
        }
    }

    pub fn artifact_manifest_summary(&self) -> SourcePackArtifactManifestSummary {
        self.artifact_manifest_summary_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_manifest_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> SourcePackArtifactManifestSummary {
        let mut summary = SourcePackArtifactManifestSummary {
            artifact_count: self.artifacts.len(),
            max_key_len: 0,
        };
        for artifact in &self.artifacts {
            summary.max_key_len = summary
                .max_key_len
                .max(artifact_key_for_target(artifact, target).len());
        }
        summary
    }

    pub fn job_artifact_io_plan(&self) -> SourcePackJobArtifactIoPlan {
        let mut jobs = Vec::new();
        self.try_for_each_job_artifact_io(|job| {
            jobs.push(job);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible job-artifact-io collection failed"));
        SourcePackJobArtifactIoPlan { jobs }
    }

    pub fn job_artifact_io_summary(&self) -> SourcePackJobArtifactIoSummary {
        let mut summary = SourcePackJobArtifactIoSummary::default();
        self.try_for_each_job_artifact_io(|job| {
            summary.record(&job);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible job-artifact-io summary failed"));
        summary
    }

    pub fn try_for_each_job_artifact_io<F, E>(&self, mut visit: F) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobArtifactIo) -> Result<(), E>,
    {
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let mut job_count = 0usize;

        for job in &self.schedule.jobs {
            let mut input_interface_artifact_indices = Vec::new();
            let mut input_interface_artifact_ranges = Vec::new();
            let input_interface_artifact_count;
            let mut input_object_artifact_indices = Vec::new();
            let mut input_object_artifact_ranges = Vec::new();
            let mut input_object_artifact_count = 0usize;

            match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    for &dependency_job_index in &job.dependency_job_indices {
                        for &artifact_index in artifact_indices_for_job_kind(
                            &artifact_indices_by_job_and_kind,
                            dependency_job_index,
                            SourcePackArtifactKind::LibraryInterface,
                        ) {
                            push_unique(&mut input_interface_artifact_indices, artifact_index);
                        }
                    }
                    for dependency_job_range in self.schedule.dependency_job_ranges_for_job(job) {
                        push_interface_artifact_inputs_for_job_range(
                            &artifact_indices_by_job_and_kind,
                            dependency_job_range,
                            &mut input_interface_artifact_ranges,
                            &mut input_interface_artifact_indices,
                        );
                    }
                    input_interface_artifact_count =
                        input_interface_artifact_indices.len().saturating_add(
                            artifact_index_range_count(&input_interface_artifact_ranges),
                        );
                }
                SourcePackJobPhase::Link => {
                    input_interface_artifact_count = self.link.input_interface_artifact_count();
                    input_interface_artifact_ranges =
                        self.link.input_interface_artifact_ranges.clone();
                    input_interface_artifact_indices =
                        self.link.input_interface_artifact_indices.clone();
                    input_object_artifact_count = self.link.input_object_artifact_count();
                    input_object_artifact_ranges = self.link.input_object_artifact_ranges.clone();
                    input_object_artifact_indices = self.link.input_object_artifact_indices.clone();
                }
            }

            let output_artifact_indices = artifact_indices_by_job
                .get(job.job_index)
                .cloned()
                .unwrap_or_default();

            visit(SourcePackJobArtifactIo {
                job_index: job.job_index,
                phase: job.phase,
                input_interface_artifact_count,
                input_interface_artifact_ranges,
                input_interface_artifact_indices,
                input_object_artifact_count,
                input_object_artifact_ranges,
                input_object_artifact_indices,
                output_artifact_indices,
            })?;
            job_count += 1;
        }

        Ok(job_count)
    }

    pub fn job_artifact_manifest_plan(&self) -> SourcePackJobArtifactManifestPlan {
        self.job_artifact_manifest_plan_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn job_artifact_manifest_plan_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> SourcePackJobArtifactManifestPlan {
        let mut jobs = Vec::new();
        self.try_for_each_job_artifact_manifest_for_target(target, |job| {
            jobs.push(job);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible job-artifact-manifest collection failed"));
        SourcePackJobArtifactManifestPlan { jobs }
    }

    pub fn job_artifact_manifest_summary(&self) -> SourcePackJobArtifactManifestSummary {
        let io_summary = self.job_artifact_io_summary();
        SourcePackJobArtifactManifestSummary {
            job_count: io_summary.job_count,
            max_input_artifact_count: io_summary.max_input_artifact_count,
        }
    }

    pub fn try_for_each_job_artifact_manifest_for_target<F, E>(
        &self,
        target: SourcePackArtifactTarget,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobArtifactManifest) -> Result<(), E>,
    {
        let mut job_count = 0usize;
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();

        for job in &self.schedule.jobs {
            let mut input_interface_artifact_indices = Vec::new();
            let mut input_interface_ranges = Vec::new();
            let mut input_interface_artifact_ranges = Vec::new();
            let input_interface_count;
            let mut input_object_artifact_indices = Vec::new();
            let mut input_object_artifact_ranges = Vec::new();
            let mut input_object_count = 0usize;

            match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    for &dependency_job_index in &job.dependency_job_indices {
                        for &artifact_index in artifact_indices_for_job_kind(
                            &artifact_indices_by_job_and_kind,
                            dependency_job_index,
                            SourcePackArtifactKind::LibraryInterface,
                        ) {
                            push_unique(&mut input_interface_artifact_indices, artifact_index);
                        }
                    }
                    input_interface_ranges =
                        self.schedule.dependency_job_ranges_for_job(job).to_vec();
                    input_interface_count = input_interface_artifact_indices
                        .len()
                        .saturating_add(job_index_range_dependency_count(&input_interface_ranges));
                }
                SourcePackJobPhase::Link => {
                    input_interface_count = self.link.input_interface_artifact_count();
                    input_interface_artifact_ranges =
                        self.link.input_interface_artifact_ranges.clone();
                    input_interface_artifact_indices =
                        self.link.input_interface_artifact_indices.clone();
                    input_object_count = self.link.input_object_artifact_count();
                    input_object_artifact_ranges = self.link.input_object_artifact_ranges.clone();
                    input_object_artifact_indices = self.link.input_object_artifact_indices.clone();
                }
            }

            let output_artifact_indices = artifact_indices_by_job
                .get(job.job_index)
                .cloned()
                .unwrap_or_default();
            visit(SourcePackJobArtifactManifest {
                job_index: job.job_index,
                phase: job.phase,
                input_interface_count,
                input_interface_page_count: 0,
                input_interface_ranges,
                input_interface_artifact_ranges,
                input_interfaces: artifact_refs_from_indices(
                    &self.artifacts,
                    &input_interface_artifact_indices,
                    target,
                ),
                input_object_count,
                input_object_page_count: 0,
                input_object_artifact_ranges,
                input_objects: artifact_refs_from_indices(
                    &self.artifacts,
                    &input_object_artifact_indices,
                    target,
                ),
                outputs: artifact_refs_from_indices(
                    &self.artifacts,
                    &output_artifact_indices,
                    target,
                ),
            })?;
            job_count += 1;
        }
        Ok(job_count)
    }

    fn artifact_indices_by_producing_job(&self) -> Vec<Vec<usize>> {
        let max_job_index = self
            .artifacts
            .iter()
            .map(|artifact| artifact.producing_job_index)
            .max()
            .unwrap_or(0);
        let mut artifact_indices_by_job = vec![Vec::new(); max_job_index.saturating_add(1)];
        for artifact in &self.artifacts {
            if let Some(artifact_indices) =
                artifact_indices_by_job.get_mut(artifact.producing_job_index)
            {
                artifact_indices.push(artifact.artifact_index);
            }
        }
        artifact_indices_by_job
    }

    fn artifact_indices_by_producing_job_and_kind(&self) -> Vec<SourcePackArtifactIndicesByKind> {
        let max_job_index = self
            .artifacts
            .iter()
            .map(|artifact| artifact.producing_job_index)
            .max()
            .unwrap_or(0);
        let mut artifact_indices_by_job =
            vec![SourcePackArtifactIndicesByKind::default(); max_job_index.saturating_add(1)];
        for artifact in &self.artifacts {
            let Some(artifact_indices) =
                artifact_indices_by_job.get_mut(artifact.producing_job_index)
            else {
                continue;
            };
            match artifact.kind {
                SourcePackArtifactKind::LibraryInterface => {
                    artifact_indices
                        .library_interfaces
                        .push(artifact.artifact_index);
                }
                SourcePackArtifactKind::CodegenObject => {
                    artifact_indices
                        .codegen_objects
                        .push(artifact.artifact_index);
                }
                SourcePackArtifactKind::LinkedOutput => {
                    artifact_indices
                        .linked_outputs
                        .push(artifact.artifact_index);
                }
            }
        }
        artifact_indices_by_job
    }

    pub fn link_interface_batches(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkInterfaceBatchPlan {
        let mut batches = Vec::new();
        self.try_for_each_link_interface_batch(limits, |batch| {
            batches.push(batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-interface batch collection failed"));
        SourcePackLinkInterfaceBatchPlan { batches }
    }

    pub fn link_interface_batch_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkInterfaceBatchSummary {
        let mut summary = SourcePackLinkInterfaceBatchSummary::default();
        self.try_for_each_link_interface_batch(limits, |batch| {
            summary.record(&batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-interface batch summary failed"));
        summary
    }

    pub fn try_for_each_link_interface_batch<F, E>(
        &self,
        limits: SourcePackJobBatchLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackLinkInterfaceBatch) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let max_input_artifacts_per_batch = link_batch_input_limit(limits);
        let mut current_artifacts = Vec::new();
        let mut current_source_bytes = 0usize;
        let mut current_source_file_count = 0usize;
        let mut current_source_lines = 0usize;
        let mut batch_count = 0usize;

        self.link
            .try_for_each_input_interface_artifact_index(|artifact_index| {
                let Some(artifact) = self.artifacts.get(artifact_index) else {
                    return Ok(());
                };
                let should_flush = !current_artifacts.is_empty()
                    && (current_artifacts.len() >= max_input_artifacts_per_batch
                        || current_source_bytes.saturating_add(artifact.source_bytes)
                            > limits.max_source_bytes_per_batch
                        || current_source_file_count.saturating_add(artifact.source_file_count)
                            > limits.max_source_files_per_batch);
                if should_flush {
                    visit(SourcePackLinkInterfaceBatch {
                        batch_index: batch_count,
                        input_interface_artifact_indices: std::mem::take(&mut current_artifacts),
                        source_bytes: current_source_bytes,
                        source_file_count: current_source_file_count,
                        source_lines: current_source_lines,
                    })?;
                    batch_count += 1;
                    current_source_bytes = 0;
                    current_source_file_count = 0;
                    current_source_lines = 0;
                }
                current_artifacts.push(artifact_index);
                current_source_bytes = current_source_bytes.saturating_add(artifact.source_bytes);
                current_source_file_count =
                    current_source_file_count.saturating_add(artifact.source_file_count);
                current_source_lines = current_source_lines.saturating_add(artifact.source_lines);
                Ok(())
            })?;

        if !current_artifacts.is_empty() {
            visit(SourcePackLinkInterfaceBatch {
                batch_index: batch_count,
                input_interface_artifact_indices: current_artifacts,
                source_bytes: current_source_bytes,
                source_file_count: current_source_file_count,
                source_lines: current_source_lines,
            })?;
            batch_count += 1;
        }

        Ok(batch_count)
    }

    pub fn link_object_batches(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkObjectBatchPlan {
        let mut batches = Vec::new();
        self.try_for_each_link_object_batch(limits, |batch| {
            batches.push(batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-object batch collection failed"));
        SourcePackLinkObjectBatchPlan { batches }
    }

    pub fn link_object_batch_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkObjectBatchSummary {
        let mut summary = SourcePackLinkObjectBatchSummary::default();
        self.try_for_each_link_object_batch(limits, |batch| {
            summary.record(&batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-object batch summary failed"));
        summary
    }

    pub fn try_for_each_link_object_batch<F, E>(
        &self,
        limits: SourcePackJobBatchLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackLinkObjectBatch) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let max_input_artifacts_per_batch = link_batch_input_limit(limits);
        let mut current_artifacts = Vec::new();
        let mut current_source_bytes = 0usize;
        let mut current_source_file_count = 0usize;
        let mut current_source_lines = 0usize;
        let mut batch_count = 0usize;

        self.link
            .try_for_each_input_object_artifact_index(|artifact_index| {
                let Some(artifact) = self.artifacts.get(artifact_index) else {
                    return Ok(());
                };
                let should_flush = !current_artifacts.is_empty()
                    && (current_artifacts.len() >= max_input_artifacts_per_batch
                        || current_source_bytes.saturating_add(artifact.source_bytes)
                            > limits.max_source_bytes_per_batch
                        || current_source_file_count.saturating_add(artifact.source_file_count)
                            > limits.max_source_files_per_batch);
                if should_flush {
                    visit(SourcePackLinkObjectBatch {
                        batch_index: batch_count,
                        input_object_artifact_indices: std::mem::take(&mut current_artifacts),
                        source_bytes: current_source_bytes,
                        source_file_count: current_source_file_count,
                        source_lines: current_source_lines,
                    })?;
                    batch_count += 1;
                    current_source_bytes = 0;
                    current_source_file_count = 0;
                    current_source_lines = 0;
                }
                current_artifacts.push(artifact_index);
                current_source_bytes = current_source_bytes.saturating_add(artifact.source_bytes);
                current_source_file_count =
                    current_source_file_count.saturating_add(artifact.source_file_count);
                current_source_lines = current_source_lines.saturating_add(artifact.source_lines);
                Ok(())
            })?;

        if !current_artifacts.is_empty() {
            visit(SourcePackLinkObjectBatch {
                batch_index: batch_count,
                input_object_artifact_indices: current_artifacts,
                source_bytes: current_source_bytes,
                source_file_count: current_source_file_count,
                source_lines: current_source_lines,
            })?;
            batch_count += 1;
        }

        Ok(batch_count)
    }
}

pub(in crate::codegen::unit) fn artifact_refs_from_indices(
    artifacts: &[SourcePackArtifactPlan],
    artifact_indices: &[usize],
    target: SourcePackArtifactTarget,
) -> Vec<SourcePackArtifactRef> {
    artifact_indices
        .iter()
        .filter_map(|&artifact_index| artifacts.get(artifact_index))
        .map(|artifact| artifact_ref_for_plan(artifact, target))
        .collect()
}

pub(in crate::codegen::unit) fn artifact_ref_for_plan(
    artifact: &SourcePackArtifactPlan,
    target: SourcePackArtifactTarget,
) -> SourcePackArtifactRef {
    SourcePackArtifactRef {
        artifact_index: artifact.artifact_index,
        key: artifact_key_for_target(artifact, target),
        producing_job_index: artifact.producing_job_index,
        kind: artifact.kind,
    }
}

pub(in crate::codegen::unit) fn artifact_plan_for_job(
    artifact_index: usize,
    job: &SourcePackJob,
    kind: SourcePackArtifactKind,
) -> SourcePackArtifactPlan {
    SourcePackArtifactPlan {
        artifact_index,
        producing_job_index: job.job_index,
        kind,
        library_id: job.library_id,
        first_source_index: job.first_source_index,
        source_file_count: job.source_file_count,
        source_bytes: job.source_bytes,
        source_lines: job.source_lines,
    }
}

pub(in crate::codegen::unit) fn record_artifact_manifest_estimate(
    summary: &mut SourcePackArtifactManifestSummary,
    artifact: &SourcePackArtifactPlan,
    target: SourcePackArtifactTarget,
) {
    summary.artifact_count = summary.artifact_count.saturating_add(1);
    summary.max_key_len = summary
        .max_key_len
        .max(artifact_key_for_target(artifact, target).len());
}

pub(in crate::codegen::unit) fn job_phase_by_index(
    schedule: &SourcePackJobSchedule,
) -> Vec<Option<SourcePackJobPhase>> {
    let Some(max_job_index) = schedule.jobs.iter().map(|job| job.job_index).max() else {
        return Vec::new();
    };
    let mut phases = vec![None; max_job_index.saturating_add(1)];
    for job in &schedule.jobs {
        if let Some(phase) = phases.get_mut(job.job_index) {
            *phase = Some(job.phase);
        }
    }
    phases
}

pub(in crate::codegen::unit) fn record_job_artifact_io_estimate(
    summary: &mut SourcePackJobArtifactIoSummary,
    input_interface_count: usize,
    input_object_count: usize,
    output_artifact_count: usize,
) {
    summary.job_count = summary.job_count.saturating_add(1);
    summary.max_input_interface_count =
        summary.max_input_interface_count.max(input_interface_count);
    summary.max_input_object_count = summary.max_input_object_count.max(input_object_count);
    summary.max_input_artifact_count = summary
        .max_input_artifact_count
        .max(input_interface_count.saturating_add(input_object_count));
    summary.max_output_artifact_count =
        summary.max_output_artifact_count.max(output_artifact_count);
}

pub(in crate::codegen::unit) fn artifact_index_in_range(
    artifact_range: &Option<Range<usize>>,
    artifact_index: usize,
) -> bool {
    match artifact_range {
        Some(artifact_range) => artifact_range.contains(&artifact_index),
        None => false,
    }
}

pub(in crate::codegen::unit) fn record_link_input_batch_summary<F>(
    current_artifact_count: &mut usize,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    source_bytes: usize,
    source_file_count: usize,
    limits: SourcePackJobBatchLimits,
    max_input_artifacts_per_batch: usize,
    mut record_batch: F,
) where
    F: FnMut(usize, usize, usize),
{
    let should_flush = *current_artifact_count != 0
        && (*current_artifact_count >= max_input_artifacts_per_batch
            || (*current_source_bytes).saturating_add(source_bytes)
                > limits.max_source_bytes_per_batch
            || (*current_source_file_count).saturating_add(source_file_count)
                > limits.max_source_files_per_batch);
    if should_flush {
        record_batch(
            *current_artifact_count,
            *current_source_bytes,
            *current_source_file_count,
        );
        *current_artifact_count = 0;
        *current_source_bytes = 0;
        *current_source_file_count = 0;
    }
    *current_artifact_count = (*current_artifact_count).saturating_add(1);
    *current_source_bytes = (*current_source_bytes).saturating_add(source_bytes);
    *current_source_file_count = (*current_source_file_count).saturating_add(source_file_count);
}

pub(in crate::codegen::unit) fn finish_link_input_batch_summary<F>(
    current_artifact_count: &mut usize,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    mut record_batch: F,
) where
    F: FnMut(usize, usize, usize),
{
    if *current_artifact_count == 0 {
        return;
    }
    record_batch(
        *current_artifact_count,
        *current_source_bytes,
        *current_source_file_count,
    );
    *current_artifact_count = 0;
    *current_source_bytes = 0;
    *current_source_file_count = 0;
}

pub(in crate::codegen::unit) fn record_artifact_last_consumer(
    last_consumer_job_indices: &mut [Option<usize>],
    artifact_index: usize,
    consumer_job_index: usize,
) {
    if let Some(last_consumer_job_index) = last_consumer_job_indices.get_mut(artifact_index) {
        *last_consumer_job_index = last_consumer_job_index
            .map(|current| current.max(consumer_job_index))
            .or(Some(consumer_job_index));
    }
}

pub(in crate::codegen::unit) fn artifact_key_for_target(
    artifact: &SourcePackArtifactPlan,
    target: SourcePackArtifactTarget,
) -> String {
    artifact_key_for_output(
        target,
        artifact.kind,
        artifact.library_id,
        artifact.producing_job_index,
        artifact.first_source_index,
        artifact.source_file_count,
    )
}

pub fn artifact_key_for_output(
    target: SourcePackArtifactTarget,
    kind: SourcePackArtifactKind,
    library_id: u32,
    producing_job_index: usize,
    first_source_index: usize,
    source_file_count: usize,
) -> String {
    let source_end = first_source_index.saturating_add(source_file_count);
    let base_key = if kind == SourcePackArtifactKind::LinkedOutput {
        format!(
            "{}/job-{}/src-{}-{}",
            kind.key_segment(),
            producing_job_index,
            first_source_index,
            source_end
        )
    } else {
        format!(
            "{}/lib-{}/job-{}/src-{}-{}",
            kind.key_segment(),
            library_id,
            producing_job_index,
            first_source_index,
            source_end
        )
    };
    match target.key_prefix() {
        Some(prefix) => format!("{prefix}/{base_key}"),
        None => base_key,
    }
}
