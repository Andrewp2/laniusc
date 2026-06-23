use super::{build_plan::*, *};

mod model;
pub use model::*;

impl SourcePackJobSchedule {
    /// Returns compact dependency job ranges for `job_index`.
    pub fn dependency_job_ranges(&self, job_index: usize) -> &[SourcePackJobIndexRange] {
        self.dependency_job_ranges_by_job_index
            .get(job_index)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    /// Returns compact dependency job ranges for a scheduled job.
    pub fn dependency_job_ranges_for_job(&self, job: &SourcePackJob) -> &[SourcePackJobIndexRange] {
        self.dependency_job_ranges(job.job_index)
    }

    /// Counts scheduled library frontend jobs.
    pub fn frontend_job_count(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
            .count()
    }

    /// Counts scheduled backend codegen jobs.
    pub fn codegen_job_count(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::Codegen)
            .count()
    }

    /// Counts scheduled link jobs.
    pub fn link_job_count(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::Link)
            .count()
    }

    /// Returns the largest source-byte total of any job.
    pub fn max_job_source_bytes(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| job.source_bytes)
            .max()
            .unwrap_or(0)
    }

    /// Returns the largest source-file count of any job.
    pub fn max_job_source_files(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| job.source_file_count)
            .max()
            .unwrap_or(0)
    }

    /// Counts effective dependency edges across all jobs.
    pub fn dependency_edge_count(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| self.effective_dependency_count(job))
            .sum()
    }

    /// Returns the largest effective dependency count of any job.
    pub fn max_job_dependency_count(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| self.effective_dependency_count(job))
            .max()
            .unwrap_or(0)
    }

    fn effective_dependency_count(&self, job: &SourcePackJob) -> usize {
        let ranged_dependency_count =
            job_index_range_dependency_count(self.dependency_job_ranges_for_job(job));
        if job.phase == SourcePackJobPhase::Link
            && job.dependency_job_indices.is_empty()
            && ranged_dependency_count == 0
        {
            self.codegen_job_count()
        } else {
            job.dependency_job_indices
                .len()
                .saturating_add(ranged_dependency_count)
        }
    }

    /// Builds a dependency-wave schedule for this job graph.
    pub fn try_execution_waves(
        &self,
    ) -> Result<SourcePackJobWaveSchedule, SourcePackScheduleError> {
        let mut waves = Vec::new();
        self.try_for_each_execution_wave(
            |err| err,
            |wave| {
                waves.push(wave);
                Ok(())
            },
        )?;
        Ok(SourcePackJobWaveSchedule { waves })
    }

    /// Computes aggregate sizing information for dependency waves.
    pub fn try_execution_wave_summary(
        &self,
    ) -> Result<SourcePackJobWaveSummary, SourcePackScheduleError> {
        let mut summary = SourcePackJobWaveSummary::default();
        self.try_for_each_execution_wave_positions(
            |err| err,
            |_, ready_positions, source_bytes, source_file_count, _| {
                summary.record_wave(ready_positions.len(), source_bytes, source_file_count);
                Ok::<(), SourcePackScheduleError>(())
            },
        )?;
        Ok(summary)
    }

    /// Streams dependency waves to `visit` without retaining the wave schedule.
    pub fn try_for_each_execution_wave<F, E, M>(
        &self,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobWave) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        self.try_for_each_execution_wave_positions(
            map_schedule_error,
            |wave_index, ready_positions, source_bytes, source_file_count, source_lines| {
                let job_indices = ready_positions
                    .iter()
                    .map(|&position| self.jobs[position].job_index)
                    .collect::<Vec<_>>();
                visit(SourcePackJobWave {
                    wave_index,
                    job_indices,
                    source_bytes,
                    source_file_count,
                    source_lines,
                })
            },
        )
    }

    fn try_for_each_execution_wave_positions<F, E, M>(
        &self,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(usize, &[usize], usize, usize, usize) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        let max_job_index = self.jobs.iter().map(|job| job.job_index).max().unwrap_or(0);
        let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
        for (position, job) in self.jobs.iter().enumerate() {
            if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
                *slot = Some(position);
            }
        }

        let codegen_job_count = self.codegen_job_count();
        let mut emitted_by_position = vec![false; self.jobs.len()];
        let mut completed_job_ranges = Vec::new();
        let mut emitted_codegen_count = 0usize;
        let mut ready_positions = self
            .jobs
            .iter()
            .enumerate()
            .filter_map(|(position, job)| {
                job_dependencies_satisfied(
                    job,
                    self.dependency_job_ranges_for_job(job),
                    &job_position_by_index,
                    &emitted_by_position,
                    &completed_job_ranges,
                    emitted_codegen_count,
                    codegen_job_count,
                )
                .then_some(position)
            })
            .collect::<Vec<_>>();
        let mut emitted_count = 0usize;
        let mut wave_count = 0usize;

        while !ready_positions.is_empty() {
            ready_positions.sort_unstable();
            let mut source_bytes = 0usize;
            let mut source_file_count = 0usize;
            let mut source_lines = 0usize;

            for &position in &ready_positions {
                let job = &self.jobs[position];
                source_bytes = source_bytes.saturating_add(job.source_bytes);
                source_file_count = source_file_count.saturating_add(job.source_file_count);
                source_lines = source_lines.saturating_add(job.source_lines);
            }
            visit(
                wave_count,
                &ready_positions,
                source_bytes,
                source_file_count,
                source_lines,
            )?;
            wave_count += 1;

            let mut next_ready_positions = BTreeSet::new();
            for &position in &ready_positions {
                emitted_by_position[position] = true;
                emitted_count += 1;
                let job_index = self.jobs[position].job_index;
                push_completed_job_range(&mut completed_job_ranges, job_index);
                if self.jobs[position].phase == SourcePackJobPhase::Codegen {
                    emitted_codegen_count = emitted_codegen_count.saturating_add(1);
                }
            }
            for (position, job) in self.jobs.iter().enumerate() {
                if emitted_by_position[position] {
                    continue;
                }
                if job_dependencies_satisfied(
                    job,
                    self.dependency_job_ranges_for_job(job),
                    &job_position_by_index,
                    &emitted_by_position,
                    &completed_job_ranges,
                    emitted_codegen_count,
                    codegen_job_count,
                ) {
                    next_ready_positions.insert(position);
                }
            }
            ready_positions = next_ready_positions.into_iter().collect();
        }

        if emitted_count != self.jobs.len() {
            let unscheduled_job_indices = self
                .jobs
                .iter()
                .zip(emitted_by_position.iter().copied())
                .filter_map(|(job, emitted)| (!emitted).then_some(job.job_index))
                .collect();
            return Err(map_schedule_error(SourcePackScheduleError {
                unscheduled_job_indices,
            }));
        }

        Ok(wave_count)
    }

    /// Builds a bounded batch schedule from dependency waves.
    pub fn try_execution_batches(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackJobBatchSchedule, SourcePackScheduleError> {
        let mut batches = Vec::new();
        self.try_for_each_execution_batch(
            limits,
            |err| err,
            |batch| {
                batches.push(batch);
                Ok(())
            },
        )?;

        Ok(SourcePackJobBatchSchedule { batches })
    }

    /// Computes aggregate sizing information for execution batches.
    pub fn try_execution_batch_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackJobBatchSummary, SourcePackScheduleError> {
        let mut summary = SourcePackJobBatchSummary::default();
        self.try_for_each_execution_batch(
            limits,
            |err| err,
            |batch| {
                summary.record(&batch);
                Ok::<(), SourcePackScheduleError>(())
            },
        )?;
        Ok(summary)
    }

    /// Streams execution batches to `visit` without retaining the schedule.
    pub fn try_for_each_execution_batch<F, E, M>(
        &self,
        limits: SourcePackJobBatchLimits,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobBatch) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        let limits = limits.normalized();
        let mut batch_count = 0usize;
        self.try_for_each_execution_wave_positions(
            map_schedule_error,
            |wave_index, ready_positions, _, _, _| {
                let mut batch = SourcePackJobBatchBuilder::new(wave_index);
                for &position in ready_positions {
                    let job = &self.jobs[position];
                    if batch.should_flush_before(job, limits) {
                        if let Some(batch) = batch.take_batch(batch_count, limits) {
                            visit(batch)?;
                            batch_count += 1;
                        }
                    }
                    batch.push(job);
                }
                if let Some(batch) = batch.take_batch(batch_count, limits) {
                    visit(batch)?;
                    batch_count += 1;
                }
                Ok(())
            },
        )?;

        Ok(batch_count)
    }

    /// Builds compact dependency records for an execution batch schedule.
    pub fn try_batch_dependency_plan(
        &self,
        batches: &SourcePackJobBatchSchedule,
    ) -> Result<SourcePackJobBatchDependencyPlan, SourcePackScheduleError> {
        let mut batch_dependencies = Vec::new();
        self.try_for_each_batch_dependency(
            batches,
            |err| err,
            |dependency| {
                batch_dependencies.push(dependency);
                Ok(())
            },
        )?;

        Ok(SourcePackJobBatchDependencyPlan {
            batches: batch_dependencies,
        })
    }

    /// Computes aggregate sizing information for batch dependency records.
    pub fn try_execution_batch_dependency_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackJobBatchDependencySummary, SourcePackScheduleError> {
        let max_job_index = self.jobs.iter().map(|job| job.job_index).max().unwrap_or(0);
        let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
        for (position, job) in self.jobs.iter().enumerate() {
            if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
                *slot = Some(position);
            }
        }

        let mut batch_index_by_job_index = vec![None; max_job_index.saturating_add(1)];
        let mut codegen_batch_ranges = Vec::new();
        let mut summary = SourcePackJobBatchDependencySummary::default();
        self.try_for_each_execution_batch(
            limits,
            |err| err,
            |batch| {
                let mut contains_codegen_job = false;
                for &job_index in &batch.job_indices {
                    let Some(position) = job_position_by_index
                        .get(job_index)
                        .and_then(|position| *position)
                    else {
                        return Err(SourcePackScheduleError {
                            unscheduled_job_indices: vec![job_index],
                        });
                    };
                    let Some(slot) = batch_index_by_job_index.get_mut(job_index) else {
                        return Err(SourcePackScheduleError {
                            unscheduled_job_indices: vec![job_index],
                        });
                    };
                    *slot = Some(batch.batch_index);
                    contains_codegen_job |=
                        self.jobs[position].phase == SourcePackJobPhase::Codegen;
                }
                if contains_codegen_job {
                    push_dependency_batch_indices_as_ranges(
                        &mut codegen_batch_ranges,
                        std::iter::once(batch.batch_index),
                    );
                }

                let mut dependency_batch_indices = BTreeSet::new();
                let mut dependency_batch_ranges = Vec::new();
                for &job_index in &batch.job_indices {
                    let Some(position) = job_position_by_index
                        .get(job_index)
                        .and_then(|position| *position)
                    else {
                        return Err(SourcePackScheduleError {
                            unscheduled_job_indices: vec![job_index],
                        });
                    };
                    for &dependency_job_index in &self.jobs[position].dependency_job_indices {
                        let Some(dependency_batch_index) = batch_index_by_job_index
                            .get(dependency_job_index)
                            .and_then(|batch_index| *batch_index)
                        else {
                            return Err(SourcePackScheduleError {
                                unscheduled_job_indices: vec![dependency_job_index],
                            });
                        };
                        if dependency_batch_index != batch.batch_index {
                            dependency_batch_indices.insert(dependency_batch_index);
                        }
                    }
                    for dependency_job_range in
                        self.dependency_job_ranges_for_job(&self.jobs[position])
                    {
                        push_dependency_batch_range_for_job_range(
                            &mut dependency_batch_ranges,
                            &dependency_batch_indices,
                            &batch_index_by_job_index,
                            dependency_job_range,
                            batch.batch_index,
                        )?;
                    }
                    if self.jobs[position].phase == SourcePackJobPhase::Link
                        && self.jobs[position].dependency_job_indices.is_empty()
                        && self
                            .dependency_job_ranges_for_job(&self.jobs[position])
                            .is_empty()
                    {
                        push_dependency_batch_ranges_excluding_batch(
                            &mut dependency_batch_ranges,
                            &codegen_batch_ranges,
                            batch.batch_index,
                        );
                    }
                }
                let dependency_count = dependency_batch_indices.len().saturating_add(
                    dependency_batch_ranges.iter().fold(0usize, |count, range| {
                        count.saturating_add(range.batch_count)
                    }),
                );
                summary.record_dependency_count(dependency_count);
                Ok(())
            },
        )?;
        Ok(summary)
    }

    /// Streams batch dependency records for an execution batch schedule.
    pub fn try_for_each_batch_dependency<F, E, M>(
        &self,
        batches: &SourcePackJobBatchSchedule,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobBatchDependency) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        let max_job_index = self.jobs.iter().map(|job| job.job_index).max().unwrap_or(0);
        let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
        for (position, job) in self.jobs.iter().enumerate() {
            if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
                *slot = Some(position);
            }
        }

        let mut batch_index_by_job_index = vec![None; max_job_index.saturating_add(1)];
        let mut codegen_batch_ranges = Vec::new();
        for batch in &batches.batches {
            let mut contains_codegen_job = false;
            for &job_index in &batch.job_indices {
                let Some(position) = job_position_by_index
                    .get(job_index)
                    .and_then(|position| *position)
                else {
                    return Err(map_schedule_error(SourcePackScheduleError {
                        unscheduled_job_indices: vec![job_index],
                    }));
                };
                let Some(slot) = batch_index_by_job_index.get_mut(job_index) else {
                    return Err(map_schedule_error(SourcePackScheduleError {
                        unscheduled_job_indices: vec![job_index],
                    }));
                };
                *slot = Some(batch.batch_index);
                contains_codegen_job |= self.jobs[position].phase == SourcePackJobPhase::Codegen;
            }
            if contains_codegen_job {
                push_dependency_batch_indices_as_ranges(
                    &mut codegen_batch_ranges,
                    std::iter::once(batch.batch_index),
                );
            }
        }

        let mut batch_dependency_count = 0usize;
        for batch in &batches.batches {
            let mut dependency_batch_indices = BTreeSet::new();
            let mut dependency_batch_ranges = Vec::new();
            for &job_index in &batch.job_indices {
                let Some(position) = job_position_by_index
                    .get(job_index)
                    .and_then(|position| *position)
                else {
                    return Err(map_schedule_error(SourcePackScheduleError {
                        unscheduled_job_indices: vec![job_index],
                    }));
                };
                for &dependency_job_index in &self.jobs[position].dependency_job_indices {
                    let Some(dependency_batch_index) = batch_index_by_job_index
                        .get(dependency_job_index)
                        .and_then(|batch_index| *batch_index)
                    else {
                        return Err(map_schedule_error(SourcePackScheduleError {
                            unscheduled_job_indices: vec![dependency_job_index],
                        }));
                    };
                    if dependency_batch_index != batch.batch_index {
                        dependency_batch_indices.insert(dependency_batch_index);
                    }
                }
                for dependency_job_range in self.dependency_job_ranges_for_job(&self.jobs[position])
                {
                    push_dependency_batch_range_for_job_range(
                        &mut dependency_batch_ranges,
                        &dependency_batch_indices,
                        &batch_index_by_job_index,
                        dependency_job_range,
                        batch.batch_index,
                    )
                    .map_err(map_schedule_error)?;
                }
                if self.jobs[position].phase == SourcePackJobPhase::Link
                    && self.jobs[position].dependency_job_indices.is_empty()
                    && self
                        .dependency_job_ranges_for_job(&self.jobs[position])
                        .is_empty()
                {
                    push_dependency_batch_ranges_excluding_batch(
                        &mut dependency_batch_ranges,
                        &codegen_batch_ranges,
                        batch.batch_index,
                    );
                }
            }
            let dependency_range_count = dependency_batch_ranges.len();
            let dependency_range_batch_count =
                dependency_batch_ranges.iter().fold(0usize, |count, range| {
                    count.saturating_add(range.batch_count)
                });
            visit(SourcePackJobBatchDependency {
                batch_index: batch.batch_index,
                dependency_batch_count: 0,
                dependency_page_count: 0,
                dependency_range_count,
                dependency_range_page_count: 0,
                dependency_range_batch_count,
                dependency_batch_indices: dependency_batch_indices.into_iter().collect(),
                dependency_batch_ranges,
            })?;
            batch_dependency_count += 1;
        }

        Ok(batch_dependency_count)
    }
}
impl SourcePackJobPlan {
    /// Builds a single-library source-pack job plan from in-memory sources.
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S], limits: CodegenUnitLimits) -> Self {
        Self::from_file_stream_with_dependencies(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            &[],
            limits,
        )
    }

    /// Builds a job plan from sources and explicit library ids.
    pub fn from_source_pack_with_libraries<S, L>(
        sources: &[S],
        library_ids: &[L],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        Self::from_source_pack_with_libraries_and_dependencies(sources, library_ids, &[], limits)
    }

    /// Builds a job plan from sources, library ids, and library dependencies.
    pub fn from_source_pack_with_libraries_and_dependencies<S, L>(
        sources: &[S],
        library_ids: &[L],
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        Self::from_file_stream_with_dependencies(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            library_dependencies,
            limits,
        )
    }

    /// Builds a job plan from precomputed source-file facts.
    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        Self::from_files_with_dependencies(files, &[], limits)
    }

    /// Builds a job plan from precomputed source-file facts and dependencies.
    pub fn from_files_with_dependencies(
        files: &[SourceFileUnitInput],
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Self {
        Self::from_file_stream_with_dependencies(
            files.iter().copied(),
            library_dependencies,
            limits,
        )
    }

    /// Builds a job plan from a streaming source-file iterator.
    pub fn from_file_stream_with_dependencies<I>(
        files: I,
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
    {
        Self::try_from_fallible_file_stream_with_dependencies(
            files.into_iter().map(|file| Ok::<_, ()>(file)),
            library_dependencies,
            limits,
        )
        .unwrap_or_else(|()| unreachable!("infallible source-pack job-plan collection failed"))
    }

    /// Builds a job plan from a fallible streaming source-file iterator.
    pub fn try_from_fallible_file_stream_with_dependencies<I, E>(
        files: I,
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Result<Self, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
    {
        let mut builder = SourcePackJobPlanBuilder::new(limits);
        for file in files {
            builder.push(file?);
        }
        Ok(builder.finish(library_dependencies))
    }

    /// Returns whether the source pack must run more than one codegen job.
    pub fn requires_multiple_codegen_jobs(&self) -> bool {
        self.codegen_units.unit_count() > 1
    }

    /// Returns whether any library is split into multiple frontend jobs.
    pub fn requires_multiple_frontend_jobs(&self) -> bool {
        self.frontend_units.unit_count() > self.libraries.library_count()
    }

    /// Builds the default job schedule with one frontend job per library.
    pub fn job_schedule(&self) -> SourcePackJobSchedule {
        let dependency_index = self.library_dependency_index();
        let library_order = self.topological_library_indices(&dependency_index);
        let mut frontend_job_index_by_library_index = vec![None; self.libraries.libraries.len()];
        for (frontend_job_index, &library_index) in library_order.iter().enumerate() {
            if let Some(slot) = frontend_job_index_by_library_index.get_mut(library_index) {
                *slot = Some(frontend_job_index);
            }
        }
        let mut jobs = Vec::with_capacity(
            self.libraries
                .library_count()
                .saturating_add(self.codegen_units.unit_count())
                .saturating_add(1),
        );

        for &library_index in &library_order {
            let library = &self.libraries.libraries[library_index];
            let dependency_job_indices = self
                .dependency_library_indices_for_library(library.library_id, &dependency_index)
                .iter()
                .filter_map(|&dependency_library_index| {
                    frontend_job_index_by_library_index
                        .get(dependency_library_index)
                        .and_then(|job_index| *job_index)
                })
                .collect::<Vec<_>>();
            let mut dependency_job_indices = dependency_job_indices;
            normalize_dependency_indices(&mut dependency_job_indices);
            jobs.push(SourcePackJob {
                job_index: jobs.len(),
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: library.library_index,
                library_job_index: None,
                library_id: library.library_id,
                first_source_index: library.first_source_index,
                source_file_count: library.source_file_count,
                source_bytes: library.source_bytes,
                source_lines: library.source_lines,
                oversized_source_file: false,
                dependency_job_indices,
            });
        }

        let mut library_index_cursor = 0usize;
        for unit in &self.codegen_units.units {
            let unit_range = unit.source_range();
            while self
                .libraries
                .libraries
                .get(library_index_cursor)
                .is_some_and(|library| library.source_range().end <= unit_range.start)
            {
                library_index_cursor += 1;
            }
            let library_index = self
                .libraries
                .libraries
                .get(library_index_cursor)
                .filter(|library| range_contains_range(library.source_range(), unit_range.clone()))
                .map(|library| library.library_index);
            let library_job_index = library_index
                .and_then(|index| frontend_job_index_by_library_index.get(index).copied())
                .flatten();
            let library_id = self
                .libraries
                .libraries
                .get(library_index_cursor)
                .filter(|library| range_contains_range(library.source_range(), unit_range))
                .map(|library| library.library_id)
                .unwrap_or(unit.library_id);
            let mut dependency_job_indices = Vec::new();
            if let Some(library_job_index) = library_job_index {
                push_unique(&mut dependency_job_indices, library_job_index);
            }
            for dependency_library_index in
                self.dependency_library_indices_for_library(library_id, &dependency_index)
            {
                if let Some(dependency_job_index) = frontend_job_index_by_library_index
                    .get(*dependency_library_index)
                    .and_then(|job_index| *job_index)
                {
                    push_unique(&mut dependency_job_indices, dependency_job_index);
                }
            }
            normalize_dependency_indices(&mut dependency_job_indices);
            jobs.push(SourcePackJob {
                job_index: jobs.len(),
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: unit.unit_index,
                library_job_index,
                library_id: unit.library_id,
                first_source_index: unit.first_source_index,
                source_file_count: unit.source_file_count,
                source_bytes: unit.source_bytes,
                source_lines: unit.source_lines,
                oversized_source_file: unit.oversized_source_file,
                dependency_job_indices,
            });
        }

        jobs.push(SourcePackJob {
            job_index: jobs.len(),
            phase: SourcePackJobPhase::Link,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: 0,
            source_bytes: 0,
            source_lines: 0,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        });

        SourcePackJobSchedule {
            jobs,
            dependency_job_ranges_by_job_index: Vec::new(),
        }
    }

    /// Builds a job schedule that honors bounded frontend units.
    pub fn bounded_frontend_job_schedule(&self) -> SourcePackJobSchedule {
        let dependency_index = self.library_dependency_index();
        let library_order = self.topological_library_indices(&dependency_index);
        let mut frontend_job_ranges_by_library_index = vec![None; self.libraries.libraries.len()];
        let mut frontend_job_index_by_unit_index = vec![None; self.frontend_units.unit_count()];
        let mut jobs = Vec::with_capacity(
            self.frontend_units
                .unit_count()
                .saturating_add(self.codegen_units.unit_count())
                .saturating_add(1),
        );
        let mut dependency_job_ranges_by_job_index = Vec::with_capacity(jobs.capacity());

        for &library_index in &library_order {
            let library = &self.libraries.libraries[library_index];
            let dependency_job_ranges = self
                .dependency_library_indices_for_library(library.library_id, &dependency_index)
                .iter()
                .filter_map(|&dependency_library_index| {
                    frontend_job_ranges_by_library_index
                        .get(dependency_library_index)
                        .and_then(|range| range.clone())
                })
                .collect::<Vec<_>>();
            let dependency_job_ranges = compact_job_index_ranges(dependency_job_ranges);
            let first_frontend_job_index = jobs.len();
            let frontend_units = self.frontend_units_for_library(library);
            for frontend_unit in frontend_units {
                let job_index = jobs.len();
                jobs.push(SourcePackJob {
                    job_index,
                    phase: SourcePackJobPhase::LibraryFrontend,
                    phase_unit_index: frontend_unit.unit_index,
                    library_job_index: None,
                    library_id: frontend_unit.library_id,
                    first_source_index: frontend_unit.first_source_index,
                    source_file_count: frontend_unit.source_file_count,
                    source_bytes: frontend_unit.source_bytes,
                    source_lines: frontend_unit.source_lines,
                    oversized_source_file: frontend_unit.oversized_source_file,
                    dependency_job_indices: Vec::new(),
                });
                dependency_job_ranges_by_job_index.push(dependency_job_ranges.clone());
                if let Some(slot) =
                    frontend_job_index_by_unit_index.get_mut(frontend_unit.unit_index)
                {
                    *slot = Some(job_index);
                }
            }
            let frontend_job_count = jobs.len().saturating_sub(first_frontend_job_index);
            if frontend_job_count != 0 {
                frontend_job_ranges_by_library_index[library_index] =
                    Some(SourcePackJobIndexRange {
                        first_job_index: first_frontend_job_index,
                        job_count: frontend_job_count,
                    });
            }
        }

        let mut library_index_cursor = 0usize;
        let mut frontend_unit_cursor = 0usize;
        for unit in &self.codegen_units.units {
            let unit_range = unit.source_range();
            while self
                .libraries
                .libraries
                .get(library_index_cursor)
                .is_some_and(|library| library.source_range().end <= unit_range.start)
            {
                library_index_cursor += 1;
            }
            let library_index = self
                .libraries
                .libraries
                .get(library_index_cursor)
                .filter(|library| range_contains_range(library.source_range(), unit_range.clone()))
                .map(|library| library.library_index);
            let frontend_unit = library_index.and_then(|index| {
                self.frontend_unit_for_range_from_cursor(
                    index,
                    &mut frontend_unit_cursor,
                    unit.source_range(),
                )
            });
            let library_job_index = frontend_unit.and_then(|frontend_unit| {
                frontend_job_index_by_unit_index
                    .get(frontend_unit.unit_index)
                    .copied()
                    .flatten()
            });
            let mut dependency_job_indices = Vec::new();
            if let Some(library_job_index) = library_job_index {
                push_unique(&mut dependency_job_indices, library_job_index);
            }
            let mut dependency_job_ranges = Vec::new();
            if let (Some(library_index), Some(library_job_index)) =
                (library_index, library_job_index)
            {
                if let Some(Some(frontend_range)) =
                    frontend_job_ranges_by_library_index.get(library_index)
                {
                    if frontend_range.first_job_index < library_job_index {
                        dependency_job_ranges.push(SourcePackJobIndexRange {
                            first_job_index: frontend_range.first_job_index,
                            job_count: library_job_index - frontend_range.first_job_index,
                        });
                    }
                    let after_library_job_index = library_job_index.saturating_add(1);
                    if let Some(frontend_range_end) = frontend_range.end_job_index() {
                        if after_library_job_index < frontend_range_end {
                            dependency_job_ranges.push(SourcePackJobIndexRange {
                                first_job_index: after_library_job_index,
                                job_count: frontend_range_end - after_library_job_index,
                            });
                        }
                    }
                }
                let library_id = self
                    .libraries
                    .libraries
                    .get(library_index)
                    .map(|library| library.library_id)
                    .unwrap_or(unit.library_id);
                for dependency_library_index in
                    self.dependency_library_indices_for_library(library_id, &dependency_index)
                {
                    if let Some(Some(frontend_range)) =
                        frontend_job_ranges_by_library_index.get(*dependency_library_index)
                    {
                        dependency_job_ranges.push(frontend_range.clone());
                    }
                }
            }
            normalize_dependency_indices(&mut dependency_job_indices);
            dependency_job_ranges = compact_job_index_ranges(dependency_job_ranges);
            jobs.push(SourcePackJob {
                job_index: jobs.len(),
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: unit.unit_index,
                library_job_index,
                library_id: unit.library_id,
                first_source_index: unit.first_source_index,
                source_file_count: unit.source_file_count,
                source_bytes: unit.source_bytes,
                source_lines: unit.source_lines,
                oversized_source_file: unit.oversized_source_file,
                dependency_job_indices,
            });
            dependency_job_ranges_by_job_index.push(dependency_job_ranges);
        }

        jobs.push(SourcePackJob {
            job_index: jobs.len(),
            phase: SourcePackJobPhase::Link,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: 0,
            source_bytes: 0,
            source_lines: 0,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        });
        dependency_job_ranges_by_job_index.push(Vec::new());

        SourcePackJobSchedule {
            jobs,
            dependency_job_ranges_by_job_index,
        }
    }

    /// Builds a compact generic artifact manifest with count-only payloads.
    pub fn compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    /// Builds a compact artifact manifest for a concrete target.
    pub fn compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.try_compact_build_artifact_manifest_for_target(batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    /// Tries to build a compact generic artifact manifest with count-only payloads.
    pub fn try_compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    /// Tries to build a compact artifact manifest for a concrete target.
    pub fn try_compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let schedule = self.job_schedule();
        self.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
    }

    /// Tries to build a compact artifact manifest from a caller-provided schedule.
    pub fn try_compact_build_artifact_manifest_for_schedule(
        &self,
        schedule: &SourcePackJobSchedule,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let job_batches = schedule.try_execution_batch_summary(batch_limits)?;
        let batch_dependencies = schedule.try_execution_batch_dependency_summary(batch_limits)?;
        let artifact_estimate =
            self.build_artifact_estimate_summary_for_schedule(schedule, batch_limits, target);
        Ok(SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: schedule.jobs.len(),
            job_batch_count: job_batches.batch_count(),
            batch_dependency_count: batch_dependencies.batch_count(),
            artifact_count: artifact_estimate.total_artifacts,
            job_artifact_count: artifact_estimate.job_artifacts.job_count,
            job_artifact_io_count: artifact_estimate.job_artifacts.job_count,
            artifact_use_count: artifact_estimate.artifact_use_count,
            link_interface_batch_count: artifact_estimate.link_interface_batches.batch_count(),
            link_object_batch_count: artifact_estimate.link_object_batches.batch_count(),
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

    /// Estimates artifact, IO, and link-batch counts for the default schedule.
    pub fn build_artifact_estimate_summary(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactEstimateSummary {
        let schedule = self.job_schedule();
        self.build_artifact_estimate_summary_for_schedule(
            &schedule,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    /// Estimates artifact, IO, and link-batch counts for a caller-provided schedule.
    pub fn build_artifact_estimate_summary_for_schedule(
        &self,
        schedule: &SourcePackJobSchedule,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactEstimateSummary {
        let mut estimate = SourcePackBuildArtifactEstimateSummary::default();
        let mut artifact_index = 0usize;
        let mut first_interface_artifact_index = None;
        let mut first_object_artifact_index = None;
        let total_source_file_count = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_range().end)
            .max()
            .unwrap_or(0);
        let total_source_bytes = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_bytes)
            .sum::<usize>();
        let total_source_lines = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_lines)
            .sum::<usize>();

        for job in &schedule.jobs {
            let kind = match job.phase {
                SourcePackJobPhase::LibraryFrontend => {
                    first_interface_artifact_index.get_or_insert(artifact_index);
                    estimate.interface_artifacts = estimate.interface_artifacts.saturating_add(1);
                    SourcePackArtifactKind::LibraryInterface
                }
                SourcePackJobPhase::Codegen => {
                    first_object_artifact_index.get_or_insert(artifact_index);
                    estimate.object_artifacts = estimate.object_artifacts.saturating_add(1);
                    SourcePackArtifactKind::CodegenObject
                }
                SourcePackJobPhase::Link => continue,
            };
            let artifact = artifact_plan_for_job(artifact_index, job, kind);
            record_artifact_manifest_estimate(&mut estimate.artifact_manifest, &artifact, target);
            artifact_index = artifact_index.saturating_add(1);
        }

        let link_job_index = schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index)
            .unwrap_or(schedule.jobs.len());
        let output_artifact = SourcePackArtifactPlan {
            artifact_index,
            producing_job_index: link_job_index,
            kind: SourcePackArtifactKind::LinkedOutput,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: total_source_file_count,
            source_bytes: total_source_bytes,
            source_lines: total_source_lines,
        };
        record_artifact_manifest_estimate(
            &mut estimate.artifact_manifest,
            &output_artifact,
            target,
        );
        estimate.linked_output_artifacts = 1;
        estimate.total_artifacts = estimate.artifact_manifest.artifact_count;
        estimate.artifact_use_count = estimate.total_artifacts;
        estimate.link_interface_inputs = estimate.interface_artifacts;
        estimate.link_object_inputs = estimate.object_artifacts;
        estimate.artifact_lifetimes = SourcePackArtifactLifetimeSummary {
            artifact_count: estimate.total_artifacts,
            artifacts_without_consumers: estimate.total_artifacts.saturating_sub(
                estimate
                    .link_interface_inputs
                    .saturating_add(estimate.link_object_inputs),
            ),
        };

        let phases_by_job_index = job_phase_by_index(schedule);
        for job in &schedule.jobs {
            let (input_interface_count, input_object_count) = match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    let mut dependency_interface_jobs = Vec::new();
                    for &dependency_job_index in &job.dependency_job_indices {
                        if matches!(
                            phases_by_job_index.get(dependency_job_index),
                            Some(Some(SourcePackJobPhase::LibraryFrontend))
                        ) {
                            push_unique(&mut dependency_interface_jobs, dependency_job_index);
                        }
                    }
                    let ranged_dependency_interface_count = schedule
                        .dependency_job_ranges_for_job(job)
                        .iter()
                        .fold(0usize, |count, range| count.saturating_add(range.job_count));
                    (
                        dependency_interface_jobs
                            .len()
                            .saturating_add(ranged_dependency_interface_count),
                        0,
                    )
                }
                SourcePackJobPhase::Link => {
                    (estimate.interface_artifacts, estimate.object_artifacts)
                }
            };
            let output_artifact_count = match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => 1,
                SourcePackJobPhase::Link => usize::from(job.job_index == link_job_index),
            };
            record_job_artifact_io_estimate(
                &mut estimate.job_artifacts,
                input_interface_count,
                input_object_count,
                output_artifact_count,
            );
        }
        estimate.job_artifact_manifest = SourcePackJobArtifactManifestSummary {
            job_count: estimate.job_artifacts.job_count,
            max_input_artifact_count: estimate.job_artifacts.max_input_artifact_count,
        };

        let limits = batch_limits.normalized();
        let max_input_artifacts_per_batch = link_batch_input_limit(limits);
        let interface_artifact_range = first_interface_artifact_index
            .filter(|_| estimate.interface_artifacts != 0)
            .map(|first| first..first.saturating_add(estimate.interface_artifacts));
        let object_artifact_range = first_object_artifact_index
            .filter(|_| estimate.object_artifacts != 0)
            .map(|first| first..first.saturating_add(estimate.object_artifacts));
        let mut interface_batch_artifact_count = 0usize;
        let mut interface_batch_source_bytes = 0usize;
        let mut interface_batch_source_files = 0usize;
        let mut object_batch_artifact_count = 0usize;
        let mut object_batch_source_bytes = 0usize;
        let mut object_batch_source_files = 0usize;
        let mut artifact_index = 0usize;
        for job in &schedule.jobs {
            let kind = match job.phase {
                SourcePackJobPhase::LibraryFrontend => SourcePackArtifactKind::LibraryInterface,
                SourcePackJobPhase::Codegen => SourcePackArtifactKind::CodegenObject,
                SourcePackJobPhase::Link => continue,
            };
            let artifact = artifact_plan_for_job(artifact_index, job, kind);
            if artifact_index_in_range(&interface_artifact_range, artifact.artifact_index) {
                record_link_input_batch_summary(
                    &mut interface_batch_artifact_count,
                    &mut interface_batch_source_bytes,
                    &mut interface_batch_source_files,
                    artifact.source_bytes,
                    artifact.source_file_count,
                    limits,
                    max_input_artifacts_per_batch,
                    |artifact_count, source_bytes, source_file_count| {
                        estimate.link_interface_batches.record_batch_counts(
                            artifact_count,
                            source_bytes,
                            source_file_count,
                        );
                    },
                );
            }
            if artifact_index_in_range(&object_artifact_range, artifact.artifact_index) {
                record_link_input_batch_summary(
                    &mut object_batch_artifact_count,
                    &mut object_batch_source_bytes,
                    &mut object_batch_source_files,
                    artifact.source_bytes,
                    artifact.source_file_count,
                    limits,
                    max_input_artifacts_per_batch,
                    |artifact_count, source_bytes, source_file_count| {
                        estimate.link_object_batches.record_batch_counts(
                            artifact_count,
                            source_bytes,
                            source_file_count,
                        );
                    },
                );
            }
            artifact_index = artifact_index.saturating_add(1);
        }
        finish_link_input_batch_summary(
            &mut interface_batch_artifact_count,
            &mut interface_batch_source_bytes,
            &mut interface_batch_source_files,
            |artifact_count, source_bytes, source_file_count| {
                estimate.link_interface_batches.record_batch_counts(
                    artifact_count,
                    source_bytes,
                    source_file_count,
                );
            },
        );
        finish_link_input_batch_summary(
            &mut object_batch_artifact_count,
            &mut object_batch_source_bytes,
            &mut object_batch_source_files,
            |artifact_count, source_bytes, source_file_count| {
                estimate.link_object_batches.record_batch_counts(
                    artifact_count,
                    source_bytes,
                    source_file_count,
                );
            },
        );

        estimate
    }

    /// Builds a retained artifact plan for the default job schedule.
    pub fn build_plan(&self) -> SourcePackBuildPlan {
        self.build_plan_for_schedule(self.job_schedule())
    }

    /// Builds a retained artifact plan using bounded frontend units.
    pub fn bounded_frontend_build_plan(&self) -> SourcePackBuildPlan {
        self.build_plan_for_schedule(self.bounded_frontend_job_schedule())
    }

    fn build_plan_for_schedule(&self, schedule: SourcePackJobSchedule) -> SourcePackBuildPlan {
        let mut artifacts = Vec::with_capacity(schedule.jobs.len());
        let mut first_interface_artifact_index = None;
        let mut interface_artifact_count = 0usize;
        let mut first_object_artifact_index = None;
        let mut object_artifact_count = 0usize;
        let total_source_file_count = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_range().end)
            .max()
            .unwrap_or(0);
        let total_source_bytes = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_bytes)
            .sum::<usize>();
        let total_source_lines = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_lines)
            .sum::<usize>();

        for job in &schedule.jobs {
            match job.phase {
                SourcePackJobPhase::LibraryFrontend => {
                    first_interface_artifact_index.get_or_insert(artifacts.len());
                    interface_artifact_count = interface_artifact_count.saturating_add(1);
                    artifacts.push(SourcePackArtifactPlan {
                        artifact_index: artifacts.len(),
                        producing_job_index: job.job_index,
                        kind: SourcePackArtifactKind::LibraryInterface,
                        library_id: job.library_id,
                        first_source_index: job.first_source_index,
                        source_file_count: job.source_file_count,
                        source_bytes: job.source_bytes,
                        source_lines: job.source_lines,
                    });
                }
                SourcePackJobPhase::Codegen => {
                    first_object_artifact_index.get_or_insert(artifacts.len());
                    object_artifact_count = object_artifact_count.saturating_add(1);
                    artifacts.push(SourcePackArtifactPlan {
                        artifact_index: artifacts.len(),
                        producing_job_index: job.job_index,
                        kind: SourcePackArtifactKind::CodegenObject,
                        library_id: job.library_id,
                        first_source_index: job.first_source_index,
                        source_file_count: job.source_file_count,
                        source_bytes: job.source_bytes,
                        source_lines: job.source_lines,
                    });
                }
                SourcePackJobPhase::Link => {}
            }
        }

        let link_job_index = schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index)
            .unwrap_or(schedule.jobs.len());
        let output_artifact_index = artifacts.len();
        artifacts.push(SourcePackArtifactPlan {
            artifact_index: output_artifact_index,
            producing_job_index: link_job_index,
            kind: SourcePackArtifactKind::LinkedOutput,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: total_source_file_count,
            source_bytes: total_source_bytes,
            source_lines: total_source_lines,
        });

        SourcePackBuildPlan {
            schedule,
            artifacts,
            link: SourcePackLinkPlan {
                link_job_index,
                input_interface_artifact_count: interface_artifact_count,
                input_interface_artifact_ranges: artifact_index_ranges_from_first_count(
                    first_interface_artifact_index,
                    interface_artifact_count,
                ),
                input_interface_artifact_indices: Vec::new(),
                input_object_artifact_count: object_artifact_count,
                input_object_artifact_ranges: artifact_index_ranges_from_first_count(
                    first_object_artifact_index,
                    object_artifact_count,
                ),
                input_object_artifact_indices: Vec::new(),
                output_artifact_index,
            },
        }
    }

    fn library_dependency_index(&self) -> SourcePackLibraryDependencyIndex {
        let mut first_library_index_by_id = BTreeMap::new();
        for library in &self.libraries.libraries {
            first_library_index_by_id
                .entry(library.library_id)
                .or_insert(library.library_index);
        }

        let mut dependency_library_indices_by_library_id: BTreeMap<u32, Vec<usize>> =
            BTreeMap::new();
        for dependency in &self.library_dependencies {
            if let Some(&dependency_library_index) =
                first_library_index_by_id.get(&dependency.depends_on_library_id)
            {
                push_unique(
                    dependency_library_indices_by_library_id
                        .entry(dependency.library_id)
                        .or_default(),
                    dependency_library_index,
                );
            }
        }

        let mut dependency_library_indices_by_library_index =
            vec![Vec::new(); self.libraries.libraries.len()];
        for library in &self.libraries.libraries {
            if let Some(dependency_indices) =
                dependency_library_indices_by_library_id.get(&library.library_id)
            {
                if let Some(slot) =
                    dependency_library_indices_by_library_index.get_mut(library.library_index)
                {
                    *slot = dependency_indices.clone();
                }
            }
        }

        SourcePackLibraryDependencyIndex {
            dependency_library_indices_by_library_id,
            dependency_library_indices_by_library_index,
        }
    }

    fn dependency_library_indices_for_library<'a>(
        &self,
        library_id: u32,
        dependency_index: &'a SourcePackLibraryDependencyIndex,
    ) -> &'a [usize] {
        dependency_index
            .dependency_library_indices_by_library_id
            .get(&library_id)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    fn frontend_units_for_library<'a>(
        &'a self,
        library: &'a LibraryUnit,
    ) -> impl Iterator<Item = &'a FrontendUnit> + 'a {
        self.frontend_units.units.iter().filter(move |unit| {
            unit.library_id == library.library_id
                && range_contains_range(library.source_range(), unit.source_range())
        })
    }

    fn frontend_unit_for_range_from_cursor(
        &self,
        library_index: usize,
        frontend_unit_cursor: &mut usize,
        source_range: Range<usize>,
    ) -> Option<&FrontendUnit> {
        let library = self.libraries.libraries.get(library_index)?;
        while self
            .frontend_units
            .units
            .get(*frontend_unit_cursor)
            .is_some_and(|unit| unit.source_range().end <= source_range.start)
        {
            *frontend_unit_cursor += 1;
        }
        self.frontend_units
            .units
            .get(*frontend_unit_cursor)
            .filter(|unit| {
                unit.library_id == library.library_id
                    && range_contains_range(library.source_range(), unit.source_range())
                    && range_contains_range(unit.source_range(), source_range.clone())
            })
    }

    fn topological_library_indices(
        &self,
        dependency_index: &SourcePackLibraryDependencyIndex,
    ) -> Vec<usize> {
        let library_count = self.libraries.libraries.len();
        let mut sorted_indices = Vec::with_capacity(library_count);
        let mut emitted = vec![false; library_count];
        let mut remaining_dependency_counts = vec![0usize; library_count];
        let mut dependents_by_library_index = vec![Vec::new(); library_count];

        for (library_index, dependency_indices) in dependency_index
            .dependency_library_indices_by_library_index
            .iter()
            .enumerate()
        {
            for &dependency_library_index in dependency_indices {
                if dependency_library_index >= library_count {
                    continue;
                }
                remaining_dependency_counts[library_index] =
                    remaining_dependency_counts[library_index].saturating_add(1);
                push_unique(
                    &mut dependents_by_library_index[dependency_library_index],
                    library_index,
                );
            }
        }

        let mut ready_indices = remaining_dependency_counts
            .iter()
            .enumerate()
            .filter_map(|(library_index, &count)| (count == 0).then_some(library_index))
            .collect::<BTreeSet<_>>();

        while let Some(library_index) = ready_indices.iter().next().copied() {
            ready_indices.remove(&library_index);
            if emitted[library_index] {
                continue;
            }
            emitted[library_index] = true;
            sorted_indices.push(library_index);

            for &dependent_library_index in &dependents_by_library_index[library_index] {
                let Some(remaining_dependencies) =
                    remaining_dependency_counts.get_mut(dependent_library_index)
                else {
                    continue;
                };
                if *remaining_dependencies == 0 {
                    continue;
                }
                *remaining_dependencies -= 1;
                if *remaining_dependencies == 0 && !emitted[dependent_library_index] {
                    ready_indices.insert(dependent_library_index);
                }
            }
        }

        if sorted_indices.len() < library_count {
            for library_index in 0..library_count {
                if !emitted[library_index] {
                    sorted_indices.push(library_index);
                }
            }
        }

        sorted_indices
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct SourcePackLibraryDependencyIndex {
    dependency_library_indices_by_library_id: BTreeMap<u32, Vec<usize>>,
    dependency_library_indices_by_library_index: Vec<Vec<usize>>,
}

#[derive(Clone, Debug)]
/// Streaming builder for a source-pack job plan.
pub struct SourcePackJobPlanBuilder {
    limits: CodegenUnitLimits,
    library_builder: LibraryBuilder,
    frontend_builder: UnitBuilder,
    unit_builder: UnitBuilder,
    libraries: Vec<LibraryUnit>,
    frontend_units: Vec<FrontendUnit>,
    codegen_units: Vec<CodegenUnit>,
}

impl SourcePackJobPlanBuilder {
    /// Creates a builder that applies normalized codegen unit limits.
    pub fn new(limits: CodegenUnitLimits) -> Self {
        Self {
            limits: limits.normalized(),
            library_builder: LibraryBuilder::default(),
            frontend_builder: UnitBuilder::default(),
            unit_builder: UnitBuilder::default(),
            libraries: Vec::new(),
            frontend_units: Vec::new(),
            codegen_units: Vec::new(),
        }
    }

    /// Adds one source file to the library, frontend, and codegen unit streams.
    pub fn push(&mut self, file: SourceFileUnitInput) {
        self.push_library_file(file);
        self.push_frontend_file(file);
        self.push_codegen_file(file);
    }

    fn push_library_file(&mut self, file: SourceFileUnitInput) {
        if self.library_builder.should_flush_before(file) {
            self.flush_library();
        }
        self.library_builder.push(file);
    }

    fn push_frontend_file(&mut self, file: SourceFileUnitInput) {
        if file.byte_len > self.limits.max_source_bytes {
            self.flush_frontend_unit();
            self.frontend_units.push(FrontendUnit {
                unit_index: self.frontend_units.len(),
                library_id: file.library_id,
                first_source_index: file.source_index,
                source_file_count: 1,
                source_bytes: file.byte_len,
                source_lines: file.line_count,
                oversized_source_file: true,
            });
            return;
        }

        if self.frontend_builder.should_flush_before(file, self.limits) {
            self.flush_frontend_unit();
        }
        self.frontend_builder.push(file);
    }

    fn push_codegen_file(&mut self, file: SourceFileUnitInput) {
        if file.byte_len > self.limits.max_source_bytes {
            self.flush_codegen_unit();
            self.codegen_units.push(CodegenUnit {
                unit_index: self.codegen_units.len(),
                library_id: file.library_id,
                first_source_index: file.source_index,
                source_file_count: 1,
                source_bytes: file.byte_len,
                source_lines: file.line_count,
                oversized_source_file: true,
            });
            return;
        }

        if self.unit_builder.should_flush_before(file, self.limits) {
            self.flush_codegen_unit();
        }
        self.unit_builder.push(file);
    }

    fn flush_library(&mut self) {
        if let Some(library) = self.library_builder.take(self.libraries.len()) {
            self.libraries.push(library);
        }
    }

    fn flush_frontend_unit(&mut self) {
        if let Some(unit) = self
            .frontend_builder
            .take_frontend(self.frontend_units.len(), false)
        {
            self.frontend_units.push(unit);
        }
    }

    fn flush_codegen_unit(&mut self) {
        if let Some(unit) = self.unit_builder.take(self.codegen_units.len(), false) {
            self.codegen_units.push(unit);
        }
    }

    /// Finishes the plan and attaches library dependencies.
    pub fn finish(
        mut self,
        library_dependencies: &[SourcePackLibraryDependency],
    ) -> SourcePackJobPlan {
        self.flush_library();
        self.flush_frontend_unit();
        self.flush_codegen_unit();
        SourcePackJobPlan {
            libraries: LibraryUnitPlan {
                libraries: self.libraries,
            },
            frontend_units: FrontendUnitPlan {
                units: self.frontend_units,
            },
            codegen_units: CodegenUnitPlan {
                units: self.codegen_units,
            },
            library_dependencies: library_dependencies.to_vec(),
        }
    }
}
