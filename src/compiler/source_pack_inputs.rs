use super::*;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExplicitSourceLibrary {
    pub library_id: u32,
    pub sources: Vec<String>,
    pub dependency_library_ids: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExplicitSourceLibraryPaths<P> {
    pub library_id: u32,
    pub paths: Vec<P>,
    pub dependency_library_ids: Vec<u32>,
}

#[derive(Debug)]
pub struct ExplicitSourceLibraryPathStream<I> {
    pub library_id: u32,
    pub source_file_count: usize,
    pub paths: I,
    pub dependency_library_ids: Vec<u32>,
}

#[derive(Debug)]
pub struct ExplicitSourceLibraryPathDependencyStream<PI, DI> {
    pub library_id: u32,
    pub source_file_count: usize,
    pub paths: PI,
    pub dependency_library_count: usize,
    pub dependency_library_ids: DI,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExplicitSourcePathFile {
    pub library_id: u32,
    pub path: PathBuf,
    pub byte_len: usize,
    pub modified_unix_nanos: Option<u128>,
    /// `None` means planning did not scan the file contents.
    pub line_count: Option<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExplicitSourcePackPathManifest {
    pub files: Vec<ExplicitSourcePathFile>,
    pub library_dependencies: Vec<SourcePackLibraryDependency>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExplicitSourcePack {
    pub sources: Vec<String>,
    pub library_ids: Vec<u32>,
    pub library_dependencies: Vec<SourcePackLibraryDependency>,
}

impl ExplicitSourcePack {
    pub fn new(sources: Vec<String>, library_ids: Vec<u32>) -> Result<Self, CompileError> {
        if sources.is_empty() {
            return Err(CompileError::GpuFrontend(
                "explicit source pack has no source files".to_string(),
            ));
        }
        if sources.len() != library_ids.len() {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack has {} source files but {} library ids",
                sources.len(),
                library_ids.len()
            )));
        }
        Ok(Self {
            sources,
            library_ids,
            library_dependencies: Vec::new(),
        })
    }

    pub fn in_single_library(sources: Vec<String>) -> Result<Self, CompileError> {
        Self::from_libraries(vec![ExplicitSourceLibrary {
            library_id: 0,
            sources,
            dependency_library_ids: Vec::new(),
        }])
    }

    pub fn from_libraries(libraries: Vec<ExplicitSourceLibrary>) -> Result<Self, CompileError> {
        let library_entries = libraries
            .iter()
            .map(|library| ExplicitSourceLibraryManifestEntry {
                library_id: library.library_id,
                source_file_count: library.sources.len(),
                dependency_library_ids: library.dependency_library_ids.clone(),
            })
            .collect::<Vec<_>>();
        let (topological_library_ids, library_dependencies) =
            validate_explicit_source_library_entries(&library_entries)?;
        let source_count = library_entries
            .iter()
            .map(|library| library.source_file_count)
            .sum::<usize>();
        let mut sources = Vec::with_capacity(source_count);
        let mut library_ids = Vec::with_capacity(source_count);

        let mut remaining_libraries = libraries.into_iter().map(Some).collect::<Vec<_>>();
        for library_id in topological_library_ids {
            let library_index = remaining_libraries
                .iter()
                .position(|library| {
                    library
                        .as_ref()
                        .is_some_and(|library| library.library_id == library_id)
                })
                .expect("topological library id must come from manifest");
            let library = remaining_libraries[library_index]
                .take()
                .expect("topological library should be unconsumed");
            for source in library.sources {
                sources.push(source);
                library_ids.push(library.library_id);
            }
        }

        let mut pack = Self::new(sources, library_ids)?;
        pack.library_dependencies = library_dependencies;
        Ok(pack)
    }

    pub fn with_library_dependencies(
        mut self,
        library_dependencies: Vec<SourcePackLibraryDependency>,
    ) -> Result<Self, CompileError> {
        let library_id_set = self.library_ids.iter().copied().collect::<BTreeSet<_>>();
        for dependency in &library_dependencies {
            if dependency.library_id == dependency.depends_on_library_id {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on itself",
                    dependency.library_id
                )));
            }
            if !library_id_set.contains(&dependency.library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack dependency references missing library {}",
                    dependency.library_id
                )));
            }
            if !library_id_set.contains(&dependency.depends_on_library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack dependency references missing library {}",
                    dependency.depends_on_library_id
                )));
            }
        }

        let library_ids = first_seen_library_ids(&self.library_ids);
        topologically_order_library_ids(&library_ids, &library_dependencies)?;
        self.library_dependencies = library_dependencies;
        Ok(self)
    }

    pub fn codegen_unit_plan(&self, limits: CodegenUnitLimits) -> CodegenUnitPlan {
        CodegenUnitPlan::from_source_pack_with_libraries(&self.sources, &self.library_ids, limits)
    }

    pub fn frontend_unit_plan(&self, limits: CodegenUnitLimits) -> FrontendUnitPlan {
        FrontendUnitPlan::from_source_pack_with_libraries(&self.sources, &self.library_ids, limits)
    }

    pub fn job_plan(&self, limits: CodegenUnitLimits) -> SourcePackJobPlan {
        SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &self.sources,
            &self.library_ids,
            &self.library_dependencies,
            limits,
        )
    }

    pub fn job_schedule(&self, limits: CodegenUnitLimits) -> SourcePackJobSchedule {
        self.job_plan(limits).job_schedule()
    }

    pub fn bounded_frontend_job_schedule(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackJobSchedule {
        self.job_plan(limits).bounded_frontend_job_schedule()
    }

    pub fn build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.bounded_frontend_build_plan(limits)
    }

    pub fn whole_library_frontend_build_plan(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackBuildPlan {
        self.job_plan(limits).build_plan()
    }

    pub fn bounded_frontend_build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.job_plan(limits).bounded_frontend_build_plan()
    }

    pub fn compact_build_artifact_manifest(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            limits,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest_for_target(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        let plan = self.job_plan(limits);
        let schedule = plan.bounded_frontend_job_schedule();
        plan.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    pub fn source_slice_for_unit(&self, unit: &CodegenUnit) -> &[String] {
        &self.sources[unit.source_range()]
    }

    pub fn source_slice_for_job(&self, job: &SourcePackJob) -> &[String] {
        &self.sources[job.source_range()]
    }

    pub fn source_slice_for_artifact(&self, artifact: &SourcePackArtifactPlan) -> &[String] {
        &self.sources[artifact.source_range()]
    }

    pub fn execute_build_plan<E>(
        &self,
        limits: CodegenUnitLimits,
        executor: &mut E,
    ) -> Result<
        SourcePackBuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: SourcePackBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_build(
            self,
            &build_plan,
            SourcePackJobBatchLimits::from_codegen_unit_limits(limits),
            executor,
        )
    }

    pub fn execute_build_plan_with_batch_limits<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<
        SourcePackBuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: SourcePackBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_build(self, &build_plan, batch_limits, executor)
    }
}

impl ExplicitSourcePackPathManifest {
    pub fn from_libraries<P>(
        libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    ) -> Result<Self, CompileError>
    where
        P: AsRef<Path>,
    {
        let library_entries = libraries
            .iter()
            .map(|library| ExplicitSourceLibraryManifestEntry {
                library_id: library.library_id,
                source_file_count: library.paths.len(),
                dependency_library_ids: library.dependency_library_ids.clone(),
            })
            .collect::<Vec<_>>();
        let (topological_library_ids, library_dependencies) =
            validate_explicit_source_library_entries(&library_entries)?;
        let source_file_count = library_entries
            .iter()
            .map(|library| library.source_file_count)
            .sum::<usize>();
        let mut files = Vec::with_capacity(source_file_count);
        let mut remaining_libraries = libraries.into_iter().map(Some).collect::<Vec<_>>();

        for library_id in topological_library_ids {
            let library_index = remaining_libraries
                .iter()
                .position(|library| {
                    library
                        .as_ref()
                        .is_some_and(|library| library.library_id == library_id)
                })
                .expect("topological library id must come from path manifest");
            let library = remaining_libraries[library_index]
                .take()
                .expect("topological library should be unconsumed");
            let label = format!("library {}", library.library_id);
            for (path_index, path) in library.paths.into_iter().enumerate() {
                files.push(read_explicit_source_path_metadata(
                    &label,
                    path_index,
                    library.library_id,
                    path.as_ref(),
                )?);
            }
        }

        Ok(Self {
            files,
            library_dependencies,
        })
    }

    pub fn source_file_inputs(&self) -> Vec<SourceFileUnitInput> {
        self.source_file_input_iter().collect()
    }

    pub fn source_file_input_iter(&self) -> impl Iterator<Item = SourceFileUnitInput> + '_ {
        self.files
            .iter()
            .enumerate()
            .map(|(source_index, file)| SourceFileUnitInput {
                library_id: file.library_id,
                source_index,
                byte_len: file.byte_len,
                line_count: file.line_count.unwrap_or(0),
            })
    }

    pub fn codegen_unit_plan(&self, limits: CodegenUnitLimits) -> CodegenUnitPlan {
        let mut units = Vec::new();
        CodegenUnitPlan::try_for_each_from_files(self.source_file_input_iter(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible path-manifest codegen-unit plan failed"));
        CodegenUnitPlan { units }
    }

    pub fn frontend_unit_plan(&self, limits: CodegenUnitLimits) -> FrontendUnitPlan {
        let mut units = Vec::new();
        FrontendUnitPlan::try_for_each_from_files(self.source_file_input_iter(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible path-manifest frontend-unit plan failed"));
        FrontendUnitPlan { units }
    }

    pub fn job_plan(&self, limits: CodegenUnitLimits) -> SourcePackJobPlan {
        SourcePackJobPlan::from_file_stream_with_dependencies(
            self.source_file_input_iter(),
            &self.library_dependencies,
            limits,
        )
    }

    pub fn job_schedule(&self, limits: CodegenUnitLimits) -> SourcePackJobSchedule {
        self.job_plan(limits).job_schedule()
    }

    pub fn bounded_frontend_job_schedule(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackJobSchedule {
        self.job_plan(limits).bounded_frontend_job_schedule()
    }

    pub fn build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.bounded_frontend_build_plan(limits)
    }

    pub fn whole_library_frontend_build_plan(
        &self,
        limits: CodegenUnitLimits,
    ) -> SourcePackBuildPlan {
        self.job_plan(limits).build_plan()
    }

    pub fn bounded_frontend_build_plan(&self, limits: CodegenUnitLimits) -> SourcePackBuildPlan {
        self.job_plan(limits).bounded_frontend_build_plan()
    }

    pub fn compact_build_artifact_manifest(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            limits,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest_for_target(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        let plan = self.job_plan(limits);
        let schedule = plan.bounded_frontend_job_schedule();
        plan.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    pub fn library_partition_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackLibraryPartitionIndex, CompileError> {
        source_pack_library_partition_index(self, target)
    }

    pub fn source_files_for_job(&self, job: &SourcePackJob) -> &[ExplicitSourcePathFile] {
        &self.files[job.source_range()]
    }

    pub fn source_files_for_artifact(
        &self,
        artifact: &SourcePackArtifactPlan,
    ) -> &[ExplicitSourcePathFile] {
        &self.files[artifact.source_range()]
    }

    pub fn load_sources_for_job(&self, job: &SourcePackJob) -> Result<Vec<String>, CompileError> {
        read_explicit_source_path_files("source-pack job", self.source_files_for_job(job))
    }

    pub fn execute_build_plan<E>(
        &self,
        limits: CodegenUnitLimits,
        executor: &mut E,
    ) -> Result<
        SourcePackBuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: SourcePackPathBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_path_build(
            self,
            &build_plan,
            SourcePackJobBatchLimits::from_codegen_unit_limits(limits),
            executor,
        )
    }

    pub fn execute_build_plan_with_batch_limits<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<
        SourcePackBuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
        CompileError,
    >
    where
        E: SourcePackPathBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_path_build(self, &build_plan, batch_limits, executor)
    }

    pub fn execute_build_plan_with_handles<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<SourcePackHandleBuildExecutionResult<E::LinkedOutput>, CompileError>
    where
        E: SourcePackPathHandleBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_path_handle_build(self, &build_plan, batch_limits, executor)
    }

    pub fn execute_build_plan_with_batched_link_handles<E>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
    ) -> Result<SourcePackHandleBuildExecutionResult<E::LinkedOutput>, CompileError>
    where
        E: SourcePackPathHandleBatchedLinkBuildExecutor,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_path_batched_link_build(self, &build_plan, batch_limits, executor)
    }

    pub fn execute_build_plan_with_artifact_store<E, S>(
        &self,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        executor: &mut E,
        store: &mut S,
    ) -> Result<SourcePackArtifactStoreBuildExecutionResult, CompileError>
    where
        E: SourcePackPathArtifactBuildExecutor<
                LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
                CodegenObjectArtifact = S::CodegenObjectArtifact,
                LinkedOutputArtifact = S::LinkedOutputArtifact,
            >,
        S: SourcePackPathArtifactStore,
    {
        let build_plan = self.bounded_frontend_build_plan(limits);
        execute_source_pack_path_artifact_store_build(
            self,
            &build_plan,
            batch_limits,
            executor,
            store,
        )
    }
}

pub(super) fn validate_explicit_source_library_entries(
    libraries: &[ExplicitSourceLibraryManifestEntry],
) -> Result<(Vec<u32>, Vec<SourcePackLibraryDependency>), CompileError> {
    if libraries.is_empty() {
        return Err(CompileError::GpuFrontend(
            "explicit source pack has no source files".to_string(),
        ));
    }

    let mut library_id_order = Vec::with_capacity(libraries.len());
    let mut library_id_set = BTreeSet::new();
    let mut library_dependencies = Vec::new();

    for library in libraries {
        if library.source_file_count == 0 {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} has no source files",
                library.library_id
            )));
        }
        if !library_id_set.insert(library.library_id) {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} appears more than once",
                library.library_id
            )));
        }
        library_id_order.push(library.library_id);
    }

    for library in libraries {
        for &dependency_library_id in &library.dependency_library_ids {
            if dependency_library_id == library.library_id {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on itself",
                    library.library_id
                )));
            }
            if !library_id_set.contains(&dependency_library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on missing library {}",
                    library.library_id, dependency_library_id
                )));
            }
            library_dependencies.push(SourcePackLibraryDependency {
                library_id: library.library_id,
                depends_on_library_id: dependency_library_id,
            });
        }
    }

    let topological_library_ids =
        topologically_order_library_ids(&library_id_order, &library_dependencies)?;
    Ok((topological_library_ids, library_dependencies))
}
