// CPU-only wrapper around the unchanged repository x86 executable checker.
#[allow(dead_code)]
#[path = "../../../common/x86_jumps.rs"]
mod jumps;
#[derive(Default)]
struct TimeoutDetails {}
fn temp_artifact_path(prefix: &str, stem: &str, extension: Option<&str>) -> std::path::PathBuf {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "{prefix}_{stem}_{}_{}.{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
        extension.unwrap_or("tmp")
    ))
}
fn command_output_result_with_timeout(
    _: &str,
    command: &mut std::process::Command,
    duration: std::time::Duration,
    _: TimeoutDetails,
) -> std::io::Result<std::process::Output> {
    std::process::Command::new("timeout")
        .arg("--kill-after=2s")
        .arg(format!("{}s", duration.as_secs().max(1)))
        .arg(command.get_program())
        .args(command.get_args())
        .output()
}
fn main() {
    for path in std::env::args_os().skip(1) {
        jumps::assert_x86_64_file_jumps_stay_in_functions(path);
    }
}
