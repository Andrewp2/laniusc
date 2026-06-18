use std::path::{Path, PathBuf};

use crate::{
    cli::{
        common::{
            CliError,
            LANIUS_EMIT_TARGETS,
            LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION,
            extra_cli_argument_error,
            missing_cli_option_value_error,
            unknown_cli_option_error,
            unsupported_cli_option_value_error,
        },
        source_pack::artifact_target_for_emit,
    },
    compiler::{
        CompileError,
        Diagnostic,
        FilesystemArtifactStore,
        SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        SourcePackWorkQueueProgressIndex,
    },
};

const SOURCE_PACK_PROGRESS_SCHEMA_NAME: &str = "laniusc.diagnostics.source-pack-progress";

/// Reads persisted source-pack work-queue progress without compiling source.
pub(super) fn diagnostic_source_pack_progress_json_pretty(
    args: impl IntoIterator<Item = String>,
) -> Result<String, CliError> {
    let (artifact_root, emit) = parse_diagnostic_source_pack_progress_args(args)?;
    let target = artifact_target_for_emit(&emit);
    let store = FilesystemArtifactStore::new(&artifact_root);
    let progress_index_path = store.work_queue_progress_index_path_for_target(target);
    let progress = store
        .load_work_queue_progress_index_for_target(target)
        .map_err(|err| {
            source_pack_progress_artifact_error(&artifact_root, &emit, &progress_index_path, err)
        })?;
    let complete = progress.completed_item_count == progress.work_item_count;
    let no_run_guards = serde_json::json!({
        "source_compilation": false,
        "source_scanning": false,
        "gpu_device_creation": false,
        "target_codegen": false
    });
    let document = serde_json::json!({
        "schema_version": LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION,
        "schema_name": SOURCE_PACK_PROGRESS_SCHEMA_NAME,
        "artifact_root": artifact_root.display().to_string(),
        "target": emit,
        "data_source": "source-pack work queue progress index artifact",
        "record_contract": {
            "kind": "source-pack-work-queue-progress-index",
            "schema_version": progress.version,
            "expected_schema_version": SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
            "path": progress_index_path.display().to_string()
        },
        "status": source_pack_progress_status(&progress),
        "progress": {
            "work_item_count": progress.work_item_count,
            "artifact_item_count": progress.artifact_item_count,
            "completed_item_count": progress.completed_item_count,
            "ready_item_count": progress.ready_item_count,
            "ready_artifact_item_count": progress.ready_artifact_item_count,
            "claimed_item_count": progress.claimed_item_count,
            "first_ready_item_index": progress.first_ready_item_index,
            "first_ready_artifact_item_index": progress.first_ready_artifact_item_index,
            "page_size": progress.page_size,
            "page_count": progress.page_count,
            "complete": complete
        },
        "no_run_guards": no_run_guards
    });
    serde_json::to_string_pretty(&document)
        .map_err(|err| format!("serialize source-pack progress diagnostics: {err}").into())
}

fn source_pack_progress_artifact_error(
    artifact_root: &Path,
    emit: &str,
    progress_index_path: &Path,
    err: CompileError,
) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic),
        err => CliError::Diagnostic(
            Diagnostic::error("LNC0037", "package metadata invalid")
                .with_note(
                    "diagnostics source-pack-progress reads persisted source-pack artifact records",
                )
                .with_note(format!(
                    "source-pack artifact root: {}",
                    artifact_root.display()
                ))
                .with_note(format!("source-pack emit target: {emit}"))
                .with_note(format!(
                    "source-pack progress index: {}",
                    progress_index_path.display()
                ))
                .with_note(err.to_string())
                .with_help("run source-pack prepare/build for the selected --emit target, or pass the artifact root that contains the persisted progress records"),
        ),
    }
}

fn parse_diagnostic_source_pack_progress_args(
    args: impl IntoIterator<Item = String>,
) -> Result<(PathBuf, String), CliError> {
    let mut artifact_root = None;
    let mut emit = "wasm".to_string();
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--source-pack-artifact-root" => {
                artifact_root = Some(PathBuf::from(args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--source-pack-artifact-root",
                        "a persisted source-pack artifact directory",
                    )
                })?));
            }
            "--emit" => {
                emit = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--emit",
                        format!("one of: {LANIUS_EMIT_TARGETS}"),
                    )
                })?;
            }
            flag if flag.starts_with("--source-pack-artifact-root=") => {
                artifact_root = Some(PathBuf::from(
                    flag.trim_start_matches("--source-pack-artifact-root="),
                ));
            }
            flag if flag.starts_with("--emit=") => {
                emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc diagnostics source-pack-progress",
                    flag,
                    "--emit, --source-pack-artifact-root",
                ));
            }
            other => {
                return Err(extra_cli_argument_error(
                    "laniusc diagnostics source-pack-progress",
                    other,
                    "--emit, --source-pack-artifact-root",
                ));
            }
        }
    }
    if emit != "wasm" && emit != "x86_64" {
        return Err(unsupported_cli_option_value_error(
            "--emit",
            &emit,
            LANIUS_EMIT_TARGETS,
            Some(
                "source-pack progress diagnostics select the persisted artifact target by emit mode"
                    .to_string(),
            ),
        ));
    }
    let artifact_root = artifact_root.ok_or_else(|| {
        missing_cli_option_value_error(
            "--source-pack-artifact-root",
            "a persisted source-pack artifact directory",
        )
    })?;
    Ok((artifact_root, emit))
}

fn source_pack_progress_status(progress: &SourcePackWorkQueueProgressIndex) -> &'static str {
    if progress.completed_item_count == progress.work_item_count {
        "complete"
    } else if progress.ready_item_count > 0 {
        "ready"
    } else if progress.claimed_item_count > 0 {
        "claimed"
    } else {
        "waiting"
    }
}
