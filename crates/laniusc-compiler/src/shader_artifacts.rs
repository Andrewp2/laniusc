use std::path::{Path, PathBuf};

const UNKNOWN: &str = "unknown";
const ARTIFACT_ROOT: &str = env!("LANIUS_SHADER_ARTIFACT_ROOT");

/// Resolves a generated shader artifact path under the build-time artifact root.
pub(crate) fn artifact_path(file: &str) -> PathBuf {
    PathBuf::from(ARTIFACT_ROOT).join(file)
}

/// Returns the stable keys of every compiled shader below `prefix`.
///
/// Shader discovery belongs to the generated artifact set, not to phase-local
/// Rust pass structs.  Sorting makes daemon preparation deterministic even
/// when the host filesystem enumerates artifacts in a different order.
pub(crate) fn shader_keys(prefix: &str) -> std::io::Result<Vec<String>> {
    fn visit(root: &Path, directory: &Path, keys: &mut Vec<String>) -> std::io::Result<()> {
        for entry in std::fs::read_dir(directory)? {
            let path = entry?.path();
            if path.is_dir() {
                visit(root, &path, keys)?;
            } else if path.extension().and_then(|extension| extension.to_str()) == Some("spv") {
                let relative = path
                    .strip_prefix(root)
                    .expect("visited shader artifact is below its root");
                let mut key = relative.to_string_lossy().replace('\\', "/");
                key.truncate(key.len() - ".spv".len());
                keys.push(key);
            }
        }
        Ok(())
    }

    let root = PathBuf::from(ARTIFACT_ROOT);
    let directory = root.join(prefix);
    let mut keys = Vec::new();
    visit(&root, &directory, &mut keys)?;
    keys.sort_unstable();
    Ok(keys)
}

/// Returns the digest recorded for the current shader artifact set.
pub(crate) fn digest() -> String {
    value("digest").unwrap_or_else(|| UNKNOWN.to_string())
}

/// Returns the recorded shader artifact count as text.
pub(crate) fn count_text() -> String {
    value("count").unwrap_or_else(|| UNKNOWN.to_string())
}

/// Returns the largest SPIR-V artifact size as text.
pub(crate) fn max_spv_bytes_text() -> String {
    value("max_spv_bytes").unwrap_or_else(|| UNKNOWN.to_string())
}

/// Returns the name of the largest recorded SPIR-V artifact.
pub(crate) fn max_spv_name() -> String {
    value("max_spv_name").unwrap_or_else(|| UNKNOWN.to_string())
}

/// Returns the shader artifact size-guard status.
pub(crate) fn size_guard_status() -> String {
    value("size_guard_status").unwrap_or_else(|| UNKNOWN.to_string())
}

/// Returns the configured maximum SPIR-V artifact size as text.
pub(crate) fn size_guard_max_bytes_text() -> String {
    value("size_guard_max_bytes").unwrap_or_else(|| UNKNOWN.to_string())
}

/// Returns the recorded shader artifact count when it is numeric.
pub(crate) fn count() -> Option<u64> {
    parse_u64(&count_text())
}

/// Returns the largest SPIR-V artifact size when it is numeric.
pub(crate) fn max_spv_bytes() -> Option<u64> {
    parse_u64(&max_spv_bytes_text())
}

fn parse_u64(value: &str) -> Option<u64> {
    value.parse::<u64>().ok()
}

fn value(key: &str) -> Option<String> {
    let text = std::fs::read_to_string(PathBuf::from(ARTIFACT_ROOT).join("artifacts.env")).ok()?;
    text.lines().find_map(|line| {
        let (candidate, value) = line.split_once('=')?;
        (candidate == key).then(|| value.to_string())
    })
}
