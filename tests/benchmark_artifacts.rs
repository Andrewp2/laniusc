use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use serde_json::Value;

const WORKLOADS: [&str; 3] = ["integer_mix", "grid_checksum", "array_walk"];
const LANGUAGE_LANES: [(&str, &str); 11] = [
    ("c", "debug"),
    ("c", "o2"),
    ("c", "optimized"),
    ("cpp", "debug"),
    ("cpp", "optimized"),
    ("rust", "debug"),
    ("rust", "optimized"),
    ("zig", "debug"),
    ("zig", "optimized"),
    ("tcc", "default"),
    ("lanius", "default"),
];

#[test]
fn runtime_suite_artifacts_are_complete_and_checked() {
    let repo = repo_root();
    let root = artifact_root();
    let suite = read_json(root.join("suite.json"));
    assert_eq!(suite["schema"], "lanius.runtime-suite.v1");
    assert_eq!(suite["runtime_schema"], "lanius.runtime-comparison.v2");
    assert_eq!(suite["measured"], true);
    assert_eq!(
        suite["generator_sha256"],
        sha256_file(&repo.join("tools/run_runtime_comparison.py"))
    );
    assert_eq!(
        suite["workloads"]
            .as_array()
            .expect("suite workloads")
            .iter()
            .map(|row| row["workload"].as_str().expect("workload name"))
            .collect::<Vec<_>>(),
        WORKLOADS
    );
    let summary = read_json(root.join("summary.json"));
    assert_eq!(summary["schema"], "lanius.runtime-suite.v1");
    let rows = summary["rows"].as_array().expect("suite summary rows");
    assert_eq!(rows.len(), WORKLOADS.len() * LANGUAGE_LANES.len());
    for workload in WORKLOADS {
        assert_eq!(
            rows.iter()
                .filter(|row| row["workload"] == workload)
                .count(),
            LANGUAGE_LANES.len()
        );
    }

    for workload in WORKLOADS {
        verify_workload(&root.join(workload), workload);
    }
}

#[test]
fn runtime_suite_sources_match_the_generator() {
    let repo = repo_root();
    let out_rel = Path::new("target").join("runtime-suite-regeneration");
    let out = repo.join(&out_rel);
    let _ = fs::remove_dir_all(&out);

    let result = Command::new("python3")
        .arg("tools/run_runtime_comparison.py")
        .arg("--workload")
        .arg("all")
        .arg("--out")
        .arg(&out_rel)
        .current_dir(&repo)
        .output()
        .expect("run runtime suite generator");
    assert!(
        result.status.success(),
        "runtime suite generation failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );

    for workload in WORKLOADS {
        let checked = artifact_root().join(workload);
        let regenerated = out.join(workload);
        assert_eq!(
            read_json(checked.join("config.json")),
            read_json(regenerated.join("config.json")),
            "{workload} configuration changed without a new measurement"
        );
        for language in ["c", "cpp", "rust", "zig", "lanius"] {
            let source = source_name(workload, language);
            assert_eq!(
                sha256_file(&checked.join("src").join(&source)),
                sha256_file(&regenerated.join("src").join(&source)),
                "{workload} {language} source changed without a new measurement"
            );
        }
    }
}

fn verify_workload(root: &Path, workload: &str) {
    let config = read_json(root.join("config.json"));
    assert_eq!(config["schema"], "lanius.runtime-comparison.v2");
    assert_eq!(config["workload"], workload);
    assert_eq!(config["warmups_per_language"], 3);
    assert_eq!(config["samples_per_language"], 20);
    assert!(config["operation_count"].as_u64().unwrap() >= 6_000_000);
    let expected_stdout = config["expected_stdout"].as_str().unwrap();

    let commands = read_json(root.join("commands.json"));
    assert_eq!(commands["schema"], "lanius.runtime-comparison.v2");
    assert_optimization_flags(&commands["commands"]);
    for (language, lane) in LANGUAGE_LANES {
        let command = &commands["commands"][language][lane];
        assert_command_array(command, "compile", language, lane);
        assert_command_array(command, "run", language, lane);
        assert_eq!(
            fs::read_to_string(
                root.join("outputs")
                    .join(format!("{language}-{lane}.stdout"))
            )
            .unwrap(),
            expected_stdout
        );
    }

    let samples = read_json(root.join("samples.json"));
    let samples = samples["samples"].as_array().expect("runtime samples");
    assert_eq!(samples.len(), LANGUAGE_LANES.len() * 20);
    assert_eq!(
        samples
            .iter()
            .map(|sample| sample["order"].as_u64().unwrap())
            .collect::<BTreeSet<_>>()
            .len(),
        samples.len(),
        "sample order should be a complete randomized permutation"
    );

    let summary = read_json(root.join("summary.json"));
    let rows = summary["rows"].as_array().expect("summary rows");
    assert_eq!(rows.len(), LANGUAGE_LANES.len());
    for (language, lane) in LANGUAGE_LANES {
        let row = rows
            .iter()
            .find(|row| row["language"] == language && row["lane"] == lane)
            .expect("language lane summary");
        assert_eq!(row["samples"], 20);
        for field in ["median_ms", "mean_ms", "min_ms", "max_ms"] {
            assert!(row[field].as_f64().unwrap() > 0.0, "invalid {field}");
        }
        assert!(row["mad_ms"].as_f64().unwrap() >= 0.0);
        assert!(row["lanius_speedup"].as_f64().unwrap() > 0.0);
    }

    let manifest = read_json(root.join("manifest.json"));
    assert_eq!(manifest["schema"], "lanius.runtime-comparison.v2");
    for file in manifest["files"].as_array().expect("manifest files") {
        let relative = file["path"].as_str().unwrap();
        assert_eq!(sha256_file(&root.join(relative)), file["sha256"]);
    }
}

fn assert_optimization_flags(commands: &Value) {
    for language in ["c", "cpp"] {
        assert!(
            commands[language]["debug"]["compile"]
                .as_array()
                .unwrap()
                .iter()
                .any(|arg| arg == "-O0")
        );
        assert!(
            commands[language]["optimized"]["compile"]
                .as_array()
                .unwrap()
                .iter()
                .any(|arg| arg == "-O3")
        );
    }
    assert!(
        commands["c"]["o2"]["compile"]
            .as_array()
            .unwrap()
            .iter()
            .any(|arg| arg == "-O2")
    );
    assert!(
        commands["rust"]["optimized"]["compile"]
            .as_array()
            .unwrap()
            .iter()
            .any(|arg| arg == "opt-level=3")
    );
    assert!(
        commands["zig"]["optimized"]["compile"]
            .as_array()
            .unwrap()
            .iter()
            .any(|arg| arg == "ReleaseFast")
    );
}

fn assert_command_array(command: &Value, key: &str, language: &str, lane: &str) {
    let parts = command[key]
        .as_array()
        .unwrap_or_else(|| panic!("{language} {lane} {key} command should be an array"));
    assert!(!parts.is_empty());
    assert!(parts.iter().all(|part| {
        let text = part.as_str().expect("command arguments should be strings");
        !text.is_empty() && !text.starts_with('/')
    }));
}

fn source_name(workload: &str, language: &str) -> String {
    let extension = match language {
        "c" => "c",
        "cpp" => "cpp",
        "rust" => "rs",
        "zig" => "zig",
        "lanius" => "lani",
        _ => panic!("unknown language {language}"),
    };
    format!("{workload}.{extension}")
}

fn artifact_root() -> PathBuf {
    repo_root().join("benchmark_artifacts/runtime_suite_20260820")
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf()
}

fn read_json(path: PathBuf) -> Value {
    let text =
        fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|err| panic!("parse {}: {err}", path.display()))
}

fn sha256_file(path: &Path) -> String {
    let output = Command::new("sha256sum")
        .arg(path)
        .output()
        .unwrap_or_else(|err| panic!("run sha256sum {}: {err}", path.display()));
    assert!(
        output.status.success(),
        "sha256sum failed for {}",
        path.display()
    );
    String::from_utf8(output.stdout)
        .expect("sha256sum stdout should be UTF-8")
        .split_whitespace()
        .next()
        .expect("sha256sum should print a hash")
        .to_string()
}
