use std::path::PathBuf;

const UNKNOWN: &str = "unknown";
const ARTIFACT_ROOT: &str = env!("LANIUS_SHADER_ARTIFACT_ROOT");

pub fn artifact_root() -> PathBuf {
    PathBuf::from(ARTIFACT_ROOT)
}

pub fn artifact_path(file: &str) -> PathBuf {
    artifact_root().join(file)
}

pub fn shader_spv_path(shader: &str) -> PathBuf {
    artifact_path(&format!("{shader}.spv"))
}

pub fn shader_reflection_path(shader: &str) -> PathBuf {
    artifact_path(&format!("{shader}.reflect.json"))
}

pub fn embedded_artifact(file: &str) -> Option<&'static [u8]> {
    generated::embedded_artifact(file)
}

pub fn digest() -> String {
    value("digest").unwrap_or_else(|| UNKNOWN.to_string())
}

pub fn count_text() -> String {
    value("count").unwrap_or_else(|| UNKNOWN.to_string())
}

pub fn max_spv_bytes_text() -> String {
    value("max_spv_bytes").unwrap_or_else(|| UNKNOWN.to_string())
}

pub fn max_spv_name() -> String {
    value("max_spv_name").unwrap_or_else(|| UNKNOWN.to_string())
}

pub fn size_guard_status() -> String {
    value("size_guard_status").unwrap_or_else(|| UNKNOWN.to_string())
}

pub fn size_guard_max_bytes_text() -> String {
    value("size_guard_max_bytes").unwrap_or_else(|| UNKNOWN.to_string())
}

pub fn count() -> Option<u64> {
    parse_u64(&count_text())
}

pub fn max_spv_bytes() -> Option<u64> {
    parse_u64(&max_spv_bytes_text())
}

fn parse_u64(value: &str) -> Option<u64> {
    value.parse::<u64>().ok()
}

#[cfg(all(debug_assertions, not(target_arch = "wasm32")))]
fn value(key: &str) -> Option<String> {
    runtime_metadata::value(key)
}

#[cfg(any(not(debug_assertions), target_arch = "wasm32"))]
fn value(key: &str) -> Option<String> {
    match key {
        "digest" => option_env!("LANIUS_SHADER_ARTIFACT_DIGEST"),
        "count" => option_env!("LANIUS_SHADER_ARTIFACT_COUNT"),
        "max_spv_bytes" => option_env!("LANIUS_SHADER_ARTIFACT_MAX_BYTES"),
        "max_spv_name" => option_env!("LANIUS_SHADER_ARTIFACT_MAX_NAME"),
        "size_guard_status" => option_env!("LANIUS_SHADER_SIZE_GUARD_STATUS"),
        "size_guard_max_bytes" => option_env!("LANIUS_SHADER_SIZE_GUARD_MAX_BYTES"),
        _ => None,
    }
    .map(str::to_string)
}

#[cfg(all(debug_assertions, not(target_arch = "wasm32")))]
mod runtime_metadata {
    use std::{collections::HashMap, fs, sync::OnceLock};

    static METADATA: OnceLock<HashMap<String, String>> = OnceLock::new();

    pub(super) fn value(key: &str) -> Option<String> {
        metadata().get(key).cloned()
    }

    fn metadata() -> &'static HashMap<String, String> {
        METADATA.get_or_init(|| {
            let Ok(text) = fs::read_to_string(super::artifact_root().join("artifacts.env")) else {
                return HashMap::new();
            };
            text.lines()
                .filter_map(|line| {
                    let (key, value) = line.split_once('=')?;
                    Some((key.to_string(), value.to_string()))
                })
                .collect()
        })
    }
}

mod generated {
    include!(concat!(env!("OUT_DIR"), "/shader_artifacts_generated.rs"));
}
