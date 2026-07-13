mod common;

#[cfg(unix)]
use std::os::unix::net::UnixStream;
use std::{
    env,
    fs,
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        if self.0.try_wait().ok().flatten().is_none() {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
}

#[cfg(unix)]
#[test]
fn cli_daemon_accepts_a_unix_socket_session() {
    let socket = common::temp_artifact_path("laniusc_daemon", "socket", Some("sock"));
    let mut command = Command::new(laniusc_bin());
    command
        .arg("daemon")
        .arg("--unix-socket")
        .arg(&socket)
        .arg("--backend")
        .arg("x86_64")
        .arg("--stdlib-root")
        .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut child = ChildGuard(command.spawn().expect("spawn Unix-socket daemon"));

    let deadline = Instant::now() + Duration::from_secs(10);
    let stream = loop {
        match UnixStream::connect(&socket) {
            Ok(stream) => break stream,
            Err(err) if Instant::now() < deadline => {
                assert!(
                    child
                        .0
                        .try_wait()
                        .expect("poll Unix-socket daemon")
                        .is_none(),
                    "Unix-socket daemon exited before accepting a connection: {err}"
                );
                thread::sleep(Duration::from_millis(10));
            }
            Err(err) => panic!(
                "connect to Unix-socket daemon at {}: {err}",
                socket.display()
            ),
        }
    };
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .expect("set daemon socket read timeout");
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .expect("set daemon socket write timeout");
    let mut reader = BufReader::new(stream.try_clone().expect("clone daemon client socket"));
    let mut writer = stream;

    let mut ready_line = String::new();
    reader
        .read_line(&mut ready_line)
        .expect("read daemon ready response");
    let ready: serde_json::Value =
        serde_json::from_str(&ready_line).expect("parse daemon ready response");
    assert_eq!(ready["event"], "ready");

    writeln!(writer, r#"{{"id":"stop","command":"shutdown"}}"#)
        .expect("send daemon shutdown request");
    writer.flush().expect("flush daemon shutdown request");
    let mut shutdown_line = String::new();
    reader
        .read_line(&mut shutdown_line)
        .expect("read daemon shutdown response");
    let shutdown: serde_json::Value =
        serde_json::from_str(&shutdown_line).expect("parse daemon shutdown response");
    assert_eq!(shutdown["id"], "stop");
    assert_eq!(shutdown["event"], "shutdown");

    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(status) = child.0.try_wait().expect("poll daemon shutdown") {
            assert!(status.success(), "Unix-socket daemon failed: {status}");
            break;
        }
        assert!(
            Instant::now() < deadline,
            "Unix-socket daemon did not exit after shutdown"
        );
        thread::sleep(Duration::from_millis(10));
    }
    assert!(
        !socket.exists(),
        "Unix-socket daemon should remove {} after shutdown",
        socket.display()
    );
}

#[test]
fn cli_daemon_reuses_one_process_to_emit_runnable_x86_artifact() {
    let source = common::temp_artifact_path("laniusc_daemon", "source", Some("lani"));
    let second_source = common::temp_artifact_path("laniusc_daemon", "second_source", Some("lani"));
    let invalid_source =
        common::temp_artifact_path("laniusc_daemon", "invalid_source", Some("lani"));
    let artifact = common::temp_artifact_path("laniusc_daemon", "artifact", None);
    let repeat_artifact = common::temp_artifact_path("laniusc_daemon", "repeat_artifact", None);
    let second_artifact = common::temp_artifact_path("laniusc_daemon", "second_artifact", None);
    let requests = common::temp_artifact_path("laniusc_daemon", "requests", Some("jsonl"));
    fs::write(
        &source,
        "fn main() -> i32 {\n    print(7);\n    return 0;\n}\n",
    )
    .expect("write daemon source fixture");
    fs::write(
        &second_source,
        "fn main() -> i32 {\n    print(9);\n    return 0;\n}\n",
    )
    .expect("write second daemon source fixture");
    fs::write(
        &invalid_source,
        "fn main() -> i32 {\n    print(8);\n    return 0;\n",
    )
    .expect("write invalid daemon source fixture");
    let missing = serde_json::json!({
        "id": "missing",
        "command": "compile",
        "emit": "x86_64",
        "input": source.with_extension("missing"),
        "output": artifact,
    });
    let compile = serde_json::json!({
        "id": "compile",
        "command": "compile",
        "emit": "x86_64",
        "input": source,
        "output": artifact,
    });
    let second_compile = serde_json::json!({
        "id": "second_compile",
        "command": "compile",
        "emit": "x86_64",
        "input": second_source,
        "output": second_artifact,
    });
    let repeat_compile = serde_json::json!({
        "id": "repeat_compile",
        "command": "compile",
        "emit": "x86_64",
        "input": source,
        "output": repeat_artifact,
    });
    let invalid_compile = serde_json::json!({
        "id": "invalid_compile",
        "command": "compile",
        "emit": "x86_64",
        "input": invalid_source,
        "output": second_artifact.with_extension("invalid"),
    });
    let trim = serde_json::json!({"id": "trim", "command": "trim"});
    let shutdown = serde_json::json!({"id": "shutdown", "command": "shutdown"});
    fs::write(
        &requests,
        format!(
            "{missing}\n{compile}\n{repeat_compile}\n{invalid_compile}\n{trim}\n{second_compile}\n{shutdown}\n"
        ),
    )
    .expect("write daemon request fixture");

    let stdin = fs::File::open(&requests).expect("open daemon request fixture");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("daemon")
        .arg("--stdio")
        .arg("--backend")
        .arg("x86_64")
        .arg("--stdlib-root")
        .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
        .env("LANIUS_GPU_COMPILE_HOST_TIMING", "1")
        .stdin(Stdio::from(stdin));
    let output = common::command_output_with_timeout("laniusc daemon x86 job", &mut command);
    common::assert_command_success("laniusc daemon x86 job", &output);

    let responses = String::from_utf8(output.stdout)
        .expect("daemon stdout should be UTF-8")
        .lines()
        .map(|line| serde_json::from_str::<serde_json::Value>(line).expect("daemon response JSON"))
        .collect::<Vec<_>>();
    assert_eq!(
        responses.len(),
        8,
        "ready, recoverable file error, split compile, fused repeat compile, syntax error, trim, post-trim compile, and shutdown responses"
    );
    assert_eq!(responses[0]["event"], "ready");
    assert!(
        responses[0]["startup_ms"]
            .as_f64()
            .is_some_and(|ms| ms < 60_000.0)
    );
    assert!(
        responses[0]["resident_set_bytes"]
            .as_u64()
            .is_some_and(|bytes| bytes > 0)
    );
    assert!(
        responses[0]["tracked_gpu_buffers"]["allocations"]
            .as_u64()
            .is_some_and(|count| count > 0)
    );
    assert!(
        responses[0]["tracked_gpu_buffers"]["bytes"]
            .as_u64()
            .is_some_and(|bytes| bytes > 0)
    );
    assert!(responses[0]["wgpu_resources"]["buffers"].is_object());
    assert_eq!(responses[1]["id"], "missing");
    assert_eq!(responses[1]["ok"], false);
    assert!(responses[1]["diagnostic"].is_object());
    assert_eq!(responses[2]["id"], "compile");
    assert_eq!(responses[2]["ok"], true);
    assert_eq!(responses[2]["emit"], "x86_64");
    assert!(responses[2]["tracked_gpu_buffers"].is_object());
    assert!(responses[2]["wgpu_resources"]["command_buffers"].is_object());
    assert!(
        responses[2]["elapsed_ms"]
            .as_f64()
            .is_some_and(|ms| ms > 0.0)
    );
    for field in ["load_ms", "compile_ms", "write_ms"] {
        assert!(
            responses[2][field].as_f64().is_some_and(|ms| ms >= 0.0),
            "successful compile response should contain nonnegative {field}"
        );
    }
    assert_eq!(responses[3]["id"], "repeat_compile");
    assert_eq!(responses[3]["ok"], true);
    assert_eq!(responses[3]["emit"], "x86_64");
    assert_eq!(responses[4]["id"], "invalid_compile");
    assert_eq!(responses[4]["ok"], false);
    assert!(responses[4]["diagnostic"].is_object());
    assert_eq!(responses[5]["id"], "trim");
    assert_eq!(responses[5]["ok"], true);
    assert_eq!(responses[5]["event"], "trimmed");
    let tracked_before_trim = responses[5]["tracked_gpu_buffers_before"]["bytes"]
        .as_u64()
        .expect("trim response should report tracked bytes before release");
    let tracked_after_trim = responses[5]["tracked_gpu_buffers"]["bytes"]
        .as_u64()
        .expect("trim response should report tracked bytes after release");
    assert!(
        tracked_after_trim < tracked_before_trim,
        "trim should release job-sized tracked buffers: before={tracked_before_trim} after={tracked_after_trim}"
    );
    assert!(
        responses[5]["x86_pooled_buffers_released"]
            .as_u64()
            .is_some_and(|count| count > 0),
        "trim should drain idle raw x86 scratch from the process pool"
    );
    assert_eq!(responses[6]["id"], "second_compile");
    assert_eq!(responses[6]["ok"], true);
    assert_eq!(responses[6]["emit"], "x86_64");
    assert_eq!(responses[7]["event"], "shutdown");

    let run = common::short_process_output_with_timeout(
        "run daemon-emitted x86 artifact",
        &mut Command::new(&artifact),
    );
    common::assert_command_success("run daemon-emitted x86 artifact", &run);
    assert_eq!(run.stdout, b"7\n");

    let repeat_run = common::short_process_output_with_timeout(
        "run repeat daemon-emitted x86 artifact",
        &mut Command::new(&repeat_artifact),
    );
    common::assert_command_success("run repeat daemon-emitted x86 artifact", &repeat_run);
    assert_eq!(repeat_run.stdout, b"7\n");

    let second_run = common::short_process_output_with_timeout(
        "run second daemon-emitted x86 artifact",
        &mut Command::new(&second_artifact),
    );
    common::assert_command_success("run second daemon-emitted x86 artifact", &second_run);
    assert_eq!(second_run.stdout, b"9\n");

    let _ = fs::remove_file(source);
    let _ = fs::remove_file(second_source);
    let _ = fs::remove_file(invalid_source);
    let _ = fs::remove_file(artifact);
    let _ = fs::remove_file(repeat_artifact);
    let _ = fs::remove_file(second_artifact);
    let _ = fs::remove_file(requests);
}
