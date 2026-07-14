use super::*;

/// Source-pack executor that emits GPU artifact descriptors into a filesystem store.
///
/// This executor is used by descriptor-mode source-pack builds. It validates
/// source/job metadata, checks that dependency artifacts exist, and writes
/// JSON descriptor artifacts that describe each stage's contract.
pub struct GpuSourcePackArtifactExecutor<'compiler, 'gpu> {
    pub(super) compiler: &'compiler GpuCompiler<'gpu>,
    pub(super) artifact_root: PathBuf,
    pub(super) target: SourcePackArtifactTarget,
}

/// In-flight library-interface descriptor build state.
#[derive(Clone, Debug)]
pub struct GpuSourcePackLibraryInterfaceBuildHandle {
    pub(super) job: SourcePackJob,
    pub(super) source_files: Vec<ExplicitSourcePathFile>,
    pub(super) dependency_interfaces: GpuSourcePackDependencyInterfaceSummary,
    pub(super) dependency_interface_artifacts: Vec<ArtifactPath>,
}

/// In-flight codegen-object descriptor build state.
#[derive(Clone, Debug)]
pub struct GpuSourcePackCodegenObjectBuildHandle {
    pub(super) job: SourcePackJob,
    pub(super) source_files: Vec<ExplicitSourcePathFile>,
    pub(super) library_interface_artifact: ArtifactPath,
    pub(super) dependency_interfaces: GpuSourcePackDependencyInterfaceSummary,
    pub(super) dependency_interface_artifacts: Vec<ArtifactPath>,
}

/// Accumulated bounded inputs for one source-pack link.
#[derive(Clone, Debug, Default)]
pub struct GpuSourcePackLinkHandle {
    pub(super) interface_count: usize,
    pub(super) object_count: usize,
    pub(super) partial_link_count: usize,
    pub(super) codegen_object_artifacts: Vec<ArtifactPath>,
    pub(super) partial_link_artifacts: Vec<ArtifactPath>,
}

/// Validates that source-file metadata still matches a descriptor job record.
pub(in crate::compiler) fn validate_gpu_source_pack_descriptor_job_source_file_records(
    stage: &str,
    job: &SourcePackJob,
    source_files: &[ExplicitSourcePathFile],
) -> Result<(), CompileError> {
    let expected_phase = match stage {
        "library-interface" => Some(SourcePackJobPhase::LibraryFrontend),
        "codegen" => Some(SourcePackJobPhase::Codegen),
        _ => None,
    };
    if let Some(expected_phase) = expected_phase {
        if job.phase != expected_phase {
            return Err(artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} has phase {:?} but expected {:?}",
                job.job_index, job.phase, expected_phase
            )));
        }
    }
    let source_end = job
        .first_source_index
        .checked_add(job.source_file_count)
        .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} source range {}+{} overflows",
                job.job_index, job.first_source_index, job.source_file_count
            ))
        })?;
    if source_files.len() != job.source_file_count {
        return Err(artifact_shard_contract_error(format!(
            "source-pack {stage} descriptor job {} received {} source-file records but expected {}",
            job.job_index,
            source_files.len(),
            job.source_file_count
        )));
    }
    let mut source_bytes = 0usize;
    let mut source_lines = 0usize;
    for (offset, file) in source_files.iter().enumerate() {
        if file.library_id != job.library_id {
            let source_index = job.first_source_index.saturating_add(offset);
            return Err(artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} source file {} belongs to library {} but expected {}",
                job.job_index, source_index, file.library_id, job.library_id
            )));
        }
        source_bytes = source_bytes.checked_add(file.byte_len).ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} source byte count overflows before source {}",
                job.job_index,
                job.first_source_index.saturating_add(offset)
            ))
        })?;
        source_lines = source_lines
            .checked_add(file.line_count.unwrap_or(0))
            .ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "source-pack {stage} descriptor job {} source line count overflows before source {}",
                    job.job_index,
                    job.first_source_index.saturating_add(offset)
                ))
            })?;
    }
    if source_bytes != job.source_bytes {
        return Err(artifact_shard_contract_error(format!(
            "source-pack {stage} descriptor job {} source range {}..{} has {} bytes but job record declares {}",
            job.job_index, job.first_source_index, source_end, source_bytes, job.source_bytes
        )));
    }
    if source_lines != job.source_lines {
        return Err(artifact_shard_contract_error(format!(
            "source-pack {stage} descriptor job {} source range {}..{} has {} lines but job record declares {}",
            job.job_index, job.first_source_index, source_end, source_lines, job.source_lines
        )));
    }
    Ok(())
}

/// Validates that every dependency descriptor artifact in a batch exists on disk.
pub(in crate::compiler) fn validate_gpu_source_pack_descriptor_artifact_paths(
    stage: &str,
    owner_index: usize,
    artifacts: &[ArtifactPath],
) -> Result<(), CompileError> {
    for artifact in artifacts {
        if !artifact.path.is_file() {
            return Err(source_pack_artifact_store_error(format!(
                "source-pack {stage} {owner_index} is missing dependency artifact {} at {}",
                artifact.key,
                artifact.path.display()
            )));
        }
    }
    Ok(())
}

impl<'compiler, 'gpu> GpuSourcePackArtifactExecutor<'compiler, 'gpu> {
    /// Creates a descriptor executor for one compiler, artifact root, and target.
    pub fn new(
        compiler: &'compiler GpuCompiler<'gpu>,
        artifact_root: impl Into<PathBuf>,
        target: SourcePackArtifactTarget,
    ) -> Self {
        Self {
            compiler,
            artifact_root: artifact_root.into(),
            target,
        }
    }

    /// Returns the GPU compiler used to validate frontend interface jobs.
    pub fn compiler(&self) -> &'compiler GpuCompiler<'gpu> {
        self.compiler
    }

    /// Returns the filesystem root where descriptor artifacts are written.
    pub fn artifact_root(&self) -> &Path {
        &self.artifact_root
    }

    /// Returns the source-pack artifact target this executor emits for.
    pub fn target(&self) -> SourcePackArtifactTarget {
        self.target
    }

    /// Finishes a library-interface job by type-checking its sources and writing a descriptor.
    pub(super) async fn finish_library_interface_artifact(
        &self,
        handle: GpuSourcePackLibraryInterfaceBuildHandle,
    ) -> Result<ArtifactPath, CompileError> {
        self.validate_job_source_file_records(
            "library-interface",
            &handle.job,
            &handle.source_files,
        )?;
        let sources = read_explicit_source_path_files(
            "source-pack library-interface job",
            &handle.source_files,
        )?;
        let dependency_interfaces =
            self.load_semantic_interface_artifacts(&handle.dependency_interface_artifacts)?;
        let unit_id = u32::try_from(handle.job.phase_unit_index).map_err(|_| {
            source_pack_artifact_store_error(format!(
                "source-pack semantic-interface job {} phase-unit index {} exceeds u32",
                handle.job.job_index, handle.job.phase_unit_index
            ))
        })?;
        let interface = self
            .compiler
            .semantic_interface_for_source_pack_unit_with_dependencies(
                handle.job.library_id,
                unit_id,
                &sources,
                &dependency_interfaces,
            )
            .await?;
        let interface_bytes = interface.to_bytes().map_err(|reason| {
            source_pack_artifact_store_error(format!(
                "serialize source-pack semantic interface for job {}: {reason}",
                handle.job.job_index
            ))
        })?;
        let interface_artifact =
            self.write_semantic_interface_artifact(&handle.job, &interface_bytes)?;
        let mut descriptor = GpuSourcePackArtifactDescriptor::library_interface_for_job(
            self.target,
            &handle.job,
            handle.dependency_interfaces,
        );
        attach_semantic_interface_artifact(
            &mut descriptor,
            &interface_artifact,
            semantic_interface_record_count(&interface),
            interface_bytes.len(),
        );
        descriptor.validate_contract().map_err(|reason| {
            source_pack_artifact_store_error(format!(
                "validate source-pack semantic-interface descriptor for job {}: {reason}",
                handle.job.job_index
            ))
        })?;
        self.write_descriptor_artifact(
            GpuSourcePackArtifactStage::LibraryInterface,
            &handle.job,
            &descriptor,
        )
    }

    /// Finishes a codegen-object job by validating its semantic inputs and
    /// persisting the concrete backend object when the target supports one.
    pub(super) async fn finish_codegen_object_artifact(
        &self,
        handle: GpuSourcePackCodegenObjectBuildHandle,
    ) -> Result<ArtifactPath, CompileError> {
        self.validate_job_source_file_records("codegen", &handle.job, &handle.source_files)?;
        if !handle.library_interface_artifact.path.is_file() {
            return Err(source_pack_artifact_store_error(format!(
                "source-pack codegen descriptor job {} is missing owning interface artifact {}",
                handle.job.job_index,
                handle.library_interface_artifact.path.display()
            )));
        }
        let owning_interfaces = self.load_semantic_interface_artifacts(std::slice::from_ref(
            &handle.library_interface_artifact,
        ))?;
        let owning_interface = owning_interfaces.first().ok_or_else(|| {
            source_pack_artifact_store_error(format!(
                "source-pack codegen job {} has no owning semantic interface",
                handle.job.job_index
            ))
        })?;
        if owning_interface.library_id != handle.job.library_id {
            return Err(source_pack_artifact_store_error(format!(
                "source-pack codegen job {} belongs to library {} but its owning semantic interface belongs to library {}",
                handle.job.job_index, handle.job.library_id, owning_interface.library_id
            )));
        }
        let dependency_interfaces =
            self.load_semantic_interface_artifacts(&handle.dependency_interface_artifacts)?;
        if dependency_interfaces.len() != handle.dependency_interfaces.interface_count {
            return Err(source_pack_artifact_store_error(format!(
                "source-pack codegen job {} loaded {} dependency semantic interfaces but its descriptor contract records {}",
                handle.job.job_index,
                dependency_interfaces.len(),
                handle.dependency_interfaces.interface_count
            )));
        }

        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            self.target,
            &handle.job,
            handle.dependency_interfaces,
        );
        if self.target == SourcePackArtifactTarget::X86_64 {
            let sources = read_explicit_source_path_files(
                "source-pack x86 codegen-object job",
                &handle.source_files,
            )?;
            let unit_id = u32::try_from(handle.job.phase_unit_index).map_err(|_| {
                source_pack_artifact_store_error(format!(
                    "source-pack x86 codegen job {} phase-unit index {} exceeds u32",
                    handle.job.job_index, handle.job.phase_unit_index
                ))
            })?;
            let object = self
                .compiler
                .compile_source_pack_to_x86_object(
                    &sources,
                    handle.job.library_id,
                    unit_id,
                    &dependency_interfaces,
                )
                .await?;
            let object_bytes = object.to_bytes().map_err(|reason| {
                source_pack_artifact_store_error(format!(
                    "serialize source-pack x86 object for job {}: {reason}",
                    handle.job.job_index
                ))
            })?;
            let object_artifact =
                self.write_x86_codegen_object_artifact(&handle.job, &object_bytes)?;
            attach_x86_codegen_object_artifact(
                &mut descriptor,
                &object_artifact,
                &object,
                object_bytes.len(),
            );
        } else if self.target == SourcePackArtifactTarget::Wasm {
            let sources = read_explicit_source_path_files(
                "source-pack Wasm codegen-object job",
                &handle.source_files,
            )?;
            let unit_id = u32::try_from(handle.job.phase_unit_index).map_err(|_| {
                source_pack_artifact_store_error(format!(
                    "source-pack Wasm codegen job {} phase-unit index {} exceeds u32",
                    handle.job.job_index, handle.job.phase_unit_index
                ))
            })?;
            let object = self
                .compiler
                .compile_source_pack_to_wasm_object(
                    &sources,
                    handle.job.library_id,
                    unit_id,
                    &dependency_interfaces,
                )
                .await?;
            let object_bytes = object.to_bytes().map_err(|reason| {
                source_pack_artifact_store_error(format!(
                    "serialize source-pack Wasm object for job {}: {reason}",
                    handle.job.job_index
                ))
            })?;
            let object_artifact =
                self.write_wasm_codegen_object_artifact(&handle.job, &object_bytes)?;
            attach_wasm_codegen_object_artifact(
                &mut descriptor,
                &object_artifact,
                &object,
                object_bytes.len(),
            );
        }
        descriptor.validate_contract().map_err(|reason| {
            source_pack_artifact_store_error(format!(
                "validate source-pack codegen-object descriptor for job {}: {reason}",
                handle.job.job_index
            ))
        })?;
        self.write_descriptor_artifact(
            GpuSourcePackArtifactStage::CodegenObject,
            &handle.job,
            &descriptor,
        )
    }

    /// Finishes a direct link job by writing a linked-output descriptor.
    pub(super) async fn finish_linked_output_artifact(
        &self,
        job: &SourcePackJob,
        link_handle: GpuSourcePackLinkHandle,
    ) -> Result<ArtifactPath, CompileError> {
        let mut linked_bytes = None;
        if self.target == SourcePackArtifactTarget::X86_64 {
            let objects =
                self.load_x86_codegen_object_artifacts(&link_handle.codegen_object_artifacts)?;
            let link_input = x86::GpuX86LinkInput::for_executable(&objects).map_err(|reason| {
                source_pack_artifact_store_error(format!(
                    "prepare source-pack x86 link job {}: {reason}",
                    job.job_index
                ))
            })?;
            let generator = self.compiler.x86_generator().map_err(|reason| {
                source_pack_artifact_store_error(format!(
                    "initialize source-pack x86 linker for job {}: {reason}",
                    job.job_index
                ))
            })?;
            let _resident_guard = self.compiler.resident_pipeline_lock.lock().await;
            linked_bytes = Some(
                generator
                    .link_executable(
                        &self.compiler.gpu.device,
                        &self.compiler.gpu.queue,
                        &link_input,
                    )
                    .map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "execute source-pack x86 link job {}: {err}",
                            job.job_index
                        ))
                    })?,
            );
        } else if self.target == SourcePackArtifactTarget::Wasm {
            let objects =
                self.load_wasm_codegen_object_artifacts(&link_handle.codegen_object_artifacts)?;
            let link_input = wasm::GpuWasmLinkInput::for_executable(&objects).map_err(|reason| {
                source_pack_artifact_store_error(format!(
                    "prepare source-pack Wasm link job {}: {reason}",
                    job.job_index
                ))
            })?;
            let generator = self.compiler.wasm_generator().map_err(|reason| {
                source_pack_artifact_store_error(format!(
                    "initialize source-pack Wasm linker for job {}: {reason}",
                    job.job_index
                ))
            })?;
            let _resident_guard = self.compiler.resident_pipeline_lock.lock().await;
            linked_bytes = Some(
                generator
                    .link_executable(
                        &self.compiler.gpu.device,
                        &self.compiler.gpu.queue,
                        &link_input,
                    )
                    .map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "execute source-pack Wasm link job {}: {err}",
                            job.job_index
                        ))
                    })?,
            );
        }
        let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            self.target,
            job,
            link_handle.interface_count,
            link_handle.object_count,
        );
        if let Some(bytes) = linked_bytes {
            let artifact = match self.target {
                SourcePackArtifactTarget::X86_64 => {
                    self.write_x86_linked_output_artifact(job, &bytes)?
                }
                SourcePackArtifactTarget::Wasm => {
                    self.write_wasm_linked_output_artifact(job, &bytes)?
                }
                SourcePackArtifactTarget::Generic => {
                    return Err(source_pack_artifact_store_error(format!(
                        "source-pack generic link job {} unexpectedly produced target bytes",
                        job.job_index
                    )));
                }
            };
            attach_linked_output_artifact(&mut descriptor, &artifact, bytes.len());
        }
        descriptor.validate_contract().map_err(|reason| {
            source_pack_artifact_store_error(format!(
                "validate source-pack linked-output descriptor for job {}: {reason}",
                job.job_index
            ))
        })?;
        self.write_descriptor_artifact(GpuSourcePackArtifactStage::LinkedOutput, job, &descriptor)
    }

    /// Finishes a hierarchical partial-link group by writing a partial-link descriptor.
    pub(super) fn finish_hierarchical_partial_link_artifact(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: GpuSourcePackLinkHandle,
    ) -> Result<ArtifactPath, CompileError> {
        let descriptor = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            page,
            link_handle.interface_count,
            link_handle.object_count,
            link_handle.partial_link_count,
        );
        self.write_descriptor_artifact_for_suffix(
            GpuSourcePackArtifactStage::PartialLink,
            format!("group-{}", page.group_index),
            &descriptor,
        )
    }

    /// Finishes a hierarchical final-link group by writing a linked-output descriptor.
    pub(super) fn finish_hierarchical_linked_output_artifact(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: GpuSourcePackLinkHandle,
    ) -> Result<ArtifactPath, CompileError> {
        let descriptor =
            GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
                page,
                link_handle.interface_count,
                link_handle.object_count,
                link_handle.partial_link_count,
            );
        self.write_descriptor_artifact_for_suffix(
            GpuSourcePackArtifactStage::LinkedOutput,
            format!("group-{}", page.group_index),
            &descriptor,
        )
    }

    /// Writes a job-scoped descriptor artifact using the standard job key suffix.
    pub(super) fn write_descriptor_artifact(
        &self,
        stage: GpuSourcePackArtifactStage,
        job: &SourcePackJob,
        descriptor: &GpuSourcePackArtifactDescriptor,
    ) -> Result<ArtifactPath, CompileError> {
        self.write_descriptor_artifact_for_suffix(
            stage,
            format!("job-{}", job.job_index),
            descriptor,
        )
    }

    /// Serializes and writes a descriptor artifact using an explicit key suffix.
    pub(super) fn write_descriptor_artifact_for_suffix(
        &self,
        stage: GpuSourcePackArtifactStage,
        key_suffix: impl AsRef<str>,
        descriptor: &GpuSourcePackArtifactDescriptor,
    ) -> Result<ArtifactPath, CompileError> {
        let key = gpu_source_pack_descriptor_artifact_key(self.target, stage, key_suffix.as_ref());
        let path = artifact_path(&self.artifact_root, &key)?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                source_pack_artifact_store_error(format!(
                    "create source-pack descriptor artifact directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let bytes = serde_json::to_vec_pretty(descriptor).map_err(|err| {
            source_pack_artifact_store_error(format!(
                "serialize source-pack {:?} descriptor for {}: {err}",
                stage,
                key_suffix.as_ref()
            ))
        })?;
        write_file_atomic_with_error(
            &path,
            &bytes,
            "source-pack descriptor artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    /// Validates that source-file metadata still matches a job record.
    pub(super) fn validate_job_source_file_records(
        &self,
        stage: &str,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Result<(), CompileError> {
        validate_gpu_source_pack_descriptor_job_source_file_records(stage, job, source_files)
    }

    /// Validates that every dependency artifact in a batch exists on disk.
    pub(super) fn validate_existing_path_artifact_batch(
        &self,
        stage: &str,
        owner_index: usize,
        artifacts: &[ArtifactPath],
    ) -> Result<(), CompileError> {
        validate_gpu_source_pack_descriptor_artifact_paths(stage, owner_index, artifacts)
    }

    fn write_semantic_interface_artifact(
        &self,
        job: &SourcePackJob,
        bytes: &[u8],
    ) -> Result<ArtifactPath, CompileError> {
        let key = gpu_source_pack_semantic_interface_artifact_key(
            self.target,
            &format!("job-{}", job.job_index),
        );
        let path = artifact_path(&self.artifact_root, &key)?;
        write_file_atomic_with_error(
            &path,
            bytes,
            "source-pack semantic-interface artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    fn write_x86_codegen_object_artifact(
        &self,
        job: &SourcePackJob,
        bytes: &[u8],
    ) -> Result<ArtifactPath, CompileError> {
        let key =
            gpu_source_pack_x86_codegen_object_artifact_key(&format!("job-{}", job.job_index));
        let path = artifact_path(&self.artifact_root, &key)?;
        write_file_atomic_with_error(
            &path,
            bytes,
            "source-pack x86 codegen-object artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    fn write_wasm_codegen_object_artifact(
        &self,
        job: &SourcePackJob,
        bytes: &[u8],
    ) -> Result<ArtifactPath, CompileError> {
        let key =
            gpu_source_pack_wasm_codegen_object_artifact_key(&format!("job-{}", job.job_index));
        let path = artifact_path(&self.artifact_root, &key)?;
        write_file_atomic_with_error(
            &path,
            bytes,
            "source-pack Wasm codegen-object artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    fn write_x86_linked_output_artifact(
        &self,
        job: &SourcePackJob,
        bytes: &[u8],
    ) -> Result<ArtifactPath, CompileError> {
        let key = gpu_source_pack_x86_linked_output_artifact_key(&format!("job-{}", job.job_index));
        let path = artifact_path(&self.artifact_root, &key)?;
        write_file_atomic_with_error(
            &path,
            bytes,
            "source-pack x86 linked-output artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    fn write_wasm_linked_output_artifact(
        &self,
        job: &SourcePackJob,
        bytes: &[u8],
    ) -> Result<ArtifactPath, CompileError> {
        let key =
            gpu_source_pack_wasm_linked_output_artifact_key(&format!("job-{}", job.job_index));
        let path = artifact_path(&self.artifact_root, &key)?;
        write_file_atomic_with_error(
            &path,
            bytes,
            "source-pack Wasm linked-output artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    fn load_semantic_interface_artifacts(
        &self,
        descriptor_artifacts: &[ArtifactPath],
    ) -> Result<Vec<GpuSemanticInterfaceArtifact>, CompileError> {
        descriptor_artifacts
            .iter()
            .map(|descriptor_artifact| {
                let descriptor_bytes = fs::read(&descriptor_artifact.path).map_err(|err| {
                    source_pack_artifact_store_error(format!(
                        "read dependency interface descriptor {} at {}: {err}",
                        descriptor_artifact.key,
                        descriptor_artifact.path.display()
                    ))
                })?;
                let descriptor: GpuSourcePackArtifactDescriptor =
                    serde_json::from_slice(&descriptor_bytes).map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "parse dependency interface descriptor {} at {}: {err}",
                            descriptor_artifact.key,
                            descriptor_artifact.path.display()
                        ))
                    })?;
                descriptor
                    .validate_contract_for(
                        GpuSourcePackArtifactStage::LibraryInterface,
                        Some(self.target),
                    )
                    .map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "validate dependency interface descriptor {}: {reason}",
                        descriptor_artifact.key
                    ))
                })?;
                let storage_key = descriptor
                    .output_record_arrays
                    .iter()
                    .find(|array| array.name == "semantic_interface_records")
                    .and_then(|array| array.storage_key.as_deref())
                    .ok_or_else(|| {
                        source_pack_artifact_store_error(format!(
                            "dependency interface descriptor {} has no persisted semantic_interface_records storage key",
                            descriptor_artifact.key
                        ))
                    })?;
                let interface_path = artifact_path(&self.artifact_root, storage_key)?;
                let interface_bytes = fs::read(&interface_path).map_err(|err| {
                    source_pack_artifact_store_error(format!(
                        "read dependency semantic interface {storage_key} at {}: {err}",
                        interface_path.display()
                    ))
                })?;
                GpuSemanticInterfaceArtifact::from_bytes(&interface_bytes).map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "parse dependency semantic interface {storage_key}: {reason}"
                    ))
                })
            })
            .collect()
    }

    fn load_x86_codegen_object_artifacts(
        &self,
        descriptor_artifacts: &[ArtifactPath],
    ) -> Result<Vec<x86::GpuX86RelocatableObject>, CompileError> {
        descriptor_artifacts
            .iter()
            .map(|descriptor_artifact| {
                let descriptor_bytes = fs::read(&descriptor_artifact.path).map_err(|err| {
                    source_pack_artifact_store_error(format!(
                        "read x86 codegen-object descriptor {} at {}: {err}",
                        descriptor_artifact.key,
                        descriptor_artifact.path.display()
                    ))
                })?;
                let descriptor: GpuSourcePackArtifactDescriptor =
                    serde_json::from_slice(&descriptor_bytes).map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "parse x86 codegen-object descriptor {} at {}: {err}",
                            descriptor_artifact.key,
                            descriptor_artifact.path.display()
                        ))
                    })?;
                descriptor
                    .validate_contract_for(
                        GpuSourcePackArtifactStage::CodegenObject,
                        Some(SourcePackArtifactTarget::X86_64),
                    )
                    .map_err(|reason| {
                        source_pack_artifact_store_error(format!(
                            "validate x86 codegen-object descriptor {}: {reason}",
                            descriptor_artifact.key
                        ))
                    })?;
                let payload = descriptor.codegen_object_payload.as_ref().ok_or_else(|| {
                    source_pack_artifact_store_error(format!(
                        "x86 codegen-object descriptor {} has no persisted object payload",
                        descriptor_artifact.key
                    ))
                })?;
                if payload.format != GpuSourcePackCodegenObjectFormat::LaniusX86_64
                    || payload.format_version != x86::GPU_X86_OBJECT_VERSION
                {
                    return Err(source_pack_artifact_store_error(format!(
                        "x86 codegen-object descriptor {} has unsupported payload {:?} version {}",
                        descriptor_artifact.key, payload.format, payload.format_version
                    )));
                }
                let object_path = artifact_path(&self.artifact_root, &payload.storage_key)?;
                let object_bytes = fs::read(&object_path).map_err(|err| {
                    source_pack_artifact_store_error(format!(
                        "read x86 codegen object {} at {}: {err}",
                        payload.storage_key,
                        object_path.display()
                    ))
                })?;
                if object_bytes.len() != payload.byte_len {
                    return Err(source_pack_artifact_store_error(format!(
                        "x86 codegen object {} has {} bytes but descriptor records {}",
                        payload.storage_key,
                        object_bytes.len(),
                        payload.byte_len
                    )));
                }
                x86::GpuX86RelocatableObject::from_bytes(&object_bytes).map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "parse x86 codegen object {}: {reason}",
                        payload.storage_key
                    ))
                })
            })
            .collect()
    }

    fn load_wasm_codegen_object_artifacts(
        &self,
        descriptor_artifacts: &[ArtifactPath],
    ) -> Result<Vec<wasm::GpuWasmRelocatableObject>, CompileError> {
        descriptor_artifacts
            .iter()
            .map(|descriptor_artifact| {
                let descriptor_bytes = fs::read(&descriptor_artifact.path).map_err(|err| {
                    source_pack_artifact_store_error(format!(
                        "read Wasm codegen-object descriptor {} at {}: {err}",
                        descriptor_artifact.key,
                        descriptor_artifact.path.display()
                    ))
                })?;
                let descriptor: GpuSourcePackArtifactDescriptor =
                    serde_json::from_slice(&descriptor_bytes).map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "parse Wasm codegen-object descriptor {} at {}: {err}",
                            descriptor_artifact.key,
                            descriptor_artifact.path.display()
                        ))
                    })?;
                descriptor
                    .validate_contract_for(
                        GpuSourcePackArtifactStage::CodegenObject,
                        Some(SourcePackArtifactTarget::Wasm),
                    )
                    .map_err(|reason| {
                        source_pack_artifact_store_error(format!(
                            "validate Wasm codegen-object descriptor {}: {reason}",
                            descriptor_artifact.key
                        ))
                    })?;
                let payload = descriptor.codegen_object_payload.as_ref().ok_or_else(|| {
                    source_pack_artifact_store_error(format!(
                        "Wasm codegen-object descriptor {} has no persisted object payload",
                        descriptor_artifact.key
                    ))
                })?;
                if payload.format != GpuSourcePackCodegenObjectFormat::LaniusWasm
                    || payload.format_version != wasm::GPU_WASM_OBJECT_VERSION
                {
                    return Err(source_pack_artifact_store_error(format!(
                        "Wasm codegen-object descriptor {} has unsupported payload {:?} version {}",
                        descriptor_artifact.key, payload.format, payload.format_version
                    )));
                }
                let object_path = artifact_path(&self.artifact_root, &payload.storage_key)?;
                let object_bytes = fs::read(&object_path).map_err(|err| {
                    source_pack_artifact_store_error(format!(
                        "read Wasm codegen object {} at {}: {err}",
                        payload.storage_key,
                        object_path.display()
                    ))
                })?;
                if object_bytes.len() != payload.byte_len {
                    return Err(source_pack_artifact_store_error(format!(
                        "Wasm codegen object {} has {} bytes but descriptor records {}",
                        payload.storage_key,
                        object_bytes.len(),
                        payload.byte_len
                    )));
                }
                wasm::GpuWasmRelocatableObject::from_bytes(&object_bytes).map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "parse Wasm codegen object {}: {reason}",
                        payload.storage_key
                    ))
                })
            })
            .collect()
    }
}

/// Builds the artifact key for a source-pack descriptor artifact.
pub(super) fn gpu_source_pack_descriptor_artifact_key(
    target: SourcePackArtifactTarget,
    stage: GpuSourcePackArtifactStage,
    key_suffix: &str,
) -> String {
    let target = target.key_prefix().unwrap_or("generic");
    let stage = match stage {
        GpuSourcePackArtifactStage::LibraryInterface => "library-interface",
        GpuSourcePackArtifactStage::CodegenObject => "codegen-object",
        GpuSourcePackArtifactStage::PartialLink => "partial-link",
        GpuSourcePackArtifactStage::LinkedOutput => "linked-output",
    };
    format!("gpu-source-pack/{target}/{stage}/{key_suffix}.json")
}

fn gpu_source_pack_semantic_interface_artifact_key(
    target: SourcePackArtifactTarget,
    key_suffix: &str,
) -> String {
    let target = target.key_prefix().unwrap_or("generic");
    format!("gpu-source-pack/{target}/semantic-interface/{key_suffix}.lnsi")
}

fn gpu_source_pack_x86_codegen_object_artifact_key(key_suffix: &str) -> String {
    format!("gpu-source-pack/x86_64/codegen-object/{key_suffix}.lnxo")
}

fn gpu_source_pack_wasm_codegen_object_artifact_key(key_suffix: &str) -> String {
    format!("gpu-source-pack/wasm/codegen-object/{key_suffix}.lnwo")
}

fn gpu_source_pack_x86_linked_output_artifact_key(key_suffix: &str) -> String {
    format!("gpu-source-pack/x86_64/linked-output/{key_suffix}.elf")
}

fn gpu_source_pack_wasm_linked_output_artifact_key(key_suffix: &str) -> String {
    format!("gpu-source-pack/wasm/linked-output/{key_suffix}.wasm")
}

fn semantic_interface_record_count(interface: &GpuSemanticInterfaceArtifact) -> usize {
    interface
        .modules
        .len()
        .saturating_add(interface.module_segments.len())
        .saturating_add(interface.declarations.len())
        .saturating_add(interface.types.len())
        .saturating_add(interface.type_edges.len())
        .saturating_add(interface.members.len())
}

fn attach_semantic_interface_artifact(
    descriptor: &mut GpuSourcePackArtifactDescriptor,
    artifact: &ArtifactPath,
    record_count: usize,
    byte_len: usize,
) {
    let attach_array = |array: &mut GpuSourcePackRecordArrayDescriptor| {
        if array.name == "semantic_interface_records" {
            array.element_count = Some(record_count);
            array.byte_len = Some(byte_len);
            array.storage_key = Some(artifact.key.clone());
        }
    };
    descriptor
        .output_record_arrays
        .iter_mut()
        .for_each(attach_array);
    descriptor.record_arrays.iter_mut().for_each(attach_array);
    for record in &mut descriptor.descriptor_records {
        if record.record_array == "semantic_interface_records" {
            record.element_count = Some(record_count);
        }
    }
}

fn attach_x86_codegen_object_artifact(
    descriptor: &mut GpuSourcePackArtifactDescriptor,
    artifact: &ArtifactPath,
    object: &x86::GpuX86RelocatableObject,
    byte_len: usize,
) {
    let count_for = |name: &str| match name {
        "object_section_records" => Some(2),
        "object_symbol_records" => Some(object.symbols.len()),
        "relocation_records" => Some(object.relocations.len()),
        _ => None,
    };
    let attach_array = |array: &mut GpuSourcePackRecordArrayDescriptor| {
        if let Some(count) = count_for(&array.name) {
            array.element_count = Some(count);
        }
    };
    descriptor
        .output_record_arrays
        .iter_mut()
        .for_each(attach_array);
    descriptor.record_arrays.iter_mut().for_each(attach_array);
    for record in &mut descriptor.descriptor_records {
        if let Some(count) = count_for(&record.record_array) {
            record.element_count = Some(count);
        }
    }
    descriptor.codegen_object_payload = Some(GpuSourcePackCodegenObjectPayloadDescriptor {
        format: GpuSourcePackCodegenObjectFormat::LaniusX86_64,
        format_version: x86::GPU_X86_OBJECT_VERSION,
        storage_key: artifact.key.clone(),
        byte_len,
    });
}

fn attach_wasm_codegen_object_artifact(
    descriptor: &mut GpuSourcePackArtifactDescriptor,
    artifact: &ArtifactPath,
    object: &wasm::GpuWasmRelocatableObject,
    byte_len: usize,
) {
    let count_for = |name: &str| match name {
        "object_section_records" => Some(2),
        "object_symbol_records" => Some(object.symbols.len()),
        "relocation_records" => Some(object.relocations.len()),
        _ => None,
    };
    let attach_array = |array: &mut GpuSourcePackRecordArrayDescriptor| {
        if let Some(count) = count_for(&array.name) {
            array.element_count = Some(count);
        }
    };
    descriptor
        .output_record_arrays
        .iter_mut()
        .for_each(attach_array);
    descriptor.record_arrays.iter_mut().for_each(attach_array);
    for record in &mut descriptor.descriptor_records {
        if let Some(count) = count_for(&record.record_array) {
            record.element_count = Some(count);
        }
    }
    descriptor.codegen_object_payload = Some(GpuSourcePackCodegenObjectPayloadDescriptor {
        format: GpuSourcePackCodegenObjectFormat::LaniusWasm,
        format_version: wasm::GPU_WASM_OBJECT_VERSION,
        storage_key: artifact.key.clone(),
        byte_len,
    });
}

fn attach_linked_output_artifact(
    descriptor: &mut GpuSourcePackArtifactDescriptor,
    artifact: &ArtifactPath,
    byte_len: usize,
) {
    let attach_array = |array: &mut GpuSourcePackRecordArrayDescriptor| {
        if array.name == "emitted_byte_records" {
            array.element_count = Some(byte_len);
            array.byte_len = Some(byte_len);
            array.storage_key = Some(artifact.key.clone());
        }
    };
    descriptor
        .output_record_arrays
        .iter_mut()
        .for_each(attach_array);
    descriptor.record_arrays.iter_mut().for_each(attach_array);
}

impl<'compiler, 'gpu> AsyncPagedArtifactBuildExecutor
    for GpuSourcePackArtifactExecutor<'compiler, 'gpu>
{
    type LibraryInterfaceArtifact = ArtifactPath;
    type CodegenObjectArtifact = ArtifactPath;
    type LinkHandle = GpuSourcePackLinkHandle;
    type LinkedOutputArtifact = ArtifactPath;
    type LibraryInterfaceBuildHandle = GpuSourcePackLibraryInterfaceBuildHandle;
    type CodegenObjectBuildHandle = GpuSourcePackCodegenObjectBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle> {
        Box::pin(async move {
            Ok(GpuSourcePackLibraryInterfaceBuildHandle {
                job: job.clone(),
                source_files: source_files.to_vec(),
                dependency_interfaces: GpuSourcePackDependencyInterfaceSummary::default(),
                dependency_interface_artifacts: Vec::new(),
            })
        })
    }

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "library-interface dependency batch",
                job.job_index,
                dependency_interfaces,
            )?;
            handle
                .dependency_interfaces
                .add_batch(dependency_interfaces.len());
            handle
                .dependency_interface_artifacts
                .extend_from_slice(dependency_interfaces);
            Ok(())
        })
    }

    fn finish_library_interface<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact> {
        Box::pin(async move { self.finish_library_interface_artifact(handle).await })
    }

    fn begin_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle> {
        Box::pin(async move {
            Ok(GpuSourcePackCodegenObjectBuildHandle {
                job: job.clone(),
                source_files: source_files.to_vec(),
                library_interface_artifact: library_interface.clone(),
                dependency_interfaces: GpuSourcePackDependencyInterfaceSummary::default(),
                dependency_interface_artifacts: Vec::new(),
            })
        })
    }

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "codegen dependency batch",
                job.job_index,
                dependency_interfaces,
            )?;
            handle
                .dependency_interfaces
                .add_batch(dependency_interfaces.len());
            handle
                .dependency_interface_artifacts
                .extend_from_slice(dependency_interfaces);
            Ok(())
        })
    }

    fn finish_codegen_object<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact> {
        Box::pin(async move { self.finish_codegen_object_artifact(handle).await })
    }

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move { Ok(GpuSourcePackLinkHandle::default()) })
    }

    fn link_library_interface_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        _batch: &'a SourcePackLinkInterfaceBatch,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "link interface batch",
                job.job_index,
                library_interfaces,
            )?;
            link_handle.interface_count = link_handle
                .interface_count
                .saturating_add(library_interfaces.len());
            Ok(())
        })
    }

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        _batch: &'a SourcePackLinkObjectBatch,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "link object batch",
                job.job_index,
                codegen_objects,
            )?;
            link_handle.object_count = link_handle
                .object_count
                .saturating_add(codegen_objects.len());
            link_handle
                .codegen_object_artifacts
                .extend_from_slice(codegen_objects);
            Ok(())
        })
    }

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move { self.finish_linked_output_artifact(job, link_handle).await })
    }
}

impl<'compiler, 'gpu> AsyncHierarchicalLinkExecutor
    for GpuSourcePackArtifactExecutor<'compiler, 'gpu>
{
    type PartialLinkArtifact = ArtifactPath;

    fn begin_hierarchical_link_group<'a>(
        &'a mut self,
        _page: &'a SourcePackHierarchicalLinkExecutionPage,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move { Ok(GpuSourcePackLinkHandle::default()) })
    }

    fn link_hierarchical_library_interfaces<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "hierarchical link interface batch",
                page.group_index,
                library_interfaces,
            )?;
            link_handle.interface_count = link_handle
                .interface_count
                .saturating_add(library_interfaces.len());
            Ok(())
        })
    }

    fn link_hierarchical_codegen_objects<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "hierarchical link object batch",
                page.group_index,
                codegen_objects,
            )?;
            link_handle.object_count = link_handle
                .object_count
                .saturating_add(codegen_objects.len());
            link_handle
                .codegen_object_artifacts
                .extend_from_slice(codegen_objects);
            Ok(())
        })
    }

    fn link_hierarchical_partial_links<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        partial_links: &'a [Self::PartialLinkArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "hierarchical partial-link batch",
                page.group_index,
                partial_links,
            )?;
            link_handle.partial_link_count = link_handle
                .partial_link_count
                .saturating_add(partial_links.len());
            link_handle
                .partial_link_artifacts
                .extend_from_slice(partial_links);
            Ok(())
        })
    }

    fn finish_hierarchical_partial_link_group<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::PartialLinkArtifact> {
        Box::pin(async move { self.finish_hierarchical_partial_link_artifact(page, link_handle) })
    }

    fn finish_hierarchical_link_output<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move { self.finish_hierarchical_linked_output_artifact(page, link_handle) })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_interface_descriptor_points_at_concrete_semantic_interface_bytes() {
        let job = SourcePackJob {
            job_index: 7,
            phase: SourcePackJobPhase::LibraryFrontend,
            phase_unit_index: 3,
            library_job_index: None,
            library_id: 11,
            first_source_index: 5,
            source_file_count: 2,
            source_bytes: 4096,
            source_lines: 90,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        };
        let mut descriptor = GpuSourcePackArtifactDescriptor::library_interface_for_job(
            SourcePackArtifactTarget::Wasm,
            &job,
            GpuSourcePackDependencyInterfaceSummary::counted(2, 1),
        );
        let artifact = ArtifactPath {
            key: "gpu-source-pack/wasm/semantic-interface/job-7.lnsi".into(),
            path: PathBuf::from("unused-by-descriptor-test"),
        };

        attach_semantic_interface_artifact(&mut descriptor, &artifact, 31, 512);

        descriptor
            .validate_contract()
            .expect("concrete semantic-interface descriptor should remain valid");
        for arrays in [&descriptor.output_record_arrays, &descriptor.record_arrays] {
            let semantic = arrays
                .iter()
                .find(|array| array.name == "semantic_interface_records")
                .expect("descriptor should retain semantic-interface record array");
            assert_eq!(semantic.element_count, Some(31));
            assert_eq!(semantic.byte_len, Some(512));
            assert_eq!(semantic.storage_key.as_deref(), Some(artifact.key.as_str()));
        }
        let symbols = descriptor
            .descriptor_records
            .iter()
            .find(|record| record.name == "semantic_interface_symbols")
            .expect("descriptor should retain semantic-interface symbol row");
        assert_eq!(symbols.element_count, Some(31));
    }

    #[test]
    fn x86_codegen_descriptor_points_at_one_complete_object_container() {
        let job = SourcePackJob {
            job_index: 9,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: 4,
            library_job_index: Some(3),
            library_id: 11,
            first_source_index: 5,
            source_file_count: 1,
            source_bytes: 128,
            source_lines: 6,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        };
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::X86_64,
            &job,
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        let artifact = ArtifactPath {
            key: "gpu-source-pack/x86_64/codegen-object/job-9.lnxo".into(),
            path: PathBuf::from("unused-by-descriptor-test"),
        };
        let object = x86::GpuX86RelocatableObject {
            version: x86::GPU_X86_OBJECT_VERSION,
            library_id: 11,
            unit_id: 4,
            entry_offset: Some(0),
            text: vec![0xc3],
            rodata: Vec::new(),
            relocations: Vec::new(),
            symbols: Vec::new(),
            identity_bytes: Vec::new(),
        };

        attach_x86_codegen_object_artifact(&mut descriptor, &artifact, &object, 41);

        descriptor
            .validate_contract()
            .expect("concrete x86 object descriptor should remain valid");
        let payload = descriptor
            .codegen_object_payload
            .as_ref()
            .expect("descriptor should reference the object container");
        assert_eq!(payload.storage_key, artifact.key);
        assert_eq!(payload.byte_len, 41);
        assert_eq!(payload.format_version, x86::GPU_X86_OBJECT_VERSION);
        assert_eq!(
            payload.format,
            GpuSourcePackCodegenObjectFormat::LaniusX86_64
        );
        for arrays in [&descriptor.output_record_arrays, &descriptor.record_arrays] {
            assert_eq!(
                arrays
                    .iter()
                    .find(|array| array.name == "object_section_records")
                    .and_then(|array| array.element_count),
                Some(2)
            );
            assert_eq!(
                arrays
                    .iter()
                    .find(|array| array.name == "object_symbol_records")
                    .and_then(|array| array.element_count),
                Some(0)
            );
            assert!(arrays.iter().all(|array| array.storage_key.is_none()));
        }
    }
}
