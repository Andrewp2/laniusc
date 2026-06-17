use std::path::PathBuf;

const UNKNOWN: &str = "unknown";
const ARTIFACT_ROOT: &str = env!("LANIUS_SHADER_ARTIFACT_ROOT");

pub(crate) fn artifact_path(file: &str) -> PathBuf {
    PathBuf::from(ARTIFACT_ROOT).join(file)
}

pub(crate) fn digest() -> String {
    value("digest").unwrap_or_else(|| UNKNOWN.to_string())
}

pub(crate) fn count_text() -> String {
    value("count").unwrap_or_else(|| UNKNOWN.to_string())
}

pub(crate) fn max_spv_bytes_text() -> String {
    value("max_spv_bytes").unwrap_or_else(|| UNKNOWN.to_string())
}

pub(crate) fn max_spv_name() -> String {
    value("max_spv_name").unwrap_or_else(|| UNKNOWN.to_string())
}

pub(crate) fn size_guard_status() -> String {
    value("size_guard_status").unwrap_or_else(|| UNKNOWN.to_string())
}

pub(crate) fn size_guard_max_bytes_text() -> String {
    value("size_guard_max_bytes").unwrap_or_else(|| UNKNOWN.to_string())
}

pub(crate) fn count() -> Option<u64> {
    parse_u64(&count_text())
}

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
