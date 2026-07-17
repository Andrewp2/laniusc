use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use serde_json::Value;

const LANGUAGES: [&str; 5] = ["rust", "c", "cpp", "zig", "lanius"];
const EXPECTED_STDOUT: &str = "44483\n";

#[test]
fn grid_checksum_benchmark_artifacts_are_checked() {
    let root = artifact_root();
    let config = read_json(root.join("generator_config.json"));
    assert_eq!(config["schema"], "lanius.benchmark-generator.v1");
    assert_eq!(config["name"], "grid_checksum");
    assert_eq!(config["width"], 32);
    assert_eq!(config["height"], 24);
    assert_eq!(config["seed"], 19);
    assert_eq!(config["warmups"], 1);
    assert_eq!(config["iters"], 3);
    assert_eq!(config["expected_stdout"], EXPECTED_STDOUT);

    let commands = read_json(root.join("commands.json"));
    assert_eq!(commands["schema"], "lanius.benchmark-commands.v1");
    let command_map = commands["commands"]
        .as_object()
        .expect("commands.json should contain command map");
    assert_no_debug_info_flags(command_map);

    let machine = read_json(root.join("machine_info.json"));
    assert_eq!(machine["schema"], "lanius.benchmark-machine.v1");
    for key in ["rustc", "gcc", "g++", "zig", "laniusc"] {
        let value = machine[key]
            .as_str()
            .unwrap_or_else(|| panic!("machine_info missing {key}"));
        assert_ne!(value, "missing", "machine_info {key} should be recorded");
        assert!(!value.is_empty(), "machine_info {key} should be nonempty");
    }
    for key in [
        "cpu_model",
        "logical_cpus",
        "memory_total_bytes",
        "gpu",
        "gpu_measurement_state",
        "gpu_compute_processes",
        "lanius_profile",
    ] {
        let value = machine[key]
            .as_str()
            .unwrap_or_else(|| panic!("machine_info missing {key}"));
        assert_ne!(value, "missing", "machine_info {key} should be recorded");
        assert!(!value.is_empty(), "machine_info {key} should be nonempty");
    }
    assert_eq!(machine["lanius_profile"], "release");

    let rows = parse_results(&root.join("results.tsv"));
    assert_eq!(
        rows.keys().cloned().collect::<BTreeSet<_>>(),
        LANGUAGES.into_iter().map(str::to_string).collect()
    );

    let expected_stdout_hash = sha256_bytes(EXPECTED_STDOUT.as_bytes());
    for language in LANGUAGES {
        let source_path = root.join("src").join(source_name(language));
        let output_path = root.join("outputs").join(format!("{language}.stdout"));
        assert!(source_path.is_file(), "{language} source should exist");
        assert!(output_path.is_file(), "{language} output should exist");
        assert_eq!(fs::read_to_string(&output_path).unwrap(), EXPECTED_STDOUT);

        let command = command_map
            .get(language)
            .unwrap_or_else(|| panic!("commands missing {language}"));
        assert_command_array(command, "compile", language);
        assert_command_array(command, "run", language);
        if language == "lanius" {
            assert_command_array(command, "daemon_start", language);
            assert_eq!(command["compile_request"]["command"], "compile");
            assert_eq!(command["compile_request"]["emit"], "x86_64");
        }

        let row = rows
            .get(language)
            .unwrap_or_else(|| panic!("results missing {language}"));
        assert_eq!(row["status"], "ok");
        assert_positive_number(&row["compile_ms"], "compile_ms", language);
        assert_positive_number(&row["compile_avg_ms"], "compile_avg_ms", language);
        assert_positive_number(&row["run_ms"], "run_ms", language);
        assert_positive_number(&row["run_avg_ms"], "run_avg_ms", language);
        assert_eq!(
            row["compile_mode"],
            if language == "lanius" {
                "daemon_job"
            } else {
                "process"
            }
        );
        if language == "lanius" {
            for field in ["daemon_load_ms", "daemon_compile_ms", "daemon_write_ms"] {
                assert_positive_number(&row[field], field, language);
            }
            assert_positive_number(&row["startup_ms"], "startup_ms", language);
            assert!(
                row["startup_ms"].parse::<f64>().unwrap() < 60_000.0,
                "lanius daemon startup should stay under one minute"
            );
            assert_positive_number(
                &row["startup_resident_set_bytes"],
                "startup_resident_set_bytes",
                language,
            );
            assert_positive_number(
                &row["final_resident_set_bytes"],
                "final_resident_set_bytes",
                language,
            );
            assert_positive_number(
                &row["peak_resident_set_bytes"],
                "peak_resident_set_bytes",
                language,
            );
            let startup_rss = row["startup_resident_set_bytes"].parse::<u64>().unwrap();
            let final_rss = row["final_resident_set_bytes"].parse::<u64>().unwrap();
            let peak_rss = row["peak_resident_set_bytes"].parse::<u64>().unwrap();
            assert!(peak_rss >= startup_rss);
            assert!(peak_rss >= final_rss);
        } else {
            assert!(row["daemon_load_ms"].is_empty());
            assert!(row["daemon_compile_ms"].is_empty());
            assert!(row["daemon_write_ms"].is_empty());
            assert!(row["startup_ms"].is_empty());
            assert!(row["startup_resident_set_bytes"].is_empty());
            assert!(row["final_resident_set_bytes"].is_empty());
            assert!(row["peak_resident_set_bytes"].is_empty());
        }
        assert_eq!(row["stdout_sha256"], expected_stdout_hash);
        assert_eq!(row["source_sha256"], sha256_file(&source_path));
    }

    let manifest = read_json(root.join("manifest.json"));
    assert_eq!(manifest["schema"], "lanius.benchmark-artifacts.v1");
    assert_eq!(manifest["workload"], "grid_checksum");
    assert_eq!(
        manifest["languages"]
            .as_array()
            .expect("manifest languages should be an array")
            .iter()
            .map(|value| value.as_str().expect("language should be a string"))
            .collect::<Vec<_>>(),
        LANGUAGES
    );
    let statuses = manifest["result_status"]
        .as_object()
        .expect("manifest result status should be an object");
    for language in LANGUAGES {
        assert_eq!(statuses[language], "ok");
    }
    for file in manifest["files"]
        .as_array()
        .expect("manifest files should be an array")
    {
        let relative = file["path"]
            .as_str()
            .expect("manifest file path should be a string");
        let expected_hash = file["sha256"]
            .as_str()
            .expect("manifest file hash should be a string");
        assert_eq!(sha256_file(&root.join(relative)), expected_hash);
    }
}

#[test]
fn grid_checksum_sources_match_generator() {
    let repo = repo_root();
    let out_rel = Path::new("target")
        .join("benchmark-artifact-regeneration")
        .join("grid_checksum");
    let out_abs = repo.join(&out_rel);
    let _ = fs::remove_dir_all(&out_abs);

    let output = Command::new("python3")
        .arg("tools/generate_benchmark_artifacts.py")
        .arg("--out")
        .arg(&out_rel)
        .current_dir(&repo)
        .output()
        .expect("run benchmark artifact generator");
    assert!(
        output.status.success(),
        "benchmark artifact generator should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    assert_eq!(
        read_json(out_abs.join("generator_config.json")),
        read_json(artifact_root().join("generator_config.json")),
        "checked generator config should match regenerated config"
    );
    for language in LANGUAGES {
        let source = source_name(language);
        let regenerated = sha256_file(&out_abs.join("src").join(source));
        let checked = sha256_file(&artifact_root().join("src").join(source));
        assert_eq!(
            regenerated, checked,
            "checked {language} benchmark source hash should match generator output"
        );
    }
}

#[test]
fn compile_scaling_1101000_artifacts_are_checked_and_reproducible() {
    let repo = repo_root();
    let root = repo.join("benchmark_artifacts/compile_scaling_1101000");
    let config = read_json(root.join("config.json"));
    assert_eq!(config["schema"], "lanius.compile-scaling-matrix-config.v1");
    assert_eq!(config["size"], 1_101_000);
    assert_eq!(
        config["seeds"],
        serde_json::json!([20, 21, 22, 23, 24, 25, 26])
    );
    assert_eq!(config["warm_seed"], 19);
    assert_eq!(
        config["sample_policy"],
        "all samples retained; median is primary, min/max/MAD are reported"
    );
    assert_eq!(
        config["validation_policy"],
        "every artifact must execute with exact model-derived stdout"
    );
    assert!(
        config["daemon_warmup_policy"]
            .as_str()
            .unwrap()
            .contains("contiguous randomized hot-daemon batch")
    );

    let commands = read_json(root.join("commands.json"));
    assert_eq!(
        commands["schema"],
        "lanius.compile-scaling-command-templates.v1"
    );
    for lane in ["o0", "optimized"] {
        let map = commands[lane].as_object().expect("lane command map");
        assert_no_debug_info_flags(map);
        for language in ["rust", "c", "cpp", "zig"] {
            assert_command_array(&commands[lane], language, lane);
        }
    }
    assert_command_array(&commands, "lanius_daemon", "compile scaling");
    assert!(
        commands["o0"]["c"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v == "-O0")
    );
    assert!(
        commands["optimized"]["c"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v == "-O2")
    );

    let source_manifest = read_json(root.join("source_manifest.json"));
    assert_eq!(
        source_manifest["schema"],
        "lanius.compile-scaling-source-manifest.v2"
    );
    for seed in 19..=26 {
        let variant = &source_manifest["variants"][seed.to_string()];
        assert_eq!(variant["target_lanius_bytes"], 1_101_000);
        assert_eq!(variant["workload"]["all_functions_reachable"], true);
        assert!(
            variant["workload"]["reachable_function_count"]
                .as_u64()
                .unwrap()
                > 1_900
        );
        for family in ["array", "bitwise", "loop", "nested_branch", "struct"] {
            assert!(
                variant["workload"]["leaf_family_counts"][family]
                    .as_u64()
                    .unwrap()
                    > 0
            );
        }
    }

    let samples = read_json(root.join("samples.json"));
    let rows = samples["samples"].as_array().expect("raw samples");
    assert_eq!(rows.len(), 63);
    assert_eq!(
        rows.iter()
            .filter(|row| row["language"] == "lanius")
            .count(),
        7
    );
    let orders = rows
        .iter()
        .map(|row| row["order"].as_u64().unwrap())
        .collect::<BTreeSet<_>>();
    assert_eq!(orders.len(), 63);
    for row in rows {
        assert!(row["wall_ms"].as_f64().unwrap() > 0.0);
        let seed = row["seed"].as_u64().unwrap();
        let expected = fs::read(root.join("outputs").join(format!("seed-{seed}.stdout"))).unwrap();
        assert_eq!(row["stdout_sha256"], sha256_bytes(&expected));
    }

    let provenance = read_json(root.join("provenance.json"));
    assert_eq!(
        provenance["runner_sha256"],
        sha256_file(&repo.join("tools/run_compile_scaling_matrix.py"))
    );
    assert_eq!(
        provenance["generator_sha256"],
        sha256_file(&repo.join("tools/generate_compile_scaling_sources.py"))
    );
    assert_eq!(
        provenance["model_sha256"],
        sha256_file(&repo.join("tools/compile_workload_model.py"))
    );

    let summary = read_json(root.join("summary.json"));
    assert_eq!(summary["schema"], "lanius.compile-scaling-summary.v1");
    assert_eq!(summary["rows"].as_array().unwrap().len(), 9);
    let lanius = summary["rows"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["language"] == "lanius")
        .unwrap();
    assert_eq!(lanius["lane"], "hot_daemon");
    assert_eq!(lanius["samples"], 7);
    let manifest = read_json(root.join("manifest.json"));
    assert_eq!(
        manifest["schema"],
        "lanius.compile-scaling-matrix-manifest.v1"
    );
    for file in manifest["files"].as_array().unwrap() {
        let relative = file["path"].as_str().unwrap();
        assert_eq!(sha256_file(&root.join(relative)), file["sha256"]);
        assert_eq!(
            fs::metadata(root.join(relative)).unwrap().len(),
            file["bytes"].as_u64().unwrap()
        );
    }
}

fn artifact_root() -> PathBuf {
    repo_root().join("benchmark_artifacts/grid_checksum")
}

fn assert_no_debug_info_flags(commands: &serde_json::Map<String, Value>) {
    let command = |language: &str| {
        let value = commands
            .get(language)
            .unwrap_or_else(|| panic!("commands missing {language}"));
        value
            .get("compile")
            .unwrap_or(value)
            .as_array()
            .unwrap_or_else(|| panic!("{language} compile command should be an array"))
            .iter()
            .map(|arg| arg.as_str().expect("command argument should be a string"))
            .collect::<Vec<_>>()
    };

    for language in ["c", "cpp"] {
        assert!(command(language).contains(&"-g0"));
    }
    let rust = command("rust");
    assert!(rust.contains(&"debuginfo=0"));
    assert!(rust.contains(&"strip=debuginfo"));
    assert!(command("zig").contains(&"-fstrip"));
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf()
}

fn read_json(path: PathBuf) -> Value {
    let text =
        fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|err| panic!("parse {}: {err}", path.display()))
}

fn source_name(language: &str) -> &'static str {
    match language {
        "rust" => "grid_checksum.rs",
        "c" => "grid_checksum.c",
        "cpp" => "grid_checksum.cpp",
        "zig" => "grid_checksum.zig",
        "lanius" => "grid_checksum.lani",
        _ => panic!("unknown language {language}"),
    }
}

fn assert_command_array(command: &Value, key: &str, language: &str) {
    let parts = command[key]
        .as_array()
        .unwrap_or_else(|| panic!("{language} {key} command should be an array"));
    assert!(
        !parts.is_empty(),
        "{language} {key} command should be nonempty"
    );
    for part in parts {
        let text = part
            .as_str()
            .unwrap_or_else(|| panic!("{language} {key} command part should be a string"));
        assert!(
            !text.is_empty(),
            "{language} {key} command part should be nonempty"
        );
        assert!(
            !text.starts_with('/'),
            "{language} {key} command should use repo-relative paths: {text}"
        );
    }
}

fn assert_positive_number(raw: &str, field: &str, language: &str) {
    let value = raw
        .parse::<f64>()
        .unwrap_or_else(|err| panic!("{language} {field} should be numeric: {err}"));
    assert!(value > 0.0, "{language} {field} should be positive");
}

fn parse_results(path: &Path) -> BTreeMap<String, BTreeMap<String, String>> {
    let text =
        fs::read_to_string(path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
    let mut lines = text.lines();
    let header = lines
        .next()
        .unwrap_or_else(|| panic!("{} should include a header", path.display()))
        .split('\t')
        .map(str::to_string)
        .collect::<Vec<_>>();
    let mut rows = BTreeMap::new();
    for line in lines {
        let fields = line.split('\t').map(str::to_string).collect::<Vec<_>>();
        assert_eq!(fields.len(), header.len(), "results row width mismatch");
        let row = header
            .iter()
            .cloned()
            .zip(fields)
            .collect::<BTreeMap<_, _>>();
        let language = row
            .get("language")
            .expect("results row should include language")
            .to_owned();
        assert!(
            rows.insert(language.clone(), row).is_none(),
            "duplicate result for {language}"
        );
    }
    rows
}

fn sha256_file(path: &Path) -> String {
    let output = Command::new("sha256sum")
        .arg(path)
        .output()
        .unwrap_or_else(|err| panic!("run sha256sum {}: {err}", path.display()));
    assert!(
        output.status.success(),
        "sha256sum failed for {}\nstderr:\n{}",
        path.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout)
        .expect("sha256sum stdout should be UTF-8")
        .split_whitespace()
        .next()
        .expect("sha256sum should print a hash")
        .to_string()
}

fn sha256_bytes(bytes: &[u8]) -> String {
    let temp = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("target")
        .join("benchmark-artifact-stdout.sha256-input");
    fs::write(&temp, bytes).unwrap_or_else(|err| panic!("write {}: {err}", temp.display()));
    let hash = sha256_file(&temp);
    let _ = fs::remove_file(temp);
    hash
}
