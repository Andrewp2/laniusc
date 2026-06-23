use std::{
    fs,
    io::{BufRead, BufReader, Seek, SeekFrom},
    path::{Path, PathBuf},
};

use crate::{
    codegen::unit::SourcePackArtifactTarget,
    cli::common::{explicit_source_pack_manifest_invalid_error, CliError},
    compiler::ExplicitSourceLibraryPathDependencyStream,
};

/// Maximum UTF-8 bytes accepted for one JSONL library-manifest record.
pub(super) const LIBRARY_MANIFEST_MAX_LINE_BYTES: usize = 4096;
/// Maximum blank manifest lines skipped by one bounded metadata chunk.
pub(super) const LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK: usize = 64;
/// Maximum UTF-8 bytes accepted for one source path-list line.
pub(super) const PATH_LIST_MAX_LINE_BYTES: usize = 4096;
/// Maximum blank path-list lines skipped before the next source path.
pub(super) const PATH_LIST_MAX_BLANK_LINES_PER_ITEM: usize = 64;

const PROGRESS_VERSION: u32 = 1;

type ManifestResult<T> = Result<T, CliError>;

fn manifest_error(reason: impl Into<String>) -> CliError {
    explicit_source_pack_manifest_invalid_error(reason)
}

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
/// Persistent cursor for chunked source-pack library-manifest preparation.
pub(super) struct Progress {
    /// Progress schema version.
    pub(super) version: u32,
    /// Target whose artifact files own this progress cursor.
    pub(super) target: SourcePackArtifactTarget,
    /// Canonical manifest path associated with this cursor.
    pub(super) manifest_path: PathBuf,
    /// Libraries already persisted before `next_byte_offset`.
    pub(super) library_count: usize,
    /// Byte offset where the next metadata-preparation chunk should begin.
    pub(super) next_byte_offset: u64,
}

#[derive(Clone, Debug, serde::Deserialize)]
/// One JSONL library record from a source-pack library manifest.
pub(super) struct LibraryPathEntry {
    library_id: u32,
    source_file_count: usize,
    path_list: PathBuf,
    #[serde(default)]
    dependency_library_ids: Vec<u32>,
}

fn read_path_list_line(
    reader: &mut impl BufRead,
    line: &mut String,
    path: &Path,
    line_number: usize,
    byte_offset: u64,
) -> ManifestResult<usize> {
    read_bounded_utf8_line(
        reader,
        line,
        PATH_LIST_MAX_LINE_BYTES,
        || {
            format!(
                "source-pack path list {} line {line_number} at byte offset {byte_offset}",
                path.display()
            )
        },
        "split large path-list records",
    )
}

/// Loads the source files referenced by one library-manifest path list.
pub(super) fn load_path_list(
    path: &Path,
    expected_source_file_count: usize,
) -> ManifestResult<Vec<PathBuf>> {
    let base_dir = path
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    let file = fs::File::open(path).map_err(|err| {
        manifest_error(format!(
            "open source-pack path list {}: {err}",
            path.display()
        ))
    })?;
    let mut reader = BufReader::new(file);
    let mut paths = Vec::with_capacity(expected_source_file_count);
    let mut line = String::new();
    let mut line_number = 0usize;
    let mut byte_offset = 0u64;
    let mut blank_line_count = 0usize;

    loop {
        let bytes_read =
            read_path_list_line(&mut reader, &mut line, path, line_number + 1, byte_offset)?;
        if bytes_read == 0 {
            break;
        }
        byte_offset = byte_offset.checked_add(bytes_read as u64).ok_or_else(|| {
            manifest_error(format!(
                "source-pack path list {} byte offset overflows",
                path.display()
            ))
        })?;
        line_number += 1;
        let source_path = line.trim();
        if source_path.is_empty() {
            blank_line_count += 1;
            if blank_line_count > PATH_LIST_MAX_BLANK_LINES_PER_ITEM {
                return Err(manifest_error(format!(
                    "source-pack path list {} has more than {PATH_LIST_MAX_BLANK_LINES_PER_ITEM} blank lines before the next path at line {}; remove blank padding",
                    path.display(),
                    line_number
                )));
            }
            continue;
        }
        blank_line_count = 0;
        if paths.len() == expected_source_file_count {
            return Err(manifest_error(format!(
                "source-pack path list {} declares {expected_source_file_count} source files but has an extra path at line {line_number}",
                path.display()
            )));
        }
        paths.push(resolve_relative_path(&base_dir, Path::new(source_path)));
    }

    if paths.len() != expected_source_file_count {
        return Err(manifest_error(format!(
            "source-pack path list {} contains {} source files but the library manifest declares {expected_source_file_count}",
            path.display(),
            paths.len()
        )));
    }

    Ok(paths)
}

/// Returns the target-specific manifest-progress file path.
pub(super) fn progress_path(artifact_root: &Path, target: SourcePackArtifactTarget) -> PathBuf {
    let file_name = target.key_prefix().map_or_else(
        || "source-pack-library-manifest-progress.json".to_string(),
        |prefix| format!("source-pack-library-manifest-progress.{prefix}.json"),
    );
    artifact_root.join(file_name)
}

fn manifest_identity_path(manifest_path: &Path) -> ManifestResult<PathBuf> {
    fs::canonicalize(manifest_path).map_err(|err| {
        manifest_error(format!(
            "canonicalize source-pack library manifest {}: {err}",
            manifest_path.display()
        ))
    })
}

/// Loads existing manifest progress or derives a cursor from stored metadata.
pub(super) fn load_progress_or_default(
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
    manifest_path: &Path,
    persisted_library_count: usize,
) -> ManifestResult<Progress> {
    let manifest_path = manifest_identity_path(manifest_path)?;
    let progress_path = progress_path(artifact_root, target);
    if progress_path.is_file() {
        let bytes = fs::read(&progress_path).map_err(|err| {
            manifest_error(format!(
                "read source-pack library manifest progress {}: {err}",
                progress_path.display()
            ))
        })?;
        let progress = serde_json::from_slice::<Progress>(&bytes).map_err(|err| {
            manifest_error(format!(
                "parse source-pack library manifest progress {}: {err}",
                progress_path.display()
            ))
        })?;
        validate_progress(&progress, target, &manifest_path)?;
        return Ok(progress);
    }

    let next_byte_offset = offset_after_entry_count(&manifest_path, persisted_library_count)?;
    Ok(Progress {
        version: PROGRESS_VERSION,
        target,
        manifest_path,
        library_count: persisted_library_count,
        next_byte_offset,
    })
}

fn validate_progress(
    progress: &Progress,
    target: SourcePackArtifactTarget,
    manifest_path: &Path,
) -> ManifestResult<()> {
    if progress.version != PROGRESS_VERSION {
        return Err(manifest_error(format!(
            "unsupported source-pack library manifest progress version {}; expected {}",
            progress.version, PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(manifest_error(format!(
            "source-pack library manifest progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.manifest_path != manifest_path {
        return Err(manifest_error(format!(
            "source-pack library manifest progress was created for {}, not {}",
            progress.manifest_path.display(),
            manifest_path.display()
        )));
    }
    Ok(())
}

/// Stores a validated manifest-progress cursor under the artifact root.
pub(super) fn store_progress(artifact_root: &Path, progress: &Progress) -> ManifestResult<()> {
    validate_progress(progress, progress.target, &progress.manifest_path)?;
    let path = progress_path(artifact_root, progress.target);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            manifest_error(format!(
                "create source-pack library manifest progress directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    let bytes = serde_json::to_vec_pretty(progress)
        .map_err(|err| {
            manifest_error(format!(
                "serialize source-pack library manifest progress: {err}"
            ))
        })?;
    fs::write(&path, bytes).map_err(|err| {
        manifest_error(format!(
            "write source-pack library manifest progress {}: {err}",
            path.display()
        ))
    })
}

/// Finds the manifest byte offset immediately after a library-count prefix.
pub(super) fn offset_after_entry_count(
    manifest_path: &Path,
    expected_entry_count: usize,
) -> ManifestResult<u64> {
    if expected_entry_count == 0 {
        return Ok(0);
    }
    let file = fs::File::open(manifest_path).map_err(|err| {
        manifest_error(format!(
            "open source-pack library manifest {}: {err}",
            manifest_path.display()
        ))
    })?;
    let mut reader = BufReader::new(file);
    let mut byte_offset = 0u64;
    let mut entry_count = 0usize;
    let mut blank_line_count = 0usize;
    let mut line = String::new();
    loop {
        let bytes_read = read_manifest_line(&mut reader, &mut line, manifest_path, byte_offset)?;
        if bytes_read == 0 {
            return Err(manifest_error(format!(
                "source-pack library manifest {} has only {entry_count} libraries, but persisted metadata records {expected_entry_count}",
                manifest_path.display()
            )));
        }
        byte_offset = byte_offset
            .checked_add(bytes_read as u64)
            .ok_or_else(|| manifest_error("source-pack library manifest byte offset overflows"))?;
        if line.trim().is_empty() {
            blank_line_count += 1;
            if blank_line_count > LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK {
                return Err(manifest_error(format!(
                    "source-pack library manifest {} has more than {LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK} blank lines before entry {} at byte offset {byte_offset}; remove blank padding",
                    manifest_path.display(),
                    entry_count + 1
                )));
            }
            continue;
        }
        blank_line_count = 0;
        entry_count = entry_count
            .checked_add(1)
            .ok_or_else(|| manifest_error("source-pack library manifest entry count overflows"))?;
        if entry_count == expected_entry_count {
            return Ok(byte_offset);
        }
    }
}

/// Bounded chunk of library-manifest entries ready for metadata preparation.
pub(super) struct EntryChunk {
    /// Library entries selected for this chunk.
    pub(super) entries: Vec<LibraryPathEntry>,
    /// Byte offset where the next chunk should resume.
    pub(super) next_byte_offset: u64,
    /// Whether the manifest ended after this chunk's input was consumed.
    pub(super) manifest_complete_after_input: bool,
}

fn read_bounded_utf8_line(
    reader: &mut impl BufRead,
    line: &mut String,
    max_line_bytes: usize,
    context: impl Fn() -> String,
    advice: &str,
) -> ManifestResult<usize> {
    line.clear();
    let mut line_bytes = Vec::new();
    loop {
        let available = reader
            .fill_buf()
            .map_err(|err| manifest_error(format!("read {}: {err}", context())))?;
        if available.is_empty() {
            break;
        }
        let newline_position = available.iter().position(|&byte| byte == b'\n');
        let take_len = newline_position
            .map(|position| position + 1)
            .unwrap_or(available.len());
        let next_len = line_bytes
            .len()
            .checked_add(take_len)
            .ok_or_else(|| manifest_error(format!("{} line byte count overflows", context())))?;
        if next_len > max_line_bytes {
            return Err(manifest_error(format!(
                "{} exceeds line byte limit {max_line_bytes}; {advice}",
                context()
            )));
        }
        line_bytes.extend_from_slice(&available[..take_len]);
        reader.consume(take_len);
        if newline_position.is_some() {
            break;
        }
    }
    if line_bytes.is_empty() {
        return Ok(0);
    }
    let text = std::str::from_utf8(&line_bytes)
        .map_err(|err| manifest_error(format!("read {}: invalid UTF-8: {err}", context())))?;
    line.push_str(text);
    Ok(line_bytes.len())
}

fn read_manifest_line(
    reader: &mut impl BufRead,
    line: &mut String,
    manifest_path: &Path,
    byte_offset: u64,
) -> ManifestResult<usize> {
    read_bounded_utf8_line(
        reader,
        line,
        LIBRARY_MANIFEST_MAX_LINE_BYTES,
        || {
            format!(
                "source-pack library manifest {} line at byte offset {byte_offset}",
                manifest_path.display()
            )
        },
        "split large library records",
    )
}

/// Loads a bounded source-pack library-manifest chunk from a byte offset.
pub(super) fn load_entries_chunk_from_offset(
    manifest_path: &Path,
    start_byte_offset: u64,
    max_entries: usize,
    max_source_files: usize,
) -> ManifestResult<EntryChunk> {
    let manifest_base_dir = manifest_path
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    let mut file = fs::File::open(manifest_path).map_err(|err| {
        manifest_error(format!(
            "open source-pack library manifest {}: {err}",
            manifest_path.display()
        ))
    })?;
    file.seek(SeekFrom::Start(start_byte_offset))
        .map_err(|err| {
            manifest_error(format!(
                "seek source-pack library manifest {} to byte offset {start_byte_offset}: {err}",
                manifest_path.display()
            ))
        })?;
    let mut reader = BufReader::new(file);
    let mut entries = Vec::new();
    if max_entries == 0 || max_source_files == 0 {
        return Ok(EntryChunk {
            entries,
            next_byte_offset: start_byte_offset,
            manifest_complete_after_input: false,
        });
    }

    let mut byte_offset = start_byte_offset;
    let mut next_byte_offset = start_byte_offset;
    let mut new_source_file_count = 0usize;
    let mut blank_line_count = 0usize;
    let mut line = String::new();
    while entries.len() < max_entries {
        let line_start = byte_offset;
        let bytes_read = read_manifest_line(&mut reader, &mut line, manifest_path, line_start)?;
        if bytes_read == 0 {
            if entries.is_empty() {
                return Err(manifest_error(format!(
                    "source-pack library manifest {} has no libraries at byte offset {start_byte_offset}",
                    manifest_path.display()
                )));
            }
            return Ok(EntryChunk {
                entries,
                next_byte_offset,
                manifest_complete_after_input: true,
            });
        }
        byte_offset = byte_offset
            .checked_add(bytes_read as u64)
            .ok_or_else(|| manifest_error("source-pack library manifest byte offset overflows"))?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            blank_line_count += 1;
            if blank_line_count > LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK {
                return Err(manifest_error(format!(
                    "source-pack library manifest {} has more than {LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK} blank lines in one metadata chunk before byte offset {byte_offset}; remove blank padding",
                    manifest_path.display()
                )));
            }
            next_byte_offset = byte_offset;
            continue;
        }
        blank_line_count = 0;
        let mut entry = serde_json::from_str::<LibraryPathEntry>(trimmed).map_err(|err| {
            manifest_error(format!(
                "parse source-pack library manifest {} at byte offset {line_start}: {err}",
                manifest_path.display()
            ))
        })?;
        let next_source_file_count = new_source_file_count
            .checked_add(entry.source_file_count)
            .ok_or_else(|| {
                manifest_error("source-pack library manifest chunk source-file count overflows")
            })?;
        if next_source_file_count > max_source_files {
            if entries.is_empty() {
                return Err(manifest_error(format!(
                    "source-pack library manifest library {} has {} source files, exceeding the per-chunk source-file limit {}; split the library path list into smaller library records",
                    entry.library_id, entry.source_file_count, max_source_files
                )));
            }
            return Ok(EntryChunk {
                entries,
                next_byte_offset: line_start,
                manifest_complete_after_input: false,
            });
        }
        entry.path_list = resolve_relative_path(&manifest_base_dir, &entry.path_list);
        new_source_file_count = next_source_file_count;
        entries.push(entry);
        next_byte_offset = byte_offset;
    }

    let mut manifest_complete_after_input = true;
    let mut trailing_blank_line_count = 0usize;
    loop {
        let line_start = byte_offset;
        let bytes_read = read_manifest_line(&mut reader, &mut line, manifest_path, line_start)?;
        if bytes_read == 0 {
            break;
        }
        byte_offset = byte_offset
            .checked_add(bytes_read as u64)
            .ok_or_else(|| manifest_error("source-pack library manifest byte offset overflows"))?;
        if line.trim().is_empty() {
            trailing_blank_line_count += 1;
            if trailing_blank_line_count > LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK {
                return Err(manifest_error(format!(
                    "source-pack library manifest {} has more than {LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK} blank lines after a metadata chunk before byte offset {byte_offset}; remove blank padding",
                    manifest_path.display()
                )));
            }
        } else {
            manifest_complete_after_input = false;
            break;
        }
    }

    Ok(EntryChunk {
        entries,
        next_byte_offset,
        manifest_complete_after_input,
    })
}

/// Converts manifest entries into dependency streams consumed by compiler APIs.
pub(super) fn path_dependency_streams(
    entries: Vec<LibraryPathEntry>,
) -> ManifestResult<Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>>> {
    let mut streams = Vec::with_capacity(entries.len());
    for mut entry in entries {
        if entry.source_file_count == 0 {
            return Err(manifest_error(format!(
                "source-pack library manifest library {} has no source files",
                entry.library_id
            )));
        }
        entry.dependency_library_ids.sort_unstable();
        if let Some(duplicate_dependency_library_id) = entry
            .dependency_library_ids
            .windows(2)
            .find_map(|ids| (ids[0] == ids[1]).then_some(ids[0]))
        {
            return Err(manifest_error(format!(
                "source-pack library manifest library {} declares duplicate dependency library {}; dependency edges must be unique so descriptor replay cannot silently deduplicate package boundaries",
                entry.library_id, duplicate_dependency_library_id
            )));
        }
        if entry.dependency_library_ids.contains(&entry.library_id) {
            return Err(manifest_error(format!(
                "source-pack library manifest library {} depends on itself",
                entry.library_id
            )));
        }
        let paths = load_path_list(&entry.path_list, entry.source_file_count)?;
        streams.push(ExplicitSourceLibraryPathDependencyStream {
            library_id: entry.library_id,
            source_file_count: entry.source_file_count,
            paths,
            dependency_library_count: entry.dependency_library_ids.len(),
            dependency_library_ids: entry.dependency_library_ids,
        });
    }
    Ok(streams)
}

fn resolve_relative_path(base_dir: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        base_dir.join(path)
    }
}
