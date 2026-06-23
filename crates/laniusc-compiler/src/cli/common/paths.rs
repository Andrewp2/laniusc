use std::{collections::BTreeSet, fs, path::PathBuf};

use super::{invalid_cli_directory_path_error, CliError};

/// Canonicalizes a CLI path and verifies that it names a directory.
pub(crate) fn canonical_directory_path(label: &str, path: PathBuf) -> Result<PathBuf, CliError> {
    let canonical = fs::canonicalize(&path).map_err(|err| {
        invalid_cli_directory_path_error(
            label,
            &path,
            format!("could not canonicalize {}: {err}", path.display()),
        )
    })?;
    if !canonical.is_dir() {
        return Err(invalid_cli_directory_path_error(
            label,
            &canonical,
            format!("{} is not a directory", canonical.display()),
        ));
    }
    Ok(canonical)
}

/// Canonicalizes, validates, and deduplicates a list of directory paths.
pub(crate) fn canonical_unique_directory_paths(
    label: &str,
    paths: Vec<PathBuf>,
) -> Result<Vec<PathBuf>, CliError> {
    let mut seen = BTreeSet::new();
    let mut unique = Vec::with_capacity(paths.len());
    for path in paths {
        let canonical = canonical_directory_path(label, path)?;
        if seen.insert(canonical.clone()) {
            unique.push(canonical);
        }
    }
    Ok(unique)
}
