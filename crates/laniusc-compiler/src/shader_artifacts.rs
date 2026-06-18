use std::path::PathBuf;

const UNKNOWN: &str = "unknown";
const ARTIFACT_ROOT: &str = env!("LANIUS_SHADER_ARTIFACT_ROOT");

/// Resolves a generated shader artifact path under the build-time artifact root.
pub(crate) fn artifact_path(file: &str) -> PathBuf {
    PathBuf::from(ARTIFACT_ROOT).join(file)
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
