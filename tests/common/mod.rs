pub mod sample_programs;

use std::path::PathBuf;

pub fn temp_artifact_path(prefix: &str, stem: &str, extension: Option<&str>) -> PathBuf {
    let mut path = std::env::temp_dir().join(format!(
        "{}_{}_{}_{}",
        prefix,
        sanitize_path_component(stem),
        std::process::id(),
        unique_suffix()
    ));
    if let Some(extension) = extension {
        path.set_extension(extension);
    }
    path
}

fn sanitize_path_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}
