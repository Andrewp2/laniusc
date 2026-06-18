use super::*;
use crate::codegen::unit::artifact_key_for_output;

/// Validates the full artifact manifest contract.
///
/// This is the top-level consistency check for manifest replay: it verifies
/// counts, dense positional records, job dependency shape, artifact provenance,
/// job batches, artifact IO, artifact uses, and link-input batches.
pub(in crate::compiler) fn validate_artifact_manifest_contract(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    let job_count = manifest.job_count;
    let artifact_count = manifest.artifact_count;
    if job_count == 0 {
        return Err(manifest_contract_error("artifact manifest has no jobs"));
    }
    if manifest.job_batch_count == 0 {
        return Err(manifest_contract_error(
            "artifact manifest has no job batches",
        ));
    }
    if artifact_count == 0 {
        return Err(manifest_contract_error(
            "artifact manifest has no artifacts",
        ));
    }
    if manifest.batch_dependency_count != manifest.job_batch_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest records {} batch dependencies but {} job batches",
            manifest.batch_dependency_count, manifest.job_batch_count
        )));
    }
    if manifest.job_artifact_count != job_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest records {} job artifact manifests but {} jobs",
            manifest.job_artifact_count, job_count
        )));
    }
    if manifest.job_artifact_io_count != job_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest records {} job artifact-io records but {} jobs",
            manifest.job_artifact_io_count, job_count
        )));
    }
    if manifest.artifact_use_count != artifact_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest records {} artifact uses but {} artifacts",
            manifest.artifact_use_count, artifact_count
        )));
    }

    let has_record_arrays = !manifest.job_schedule.jobs.is_empty()
        || !manifest.job_batches.batches.is_empty()
        || !manifest.batch_dependencies.batches.is_empty()
        || !manifest.artifacts.artifacts.is_empty()
        || !manifest.job_artifacts.jobs.is_empty()
        || !manifest.job_artifact_io.jobs.is_empty()
        || !manifest.artifact_uses.uses.is_empty()
        || !manifest.link_interface_batches.batches.is_empty()
        || !manifest.link_object_batches.batches.is_empty();
    if !has_record_arrays {
        return Ok(());
    }
    if manifest.job_schedule.jobs.len() != job_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} job records but job_count {}",
            manifest.job_schedule.jobs.len(),
            job_count
        )));
    }
    if !manifest
        .job_schedule
        .dependency_job_ranges_by_job_index
        .is_empty()
        && manifest
            .job_schedule
            .dependency_job_ranges_by_job_index
            .len()
            != job_count
    {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} positional dependency-range rows but job_count {}; package/link replay must either omit dependency range rows or carry exactly one row per job",
            manifest
                .job_schedule
                .dependency_job_ranges_by_job_index
                .len(),
            job_count
        )));
    }
    if manifest.job_batches.batches.len() != manifest.job_batch_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} job-batch records but job_batch_count {}",
            manifest.job_batches.batches.len(),
            manifest.job_batch_count
        )));
    }
    if manifest.batch_dependencies.batches.len() != manifest.batch_dependency_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} batch-dependency records but batch_dependency_count {}",
            manifest.batch_dependencies.batches.len(),
            manifest.batch_dependency_count
        )));
    }
    if manifest.artifacts.artifacts.len() != artifact_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} artifact records but artifact_count {}",
            manifest.artifacts.artifacts.len(),
            artifact_count
        )));
    }
    if manifest.job_artifacts.jobs.len() != manifest.job_artifact_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} job-artifact records but job_artifact_count {}",
            manifest.job_artifacts.jobs.len(),
            manifest.job_artifact_count
        )));
    }
    if manifest.job_artifact_io.jobs.len() != manifest.job_artifact_io_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} job-artifact-io records but job_artifact_io_count {}",
            manifest.job_artifact_io.jobs.len(),
            manifest.job_artifact_io_count
        )));
    }
    if manifest.artifact_uses.uses.len() != manifest.artifact_use_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} artifact-use records but artifact_use_count {}",
            manifest.artifact_uses.uses.len(),
            manifest.artifact_use_count
        )));
    }
    if manifest.link_interface_batches.batches.len() != manifest.link_interface_batch_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} link-interface batch records but link_interface_batch_count {}",
            manifest.link_interface_batches.batches.len(),
            manifest.link_interface_batch_count
        )));
    }
    if manifest.link_object_batches.batches.len() != manifest.link_object_batch_count {
        return Err(manifest_contract_error(format!(
            "artifact manifest has {} link-object batch records but link_object_batch_count {}",
            manifest.link_object_batches.batches.len(),
            manifest.link_object_batch_count
        )));
    }

    let mut link_job_indices = Vec::new();

    for (job_position, job) in manifest.job_schedule.jobs.iter().enumerate() {
        if job.job_index != job_position {
            return Err(manifest_contract_error(format!(
                "job schedule entry {job_position} has job_index {}",
                job.job_index
            )));
        }
        if job.phase == SourcePackJobPhase::Link {
            link_job_indices.push(job.job_index);
        }
        let explicit_dependencies = unique_usize_set(
            &job.dependency_job_indices,
            &format!("job {} dependencies", job.job_index),
        )?;
        validate_usize_values_strictly_ascending(
            &job.dependency_job_indices,
            &format!("job {} dependencies", job.job_index),
            |message| manifest_contract_error(message),
        )?;
        validate_job_dependency_ranges(
            manifest.job_schedule.dependency_job_ranges_for_job(job),
            &explicit_dependencies,
            &format!("job {}", job.job_index),
            job_count,
            |message| manifest_contract_error(message),
        )?;
        for &dependency_job_index in &job.dependency_job_indices {
            if dependency_job_index >= job_count {
                return Err(manifest_contract_error(format!(
                    "job {} depends on missing job {}",
                    job.job_index, dependency_job_index
                )));
            }
            if dependency_job_index == job.job_index {
                return Err(manifest_contract_error(format!(
                    "job {} depends on itself",
                    job.job_index
                )));
            }
        }
        for dependency_job_range in manifest.job_schedule.dependency_job_ranges_for_job(job) {
            if dependency_job_range.contains(job.job_index) {
                return Err(manifest_contract_error(format!(
                    "job {} dependency range contains itself",
                    job.job_index
                )));
            }
        }
    }

    if link_job_indices.len() != 1 {
        return Err(manifest_contract_error(format!(
            "expected exactly one link job, found {}",
            link_job_indices.len()
        )));
    }
    let link_job_index = link_job_indices[0];
    validate_manifest_link_job_dependency_shape(manifest, link_job_index)?;

    let mut output_artifact_indices_by_job = vec![Vec::new(); job_count];
    let mut linked_output_artifact_count = 0usize;
    for (artifact_position, artifact) in manifest.artifacts.artifacts.iter().enumerate() {
        if artifact.artifact_index != artifact_position {
            return Err(manifest_contract_error(format!(
                "artifact entry {artifact_position} has artifact_index {}",
                artifact.artifact_index
            )));
        }
        validate_manifest_artifact_key_kind(
            manifest.target,
            &artifact.key,
            artifact.kind,
            &format!("artifact {}", artifact.artifact_index),
        )?;
        validate_manifest_artifact_key_identity(manifest.target, artifact)?;
        let Some(producer_job) = manifest.job_schedule.jobs.get(artifact.producing_job_index)
        else {
            return Err(manifest_contract_error(format!(
                "artifact {} is produced by missing job {}",
                artifact.artifact_index, artifact.producing_job_index
            )));
        };
        let expected_kind = match producer_job.phase {
            SourcePackJobPhase::LibraryFrontend => SourcePackArtifactKind::LibraryInterface,
            SourcePackJobPhase::Codegen => SourcePackArtifactKind::CodegenObject,
            SourcePackJobPhase::Link => SourcePackArtifactKind::LinkedOutput,
        };
        if artifact.kind != expected_kind {
            return Err(manifest_contract_error(format!(
                "artifact {} kind {:?} does not match producer job {} phase {:?}",
                artifact.artifact_index, artifact.kind, producer_job.job_index, producer_job.phase
            )));
        }
        validate_manifest_artifact_producer_provenance(artifact, producer_job)?;
        if artifact.kind == SourcePackArtifactKind::LinkedOutput {
            linked_output_artifact_count += 1;
        }
        output_artifact_indices_by_job[artifact.producing_job_index].push(artifact.artifact_index);
    }

    if linked_output_artifact_count != 1 {
        return Err(manifest_contract_error(format!(
            "expected exactly one linked output artifact, found {linked_output_artifact_count}"
        )));
    }

    let job_to_batch = validate_manifest_job_batches(manifest, job_count)?;
    validate_manifest_batch_dependencies(manifest, &job_to_batch)?;

    let mut actual_artifact_consumers = vec![BTreeSet::new(); artifact_count];
    validate_manifest_job_artifacts(
        manifest,
        &output_artifact_indices_by_job,
        &mut actual_artifact_consumers,
    )?;
    validate_manifest_job_artifact_io(manifest)?;
    validate_manifest_artifact_uses(manifest, &actual_artifact_consumers)?;
    validate_manifest_link_batches(manifest, link_job_index)?;

    Ok(())
}

fn validate_manifest_link_job_dependency_shape(
    manifest: &SourcePackBuildArtifactManifest,
    link_job_index: usize,
) -> Result<(), CompileError> {
    let link_job = &manifest.job_schedule.jobs[link_job_index];
    let link_dependency_ranges = manifest
        .job_schedule
        .dependency_job_ranges_for_job(link_job);
    if link_job.dependency_job_indices.is_empty() && link_dependency_ranges.is_empty() {
        return Ok(());
    }

    let mut actual_dependencies = unique_usize_set(
        &link_job.dependency_job_indices,
        &format!("link job {} dependencies", link_job.job_index),
    )?;
    for dependency_job_range in link_dependency_ranges {
        let Some(dependency_job_indices) = dependency_job_range.iter() else {
            return Err(manifest_contract_error(format!(
                "link job {} dependency range starting at {} overflows usize",
                link_job.job_index, dependency_job_range.first_job_index
            )));
        };
        actual_dependencies.extend(dependency_job_indices);
    }

    let expected_codegen_dependencies = manifest
        .job_schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::Codegen)
        .map(|job| job.job_index)
        .collect::<BTreeSet<_>>();
    if actual_dependencies == expected_codegen_dependencies {
        return Ok(());
    }

    let missing = expected_codegen_dependencies
        .difference(&actual_dependencies)
        .copied()
        .collect::<Vec<_>>();
    let unexpected = actual_dependencies
        .difference(&expected_codegen_dependencies)
        .copied()
        .collect::<Vec<_>>();
    Err(manifest_contract_error(format!(
        "link job {} explicit dependencies do not cover exactly the codegen object producer jobs: missing {:?}, unexpected {:?}; link readiness must be all codegen outputs, not a package/import subset",
        link_job.job_index, missing, unexpected
    )))
}

fn validate_manifest_artifact_key_identity(
    target: SourcePackArtifactTarget,
    artifact: &SourcePackArtifactManifestEntry,
) -> Result<(), CompileError> {
    let expected_key = artifact_key_for_output(
        target,
        artifact.kind,
        artifact.library_id,
        artifact.producing_job_index,
        artifact.first_source_index,
        artifact.source_file_count,
    );
    if artifact.key == expected_key {
        return Ok(());
    }
    Err(manifest_contract_error(format!(
        "artifact {} key {:?} does not match persisted artifact identity; expected {:?} for target {:?} {:?} library {} producer job {} source range {}..{}",
        artifact.artifact_index,
        artifact.key,
        expected_key,
        target,
        artifact.kind,
        artifact.library_id,
        artifact.producing_job_index,
        artifact.first_source_index,
        artifact
            .first_source_index
            .saturating_add(artifact.source_file_count)
    )))
}

fn validate_manifest_artifact_producer_provenance(
    artifact: &SourcePackArtifactManifestEntry,
    producer_job: &SourcePackJob,
) -> Result<(), CompileError> {
    if artifact.kind == SourcePackArtifactKind::LinkedOutput {
        return Ok(());
    }

    if artifact.library_id == producer_job.library_id
        && artifact.first_source_index == producer_job.first_source_index
        && artifact.source_file_count == producer_job.source_file_count
        && artifact.source_bytes == producer_job.source_bytes
        && artifact.source_lines == producer_job.source_lines
    {
        return Ok(());
    }

    Err(manifest_contract_error(format!(
        "artifact {} provenance does not match producer job {}: artifact library {} source range {}..{} bytes {} lines {}, producer library {} source range {}..{} bytes {} lines {}",
        artifact.artifact_index,
        producer_job.job_index,
        artifact.library_id,
        artifact.first_source_index,
        artifact
            .first_source_index
            .saturating_add(artifact.source_file_count),
        artifact.source_bytes,
        artifact.source_lines,
        producer_job.library_id,
        producer_job.first_source_index,
        producer_job
            .first_source_index
            .saturating_add(producer_job.source_file_count),
        producer_job.source_bytes,
        producer_job.source_lines
    )))
}

/// Validates job-batch records and returns each job's owning batch.
///
/// Every job must appear in exactly one batch, batch job indices must be sorted
/// and unique, and batch source totals must equal the sum of their jobs.
pub(in crate::compiler) fn validate_manifest_job_batches(
    manifest: &SourcePackBuildArtifactManifest,
    job_count: usize,
) -> Result<Vec<usize>, CompileError> {
    let mut job_to_batch = vec![None; job_count];
    for (batch_position, batch) in manifest.job_batches.batches.iter().enumerate() {
        if batch.batch_index != batch_position {
            return Err(manifest_contract_error(format!(
                "job batch entry {batch_position} has batch_index {}",
                batch.batch_index
            )));
        }
        unique_usize_set(
            &batch.job_indices,
            &format!("job batch {} jobs", batch.batch_index),
        )?;
        validate_usize_values_strictly_ascending(
            &batch.job_indices,
            &format!("job batch {} jobs", batch.batch_index),
            |message| manifest_contract_error(message),
        )?;
        let mut source_bytes = 0usize;
        let mut source_file_count = 0usize;
        for &job_index in &batch.job_indices {
            let Some(job) = manifest.job_schedule.jobs.get(job_index) else {
                return Err(manifest_contract_error(format!(
                    "job batch {} references missing job {}",
                    batch.batch_index, job_index
                )));
            };
            if job_to_batch[job_index].replace(batch.batch_index).is_some() {
                return Err(manifest_contract_error(format!(
                    "job {job_index} appears in more than one batch"
                )));
            }
            source_bytes = source_bytes.saturating_add(job.source_bytes);
            source_file_count = source_file_count.saturating_add(job.source_file_count);
        }
        if batch.source_bytes != source_bytes {
            return Err(manifest_contract_error(format!(
                "job batch {} records {} source bytes but its jobs sum to {}",
                batch.batch_index, batch.source_bytes, source_bytes
            )));
        }
        if batch.source_file_count != source_file_count {
            return Err(manifest_contract_error(format!(
                "job batch {} records {} source files but its jobs sum to {}",
                batch.batch_index, batch.source_file_count, source_file_count
            )));
        }
    }

    let mut dense_job_to_batch = Vec::with_capacity(job_count);
    for (job_index, batch_index) in job_to_batch.into_iter().enumerate() {
        let Some(batch_index) = batch_index else {
            return Err(manifest_contract_error(format!(
                "job {job_index} does not appear in any batch"
            )));
        };
        dense_job_to_batch.push(batch_index);
    }
    Ok(dense_job_to_batch)
}

/// Validates that batch dependencies match the job dependency graph.
///
/// The listed dependency batches, including compact ranges, are compared with
/// the dependencies implied by every job in the batch. Link jobs without explicit
/// dependencies are treated as depending on all codegen batches.
pub(in crate::compiler) fn validate_manifest_batch_dependencies(
    manifest: &SourcePackBuildArtifactManifest,
    job_to_batch: &[usize],
) -> Result<(), CompileError> {
    let batch_count = manifest.job_batches.batches.len();
    if manifest.batch_dependencies.batches.len() != batch_count {
        return Err(manifest_contract_error(format!(
            "batch dependency plan has {} batches but job batch schedule has {}",
            manifest.batch_dependencies.batches.len(),
            batch_count
        )));
    }

    for (batch_position, dependency) in manifest.batch_dependencies.batches.iter().enumerate() {
        if dependency.batch_index != batch_position {
            return Err(manifest_contract_error(format!(
                "batch dependency entry {batch_position} has batch_index {}",
                dependency.batch_index
            )));
        }
        let mut listed = unique_usize_set(
            &dependency.dependency_batch_indices,
            &format!("batch {} dependencies", dependency.batch_index),
        )?;
        validate_usize_values_strictly_ascending(
            &dependency.dependency_batch_indices,
            &format!("batch {} dependencies", dependency.batch_index),
            |message| manifest_contract_error(message),
        )?;
        for &dependency_batch_index in &dependency.dependency_batch_indices {
            if dependency_batch_index >= batch_count {
                return Err(manifest_contract_error(format!(
                    "batch {} depends on missing batch {}",
                    dependency.batch_index, dependency_batch_index
                )));
            }
            if dependency_batch_index == dependency.batch_index {
                return Err(manifest_contract_error(format!(
                    "batch {} depends on itself",
                    dependency.batch_index
                )));
            }
        }
        validate_job_batch_dependency_ranges(
            dependency,
            &listed,
            &format!("batch {}", dependency.batch_index),
            batch_count,
            Some(dependency.batch_index),
            |message| manifest_contract_error(message),
        )?;
        for range in &dependency.dependency_batch_ranges {
            let Some(indices) = range.iter() else {
                return Err(manifest_contract_error(format!(
                    "batch {} dependency range starting at {} overflows usize",
                    dependency.batch_index, range.first_batch_index
                )));
            };
            listed.extend(indices);
        }

        let batch = &manifest.job_batches.batches[dependency.batch_index];
        let mut expected = BTreeSet::new();
        for &job_index in &batch.job_indices {
            let job = &manifest.job_schedule.jobs[job_index];
            for &dependency_job_index in &job.dependency_job_indices {
                let dependency_batch_index = job_to_batch[dependency_job_index];
                if dependency_batch_index != dependency.batch_index {
                    expected.insert(dependency_batch_index);
                }
            }
            for dependency_job_range in manifest.job_schedule.dependency_job_ranges_for_job(job) {
                let Some(dependency_job_indices) = dependency_job_range.iter() else {
                    return Err(manifest_contract_error(format!(
                        "job {} dependency range starting at {} overflows usize",
                        job.job_index, dependency_job_range.first_job_index
                    )));
                };
                for dependency_job_index in dependency_job_indices {
                    let dependency_batch_index = job_to_batch[dependency_job_index];
                    if dependency_batch_index != dependency.batch_index {
                        expected.insert(dependency_batch_index);
                    }
                }
            }
            if job.phase == SourcePackJobPhase::Link
                && job.dependency_job_indices.is_empty()
                && manifest
                    .job_schedule
                    .dependency_job_ranges_for_job(job)
                    .is_empty()
            {
                for codegen_job in manifest
                    .job_schedule
                    .jobs
                    .iter()
                    .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                {
                    let dependency_batch_index = job_to_batch[codegen_job.job_index];
                    if dependency_batch_index != dependency.batch_index {
                        expected.insert(dependency_batch_index);
                    }
                }
            }
        }
        if listed != expected {
            return Err(manifest_contract_error(format!(
                "batch dependency mismatch for batch {}: listed {:?}, expected {:?}",
                dependency.batch_index, listed, expected
            )));
        }
    }
    Ok(())
}

/// Validates per-job artifact manifests and records actual artifact consumers.
///
/// The function checks each job's input/output shape, reference kinds, range
/// metadata, dependency legality, and output provenance. As it validates inputs,
/// it fills `actual_artifact_consumers` for the later artifact-use check.
pub(in crate::compiler) fn validate_manifest_job_artifacts(
    manifest: &SourcePackBuildArtifactManifest,
    output_artifact_indices_by_job: &[Vec<usize>],
    actual_artifact_consumers: &mut [BTreeSet<usize>],
) -> Result<(), CompileError> {
    let job_count = manifest.job_schedule.jobs.len();
    if manifest.job_artifacts.jobs.len() != job_count {
        return Err(manifest_contract_error(format!(
            "job artifact manifest has {} jobs but schedule has {}",
            manifest.job_artifacts.jobs.len(),
            job_count
        )));
    }

    for (job_position, job_manifest) in manifest.job_artifacts.jobs.iter().enumerate() {
        if job_manifest.job_index != job_position {
            return Err(manifest_contract_error(format!(
                "job artifact entry {job_position} has job_index {}",
                job_manifest.job_index
            )));
        }
        let job = &manifest.job_schedule.jobs[job_position];
        if job_manifest.phase != job.phase {
            return Err(manifest_contract_error(format!(
                "job artifact manifest for job {} has phase {:?} but schedule has {:?}",
                job_position, job_manifest.phase, job.phase
            )));
        }
        validate_manifest_job_input_shape(job_manifest)?;
        validate_manifest_job_input_count_metadata(job_manifest, job_count)?;
        let scheduled_dependency_job_indices = manifest_job_dependency_index_set(manifest, job)?;

        let mut seen_input_interface_artifacts = BTreeSet::new();
        for artifact_ref in &job_manifest.input_interfaces {
            if !seen_input_interface_artifacts.insert(artifact_ref.artifact_index) {
                return Err(manifest_contract_error(format!(
                    "job {} input interface artifact {} is listed more than once",
                    job_position, artifact_ref.artifact_index
                )));
            }
            if artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                return Err(manifest_contract_error(format!(
                    "job {} input interface ref {} has kind {:?}",
                    job_position, artifact_ref.artifact_index, artifact_ref.kind
                )));
            }
            validate_artifact_ref_matches_entry(
                &manifest.artifacts,
                artifact_ref,
                &format!("job {} input interface", job_position),
            )?;
            validate_manifest_non_link_interface_input_dependency(
                job,
                artifact_ref.artifact_index,
                artifact_ref.producing_job_index,
                &scheduled_dependency_job_indices,
            )?;
            actual_artifact_consumers[artifact_ref.artifact_index].insert(job_position);
        }
        for artifact_index in artifact_index_range_set(
            &job_manifest.input_interface_artifact_ranges,
            &format!("job {} input interface artifact ranges", job_position),
        )? {
            if !seen_input_interface_artifacts.insert(artifact_index) {
                return Err(manifest_contract_error(format!(
                    "job {} input interface artifact {} is listed more than once",
                    job_position, artifact_index
                )));
            }
            let artifact = manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("job {} input interface range", job_position),
            )?;
            if artifact.kind != SourcePackArtifactKind::LibraryInterface {
                return Err(manifest_contract_error(format!(
                    "job {} input interface range references artifact {} with kind {:?}",
                    job_position, artifact_index, artifact.kind
                )));
            }
            validate_manifest_non_link_interface_input_dependency(
                job,
                artifact.artifact_index,
                artifact.producing_job_index,
                &scheduled_dependency_job_indices,
            )?;
            actual_artifact_consumers[artifact_index].insert(job_position);
        }
        for range in &job_manifest.input_interface_ranges {
            let Some(ranged_dependency_job_indices) = range.iter() else {
                return Err(manifest_contract_error(format!(
                    "job {} input interface job range starting at {} overflows usize",
                    job_position, range.first_job_index
                )));
            };
            for dependency_job_index in ranged_dependency_job_indices {
                let artifact = library_interface_artifact_for_job(
                    &manifest.artifacts,
                    dependency_job_index,
                    &format!("job {} input interface job range", job_position),
                )?;
                validate_manifest_non_link_interface_input_dependency(
                    job,
                    artifact.artifact_index,
                    artifact.producing_job_index,
                    &scheduled_dependency_job_indices,
                )?;
                if !seen_input_interface_artifacts.insert(artifact.artifact_index) {
                    return Err(manifest_contract_error(format!(
                        "job {} input interface artifact {} is listed more than once",
                        job_position, artifact.artifact_index
                    )));
                }
                actual_artifact_consumers[artifact.artifact_index].insert(job_position);
            }
        }
        let mut seen_input_object_artifacts = BTreeSet::new();
        for artifact_ref in &job_manifest.input_objects {
            if !seen_input_object_artifacts.insert(artifact_ref.artifact_index) {
                return Err(manifest_contract_error(format!(
                    "job {} input object artifact {} is listed more than once",
                    job_position, artifact_ref.artifact_index
                )));
            }
            if artifact_ref.kind != SourcePackArtifactKind::CodegenObject {
                return Err(manifest_contract_error(format!(
                    "job {} input object ref {} has kind {:?}",
                    job_position, artifact_ref.artifact_index, artifact_ref.kind
                )));
            }
            validate_artifact_ref_matches_entry(
                &manifest.artifacts,
                artifact_ref,
                &format!("job {} input object", job_position),
            )?;
            actual_artifact_consumers[artifact_ref.artifact_index].insert(job_position);
        }
        for artifact_index in artifact_index_range_set(
            &job_manifest.input_object_artifact_ranges,
            &format!("job {} input object artifact ranges", job_position),
        )? {
            if !seen_input_object_artifacts.insert(artifact_index) {
                return Err(manifest_contract_error(format!(
                    "job {} input object artifact {} is listed more than once",
                    job_position, artifact_index
                )));
            }
            let artifact = manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("job {} input object range", job_position),
            )?;
            if artifact.kind != SourcePackArtifactKind::CodegenObject {
                return Err(manifest_contract_error(format!(
                    "job {} input object range references artifact {} with kind {:?}",
                    job_position, artifact_index, artifact.kind
                )));
            }
            actual_artifact_consumers[artifact_index].insert(job_position);
        }
        for artifact_ref in &job_manifest.outputs {
            validate_artifact_ref_matches_entry(
                &manifest.artifacts,
                artifact_ref,
                &format!("job {} output", job_position),
            )?;
            if artifact_ref.producing_job_index != job_position {
                return Err(manifest_contract_error(format!(
                    "job {} output artifact ref {} is produced by job {}",
                    job_position, artifact_ref.artifact_index, artifact_ref.producing_job_index
                )));
            }
        }

        let output_indices = artifact_ref_index_set(&job_manifest.outputs, "job output refs")?;
        let expected_output_indices = unique_usize_set(
            &output_artifact_indices_by_job[job_position],
            &format!("job {} produced artifacts", job_position),
        )?;
        if output_indices != expected_output_indices {
            return Err(manifest_contract_error(format!(
                "job artifact output mismatch for job {}: listed {:?}, expected {:?}",
                job_position, output_indices, expected_output_indices
            )));
        }

        validate_manifest_job_output_shape(job_manifest)?;
    }
    Ok(())
}

fn manifest_job_dependency_index_set(
    manifest: &SourcePackBuildArtifactManifest,
    job: &SourcePackJob,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut dependency_job_indices = unique_usize_set(
        &job.dependency_job_indices,
        &format!("job {} dependencies", job.job_index),
    )?;
    for range in manifest.job_schedule.dependency_job_ranges_for_job(job) {
        let Some(ranged_dependency_job_indices) = range.iter() else {
            return Err(manifest_contract_error(format!(
                "job {} dependency range starting at {} overflows usize",
                job.job_index, range.first_job_index
            )));
        };
        dependency_job_indices.extend(ranged_dependency_job_indices);
    }
    Ok(dependency_job_indices)
}

fn validate_manifest_non_link_interface_input_dependency(
    job: &SourcePackJob,
    artifact_index: usize,
    producing_job_index: usize,
    dependency_job_indices: &BTreeSet<usize>,
) -> Result<(), CompileError> {
    if job.phase == SourcePackJobPhase::Link
        || dependency_job_indices.contains(&producing_job_index)
    {
        return Ok(());
    }

    Err(manifest_contract_error(format!(
        "job {} phase {:?} consumes library-interface artifact {} from producer job {}, but that producer is not in the job's scheduled dependencies {:?}; package/import replay cannot consume interface artifacts that are not dependency-ready",
        job.job_index, job.phase, artifact_index, producing_job_index, dependency_job_indices
    )))
}

fn validate_manifest_job_input_shape(
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<(), CompileError> {
    if job_manifest.phase != SourcePackJobPhase::Link
        && (job_manifest.input_object_count != 0
            || job_manifest.input_object_page_count != 0
            || !job_manifest.input_object_artifact_ranges.is_empty()
            || !job_manifest.input_objects.is_empty())
    {
        return Err(manifest_contract_error(format!(
            "job {} phase {:?} has codegen object inputs; only link jobs may consume codegen objects",
            job_manifest.job_index, job_manifest.phase
        )));
    }

    Ok(())
}

fn validate_manifest_job_input_count_metadata(
    job_manifest: &SourcePackJobArtifactManifest,
    job_count: usize,
) -> Result<(), CompileError> {
    let context = format!("job {} artifact manifest", job_manifest.job_index);
    let explicit_interface_artifacts = artifact_ref_index_set(
        &job_manifest.input_interfaces,
        &format!("{context} input interfaces"),
    )?;
    validate_artifact_index_ranges(
        &job_manifest.input_interface_artifact_ranges,
        &explicit_interface_artifacts,
        &format!("{context} input interface artifact"),
        |message| manifest_contract_error(message),
    )?;
    validate_job_dependency_ranges(
        &job_manifest.input_interface_ranges,
        &BTreeSet::new(),
        &format!("{context} input interface job"),
        job_count,
        |message| manifest_contract_error(message),
    )?;

    let interface_job_range_count = checked_job_range_count(
        &job_manifest.input_interface_ranges,
        &format!("{context} input interface job ranges"),
    )?;
    let interface_artifact_range_count = checked_artifact_range_count(
        &job_manifest.input_interface_artifact_ranges,
        &format!("{context} input interface artifact ranges"),
    )?;
    let inline_interface_count = checked_count_sum(
        &format!("{context} input interface count"),
        &[
            job_manifest.input_interfaces.len(),
            interface_job_range_count,
            interface_artifact_range_count,
        ],
    )?;
    if job_manifest.input_interface_page_count != 0 && !job_manifest.input_interfaces.is_empty() {
        return Err(manifest_contract_error(format!(
            "{context} mixes inline and paged interface inputs; persisted count metadata must not stand in for artifact refs"
        )));
    }
    if job_manifest.input_interface_page_count == 0 {
        if job_manifest.input_interface_count != inline_interface_count {
            return Err(manifest_contract_error(format!(
                "{context} records interface input count {} but concrete refs/ranges cover {}; count metadata is not link artifact evidence",
                job_manifest.input_interface_count, inline_interface_count
            )));
        }
    } else {
        let ranged_interface_count = checked_count_sum(
            &format!("{context} ranged interface count"),
            &[interface_job_range_count, interface_artifact_range_count],
        )?;
        if job_manifest.input_interface_count < ranged_interface_count {
            return Err(manifest_contract_error(format!(
                "{context} records interface input count {} below ranged interface count {}",
                job_manifest.input_interface_count, ranged_interface_count
            )));
        }
        let paged_interface_count = job_manifest.input_interface_count - ranged_interface_count;
        let expected_page_count = paged_interface_count
            .div_ceil(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        if job_manifest.input_interface_page_count != expected_page_count {
            return Err(manifest_contract_error(format!(
                "{context} records interface page count {} but expected {} for {} paged interface artifact refs",
                job_manifest.input_interface_page_count, expected_page_count, paged_interface_count
            )));
        }
    }

    let explicit_object_artifacts = artifact_ref_index_set(
        &job_manifest.input_objects,
        &format!("{context} input objects"),
    )?;
    validate_artifact_index_ranges(
        &job_manifest.input_object_artifact_ranges,
        &explicit_object_artifacts,
        &format!("{context} input object artifact"),
        |message| manifest_contract_error(message),
    )?;
    let object_artifact_range_count = checked_artifact_range_count(
        &job_manifest.input_object_artifact_ranges,
        &format!("{context} input object artifact ranges"),
    )?;
    let concrete_object_count = checked_count_sum(
        &format!("{context} input object count"),
        &[
            job_manifest.input_objects.len(),
            object_artifact_range_count,
        ],
    )?;
    if job_manifest.input_object_page_count != 0 {
        return Err(manifest_contract_error(format!(
            "{context} records object page count {}, but job artifact manifests do not persist object input sidecar pages; object counts are not link artifact evidence",
            job_manifest.input_object_page_count
        )));
    }
    if job_manifest.input_object_count != concrete_object_count {
        return Err(manifest_contract_error(format!(
            "{context} records object input count {} but concrete refs/ranges cover {}; count metadata is not link artifact evidence",
            job_manifest.input_object_count, concrete_object_count
        )));
    }

    Ok(())
}

fn checked_job_range_count(
    ranges: &[SourcePackJobIndexRange],
    context: &str,
) -> Result<usize, CompileError> {
    ranges.iter().try_fold(0usize, |count, range| {
        count.checked_add(range.job_count).ok_or_else(|| {
            manifest_contract_error(format!("{context} count overflows persisted metadata"))
        })
    })
}

fn checked_artifact_range_count(
    ranges: &[SourcePackArtifactIndexRange],
    context: &str,
) -> Result<usize, CompileError> {
    ranges.iter().try_fold(0usize, |count, range| {
        count.checked_add(range.artifact_count).ok_or_else(|| {
            manifest_contract_error(format!("{context} count overflows persisted metadata"))
        })
    })
}

fn checked_count_sum(context: &str, counts: &[usize]) -> Result<usize, CompileError> {
    counts.iter().try_fold(0usize, |total, count| {
        total.checked_add(*count).ok_or_else(|| {
            manifest_contract_error(format!("{context} overflows persisted metadata"))
        })
    })
}

/// Validates the phase-specific output shape for one job artifact manifest.
///
/// Frontend jobs must emit one interface artifact, codegen jobs one object
/// artifact, and the link job one linked-output artifact.
pub(in crate::compiler) fn validate_manifest_job_output_shape(
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<(), CompileError> {
    let interface_outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == SourcePackArtifactKind::LibraryInterface)
        .count();
    let object_outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == SourcePackArtifactKind::CodegenObject)
        .count();
    let linked_outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == SourcePackArtifactKind::LinkedOutput)
        .count();

    let valid = match job_manifest.phase {
        SourcePackJobPhase::LibraryFrontend => {
            interface_outputs == 1 && object_outputs == 0 && linked_outputs == 0
        }
        SourcePackJobPhase::Codegen => {
            interface_outputs == 0 && object_outputs == 1 && linked_outputs == 0
        }
        SourcePackJobPhase::Link => {
            interface_outputs == 0 && object_outputs == 0 && linked_outputs == 1
        }
    };
    if !valid {
        return Err(manifest_contract_error(format!(
            "job {} phase {:?} has invalid output shape: {} interfaces, {} objects, {} linked outputs",
            job_manifest.job_index,
            job_manifest.phase,
            interface_outputs,
            object_outputs,
            linked_outputs
        )));
    }
    Ok(())
}

/// Validates the compact artifact-IO rows against per-job artifact manifests.
///
/// Each IO row must match the schedule phase and carry the same input and output
/// artifact index sets as the richer job artifact manifest.
pub(in crate::compiler) fn validate_manifest_job_artifact_io(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    let job_count = manifest.job_schedule.jobs.len();
    if manifest.job_artifact_io.jobs.len() != job_count {
        return Err(manifest_contract_error(format!(
            "job artifact IO plan has {} jobs but schedule has {}",
            manifest.job_artifact_io.jobs.len(),
            job_count
        )));
    }

    for (job_position, io) in manifest.job_artifact_io.jobs.iter().enumerate() {
        if io.job_index != job_position {
            return Err(manifest_contract_error(format!(
                "job artifact IO entry {job_position} has job_index {}",
                io.job_index
            )));
        }
        let job = &manifest.job_schedule.jobs[job_position];
        if io.phase != job.phase {
            return Err(manifest_contract_error(format!(
                "job artifact IO for job {} has phase {:?} but schedule has {:?}",
                job_position, io.phase, job.phase
            )));
        }

        let job_manifest = &manifest.job_artifacts.jobs[job_position];
        let manifest_input_interfaces = artifact_ref_and_range_index_set(
            &job_manifest.input_interfaces,
            &job_manifest.input_interface_artifact_ranges,
            "job manifest input interfaces",
        )?;
        let mut manifest_input_interfaces = manifest_input_interfaces;
        insert_interface_job_range_indices(
            &manifest.artifacts,
            &job_manifest.input_interface_ranges,
            &mut manifest_input_interfaces,
            "job manifest input interface job ranges",
        )?;
        let io_input_interfaces = unique_usize_and_artifact_range_set(
            &io.input_interface_artifact_indices,
            &io.input_interface_artifact_ranges,
            &format!("job {} IO input interfaces", job_position),
        )?;
        if manifest_input_interfaces != io_input_interfaces {
            return Err(manifest_contract_error(format!(
                "job {} input interface IO mismatch: refs {:?}, io {:?}",
                job_position, manifest_input_interfaces, io_input_interfaces
            )));
        }

        let manifest_input_objects = artifact_ref_and_range_index_set(
            &job_manifest.input_objects,
            &job_manifest.input_object_artifact_ranges,
            "job manifest inputs",
        )?;
        let io_input_objects = unique_usize_and_artifact_range_set(
            &io.input_object_artifact_indices,
            &io.input_object_artifact_ranges,
            &format!("job {} IO input objects", job_position),
        )?;
        if manifest_input_objects != io_input_objects {
            return Err(manifest_contract_error(format!(
                "job {} input object IO mismatch: refs {:?}, io {:?}",
                job_position, manifest_input_objects, io_input_objects
            )));
        }

        let manifest_outputs =
            artifact_ref_index_set(&job_manifest.outputs, "job manifest outputs")?;
        let io_outputs = unique_usize_set(
            &io.output_artifact_indices,
            &format!("job {} IO outputs", job_position),
        )?;
        if manifest_outputs != io_outputs {
            return Err(manifest_contract_error(format!(
                "job {} output IO mismatch: refs {:?}, io {:?}",
                job_position, manifest_outputs, io_outputs
            )));
        }
    }
    Ok(())
}

/// Validates artifact-use records against the consumers discovered from job inputs.
///
/// Artifact-use rows must be dense by artifact index, point at the recorded
/// producer, list exactly the discovered consumer set, and carry the correct
/// last-consumer summary.
pub(in crate::compiler) fn validate_manifest_artifact_uses(
    manifest: &SourcePackBuildArtifactManifest,
    actual_artifact_consumers: &[BTreeSet<usize>],
) -> Result<(), CompileError> {
    let artifact_count = manifest.artifacts.artifacts.len();
    let job_count = manifest.job_schedule.jobs.len();
    if manifest.artifact_uses.uses.len() != artifact_count {
        return Err(manifest_contract_error(format!(
            "artifact use plan has {} artifacts but artifact manifest has {}",
            manifest.artifact_uses.uses.len(),
            artifact_count
        )));
    }

    for (use_position, artifact_use) in manifest.artifact_uses.uses.iter().enumerate() {
        if artifact_use.artifact_index != use_position {
            return Err(manifest_contract_error(format!(
                "artifact use entry {use_position} has artifact_index {}",
                artifact_use.artifact_index
            )));
        }
        let artifact = &manifest.artifacts.artifacts[use_position];
        if artifact_use.producing_job_index != artifact.producing_job_index {
            return Err(manifest_contract_error(format!(
                "artifact use {} records producer {} but artifact records {}",
                use_position, artifact_use.producing_job_index, artifact.producing_job_index
            )));
        }
        for &consumer_job_index in &artifact_use.consumer_job_indices {
            if consumer_job_index >= job_count {
                return Err(manifest_contract_error(format!(
                    "artifact use {} references missing consumer job {}",
                    use_position, consumer_job_index
                )));
            }
        }
        let listed = unique_usize_set(
            &artifact_use.consumer_job_indices,
            &format!("artifact {} consumers", use_position),
        )?;
        if listed != actual_artifact_consumers[use_position] {
            return Err(manifest_contract_error(format!(
                "artifact use consumer mismatch for artifact {}: listed {:?}, expected {:?}",
                use_position, listed, actual_artifact_consumers[use_position]
            )));
        }
        let expected_last_consumer = actual_artifact_consumers[use_position]
            .iter()
            .copied()
            .max();
        if artifact_use.last_consumer_job_index != expected_last_consumer {
            return Err(manifest_contract_error(format!(
                "artifact use {} records last consumer {:?}, expected {:?}",
                use_position, artifact_use.last_consumer_job_index, expected_last_consumer
            )));
        }
    }
    Ok(())
}

/// Validates link-interface and link-object batch coverage.
///
/// Link batches must cover exactly the link job's expected interface and object
/// input artifact sets, with each artifact appearing in one sorted, bounded
/// batch whose source totals match the referenced artifacts.
pub(in crate::compiler) fn validate_manifest_link_batches(
    manifest: &SourcePackBuildArtifactManifest,
    link_job_index: usize,
) -> Result<(), CompileError> {
    let link_job_manifest = &manifest.job_artifacts.jobs[link_job_index];
    let expected_interface_indices = artifact_ref_and_range_index_set(
        &link_job_manifest.input_interfaces,
        &link_job_manifest.input_interface_artifact_ranges,
        "link job input interfaces",
    )?;
    let expected_object_indices = artifact_ref_and_range_index_set(
        &link_job_manifest.input_objects,
        &link_job_manifest.input_object_artifact_ranges,
        "link job inputs",
    )?;
    validate_manifest_link_inputs_cover_artifact_kind(
        manifest,
        &expected_interface_indices,
        SourcePackArtifactKind::LibraryInterface,
        "interfaces",
        "library-interface",
    )?;
    validate_manifest_link_inputs_cover_artifact_kind(
        manifest,
        &expected_object_indices,
        SourcePackArtifactKind::CodegenObject,
        "objects",
        "codegen object",
    )?;

    let mut batched_interface_indices = BTreeSet::new();
    for (batch_position, batch) in manifest.link_interface_batches.batches.iter().enumerate() {
        if batch.batch_index != batch_position {
            return Err(manifest_contract_error(format!(
                "link interface batch entry {batch_position} has batch_index {}",
                batch.batch_index
            )));
        }
        if batch.input_interface_artifact_indices.is_empty() {
            return Err(manifest_contract_error(format!(
                "link interface batch {} has no input artifacts",
                batch.batch_index
            )));
        }
        if batch.input_interface_artifact_indices.len()
            > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        {
            return Err(manifest_contract_error(format!(
                "link interface batch {} has {} input artifacts but the page limit is {}",
                batch.batch_index,
                batch.input_interface_artifact_indices.len(),
                SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
            )));
        }
        unique_usize_set(
            &batch.input_interface_artifact_indices,
            &format!("link interface batch {} inputs", batch.batch_index),
        )?;
        validate_usize_values_strictly_ascending(
            &batch.input_interface_artifact_indices,
            &format!("link interface batch {} inputs", batch.batch_index),
            |message| manifest_contract_error(message),
        )?;
        let mut source_bytes = 0usize;
        let mut source_file_count = 0usize;
        let mut source_lines = 0usize;
        for &artifact_index in &batch.input_interface_artifact_indices {
            let artifact = manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("link interface batch {}", batch.batch_index),
            )?;
            if artifact.kind != SourcePackArtifactKind::LibraryInterface {
                return Err(manifest_contract_error(format!(
                    "link interface batch {} references artifact {} with kind {:?}",
                    batch.batch_index, artifact_index, artifact.kind
                )));
            }
            if !batched_interface_indices.insert(artifact_index) {
                return Err(manifest_contract_error(format!(
                    "link interface artifact {} appears in more than one link batch",
                    artifact_index
                )));
            }
            source_bytes = source_bytes.saturating_add(artifact.source_bytes);
            source_file_count = source_file_count.saturating_add(artifact.source_file_count);
            source_lines = source_lines.saturating_add(artifact.source_lines);
        }
        if batch.source_bytes != source_bytes {
            return Err(manifest_contract_error(format!(
                "link interface batch {} records {} source bytes but artifacts sum to {}",
                batch.batch_index, batch.source_bytes, source_bytes
            )));
        }
        if batch.source_file_count != source_file_count {
            return Err(manifest_contract_error(format!(
                "link interface batch {} records {} source files but artifacts sum to {}",
                batch.batch_index, batch.source_file_count, source_file_count
            )));
        }
        if batch.source_lines != source_lines {
            return Err(manifest_contract_error(format!(
                "link interface batch {} records {} source lines but artifacts sum to {}",
                batch.batch_index, batch.source_lines, source_lines
            )));
        }
    }
    if batched_interface_indices != expected_interface_indices {
        return Err(manifest_contract_error(format!(
            "link interface batch inputs {:?} do not match link job inputs {:?}",
            batched_interface_indices, expected_interface_indices
        )));
    }

    let mut batched_object_indices = BTreeSet::new();
    for (batch_position, batch) in manifest.link_object_batches.batches.iter().enumerate() {
        if batch.batch_index != batch_position {
            return Err(manifest_contract_error(format!(
                "link object batch entry {batch_position} has batch_index {}",
                batch.batch_index
            )));
        }
        if batch.input_object_artifact_indices.is_empty() {
            return Err(manifest_contract_error(format!(
                "link object batch {} has no input artifacts",
                batch.batch_index
            )));
        }
        if batch.input_object_artifact_indices.len()
            > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        {
            return Err(manifest_contract_error(format!(
                "link object batch {} has {} input artifacts but the page limit is {}",
                batch.batch_index,
                batch.input_object_artifact_indices.len(),
                SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
            )));
        }
        unique_usize_set(
            &batch.input_object_artifact_indices,
            &format!("link object batch {} inputs", batch.batch_index),
        )?;
        validate_usize_values_strictly_ascending(
            &batch.input_object_artifact_indices,
            &format!("link object batch {} inputs", batch.batch_index),
            |message| manifest_contract_error(message),
        )?;
        let mut source_bytes = 0usize;
        let mut source_file_count = 0usize;
        let mut source_lines = 0usize;
        for &artifact_index in &batch.input_object_artifact_indices {
            let artifact = manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("link object batch {}", batch.batch_index),
            )?;
            if artifact.kind != SourcePackArtifactKind::CodegenObject {
                return Err(manifest_contract_error(format!(
                    "link object batch {} references artifact {} with kind {:?}",
                    batch.batch_index, artifact_index, artifact.kind
                )));
            }
            if !batched_object_indices.insert(artifact_index) {
                return Err(manifest_contract_error(format!(
                    "link object artifact {} appears in more than one link batch",
                    artifact_index
                )));
            }
            source_bytes = source_bytes.saturating_add(artifact.source_bytes);
            source_file_count = source_file_count.saturating_add(artifact.source_file_count);
            source_lines = source_lines.saturating_add(artifact.source_lines);
        }
        if batch.source_bytes != source_bytes {
            return Err(manifest_contract_error(format!(
                "link object batch {} records {} source bytes but artifacts sum to {}",
                batch.batch_index, batch.source_bytes, source_bytes
            )));
        }
        if batch.source_file_count != source_file_count {
            return Err(manifest_contract_error(format!(
                "link object batch {} records {} source files but artifacts sum to {}",
                batch.batch_index, batch.source_file_count, source_file_count
            )));
        }
        if batch.source_lines != source_lines {
            return Err(manifest_contract_error(format!(
                "link object batch {} records {} source lines but artifacts sum to {}",
                batch.batch_index, batch.source_lines, source_lines
            )));
        }
    }
    if batched_object_indices != expected_object_indices {
        return Err(manifest_contract_error(format!(
            "link object batch inputs {:?} do not match link job inputs {:?}",
            batched_object_indices, expected_object_indices
        )));
    }

    Ok(())
}

fn validate_manifest_link_inputs_cover_artifact_kind(
    manifest: &SourcePackBuildArtifactManifest,
    link_input_indices: &BTreeSet<usize>,
    kind: SourcePackArtifactKind,
    input_label: &str,
    artifact_label: &str,
) -> Result<(), CompileError> {
    let expected_indices = manifest
        .artifacts
        .artifacts
        .iter()
        .filter(|artifact| artifact.kind == kind)
        .map(|artifact| artifact.artifact_index)
        .collect::<BTreeSet<_>>();
    if link_input_indices == &expected_indices {
        return Ok(());
    }

    let missing = expected_indices
        .difference(link_input_indices)
        .copied()
        .collect::<Vec<_>>();
    let unexpected = link_input_indices
        .difference(&expected_indices)
        .copied()
        .collect::<Vec<_>>();
    Err(manifest_contract_error(format!(
        "link job input {input_label} do not cover all {artifact_label} artifacts: missing {:?}, unexpected {:?}",
        missing, unexpected
    )))
}
