use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    ffi::OsString,
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{Mutex, OnceLock},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const DEFAULT_GENERATED_LINES: &str = "5000";
const DEFAULT_CAPACITY_STRESS_LINES: &str = "5000";
const DEFAULT_CAPACITY_STRESS_SOURCE: &str = "expr-dense";
const DEFAULT_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES: u64 = 12 * 1024 * 1024 * 1024;
const DEFAULT_GENERATED_GATE_COMMAND_TIMEOUT_MS: u64 = 120_000;
const MAX_GENERATED_LINES_WITHOUT_OPT_IN: usize = 20_000;
const MAX_CAPACITY_STRESS_LINES_WITHOUT_OPT_IN: usize = 20_000;
const ALLOW_LARGE_GENERATED_TESTS_ENV: &str = "LANIUS_ALLOW_LARGE_GENERATED_TESTS";
const GENERATED_X86_READBACK_TIMEOUT_MS: &str = "60000";
const CHILD_PROCESS_POLL_INTERVAL_MS: u64 = 10;

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly after frontend changes"]
fn generated_frontend_suite_passes_supported_phases() {
    let bin = gpu_compile_bench_bin();
    let lines = generated_lines();
    for phase in ["lex", "parse", "typecheck"] {
        run_success(
            &bin,
            &[
                "--phase",
                phase,
                "--source",
                "all",
                "--lines",
                lines.as_str(),
                "--warmups",
                "0",
                "--iters",
                "1",
                "--allow-large",
            ],
        );
    }
}

#[test]
#[ignore = "generated capacity gate; estimate-only submits no GPU work"]
fn generated_capacity_stress_x86_has_capacity_estimate_without_gpu_work() {
    let bin = gpu_compile_bench_bin();
    let source = capacity_stress_source();
    let lines = capacity_stress_lines();
    let output = run_success(
        &bin,
        &[
            "--phase",
            "x86",
            "--emit",
            "x86_64-elf",
            "--source",
            source.as_str(),
            "--lines",
            lines.as_str(),
            "--estimate-only",
        ],
    );
    assert_eq!(
        output.matches("no GPU work was submitted").count(),
        1,
        "estimate-only should report no GPU submission for the stress source"
    );
    assert!(
        output.contains("estimate compile_allocation_floor parser_plus_typecheck_plus_x86="),
        "estimate output should include the full compile allocation floor"
    );
    assert!(
        output.contains("estimate x86_dynamic_caps"),
        "estimate output should include x86 capacity details"
    );
    assert!(
        output.contains("token_capacity_basis=test_cpu_token_count"),
        "estimate output should use the exact no-GPU token count for generated sources"
    );
    assert_x86_capacity_estimate_is_internally_consistent(&output);
    let compile_floors = parse_u64_values(&output, "compile_floor_bytes");
    assert_eq!(
        compile_floors.len(),
        1,
        "estimate output should include one raw compile floor for the stress source"
    );
    let max_compile_floor = compile_floors.into_iter().max().expect("compile floors");
    let guardrail = max_capacity_stress_compile_floor_bytes();
    eprintln!("max_capacity_stress_compile_floor_bytes={max_compile_floor}");
    assert!(
        max_compile_floor <= guardrail,
        "x86 compile allocation floor {max_compile_floor} for source={source} lines={lines} exceeds guardrail {guardrail}"
    );
}

fn assert_x86_capacity_estimate_is_internally_consistent(output: &str) {
    const MAX_X86_INSTS: u64 = 2_097_152;
    const X86_INST_CAPACITY_MIN: u64 = 256;
    const X86_INST_CAPACITY_SLACK: u64 = 1_024;
    const X86_INSTS_PER_HIR_NODE_CAPACITY: u64 = 8;
    const X86_INSTS_PER_TOKEN_CAPACITY: u64 = 1;

    let estimate_line = line_containing(output, "estimate lines=");
    let parser_line = line_containing(output, "estimate parser_path=");
    let x86_line = line_containing(output, "estimate x86_dynamic_caps");
    let token_capacity =
        parse_u64_field(estimate_line, "lexer_token_capacity").expect("lexer_token_capacity");
    let parser_tree_capacity =
        parse_u64_field(parser_line, "parser_tree_capacity").expect("parser_tree_capacity");
    let hir_words = parse_u64_field(x86_line, "hir_words").expect("hir_words");
    let inst_basis_words = parse_u64_field(x86_line, "inst_basis_words").expect("inst_basis_words");
    let requested_inst_capacity =
        parse_u64_field(x86_line, "requested_inst_capacity").expect("requested_inst_capacity");
    let inst_capacity = parse_u64_field(x86_line, "inst_capacity").expect("inst_capacity");
    let inst_capacity_capped =
        parse_bool_field(x86_line, "inst_capacity_capped").expect("inst_capacity_capped");

    assert_eq!(
        parse_field(x86_line, "hir_basis"),
        Some("parser_tree_capacity"),
        "estimate-only should use projected parser tree capacity as the x86 HIR basis"
    );
    assert_eq!(hir_words, parser_tree_capacity);
    assert_eq!(inst_basis_words, parser_tree_capacity);

    let expected_requested = inst_basis_words
        .saturating_mul(X86_INSTS_PER_HIR_NODE_CAPACITY)
        .saturating_add(X86_INST_CAPACITY_SLACK);
    let token_scaled_limit = token_capacity
        .max(1)
        .saturating_mul(X86_INSTS_PER_TOKEN_CAPACITY)
        .saturating_add(X86_INST_CAPACITY_SLACK)
        .min(MAX_X86_INSTS);
    let inst_limit = token_scaled_limit.clamp(X86_INST_CAPACITY_MIN, MAX_X86_INSTS);
    let expected_inst = expected_requested.clamp(X86_INST_CAPACITY_MIN, inst_limit);
    assert_eq!(requested_inst_capacity, expected_requested);
    assert_eq!(inst_capacity, expected_inst);
    assert_eq!(inst_capacity_capped, expected_requested > expected_inst);
}

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly after resident frontend/backend changes"]
fn generated_reused_parse_matches_independent_varied() {
    let bin = gpu_compile_bench_bin();
    let lines = generated_lines();
    let suite = run_success(
        &bin,
        &[
            "--phase",
            "parse",
            "--source",
            "all",
            "--lines",
            lines.as_str(),
            "--warmups",
            "0",
            "--iters",
            "1",
            "--allow-large",
        ],
    );
    let independent = run_success(
        &bin,
        &[
            "--phase",
            "parse",
            "--source",
            "varied",
            "--lines",
            lines.as_str(),
            "--warmups",
            "0",
            "--iters",
            "1",
            "--allow-large",
        ],
    );

    let suite_varied = parse_metrics_for_source(&suite, "varied");
    let independent_varied = parse_metric_line(
        independent
            .lines()
            .find(|line| line.contains("phase=parse token_count="))
            .expect("independent parse output should include parse metrics"),
    );
    assert_eq!(
        suite_varied, independent_varied,
        "reused compiler parse metrics for varied source diverged from an independent run"
    );
}

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly for x86 backend validation"]
fn generated_reused_x86_single_source_suite_validates() {
    let bin = gpu_compile_bench_bin();
    let lines = generated_lines();
    run_success(
        &bin,
        &[
            "--phase",
            "x86",
            "--emit",
            "x86_64-elf",
            "--source",
            "simple-lets",
            "--lines",
            lines.as_str(),
            "--warmups",
            "1",
            "--iters",
            "1",
            "--allow-large",
            "--validate-output",
        ],
    );
}

#[test]
#[ignore = "Pareas comparison provenance gate; validates the no-run scaffold only"]
fn generated_pareas_comparison_is_local_artifact_scaffold_only() {
    let Some(pareas_bin) = pareas_bin() else {
        if env_truthy("LANIUS_REQUIRE_PAREAS") {
            panic!("Pareas provenance check required, but no Pareas binary was found");
        }
        eprintln!("skipping Pareas provenance check: set PAREAS_BIN or build ~/code/pareas");
        return;
    };

    let temp_home = unique_temp_dir("acceptance_pareas_home");
    let temp_path = unique_temp_dir("acceptance_pareas_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("PAREAS_BIN", &pareas_bin)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000");
    });
    let plan = parse_measurement_plan(&output);
    let checkpoint = plan
        .checkpoints
        .get("5000")
        .unwrap_or_else(|| panic!("missing checkpoint 5000 in {plan:#?}"));

    assert_eq!(
        required_plan_field(&plan.top, "paper_numbers_accepted"),
        "false"
    );
    assert_eq!(
        required_plan_field(&plan.top, "comparison_baseline_policy"),
        "local-pareas-artifacts-only"
    );
    assert_eq!(
        required_plan_field(&plan.top, "local_pareas_claim_source"),
        local_pareas_claim_source()
    );
    for name in optional_comparison_artifact_names() {
        let artifact = required_artifact(checkpoint, &name);
        assert_eq!(
            required_plan_field(artifact, "claim_source"),
            "optional_local_comparison_artifact",
            "Pareas artifact {name:?} should require local comparison provenance"
        );
        assert_eq!(
            required_plan_field(artifact, "claim_boundary"),
            "optional-local-comparison-provenance-not-pareas-claim",
            "Pareas artifact {name:?} should stay provenance-only in the no-run scaffold"
        );
    }

    let command_labels = &plan.command_labels;
    assert!(command_labels.contains("pareas_source_command_5000l"));
    assert!(command_labels.contains("pareas_source_sha256_command_5000l"));
    assert!(command_labels.contains("pareas_binary_sha256_command_5000l"));
    assert!(command_labels.contains("pareas_wrapped_command_5000l"));
    assert!(
        output.contains(
            "this scaffold records the intended commands but does not generate or run them."
        ),
        "Pareas scaffold should stay no-run and artifact-provenance only\n{output}"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_publishes_checkpoint_evidence_manifest() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command.env("HOME", &temp_home).env("PATH", &temp_path);
    });
    let plan = parse_measurement_plan(&output);

    assert_eq!(
        required_plan_field(&plan.top, "measurement_plan_schema"),
        "lanius.measurement-plan.v1"
    );
    assert_eq!(required_plan_field(&plan.top, "mode"), "no-run");
    assert_eq!(
        required_plan_field(&plan.top, "measurement_evidence_policy"),
        "local-artifacts-only"
    );
    assert_eq!(
        required_plan_field(&plan.top, "paper_numbers_accepted"),
        "false"
    );
    assert_eq!(
        required_plan_field(&plan.top, "comparison_baseline_policy"),
        "local-pareas-artifacts-only"
    );
    assert_eq!(
        required_plan_field(&plan.top, "freshness_policy"),
        "hash-and-checkpoint-field-match"
    );
    assert_eq!(
        required_plan_field(&plan.top, "measurement_scaffold_evidence_status"),
        measurement_scaffold_evidence_status()
    );
    assert_measurement_timing_contract(&plan.top);
    assert_claim_provenance_contract(&plan.top);
    assert_eq!(
        required_plan_field(&plan.top, "source_control_policy"),
        "git-head-plus-status-in-command-environment-hash"
    );
    assert_eq!(
        required_plan_field(&plan.top, "claim_scope_policy"),
        "exact-local-checkpoint-hardware-source-binary-only"
    );
    assert_eq!(
        required_plan_field(&plan.top, "repeatability_policy"),
        "claimable-metrics-require-at-least-three-iterations"
    );
    assert_eq!(
        required_plan_field(&plan.top, "minimum_iterations_for_claim"),
        "3"
    );
    assert_eq!(required_plan_field(&plan.top, "target"), "x86_64-elf");
    assert_eq!(
        csv_set(required_plan_field(&plan.top, "checkpoints")),
        string_set(["5000"])
    );
    assert_eq!(
        csv_vec(required_plan_field(&plan.top, "checkpoint_execution_order")),
        vec!["5000"]
    );
    assert_eq!(
        required_plan_field(&plan.top, "checkpoint_run_policy"),
        "run-checkpoint_execution_order-stop-on-first-readback-timeout-vram-growth-or-responsiveness-failure"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_checkpoint_artifacts"
        )),
        required_artifact_names()
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "optional_comparison_artifacts"
        )),
        optional_comparison_artifact_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "artifact_manifest_schema"),
        "lanius.measurement-artifacts.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_artifact_manifest_fields"
        )),
        required_artifact_manifest_field_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "readback_summary_schema"),
        "lanius.readback-summary.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_readback_summary_fields"
        )),
        required_readback_summary_field_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "vram_csv_schema"),
        "lanius.vram-csv.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(&plan.top, "required_vram_csv_columns")),
        required_vram_csv_columns()
    );
    assert_eq!(
        required_plan_field(&plan.top, "hardware_identity_schema"),
        "lanius.hardware-identity.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_hardware_identity_fields"
        )),
        required_hardware_identity_field_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "command_environment_schema"),
        "lanius.command-environment.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            &plan.top,
            "required_command_environment_fields",
        )),
        required_command_environment_field_names(),
        "top-level command environment fields",
    );
    assert_eq!(
        required_plan_field(&plan.top, "responsiveness_probe_schema"),
        "lanius.responsiveness-probe.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_responsiveness_probe_fields"
        )),
        required_responsiveness_probe_field_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "command_status_schema"),
        "lanius.command-status.v1"
    );
    assert_eq!(
        required_plan_field(&plan.top, "evidence_status_schema"),
        "lanius.measurement-evidence-status.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            &plan.top,
            "required_evidence_status_fields",
        )),
        required_evidence_status_field_names(),
        "top-level evidence status fields",
    );
    assert_eq!(
        required_plan_field(&plan.top, "evidence_freshness_schema"),
        "lanius.measurement-evidence-freshness.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_evidence_freshness_fields"
        )),
        required_evidence_freshness_field_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "claim_readiness_schema"),
        "lanius.measurement-claim-readiness.v1"
    );
    assert_eq!(
        required_plan_field(&plan.top, "claim_readiness_policy"),
        "complete-local-evidence-only"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            &plan.top,
            "claim_readiness_required_evidence_classes",
        )),
        claim_readiness_required_evidence_classes(),
        "top-level claim-readiness evidence classes",
    );
    assert_claim_readiness_status_requirements(required_plan_field(
        &plan.top,
        "claim_readiness_required_statuses",
    ));
    assert_eq!(
        csv_set(required_plan_field(
            &plan.top,
            "required_claim_readiness_fields"
        )),
        required_claim_readiness_field_names()
    );
    assert_eq!(
        csv_set(required_plan_field(&plan.top, "required_status_fields")),
        required_status_field_names()
    );
    assert_eq!(
        csv_set(required_plan_field(&plan.top, "optional_status_fields")),
        optional_status_field_names()
    );
    assert_eq!(
        required_plan_field(&plan.top, "measurement_summary_schema"),
        "lanius.measurement-summary.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(&plan.top, "required_summary_fields")),
        required_summary_field_names(),
        "top-level measurement summary fields",
    );
    assert_eq!(
        required_plan_field(&plan.top, "pareas_vram_output_path"),
        "target/lanius-measurements/pareas-5000l.vram.csv"
    );
    assert!(plan.command_labels.contains("lanius_build_command"));

    for lines in ["5000", "10000", "20000"] {
        assert_checkpoint_evidence_contract(&plan, lines);
    }

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_publishes_parallel_pass_evidence_classes() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000");
    });
    let plan = parse_measurement_plan(&output);
    let checkpoint = plan
        .checkpoints
        .get("5000")
        .unwrap_or_else(|| panic!("missing checkpoint 5000 in {plan:#?}"));

    assert_parallel_pass_contract_metadata(&plan.top);
    assert_parallel_pass_contract_metadata(&checkpoint.fields);
    assert_parallel_pass_contract_rows(&checkpoint.fields);

    assert_contains_fields(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "command_environment"),
            "fields",
        )),
        parallel_pass_artifact_field_names(),
        "command-environment pass-contract artifact fields",
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "fields",
        )),
        parallel_pass_artifact_field_names(),
        "measurement summary pass-contract artifact fields",
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "claim_fields",
        )),
        parallel_pass_artifact_field_names(),
        "measurement summary pass-contract claim fields",
    );

    assert!(
        !output.contains("paper_numbers_accepted: true")
            && !output.contains("local_performance_claim_status: claimable")
            && !output.contains("scaling_claim_status: claimable")
            && !output.contains("pass_contract_readiness_status: claimable"),
        "parallel pass scaffold must not promote no-run metadata into claimable evidence\n{output}"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_summary_preserves_link_artifact_claim_boundary() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let measurement_summary_path = artifacts.join("summary.tsv");
    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    let link_artifact_blocker = link_artifact_claim_blocker();
    let link_artifact_short_blocker = link_artifact_claim_short_blocker();

    assert_eq!(
        required_plan_field(&summary_fields, "link_artifact_evidence_policy"),
        link_artifact_evidence_policy()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "link_artifact_evidence_schema"),
        link_artifact_evidence_schema()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "link_artifact_required_evidence_classes"),
        link_artifact_required_evidence_classes()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "link_artifact_evidence_status"),
        link_artifact_evidence_status()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "link_artifact_claim_blockers"),
        link_artifact_claim_blockers()
    );
    assert!(
        required_plan_field(&summary_fields, "local_performance_claim_blockers")
            .contains(&link_artifact_short_blocker),
        "local performance claims should stay blocked without link artifact evidence\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains(&link_artifact_blocker),
        "production readiness should require object/interface/partial-link/link-output artifacts\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_readiness_blockers")
            .contains(&link_artifact_short_blocker),
        "claim readiness should carry the link-artifact evidence blocker\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_readiness_required_statuses")
            .contains("link_artifact_evidence_status=artifact-backed"),
        "claim readiness should require artifact-backed link evidence\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_blocks_claims_without_valid_source_control_revision() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let command_env_path = artifacts.join("command-env.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_COMMAND_ENV_OUTPUT_PATH", &command_env_path)
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    fs::write(
        &command_env_path,
        "\
command_environment_schema=lanius.command-environment.v1
git_head=paper-number
git_status_short_begin
git_status_short_end
",
    )
    .expect("write command-environment artifact without a commit-shaped git revision");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);

    assert_eq!(
        required_plan_field(&summary_fields, "source_control_policy"),
        "git-head-plus-status-in-command-environment-hash"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "source_control_state"),
        "unavailable"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "source_control_revision"),
        "unavailable"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("source_control:unavailable"),
        "invalid git revision should block measurement claims\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_readiness_blockers")
            .contains("source_control:unavailable"),
        "claim-readiness blockers should carry source-control provenance failures\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_readiness_required_statuses")
            .contains("source_control_state=clean-or-dirty"),
        "claim-readiness requirements should demand a known source-control state\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_readiness_required_statuses")
            .contains("source_control_revision=local-git-commit-sha"),
        "claim-readiness requirements should demand a locally resolvable git commit revision\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_scope_key")
            .contains("source_control_state:unavailable"),
        "claim scope should expose the unusable source-control state\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_scope_key")
            .contains("source_control_revision:unavailable"),
        "claim scope should expose the unusable source-control revision\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_nonlocal_source_control_revision() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let command_env_path = artifacts.join("command-env.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");
    let nonlocal_commit = "0123456789abcdef0123456789abcdef01234567";

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_COMMAND_ENV_OUTPUT_PATH", &command_env_path)
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    fs::write(
        &command_env_path,
        format!(
            "\
command_environment_schema=lanius.command-environment.v1
cwd={}
git_head={nonlocal_commit}
git_status_short_begin
git_status_short_end
",
            env!("CARGO_MANIFEST_DIR")
        ),
    )
    .expect("write command-environment artifact with a nonlocal commit-shaped revision");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    let stale_artifacts = csv_set(required_plan_field(&summary_fields, "stale_artifacts"));

    assert_eq!(
        required_plan_field(&summary_fields, "source_control_state"),
        "unavailable"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "source_control_revision"),
        "unavailable"
    );
    assert!(
        stale_artifacts.contains("command_environment:git_head:not-local"),
        "a commit-shaped revision that is not present in the local repo must be stale\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifact_checks")
            .contains("source_control_revision_is_local_git_commit"),
        "freshness checks should include local git commit resolution\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_readiness_blockers")
            .contains("source_control:unavailable"),
        "nonlocal source-control revisions should block measurement claims\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_plan_publishes_claim_provenance_boundaries() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command.env("HOME", &temp_home).env("PATH", &temp_path);
    });
    let plan = parse_measurement_plan(&output);

    assert_claim_provenance_contract(&plan.top);
    for lines in ["5000", "10000", "20000"] {
        let checkpoint = plan
            .checkpoints
            .get(lines)
            .unwrap_or_else(|| panic!("missing checkpoint {lines}"));
        assert_claim_provenance_contract(&checkpoint.fields);
    }

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_scopes_generated_workload_claims_to_source_shape() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command.env("HOME", &temp_home).env("PATH", &temp_path);
    });
    let plan = parse_measurement_plan(&output);

    assert_eq!(
        required_plan_field(&plan.top, "workload_shape_policy"),
        workload_shape_policy()
    );
    assert_eq!(
        required_plan_field(&plan.top, "workload_shape_scope"),
        workload_shape_scope()
    );
    assert_eq!(
        required_plan_field(&plan.top, "workload_generalization_status"),
        workload_generalization_status()
    );
    assert_eq!(
        required_plan_field(&plan.top, "workload_generalization_blockers"),
        workload_generalization_blockers()
    );
    for lines in ["5000", "10000", "20000"] {
        let checkpoint = plan
            .checkpoints
            .get(lines)
            .unwrap_or_else(|| panic!("missing checkpoint {lines}"));
        assert_claim_provenance_contract(&checkpoint.fields);
        assert_eq!(
            required_plan_field(&checkpoint.fields, "source"),
            "call-graph",
            "generated workload claims should remain tied to the source shape"
        );
        assert!(
            csv_set(required_plan_field(
                required_artifact(checkpoint, "command_environment"),
                "claim_fields"
            ))
            .is_superset(&string_set([
                "workload_shape_policy",
                "workload_shape_scope",
                "workload_generalization_status",
                "workload_generalization_blockers",
            ])),
            "command-environment provenance should preserve workload scope"
        );
        assert!(
            csv_set(required_plan_field(
                required_artifact(checkpoint, "measurement_summary"),
                "claim_fields"
            ))
            .is_superset(&string_set([
                "workload_shape_policy",
                "workload_shape_scope",
                "workload_generalization_status",
                "workload_generalization_blockers",
            ])),
            "measurement summaries should preserve workload scope"
        );
    }

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_separates_timeout_provenance_from_latency_claims() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command.env("HOME", &temp_home).env("PATH", &temp_path);
    });
    let plan = parse_measurement_plan(&output);

    assert_measurement_timing_contract(&plan.top);
    for lines in ["5000", "10000", "20000"] {
        let checkpoint = plan
            .checkpoints
            .get(lines)
            .unwrap_or_else(|| panic!("missing checkpoint {lines}"));
        assert_measurement_timing_contract(&checkpoint.fields);

        assert_eq!(
            csv_set(required_plan_field(
                required_artifact(checkpoint, "lanius_stdout"),
                "claim_fields"
            )),
            string_set(["best_ms", "throughput_lines_per_second"]),
            "stdout claim fields should be inner benchmark output, not wrapper wall time"
        );
        assert!(
            csv_set(required_plan_field(
                required_artifact(checkpoint, "command_status"),
                "claim_fields"
            ))
            .is_superset(&required_timeout_provenance_field_names()),
            "command status should carry timeout provenance fields"
        );
        assert!(
            required_status_field_names().is_superset(&required_timeout_provenance_field_names()),
            "status schema should require timeout provenance fields"
        );
        assert!(
            required_summary_field_names().is_superset(&required_timeout_provenance_field_names()),
            "summary schema should preserve timeout provenance fields"
        );
    }

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_stale_resource_usage_artifact() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let lanius_stdout_path = artifacts.join("lanius.stdout.txt");
    let trace_path = artifacts.join("trace.perfetto.json");
    let readback_summary_path = artifacts.join("readback.txt");
    let vram_path = artifacts.join("vram.csv");
    let source_replay_path = artifacts.join("source.lani");
    let source_sha256_path = artifacts.join("source.sha256.txt");
    let bench_sha256_path = artifacts.join("bench.sha256.txt");
    let hardware_path = artifacts.join("hardware.txt");
    let command_env_path = artifacts.join("command-env.txt");
    let command_status_path = artifacts.join("status.txt");
    let responsiveness_path = artifacts.join("responsiveness.txt");
    let resource_usage_path = artifacts.join("resource-usage.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_PERF_OUTPUT_PATH", &lanius_stdout_path)
            .env("LANIUS_PERFETTO_TRACE", &trace_path)
            .env(
                "LANIUS_READBACK_SUMMARY_OUTPUT_PATH",
                &readback_summary_path,
            )
            .env("LANIUS_VRAM_OUTPUT_PATH", &vram_path)
            .env("LANIUS_SOURCE_REPLAY_OUTPUT_PATH", &source_replay_path)
            .env("LANIUS_SOURCE_SHA256_OUTPUT_PATH", &source_sha256_path)
            .env("LANIUS_BENCH_SHA256_OUTPUT_PATH", &bench_sha256_path)
            .env("LANIUS_HARDWARE_OUTPUT_PATH", &hardware_path)
            .env("LANIUS_COMMAND_ENV_OUTPUT_PATH", &command_env_path)
            .env("LANIUS_COMMAND_STATUS_OUTPUT_PATH", &command_status_path)
            .env("LANIUS_RESPONSIVENESS_OUTPUT_PATH", &responsiveness_path)
            .env("LANIUS_RESOURCE_USAGE_OUTPUT_PATH", &resource_usage_path)
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);
    let checkpoint = plan
        .checkpoints
        .get("5000")
        .unwrap_or_else(|| panic!("missing checkpoint 5000 in {plan:#?}"));
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "resource_usage"),
            "stale_check"
        ),
        "resource_usage_command_matches_checkpoint"
    );

    fs::write(
        &command_status_path,
        format!(
            "\
command_status_schema=lanius.command-status.v1
lanius_exit_status=0
lanius_wall_elapsed_ms=100
measurement_timing_policy={}
cold_start_policy={}
compile_latency_claim_source={}
runtime_validation_policy={}
timeout_provenance_schema=lanius.timeout-provenance.v1
timeout_scope={}
timeout_ms=120000
timeout_seconds=120
timeout_source={}
timeout_enforced_by={}
timeout_exit_code=124
timeout_exit_code_means_timed_out=true
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
source_seed=3235798765
iterations=1
readback_timeout_ms=60000
vram_sample_interval_ms=250
machine_responsive_after=true
responsiveness_probe_status=0
responsiveness_probe_path={}
lanius_stdout_path={}
perfetto_trace_path={}
resource_usage_status=0
resource_usage_path={}
",
            measurement_timing_policy(),
            cold_start_policy(),
            compile_latency_claim_source(),
            runtime_validation_policy(),
            timeout_scope(),
            timeout_source(),
            timeout_enforced_by(),
            responsiveness_path.display(),
            lanius_stdout_path.display(),
            trace_path.display(),
            resource_usage_path.display()
        ),
    )
    .expect("write command-status artifact");
    fs::write(
        &resource_usage_path,
        "\
\tCommand being timed: \"timeout 120s env LANIUS_GPU_TIMING=1 target/release/gpu_compile_bench --phase x86 --emit x86_64-elf --source call-graph --lines 10000 --seed 3235798765 --warmups 0 --iters 1 --allow-large --validate-output\"
\tUser time (seconds): 1.00
\tSystem time (seconds): 0.25
\tMaximum resident set size (kbytes): 4096
",
    )
    .expect("write stale resource-usage artifact");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    assert_eq!(
        required_plan_field(&summary_fields, "evidence_freshness_status"),
        "stale"
    );
    assert!(
        csv_set(required_plan_field(&summary_fields, "stale_artifacts"))
            .contains("resource_usage:command"),
        "stale resource usage command identity should block freshness\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifact_checks")
            .contains("quantitative_artifact_fields_are_numeric"),
        "freshness checks should include numeric metric validation\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("freshness:stale"),
        "production-readiness blockers should carry stale resource provenance\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_nonnumeric_metric_artifacts() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let lanius_stdout_path = artifacts.join("lanius.stdout.txt");
    let trace_path = artifacts.join("trace.perfetto.json");
    let readback_summary_path = artifacts.join("readback.txt");
    let vram_path = artifacts.join("vram.csv");
    let source_replay_path = artifacts.join("source.lani");
    let source_sha256_path = artifacts.join("source.sha256.txt");
    let bench_sha256_path = artifacts.join("bench.sha256.txt");
    let hardware_path = artifacts.join("hardware.txt");
    let command_env_path = artifacts.join("command-env.txt");
    let command_status_path = artifacts.join("status.txt");
    let responsiveness_path = artifacts.join("responsiveness.txt");
    let resource_usage_path = artifacts.join("resource-usage.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_PERF_OUTPUT_PATH", &lanius_stdout_path)
            .env("LANIUS_PERFETTO_TRACE", &trace_path)
            .env(
                "LANIUS_READBACK_SUMMARY_OUTPUT_PATH",
                &readback_summary_path,
            )
            .env("LANIUS_VRAM_OUTPUT_PATH", &vram_path)
            .env("LANIUS_SOURCE_REPLAY_OUTPUT_PATH", &source_replay_path)
            .env("LANIUS_SOURCE_SHA256_OUTPUT_PATH", &source_sha256_path)
            .env("LANIUS_BENCH_SHA256_OUTPUT_PATH", &bench_sha256_path)
            .env("LANIUS_HARDWARE_OUTPUT_PATH", &hardware_path)
            .env("LANIUS_COMMAND_ENV_OUTPUT_PATH", &command_env_path)
            .env("LANIUS_COMMAND_STATUS_OUTPUT_PATH", &command_status_path)
            .env("LANIUS_RESPONSIVENESS_OUTPUT_PATH", &responsiveness_path)
            .env("LANIUS_RESOURCE_USAGE_OUTPUT_PATH", &resource_usage_path)
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    fs::write(&lanius_stdout_path, "best_ms=paper\n").expect("write stdout artifact");
    fs::write(&trace_path, "{}\n").expect("write trace artifact");
    fs::write(&source_replay_path, "fn main() -> i32 { 0 }\n").expect("write source artifact");
    write_sha256_artifact(&source_replay_path, &source_sha256_path);
    fs::write(
        &readback_summary_path,
        format!(
            "\
readback_summary_schema=lanius.readback-summary.v1
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
trace_path={}
readback_timeout_ms=60000
span_count=paper
total_ms=paper
max_span_ms=paper
",
            trace_path.display()
        ),
    )
    .expect("write readback summary artifact");
    fs::write(
        &vram_path,
        "\
timestamp,index,name,memory.used,memory.total,utilization.gpu
2026/05/29 00:00:00.000,0,local GPU,12 MiB,100 MiB,0 %
",
    )
    .expect("write vram artifact");
    fs::write(
        &hardware_path,
        "\
hardware_identity_schema=lanius.hardware-identity.v1
target=x86_64-elf
uname=test
nvidia_smi_status=available
",
    )
    .expect("write hardware artifact");
    fs::write(
        &command_env_path,
        format!(
            "\
command_environment_schema=lanius.command-environment.v1
timestamp_utc=2026-05-29T00:00:00Z
cwd={}
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
iterations=1
measurement_timing_policy={}
cold_start_policy={}
compile_latency_claim_source={}
runtime_validation_policy={}
timeout_provenance_schema=lanius.timeout-provenance.v1
timeout_scope={}
timeout_source={}
timeout_ms=120000
timeout_seconds=120
readback_timeout_ms=60000
vram_sample_interval_ms=250
source_seed=3235798765
responsiveness_probe_timeout_ms=2000
responsiveness_probe_timeout_seconds=2
git_head=test
rustc_version=test
cargo_version=test
slangc_version=test
git_status_short_begin
git_status_short_end
",
            env!("CARGO_MANIFEST_DIR"),
            measurement_timing_policy(),
            cold_start_policy(),
            compile_latency_claim_source(),
            runtime_validation_policy(),
            timeout_scope(),
            timeout_source(),
        ),
    )
    .expect("write command environment artifact");
    fs::write(
        &responsiveness_path,
        "\
responsiveness_probe_schema=lanius.responsiveness-probe.v1
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
timeout_ms=2000
timeout_seconds=2
probe_command=timeout_sh_noop
probe_exit_status=0
responsive=true
elapsed_ms=1
",
    )
    .expect("write responsiveness artifact");
    fs::write(
        &command_status_path,
        format!(
            "\
command_status_schema=lanius.command-status.v1
lanius_exit_status=0
lanius_wall_elapsed_ms=paper
measurement_timing_policy={}
cold_start_policy={}
compile_latency_claim_source={}
runtime_validation_policy={}
timeout_provenance_schema=lanius.timeout-provenance.v1
timeout_scope={}
timeout_ms=120000
timeout_seconds=120
timeout_source={}
timeout_enforced_by={}
timeout_exit_code=124
timeout_exit_code_means_timed_out=true
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
source_seed=3235798765
iterations=1
readback_timeout_ms=60000
vram_sample_interval_ms=250
machine_responsive_after=true
responsiveness_probe_status=0
responsiveness_probe_path={}
lanius_stdout_path={}
perfetto_trace_path={}
resource_usage_status=0
resource_usage_path={}
nvidia_smi_exit_status=0
vram_output_path={}
",
            measurement_timing_policy(),
            cold_start_policy(),
            compile_latency_claim_source(),
            runtime_validation_policy(),
            timeout_scope(),
            timeout_source(),
            timeout_enforced_by(),
            responsiveness_path.display(),
            lanius_stdout_path.display(),
            trace_path.display(),
            resource_usage_path.display(),
            vram_path.display(),
        ),
    )
    .expect("write command-status artifact");
    fs::write(
        &resource_usage_path,
        "\
\tCommand being timed: \"timeout 120s env LANIUS_GPU_TIMING=1 target/release/gpu_compile_bench --phase x86 --emit x86_64-elf --source call-graph --lines 5000 --seed 3235798765 --warmups 0 --iters 1 --allow-large --validate-output\"
\tUser time (seconds): paper
\tSystem time (seconds): 0.25
\tMaximum resident set size (kbytes): 4096
",
    )
    .expect("write resource-usage artifact");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    let stale_artifacts = csv_set(required_plan_field(&summary_fields, "stale_artifacts"));

    assert_eq!(
        required_plan_field(&summary_fields, "claim_provenance_schema"),
        claim_provenance_schema()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "paper_baseline_policy"),
        paper_baseline_policy()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "paper_baseline_claim_status"),
        paper_baseline_claim_status()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "local_performance_claim_source"),
        local_performance_claim_source()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "local_vram_claim_source"),
        local_vram_claim_source()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "local_pareas_claim_source"),
        local_pareas_claim_source()
    );
    assert_eq!(
        required_plan_field(&summary_fields, "evidence_freshness_status"),
        "stale"
    );
    assert!(
        stale_artifacts.contains("command_status:lanius_wall_elapsed_ms:nonnumeric"),
        "wall elapsed provenance must be numeric\n{summary}"
    );
    assert!(
        stale_artifacts.contains("lanius_stdout:best_ms:nonnumeric"),
        "benchmark stdout best_ms must be numeric\n{summary}"
    );
    assert!(
        stale_artifacts.contains("readback_summary:span_count:nonnumeric"),
        "readback span counts must be numeric\n{summary}"
    );
    assert!(
        stale_artifacts.contains("readback_summary:total_ms:nonnumeric"),
        "readback timing must be numeric\n{summary}"
    );
    assert!(
        stale_artifacts.contains("readback_summary:max_span_ms:nonnumeric"),
        "maximum readback span timing must be numeric\n{summary}"
    );
    assert!(
        stale_artifacts.contains("resource_usage:resource_user_seconds:nonnumeric"),
        "resource usage CPU seconds must be numeric\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_zero_readback_span_artifact() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let trace_path = artifacts.join("trace.perfetto.json");
    let readback_summary_path = artifacts.join("readback.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_PERFETTO_TRACE", &trace_path)
            .env(
                "LANIUS_READBACK_SUMMARY_OUTPUT_PATH",
                &readback_summary_path,
            )
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    fs::write(
        &readback_summary_path,
        format!(
            "\
readback_summary_schema=lanius.readback-summary.v1
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
trace_path={}
readback_timeout_ms=60000
steady_readback_claim_source={}
span_count=0
total_ms=0
max_span_ms=0
",
            trace_path.display(),
            steady_readback_claim_source()
        ),
    )
    .expect("write zero-span readback summary artifact");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    let stale_artifacts = csv_set(required_plan_field(&summary_fields, "stale_artifacts"));

    assert_eq!(
        required_plan_field(&summary_fields, "readback_span_count"),
        "0"
    );
    assert!(
        stale_artifacts.contains("readback_summary:span-metrics"),
        "zero readback spans should not satisfy readback timing evidence\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "local_readback_evidence_status"),
        "incomplete",
        "readback evidence should require a positive span count and positive timing\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifact_checks")
            .contains("readback_summary_span_metrics_are_consistent"),
        "freshness checks should include readback span consistency\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("readback:incomplete"),
        "zero-span readback evidence should block production readiness\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("freshness:stale"),
        "zero-span readback evidence should make freshness stale\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_readback_summary_without_trace_spans() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let trace_path = artifacts.join("trace.perfetto.json");
    let readback_summary_path = artifacts.join("readback.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_PERFETTO_TRACE", &trace_path)
            .env(
                "LANIUS_READBACK_SUMMARY_OUTPUT_PATH",
                &readback_summary_path,
            )
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    fs::write(&trace_path, "{ \"traceEvents\": [] }\n").expect("write empty trace artifact");
    fs::write(
        &readback_summary_path,
        format!(
            "\
readback_summary_schema=lanius.readback-summary.v1
line_count=5000
source=call-graph
phase=x86
target=x86_64-elf
trace_path={}
readback_timeout_ms=60000
steady_readback_claim_source={}
span_count=3
total_ms=12.5
max_span_ms=8.0
",
            trace_path.display(),
            steady_readback_claim_source()
        ),
    )
    .expect("write forged readback summary artifact");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    let stale_artifacts = csv_set(required_plan_field(&summary_fields, "stale_artifacts"));

    assert_eq!(
        required_plan_field(&summary_fields, "readback_span_count"),
        "3"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "local_readback_evidence_status"),
        "incomplete",
        "positive readback summary metrics should still require backing trace spans\n{summary}"
    );
    assert!(
        stale_artifacts.contains("readback_summary:trace-spans"),
        "readback summary spans must be backed by recorded trace spans\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifact_checks")
            .contains("readback_summary_trace_contains_recorded_spans"),
        "freshness checks should include trace-span validation\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("readback:incomplete"),
        "unbacked readback metrics should block production readiness\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("freshness:stale"),
        "unbacked readback metrics should stale the artifact set\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_short_source_replay_artifact() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let lanius_stdout_path = artifacts.join("lanius.stdout.txt");
    let trace_path = artifacts.join("trace.perfetto.json");
    let readback_summary_path = artifacts.join("readback.txt");
    let vram_path = artifacts.join("vram.csv");
    let source_replay_path = artifacts.join("source.lani");
    let source_sha256_path = artifacts.join("source.sha256.txt");
    let bench_sha256_path = artifacts.join("bench.sha256.txt");
    let hardware_path = artifacts.join("hardware.txt");
    let command_env_path = artifacts.join("command-env.txt");
    let command_status_path = artifacts.join("status.txt");
    let responsiveness_path = artifacts.join("responsiveness.txt");
    let resource_usage_path = artifacts.join("resource-usage.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_PERF_OUTPUT_PATH", &lanius_stdout_path)
            .env("LANIUS_PERFETTO_TRACE", &trace_path)
            .env(
                "LANIUS_READBACK_SUMMARY_OUTPUT_PATH",
                &readback_summary_path,
            )
            .env("LANIUS_VRAM_OUTPUT_PATH", &vram_path)
            .env("LANIUS_SOURCE_REPLAY_OUTPUT_PATH", &source_replay_path)
            .env("LANIUS_SOURCE_SHA256_OUTPUT_PATH", &source_sha256_path)
            .env("LANIUS_BENCH_SHA256_OUTPUT_PATH", &bench_sha256_path)
            .env("LANIUS_HARDWARE_OUTPUT_PATH", &hardware_path)
            .env("LANIUS_COMMAND_ENV_OUTPUT_PATH", &command_env_path)
            .env("LANIUS_COMMAND_STATUS_OUTPUT_PATH", &command_status_path)
            .env("LANIUS_RESPONSIVENESS_OUTPUT_PATH", &responsiveness_path)
            .env("LANIUS_RESOURCE_USAGE_OUTPUT_PATH", &resource_usage_path)
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            );
    });
    let plan = parse_measurement_plan(&output);

    fs::write(&source_replay_path, "fn main() {\n    return 0;\n").expect("write short source");
    write_sha256_artifact(&source_replay_path, &source_sha256_path);

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);
    let stale_artifacts = csv_set(required_plan_field(&summary_fields, "stale_artifacts"));

    assert_eq!(
        required_plan_field(&summary_fields, "source_replay_line_count"),
        "2"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "evidence_freshness_status"),
        "stale"
    );
    assert!(
        stale_artifacts.contains("source_replay:line_count"),
        "source replay smaller than the checkpoint should block freshness\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifact_checks")
            .contains("source_replay_line_count_covers_checkpoint"),
        "freshness checks should include replayed source size validation\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_scope_key")
            .contains("source_replay_line_count:2"),
        "claim scope should include the replayed source size\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_summary_rejects_pareas_ratio_without_binary_identity() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    let artifacts = unique_temp_dir("acceptance_measurement_artifacts");
    install_cat_on_path(&temp_path);

    let command_status_path = artifacts.join("status.txt");
    let measurement_summary_path = artifacts.join("summary.tsv");
    let pareas_source_path = artifacts.join("pareas.par");
    let pareas_source_sha256_path = artifacts.join("pareas.source.sha256.txt");
    let pareas_binary_sha256_path = artifacts.join("pareas.compiler.sha256.txt");
    let pareas_output_path = artifacts.join("pareas.out");
    let pareas_stdout_path = artifacts.join("pareas.stdout.txt");

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000")
            .env("LANIUS_COMMAND_STATUS_OUTPUT_PATH", &command_status_path)
            .env(
                "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
                &measurement_summary_path,
            )
            .env("LANIUS_PAREAS_SOURCE_PATH", &pareas_source_path)
            .env(
                "LANIUS_PAREAS_SOURCE_SHA256_OUTPUT_PATH",
                &pareas_source_sha256_path,
            )
            .env(
                "LANIUS_PAREAS_BINARY_SHA256_OUTPUT_PATH",
                &pareas_binary_sha256_path,
            )
            .env("LANIUS_PAREAS_OUTPUT_PATH", &pareas_output_path)
            .env("LANIUS_PAREAS_STDOUT_PATH", &pareas_stdout_path);
    });
    let plan = parse_measurement_plan(&output);

    fs::write(&pareas_source_path, "fn main[]: int {\n  return 0;\n}\n")
        .expect("write Pareas source");
    write_sha256_artifact(&pareas_source_path, &pareas_source_sha256_path);
    fs::write(&pareas_output_path, b"pareas-output").expect("write Pareas output");
    fs::write(&pareas_stdout_path, b"pareas stdout").expect("write Pareas stdout");
    fs::write(
        &command_status_path,
        format!(
            "\
command_status_schema=lanius.command-status.v1
pareas_exit_status=0
pareas_wall_elapsed_ms=100
timeout_seconds=120
line_count=5000
pareas_bin_path=/tmp/pareas-for-test
pareas_source_path={}
pareas_output_path={}
pareas_stdout_path={}
",
            pareas_source_path.display(),
            pareas_output_path.display(),
            pareas_stdout_path.display()
        ),
    )
    .expect("write command status");

    let summary_command = required_artifact_command(&plan, "5000", "measurement_summary");
    run_bash_command_line_success(summary_command);
    let summary = fs::read_to_string(&measurement_summary_path).expect("read summary artifact");
    let summary_fields = parse_key_value_lines(&summary);

    assert_eq!(
        required_plan_field(&summary_fields, "pareas_binary_sha256"),
        "not-run"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "pareas_source_line_count"),
        "3"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifacts")
            .contains("pareas_source:line_count"),
        "Pareas comparison should be stale when its generated source is smaller than the checkpoint\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "stale_artifact_checks")
            .contains("pareas_source_line_count_covers_checkpoint"),
        "freshness checks should include Pareas source size validation\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "local_pareas_evidence_status"),
        "failed",
        "Pareas comparison should not become complete without a local compiler identity hash\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "production_readiness_blockers")
            .contains("pareas:failed"),
        "missing Pareas compiler identity should block readiness\n{summary}"
    );
    assert!(
        required_plan_field(&summary_fields, "claim_scope_key")
            .contains("pareas_binary_sha256:not-run"),
        "claim scope should expose missing Pareas compiler identity\n{summary}"
    );
    assert_eq!(
        required_plan_field(&summary_fields, "claim_readiness_status"),
        "not-claimable"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
    let _ = fs::remove_dir_all(&artifacts);
}

#[test]
fn compiler_acceptance_measurement_plan_writes_requested_artifact_without_stdout_plan() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);
    install_system_command_on_path(&temp_path, "dirname");
    install_system_command_on_path(&temp_path, "mkdir");
    let output_path = temp_home.join("plans").join("measurement-plan.txt");
    let output_path_arg = output_path.to_string_lossy().into_owned();

    let output = run_acceptance_script(
        &["--write-measurement-plan", output_path_arg.as_str()],
        |command| {
            command.env("HOME", &temp_home).env("PATH", &temp_path);
        },
    );

    assert!(
        output.contains(&format!(
            "# wrote no-run measurement plan to {}",
            output_path.display()
        )),
        "write mode should report the persisted measurement plan path\n{output}"
    );
    assert!(
        !output.contains("measurement_plan_schema:"),
        "write mode should keep the full plan in the requested artifact, not stdout\n{output}"
    );

    let plan_text = fs::read_to_string(&output_path).expect("read persisted measurement plan");
    assert!(
        !plan_text.contains("wrote no-run measurement plan"),
        "persisted plan should contain the plan only, not the write-mode status line\n{plan_text}"
    );
    let plan = parse_measurement_plan(&plan_text);
    assert_eq!(
        required_plan_field(&plan.top, "measurement_plan_schema"),
        "lanius.measurement-plan.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(&plan.top, "checkpoints")),
        string_set(["5000", "10000", "20000"])
    );
    assert_eq!(
        csv_vec(required_plan_field(&plan.top, "checkpoint_execution_order")),
        vec!["5000", "10000", "20000"]
    );
    assert_checkpoint_evidence_contract(&plan, "5000");

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_canonicalizes_checkpoint_line_counts() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_ALLOW_LARGE_GENERATED_TESTS", "1")
            .env("LANIUS_PERF_CHECKPOINT_LINES", "05000,10000,20000");
    });

    let plan = parse_measurement_plan(&output);
    assert_eq!(
        csv_set(required_plan_field(&plan.top, "checkpoints")),
        string_set(["5000", "10000", "20000"])
    );
    assert_eq!(
        csv_vec(required_plan_field(&plan.top, "checkpoint_execution_order")),
        vec!["5000", "10000", "20000"]
    );
    assert!(plan.checkpoints.contains_key("5000"));
    let source_replay = required_artifact(
        plan.checkpoints
            .get("5000")
            .expect("canonical 5000 checkpoint"),
        "source_replay",
    );
    assert_eq!(
        required_plan_field(source_replay, "path"),
        "target/lanius-measurements/call-graph-x86-5000l-1i-s3235798765.source.lani"
    );
    assert!(
        !plan.checkpoints.contains_key("05000"),
        "measurement plan should not preserve leading-zero checkpoint labels\n{output}"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_uses_requested_small_checkpoint_runbook() {
    let temp_home = unique_temp_dir("acceptance_measurement_home");
    let temp_path = unique_temp_dir("acceptance_measurement_path");
    install_cat_on_path(&temp_path);

    let output = run_acceptance_script(&["--measurement-plan"], |command| {
        command
            .env("HOME", &temp_home)
            .env("PATH", &temp_path)
            .env("LANIUS_ALLOW_LARGE_GENERATED_TESTS", "1")
            .env("LANIUS_PERF_CHECKPOINT_LINES", "5000,10000");
    });

    let plan = parse_measurement_plan(&output);
    assert_eq!(
        csv_vec(required_plan_field(&plan.top, "checkpoint_execution_order")),
        vec!["5000", "10000"]
    );
    assert_eq!(
        required_plan_field(&plan.top, "checkpoint_run_policy"),
        "run-checkpoint_execution_order-stop-on-first-readback-timeout-vram-growth-or-responsiveness-failure"
    );
    assert!(plan.checkpoints.contains_key("5000"));
    assert!(plan.checkpoints.contains_key("10000"));
    assert!(
        !plan.checkpoints.contains_key("20000"),
        "custom 5k/10k measurement plans should not emit an unrequested 20k checkpoint\n{output}"
    );
    assert!(
        output.contains("Run checkpoints in checkpoint_execution_order."),
        "runbook should refer to the actual planned order, not a hard-coded default\n{output}"
    );
    assert!(
        !output.contains("5k first, then 10k, then 20k"),
        "runbook should not preserve stale default checkpoint text for a 5k/10k plan\n{output}"
    );

    let _ = fs::remove_dir_all(&temp_home);
    let _ = fs::remove_dir_all(&temp_path);
}

#[test]
fn compiler_acceptance_measurement_plan_rejects_non_ascending_checkpoints() {
    let failure = run_acceptance_script_failure(&["--measurement-plan"], |command| {
        command
            .env("LANIUS_ALLOW_LARGE_GENERATED_TESTS", "1")
            .env("LANIUS_PERF_CHECKPOINT_LINES", "10000,5000,20000");
    });

    assert!(
        failure.stdout.is_empty(),
        "failed measurement plan should not emit a partial plan\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure
            .stderr
            .contains("LANIUS_PERF_CHECKPOINT_LINES must be strictly ascending"),
        "measurement plan should explain the checkpoint-order contract\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure.stderr.contains("# measurement-plan failed:"),
        "measurement plan should report a no-run validation failure\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[test]
fn compiler_acceptance_measurement_plan_rejects_primary_line_outside_checkpoint_set() {
    let failure = run_acceptance_script_failure(&["--measurement-plan"], |command| {
        command
            .env("LANIUS_ALLOW_LARGE_GENERATED_TESTS", "1")
            .env("LANIUS_PERF_LINES", "5000")
            .env("LANIUS_PERF_CHECKPOINT_LINES", "10000,20000");
    });

    assert!(
        failure.stdout.is_empty(),
        "failed measurement plan should not emit a partial plan\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure.stderr.contains(
            "LANIUS_PERF_LINES=5000 is not included in LANIUS_PERF_CHECKPOINT_LINES=10000,20000"
        ),
        "measurement plan should explain that the primary artifact line must be a planned checkpoint\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure.stderr.contains("# measurement-plan failed:"),
        "measurement plan should report a no-run validation failure\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[test]
fn compiler_acceptance_measurement_plan_rejects_large_workloads_without_opt_in() {
    let large_checkpoint_failure =
        run_acceptance_script_failure(&["--measurement-plan"], |command| {
            command.env("LANIUS_PERF_CHECKPOINT_LINES", "5000,10000");
        });

    assert!(
        large_checkpoint_failure.stdout.is_empty(),
        "oversized checkpoint rejection should happen before printing a plan\nstdout:\n{}\nstderr:\n{}",
        large_checkpoint_failure.stdout,
        large_checkpoint_failure.stderr
    );
    assert!(
        large_checkpoint_failure
            .stderr
            .contains("checkpoint 10000 exceeds the default guardrail 5000"),
        "measurement plan should explain the explicit opt-in required for generated checkpoints above 5k\nstdout:\n{}\nstderr:\n{}",
        large_checkpoint_failure.stdout,
        large_checkpoint_failure.stderr
    );
    assert!(
        large_checkpoint_failure
            .stderr
            .contains("LANIUS_ALLOW_LARGE_GENERATED_TESTS=1"),
        "measurement plan should name the large-workload opt-in\nstdout:\n{}\nstderr:\n{}",
        large_checkpoint_failure.stdout,
        large_checkpoint_failure.stderr
    );

    let large_iteration_failure =
        run_acceptance_script_failure(&["--measurement-plan"], |command| {
            command.env("LANIUS_PERF_ITERS", "4");
        });

    assert!(
        large_iteration_failure.stdout.is_empty(),
        "oversized iteration rejection should happen before printing a plan\nstdout:\n{}\nstderr:\n{}",
        large_iteration_failure.stdout,
        large_iteration_failure.stderr
    );
    assert!(
        large_iteration_failure
            .stderr
            .contains("LANIUS_PERF_ITERS=4 exceeds the default guardrail 3"),
        "measurement plan should reject broad repeated performance runs without opt-in\nstdout:\n{}\nstderr:\n{}",
        large_iteration_failure.stdout,
        large_iteration_failure.stderr
    );
    assert!(
        large_iteration_failure
            .stderr
            .contains("LANIUS_ALLOW_LARGE_GENERATED_TESTS=1"),
        "measurement plan should name the large-iteration opt-in\nstdout:\n{}\nstderr:\n{}",
        large_iteration_failure.stdout,
        large_iteration_failure.stderr
    );
}

#[test]
fn compiler_acceptance_measurement_plan_rejects_check_env_mix() {
    let failure = run_acceptance_script_failure(&["--measurement-plan", "--check-env"], |_| {});

    assert!(
        failure.stdout.is_empty(),
        "measurement-plan/check-env rejection should happen before printing a plan\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure
            .stderr
            .contains("--measurement-plan is separate from --check-env"),
        "measurement-plan/check-env rejection should explain the mode conflict\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[derive(Debug, Default)]
struct MeasurementPlan {
    top: BTreeMap<String, String>,
    checkpoints: BTreeMap<String, MeasurementCheckpoint>,
    command_labels: BTreeSet<String>,
    commands: BTreeMap<String, String>,
}

#[derive(Debug, Default)]
struct MeasurementCheckpoint {
    fields: BTreeMap<String, String>,
    artifacts: BTreeMap<String, BTreeMap<String, String>>,
}

fn parse_measurement_plan(output: &str) -> MeasurementPlan {
    let mut plan = MeasurementPlan::default();
    let mut current_checkpoint = None::<String>;

    for line in output.lines() {
        if let Some(label) = output_label(line) {
            plan.command_labels.insert(label.to_string());
        }
        if let Some((label, command)) = line.split_once(" = ") {
            if output_label(line).is_some() {
                plan.commands.insert(label.to_string(), command.to_string());
            }
        }

        if let Some(checkpoint) = line
            .strip_prefix("checkpoint_")
            .and_then(|rest| rest.strip_suffix("l:"))
        {
            current_checkpoint = Some(checkpoint.to_string());
            plan.checkpoints.entry(checkpoint.to_string()).or_default();
            continue;
        }
        if line == "notes:" {
            current_checkpoint = None;
            continue;
        }

        let trimmed = line.trim_start();
        if let Some(checkpoint) = current_checkpoint.as_ref() {
            let checkpoint = plan
                .checkpoints
                .get_mut(checkpoint)
                .expect("checkpoint inserted before parsing fields");
            if let Some(rest) = trimmed.strip_prefix("evidence_artifact: ") {
                let artifact = parse_key_value_words(rest);
                let name = artifact
                    .get("name")
                    .unwrap_or_else(|| panic!("evidence artifact should name itself: {line}"))
                    .to_string();
                checkpoint.artifacts.insert(name, artifact);
            } else if let Some((key, value)) = trimmed.split_once(": ") {
                checkpoint.fields.insert(key.to_string(), value.to_string());
            }
        } else if let Some((key, value)) = line.split_once(": ") {
            plan.top.insert(key.to_string(), value.to_string());
        }
    }

    plan
}

fn output_label(line: &str) -> Option<&str> {
    if let Some((label, _)) = line.split_once(" = ") {
        return Some(label);
    }
    let (label, _) = line.split_once(':')?;
    (label.contains("_command_")
        || label.contains("_wrapped_command_")
        || label.contains("_redirect_"))
    .then_some(label)
}

fn parse_key_value_words(text: &str) -> BTreeMap<String, String> {
    text.split_ascii_whitespace()
        .filter_map(|word| word.split_once('='))
        .map(|(key, value)| (key.to_string(), value.to_string()))
        .collect()
}

fn parse_key_value_lines(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|line| line.split_once('='))
        .map(|(key, value)| (key.to_string(), value.to_string()))
        .collect()
}

fn write_sha256_artifact(input: &Path, output: &Path) {
    let sha = Command::new("sha256sum")
        .arg(input)
        .output()
        .unwrap_or_else(|err| panic!("hash {}: {err}", input.display()));
    assert!(
        sha.status.success(),
        "sha256sum failed for {}\nstdout:\n{}\nstderr:\n{}",
        input.display(),
        String::from_utf8_lossy(&sha.stdout),
        String::from_utf8_lossy(&sha.stderr)
    );
    fs::write(output, sha.stdout).unwrap_or_else(|err| panic!("write {}: {err}", output.display()));
}

fn assert_checkpoint_evidence_contract(plan: &MeasurementPlan, lines: &str) {
    let checkpoint = plan
        .checkpoints
        .get(lines)
        .unwrap_or_else(|| panic!("missing checkpoint {lines} in {plan:#?}"));

    assert_eq!(required_plan_field(&checkpoint.fields, "line_count"), lines);
    assert_eq!(required_plan_field(&checkpoint.fields, "iterations"), "1");
    assert_eq!(
        required_plan_field(&checkpoint.fields, "timeout_ms"),
        "120000"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "timeout_seconds"),
        "120"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "readback_timeout_ms"),
        "60000"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "vram_sample_interval_ms"),
        "250"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "responsiveness_probe_timeout_ms"),
        "2000"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "source"),
        "call-graph"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "source_seed"),
        "3235798765"
    );
    assert_eq!(required_plan_field(&checkpoint.fields, "phase"), "x86");
    assert_eq!(
        required_plan_field(&checkpoint.fields, "target"),
        "x86_64-elf"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "gpu_timing_env"),
        "LANIUS_GPU_TIMING=1 LANIUS_GPU_COMPILE_HOST_TIMING=1"
    );
    assert_measurement_timing_contract(&checkpoint.fields);
    assert_claim_provenance_contract(&checkpoint.fields);
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_artifacts"
        )),
        required_artifact_names()
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "optional_comparison_artifacts"
        )),
        optional_comparison_artifact_names()
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "artifact_manifest_schema"),
        "lanius.measurement-artifacts.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_artifact_manifest_fields"
        )),
        required_artifact_manifest_field_names()
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_status_fields"
        )),
        required_status_field_names()
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "optional_status_fields"
        )),
        optional_status_field_names()
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "hardware_identity_schema"),
        "lanius.hardware-identity.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_hardware_identity_fields"
        )),
        required_hardware_identity_field_names()
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "command_environment_schema"),
        "lanius.command-environment.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_command_environment_fields",
        )),
        required_command_environment_field_names(),
        "checkpoint command environment fields",
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "responsiveness_probe_schema"),
        "lanius.responsiveness-probe.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_responsiveness_probe_fields"
        )),
        required_responsiveness_probe_field_names()
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "command_status_schema"),
        "lanius.command-status.v1"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "evidence_status_schema"),
        "lanius.measurement-evidence-status.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_evidence_status_fields",
        )),
        required_evidence_status_field_names(),
        "checkpoint evidence status fields",
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "evidence_freshness_schema"),
        "lanius.measurement-evidence-freshness.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_evidence_freshness_fields"
        )),
        required_evidence_freshness_field_names()
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "claim_readiness_schema"),
        "lanius.measurement-claim-readiness.v1"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "claim_readiness_policy"),
        "complete-local-evidence-only"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "claim_scope_policy"),
        "exact-local-checkpoint-hardware-source-binary-only"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "source_control_policy"),
        "git-head-plus-status-in-command-environment-hash"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "repeatability_policy"),
        "claimable-metrics-require-at-least-three-iterations"
    );
    assert_eq!(
        required_plan_field(&checkpoint.fields, "minimum_iterations_for_claim"),
        "3"
    );
    assert_eq!(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_claim_readiness_fields"
        )),
        required_claim_readiness_field_names()
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            &checkpoint.fields,
            "required_summary_fields",
        )),
        required_summary_field_names(),
        "checkpoint measurement summary fields",
    );

    for name in required_artifact_names() {
        let artifact = required_artifact(checkpoint, &name);
        assert_artifact_manifest_entry_fields(artifact, &name);
        assert_eq!(required_plan_field(artifact, "checkpoint"), lines);
        assert_eq!(required_plan_field(artifact, "required"), "true");
        assert_eq!(
            required_plan_field(artifact, "path"),
            required_plan_field(&checkpoint.fields, artifact_checkpoint_path_field(&name))
        );
        let producer = required_plan_field(artifact, "producer");
        assert!(
            plan.command_labels.contains(producer),
            "producer {producer:?} for artifact {name:?} should be emitted as a command label"
        );
        assert_eq!(
            required_plan_field(artifact, "status_artifact"),
            expected_status_artifact(&name),
            "artifact {name:?} should declare where its status is captured"
        );
        let expected_claim_source = if name == "measurement_summary" {
            "derived_local_artifacts"
        } else {
            "local_artifact"
        };
        assert_eq!(
            required_plan_field(artifact, "claim_source"),
            expected_claim_source,
            "required artifact {name:?} should reject paper-number or manual-estimate claim provenance"
        );
        let expected_claim_boundary = if name == "measurement_summary" {
            "derived-summary-rollup-not-no-run-performance-evidence"
        } else {
            "checkpoint-local-artifact-not-claimable-without-summary"
        };
        assert_eq!(
            required_plan_field(artifact, "claim_boundary"),
            expected_claim_boundary,
            "required artifact {name:?} should publish its claim boundary"
        );
        assert_contains_fields(
            csv_set(required_plan_field(artifact, "claim_fields")),
            expected_claim_fields_for_artifact(&name),
            &format!("required artifact {name:?} claim fields"),
        );
        if required_plan_field(artifact, "status_field") == "not_captured" {
            assert_eq!(
                required_plan_field(artifact, "status_artifact"),
                "none",
                "artifact {name:?} should mark status_artifact=none when no status is captured"
            );
        } else {
            assert_eq!(
                required_plan_field(artifact, "status_artifact"),
                "command_status",
                "artifact {name:?} should point status-bearing fields at the command_status artifact"
            );
        }
    }

    for name in optional_comparison_artifact_names() {
        let artifact = required_artifact(checkpoint, &name);
        assert_artifact_manifest_entry_fields(artifact, &name);
        assert_eq!(required_plan_field(artifact, "checkpoint"), lines);
        assert_eq!(required_plan_field(artifact, "required"), "false");
        assert_eq!(
            required_plan_field(artifact, "path"),
            required_plan_field(&checkpoint.fields, artifact_checkpoint_path_field(&name))
        );
        let expected_availability = if name == "pareas_vram_csv" {
            "requires_pareas_and_nvidia_smi"
        } else if matches!(name.as_str(), "pareas_source" | "pareas_source_sha256") {
            "optional_comparison"
        } else {
            "requires_pareas"
        };
        assert_eq!(
            required_plan_field(artifact, "availability"),
            expected_availability
        );
        let producer = required_plan_field(artifact, "producer");
        assert!(
            plan.command_labels.contains(producer),
            "producer {producer:?} for Pareas artifact {name:?} should be emitted as a command label"
        );
        assert_eq!(
            required_plan_field(artifact, "status_artifact"),
            expected_status_artifact(&name),
            "Pareas artifact {name:?} should declare where its status is captured"
        );
        assert_eq!(
            required_plan_field(artifact, "claim_source"),
            "optional_local_comparison_artifact",
            "Pareas artifact {name:?} should require local comparison provenance"
        );
        assert_eq!(
            required_plan_field(artifact, "claim_boundary"),
            "optional-local-comparison-provenance-not-pareas-claim",
            "Pareas artifact {name:?} should not imply a Pareas comparison claim"
        );
        assert_contains_fields(
            csv_set(required_plan_field(artifact, "claim_fields")),
            expected_claim_fields_for_artifact(&name),
            &format!("Pareas artifact {name:?} claim fields"),
        );
    }

    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "lanius_stdout"),
            "claim_fields"
        )),
        string_set(["best_ms", "throughput_lines_per_second"]),
        "stdout-derived claim fields should not treat cold-start wall time as compile latency"
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "perfetto_trace"), "env_var"),
        "LANIUS_PERFETTO_TRACE"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "bench_binary_sha256"),
            "input"
        ),
        "target/release/gpu_compile_bench"
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "readback_summary"), "input"),
        "perfetto_trace"
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "vram_csv"), "availability"),
        "requires_nvidia_smi"
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "vram_csv"), "stale_check"),
        "vram_csv_header_matches_required_columns"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "pareas_vram_csv"),
            "availability"
        ),
        "requires_pareas_and_nvidia_smi"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "pareas_vram_csv"),
            "stale_check"
        ),
        "pareas_vram_csv_header_matches_required_columns"
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "pareas_vram_csv"),
            "claim_fields"
        )),
        string_set(["pareas_max_vram_bytes", "pareas_nvidia_smi_exit_status"])
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "resource_usage"), "claim"),
        "cpu_time_and_memory"
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "resource_usage"), "fields"),
        "user_seconds,system_seconds,max_rss_kb"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "resource_usage"),
            "stale_check"
        ),
        "resource_usage_command_matches_checkpoint"
    );
    assert_eq!(
        required_plan_field(required_artifact(checkpoint, "hardware_identity"), "schema"),
        "lanius.hardware-identity.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "hardware_identity"),
            "fields"
        )),
        required_hardware_identity_field_names()
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "command_environment"),
            "schema"
        ),
        "lanius.command-environment.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "command_environment"),
            "fields",
        )),
        required_command_environment_field_names(),
        "command environment artifact fields",
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "responsiveness_probe"),
            "schema"
        ),
        "lanius.responsiveness-probe.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "responsiveness_probe"),
            "fields"
        )),
        required_responsiveness_probe_field_names()
    );
    let pareas_source_redirect =
        required_plan_field(required_artifact(checkpoint, "pareas_source"), "redirect");
    assert!(
        plan.command_labels.contains(pareas_source_redirect),
        "declared Pareas source redirect {pareas_source_redirect:?} should be emitted as a command label"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "pareas_source_sha256"),
            "input"
        ),
        "pareas_source"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "pareas_binary_sha256"),
            "input"
        ),
        "PAREAS_BIN"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "pareas_binary_sha256"),
            "stale_check"
        ),
        "pareas_binary_sha256_matches_pareas_binary"
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "command_status"),
            "status_fields"
        )),
        required_status_field_names()
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "schema"
        ),
        "lanius.measurement-summary.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "fields",
        )),
        required_summary_field_names(),
        "measurement summary artifact fields",
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "completion_schema"
        ),
        "lanius.measurement-evidence-status.v1"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "completion_fields",
        )),
        required_evidence_status_field_names(),
        "measurement summary completion fields",
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "freshness_schema"
        ),
        "lanius.measurement-evidence-freshness.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "freshness_fields"
        )),
        required_evidence_freshness_field_names()
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "claim_readiness_schema"
        ),
        "lanius.measurement-claim-readiness.v1"
    );
    assert_eq!(
        required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "claim_readiness_policy"
        ),
        "complete-local-evidence-only"
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "claim_readiness_fields"
        )),
        required_claim_readiness_field_names()
    );
    assert_eq!(
        csv_set(required_plan_field(
            required_artifact(checkpoint, "measurement_summary"),
            "inputs"
        )),
        string_set([
            "lanius_stdout",
            "readback_summary",
            "vram_csv",
            "source_replay",
            "source_sha256",
            "bench_binary_sha256",
            "hardware_identity",
            "command_environment",
            "command_status",
            "responsiveness_probe",
            "resource_usage",
            "pareas_source",
            "pareas_source_sha256",
            "pareas_binary_sha256",
            "pareas_vram_csv",
        ])
    );
}

fn parse_acceptance_plan_status(output: &str) -> BTreeMap<String, String> {
    let status_lines = output
        .lines()
        .filter_map(|line| line.strip_prefix("# acceptance-plan: "))
        .collect::<Vec<_>>();
    assert_eq!(
        status_lines.len(),
        1,
        "readiness check-plan should publish one machine-readable status line\n{output}"
    );
    parse_key_value_words(status_lines[0])
}

fn plan_counter(fields: &BTreeMap<String, String>, name: &str) -> u64 {
    required_plan_field(fields, name)
        .parse()
        .unwrap_or_else(|err| panic!("field {name:?} should be an unsigned counter: {err}"))
}

fn assert_zero_plan_counter(fields: &BTreeMap<String, String>, name: &str) {
    assert_eq!(plan_counter(fields, name), 0, "{name} should be zero");
}

fn assert_positive_plan_counter(fields: &BTreeMap<String, String>, name: &str) {
    assert!(
        plan_counter(fields, name) > 0,
        "{name} should record exercised no-run evidence"
    );
}

fn required_command<'a>(plan: &'a MeasurementPlan, label: &str) -> &'a str {
    plan.commands
        .get(label)
        .map(String::as_str)
        .unwrap_or_else(|| panic!("missing command {label:?} in {plan:#?}"))
}

fn required_artifact_command<'a>(
    plan: &'a MeasurementPlan,
    lines: &str,
    artifact: &str,
) -> &'a str {
    let checkpoint = plan
        .checkpoints
        .get(lines)
        .unwrap_or_else(|| panic!("missing checkpoint {lines} in {plan:#?}"));
    let producer = required_plan_field(required_artifact(checkpoint, artifact), "producer");
    required_command(plan, producer)
}

fn required_artifact<'a>(
    checkpoint: &'a MeasurementCheckpoint,
    name: &str,
) -> &'a BTreeMap<String, String> {
    checkpoint
        .artifacts
        .get(name)
        .unwrap_or_else(|| panic!("missing artifact {name:?} in {checkpoint:#?}"))
}

fn required_plan_field<'a>(fields: &'a BTreeMap<String, String>, name: &str) -> &'a str {
    fields
        .get(name)
        .map(String::as_str)
        .unwrap_or_else(|| panic!("missing field {name:?} in {fields:#?}"))
}

fn assert_measurement_timing_contract(fields: &BTreeMap<String, String>) {
    assert_eq!(
        required_plan_field(fields, "measurement_timing_policy"),
        measurement_timing_policy()
    );
    assert_eq!(
        required_plan_field(fields, "cold_start_policy"),
        cold_start_policy()
    );
    assert_eq!(
        required_plan_field(fields, "cold_gpu_pipeline_init_policy"),
        cold_gpu_pipeline_init_policy()
    );
    assert_eq!(
        required_plan_field(fields, "compile_latency_claim_source"),
        compile_latency_claim_source()
    );
    assert_eq!(
        required_plan_field(fields, "steady_compile_latency_claim_source"),
        steady_compile_latency_claim_source()
    );
    assert_eq!(
        required_plan_field(fields, "steady_readback_claim_source"),
        steady_readback_claim_source()
    );
    assert_eq!(
        required_plan_field(fields, "runtime_validation_policy"),
        runtime_validation_policy()
    );
    assert_eq!(
        required_plan_field(fields, "timeout_provenance_schema"),
        "lanius.timeout-provenance.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            fields,
            "required_timeout_provenance_fields"
        )),
        required_timeout_provenance_field_names()
    );
    assert_eq!(
        required_plan_field(fields, "timeout_scope"),
        timeout_scope()
    );
    assert_eq!(
        required_plan_field(fields, "timeout_source"),
        timeout_source()
    );
    assert_eq!(
        required_plan_field(fields, "timeout_enforced_by"),
        timeout_enforced_by()
    );
    assert_eq!(required_plan_field(fields, "timeout_exit_code"), "124");
    assert_eq!(
        required_plan_field(fields, "timeout_exit_code_means_timed_out"),
        "true"
    );
}

fn assert_claim_provenance_contract(fields: &BTreeMap<String, String>) {
    assert_eq!(
        required_plan_field(fields, "claim_provenance_schema"),
        claim_provenance_schema()
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            fields,
            "required_claim_provenance_fields",
        )),
        required_claim_provenance_field_names(),
        "claim provenance fields",
    );
    assert_eq!(
        required_plan_field(fields, "paper_baseline_policy"),
        paper_baseline_policy()
    );
    assert_eq!(
        required_plan_field(fields, "paper_baseline_claim_status"),
        paper_baseline_claim_status()
    );
    assert_eq!(
        required_plan_field(fields, "workload_shape_policy"),
        workload_shape_policy()
    );
    assert_eq!(
        required_plan_field(fields, "workload_shape_scope"),
        workload_shape_scope()
    );
    assert_eq!(
        required_plan_field(fields, "workload_generalization_status"),
        workload_generalization_status()
    );
    assert_eq!(
        required_plan_field(fields, "workload_generalization_blockers"),
        workload_generalization_blockers()
    );
    assert_eq!(
        required_plan_field(fields, "link_artifact_evidence_policy"),
        link_artifact_evidence_policy()
    );
    assert_eq!(
        required_plan_field(fields, "link_artifact_evidence_schema"),
        link_artifact_evidence_schema()
    );
    assert_eq!(
        required_plan_field(fields, "link_artifact_required_evidence_classes"),
        link_artifact_required_evidence_classes()
    );
    assert_eq!(
        required_plan_field(fields, "link_artifact_evidence_status"),
        link_artifact_evidence_status()
    );
    assert_eq!(
        required_plan_field(fields, "link_artifact_claim_blockers"),
        link_artifact_claim_blockers()
    );
    assert_eq!(
        required_plan_field(fields, "local_performance_claim_source"),
        local_performance_claim_source()
    );
    assert_eq!(
        required_plan_field(fields, "local_vram_claim_source"),
        local_vram_claim_source()
    );
    assert_eq!(
        required_plan_field(fields, "local_pareas_claim_source"),
        local_pareas_claim_source()
    );
}

fn assert_parallel_pass_contract_metadata(fields: &BTreeMap<String, String>) {
    assert_eq!(
        required_plan_field(fields, "paper_pass_order_schema"),
        "lanius.paper-pass-order.v1"
    );
    assert!(
        required_plan_field(fields, "paper_pass_order_source")
            .contains("docs/PAREAS_PASS_CONTRACT.md:lanius-gate"),
        "paper pass order source should cite the checked-in pass contract"
    );
    assert_eq!(
        csv_vec(required_plan_field(fields, "paper_pass_order")),
        vec![
            "lexical_analysis",
            "parsing",
            "semantic_analysis",
            "intermediate_code_generation",
            "optimization",
            "machine_code_generation",
        ]
    );
    assert_eq!(
        required_plan_field(fields, "paper_pass_alignment_policy"),
        "parallel-pass-contracts-must-cover-paper-order-before-scale-claims"
    );
    assert_eq!(
        required_plan_field(fields, "paper_pass_alignment_status"),
        "blocked"
    );
    assert!(
        required_plan_field(fields, "paper_pass_alignment_blockers")
            .contains("pass_contracts:blocked"),
        "paper-pass alignment blockers should carry pass-contract blockers"
    );
    assert_eq!(
        required_plan_field(fields, "parallel_pass_contract_schema"),
        "lanius.parallel-pass-contracts.v1"
    );
    assert_eq!(
        required_plan_field(fields, "parallel_pass_contract_policy"),
        "scale-claims-require-behavioral-record-boundary-evidence"
    );
    assert_eq!(
        csv_set(required_plan_field(fields, "parallel_pass_contract_groups")),
        parallel_pass_contract_groups()
    );
    assert_eq!(
        csv_vec(required_plan_field(
            fields,
            "parallel_pass_contract_execution_order"
        )),
        vec![
            "record_invariant",
            "semantic_contract",
            "execution_contract",
            "measurement_scaffold",
        ]
    );
    assert_eq!(
        required_plan_field(fields, "parallel_pass_contract_order_policy"),
        "paper-pass-order-record-boundary-sequence"
    );
    assert_eq!(
        csv_set(required_plan_field(
            fields,
            "required_parallel_pass_contract_fields"
        )),
        required_parallel_pass_contract_field_names()
    );
    assert_eq!(
        required_plan_field(fields, "pass_contract_status_schema"),
        "lanius.parallel-pass-contract-status.v1"
    );
    assert_eq!(
        csv_set(required_plan_field(
            fields,
            "required_pass_contract_status_fields"
        )),
        required_pass_contract_status_field_names()
    );
    assert_eq!(
        required_plan_field(fields, "pass_contract_loop_status"),
        "bounded"
    );
    assert_eq!(
        required_plan_field(fields, "pass_contract_fallback_status"),
        "fail-closed"
    );
    assert_eq!(
        required_plan_field(fields, "pass_contract_claim_status"),
        "blocked"
    );
    assert_eq!(
        required_plan_field(fields, "pass_contract_readiness_status"),
        "blocked"
    );
    let pass_contract_blockers = required_plan_field(fields, "pass_contract_claim_blockers");
    assert!(
        pass_contract_blockers.contains("bounded_pass_loops")
            && pass_contract_blockers.contains("fail_closed_passes"),
        "pass-contract blockers should keep bounded loops and fail-closed fallbacks visible"
    );
    let scaling_blockers = required_plan_field(fields, "scaling_claim_blockers");
    assert!(
        scaling_blockers.contains("paper_pass_alignment:blocked")
            && scaling_blockers.contains("pass_contracts:blocked"),
        "scaling blockers should remain tied to paper-pass alignment and pass contracts"
    );
    assert_contains_fields(
        csv_set(required_plan_field(
            fields,
            "claim_readiness_required_evidence_classes",
        )),
        string_set(["paper_pass_alignment", "parallel_pass_contracts"]),
        "claim-readiness evidence classes",
    );
    assert_claim_readiness_status_requirements(required_plan_field(
        fields,
        "claim_readiness_required_statuses",
    ));
}

fn assert_parallel_pass_contract_rows(fields: &BTreeMap<String, String>) {
    let expected = [
        (
            "parallel_pass_contract_record_invariant",
            "record_invariant",
            "paper_record_boundary",
            "public_record_invariants",
            "record_boundary_claim",
            "record-invariant",
            "behavioral-evidence-only",
        ),
        (
            "parallel_pass_contract_semantic_contract",
            "semantic_contract",
            "paper_semantic_boundary",
            "typed_identity_contracts",
            "structured_record_contract",
            "semantic-contract",
            "behavioral-evidence-only",
        ),
        (
            "parallel_pass_contract_execution_contract",
            "execution_contract",
            "paper_codegen_boundary",
            "emitted_output_contracts",
            "execution_behavior_claim",
            "execution-contract",
            "executed-output-or-fail-closed-diagnostic",
        ),
        (
            "parallel_pass_contract_measurement_scaffold",
            "measurement_scaffold",
            "paper_scale_boundary",
            "local_artifact_provenance",
            "measurement_metadata_claim",
            "measurement-scaffold",
            "blocked-until-local-artifacts-and-contracts-claimable",
        ),
    ];
    let required_fields = required_parallel_pass_contract_field_names();
    let mut seen_groups = BTreeSet::new();

    for (
        key,
        pass_group,
        paper_pass_stage,
        record_boundary,
        parallel_primitives,
        evidence_shape,
        claim_boundary,
    ) in expected
    {
        let row = parse_key_value_words(required_plan_field(fields, key));
        assert_contains_fields(row.keys().cloned().collect(), required_fields.clone(), key);
        assert_eq!(
            required_plan_field(&row, "contract_schema"),
            "lanius.parallel-pass-contracts.v1"
        );
        assert_eq!(required_plan_field(&row, "pass_group"), pass_group);
        assert_eq!(
            required_plan_field(&row, "paper_pass_stage"),
            paper_pass_stage
        );
        assert_eq!(
            required_plan_field(&row, "record_boundary"),
            record_boundary
        );
        assert_eq!(
            required_plan_field(&row, "parallel_primitives"),
            parallel_primitives
        );
        assert_eq!(required_plan_field(&row, "evidence_shape"), evidence_shape);
        assert_eq!(required_plan_field(&row, "loop_status"), "bounded");
        assert_eq!(required_plan_field(&row, "fallback_status"), "fail-closed");
        assert_eq!(required_plan_field(&row, "claim_boundary"), claim_boundary);
        assert!(
            seen_groups.insert(pass_group.to_string()),
            "pass group {pass_group:?} should only be published once"
        );
    }

    assert_eq!(seen_groups, parallel_pass_contract_groups());
}

fn assert_artifact_manifest_entry_fields(artifact: &BTreeMap<String, String>, name: &str) {
    for field in required_artifact_manifest_field_names() {
        assert!(
            artifact.contains_key(&field),
            "artifact {name:?} should publish manifest field {field:?}: {artifact:#?}"
        );
    }
}

fn artifact_checkpoint_path_field(name: &str) -> &'static str {
    match name {
        "lanius_stdout" => "lanius_stdout_path",
        "perfetto_trace" => "lanius_perfetto_trace_path",
        "readback_summary" => "readback_summary_path",
        "vram_csv" => "vram_output_path",
        "source_replay" => "source_replay_output_path",
        "source_sha256" => "source_sha256_output_path",
        "bench_binary_sha256" => "bench_sha256_output_path",
        "hardware_identity" => "hardware_output_path",
        "command_environment" => "command_env_output_path",
        "command_status" => "command_status_output_path",
        "responsiveness_probe" => "responsiveness_probe_output_path",
        "resource_usage" => "resource_usage_output_path",
        "measurement_summary" => "measurement_summary_output_path",
        "pareas_source" => "pareas_source_path",
        "pareas_source_sha256" => "pareas_source_sha256_output_path",
        "pareas_binary_sha256" => "pareas_binary_sha256_output_path",
        "pareas_output" => "pareas_output_path",
        "pareas_stdout" => "pareas_stdout_path",
        "pareas_vram_csv" => "pareas_vram_output_path",
        other => panic!("no checkpoint path field for artifact {other:?}"),
    }
}

fn expected_status_artifact(name: &str) -> &'static str {
    match name {
        "lanius_stdout"
        | "perfetto_trace"
        | "readback_summary"
        | "vram_csv"
        | "command_status"
        | "responsiveness_probe"
        | "resource_usage"
        | "pareas_output"
        | "pareas_stdout"
        | "pareas_vram_csv" => "command_status",
        "source_replay"
        | "source_sha256"
        | "bench_binary_sha256"
        | "hardware_identity"
        | "command_environment"
        | "measurement_summary"
        | "pareas_source"
        | "pareas_source_sha256"
        | "pareas_binary_sha256" => "none",
        other => panic!("no status artifact contract for artifact {other:?}"),
    }
}

fn csv_set(value: &str) -> BTreeSet<String> {
    value.split(',').map(str::to_string).collect()
}

fn csv_vec(value: &str) -> Vec<&str> {
    value.split(',').collect()
}

fn string_set<const N: usize>(items: [&str; N]) -> BTreeSet<String> {
    items.into_iter().map(str::to_string).collect()
}

fn assert_contains_fields(actual: BTreeSet<String>, expected: BTreeSet<String>, label: &str) {
    assert!(
        actual.is_superset(&expected),
        "{label} should include {expected:?}; got {actual:?}"
    );
}

fn assert_claim_readiness_status_requirements(value: &str) {
    for status in [
        "local_performance_evidence_status=complete",
        "local_performance_claim_status=claimable",
        "local_readback_evidence_status=complete",
        "local_vram_evidence_status=complete",
        "local_pareas_evidence_status=complete",
        "local_pareas_vram_evidence_status=complete",
        "resource_usage_status=0",
        "machine_responsive_after=true",
        "source_control_state=clean-or-dirty",
        "source_control_revision=local-git-commit-sha",
        "evidence_freshness_status=complete",
        "repeatability_status=complete",
        "workload_generalization_status=generalizable",
        "link_artifact_evidence_schema=lanius.link-artifact-evidence.v1",
        "link_artifact_required_evidence_classes=library_interface_artifacts,codegen_object_artifacts,partial_link_artifacts,linked_output_artifact",
        "link_artifact_evidence_status=artifact-backed",
        "paper_pass_alignment_status=claimable",
        "pass_contract_loop_status=unbounded",
        "pass_contract_fallback_status=none",
        "pass_contract_claim_status=claimable",
        "pass_contract_readiness_status=claimable",
        "scaling_claim_status=claimable",
    ] {
        assert!(
            value.contains(status),
            "claim-readiness requirements should include {status:?}; got {value:?}"
        );
    }
}

fn measurement_timing_policy() -> &'static str {
    "compile-latency-claims-use-benchmark-best-ms-wall-time-is-provenance"
}

fn measurement_scaffold_evidence_status() -> &'static str {
    "no-run-plan-not-local-performance-evidence"
}

fn cold_start_policy() -> &'static str {
    "excluded-from-claimable-compile-latency-captured-as-wrapper-wall-time"
}

fn cold_gpu_pipeline_init_policy() -> &'static str {
    "cold-gpu-pipeline-init-is-provenance-only-excluded-from-steady-compile-and-readback-claims"
}

fn compile_latency_claim_source() -> &'static str {
    "benchmark-stdout-best-ms-local-run-only"
}

fn steady_compile_latency_claim_source() -> &'static str {
    "benchmark-stdout-best-ms-local-run-only-excludes-cold-gpu-pipeline-init"
}

fn steady_readback_claim_source() -> &'static str {
    "readback-summary-host-readback-spans-local-run-only-excludes-cold-gpu-pipeline-init"
}

fn runtime_validation_policy() -> &'static str {
    "validate-output-only-not-runtime-performance-claim"
}

fn claim_provenance_schema() -> &'static str {
    "lanius.measurement-claim-provenance.v1"
}

fn paper_baseline_policy() -> &'static str {
    "reference-only-not-local-performance-evidence"
}

fn paper_baseline_claim_status() -> &'static str {
    "not-local-performance-evidence"
}

fn workload_shape_policy() -> &'static str {
    "single-generated-workload-is-checkpoint-local-not-general-language-performance"
}

fn workload_shape_scope() -> &'static str {
    "line-count-source-phase-target-seed-binary-hardware-only"
}

fn workload_generalization_status() -> &'static str {
    "not-generalizable"
}

fn workload_generalization_blockers() -> &'static str {
    "multi-shape-local-artifacts-required,long-function-and-wide-tree-shape-coverage-required"
}

fn link_artifact_evidence_policy() -> &'static str {
    "production-claims-require-object-interface-partial-link-artifacts"
}

fn link_artifact_evidence_schema() -> &'static str {
    "lanius.link-artifact-evidence.v1"
}

fn link_artifact_required_evidence_classes() -> &'static str {
    "library_interface_artifacts,codegen_object_artifacts,partial_link_artifacts,linked_output_artifact"
}

fn link_artifact_evidence_status() -> &'static str {
    "not-artifact-backed"
}

fn link_artifact_claim_blockers() -> &'static str {
    "object_interface_partial_link_artifacts_required"
}

fn link_artifact_claim_blocker() -> String {
    format!(
        "link_artifacts:{}:{}:{}",
        link_artifact_evidence_status(),
        link_artifact_claim_blockers(),
        link_artifact_required_evidence_classes()
    )
}

fn link_artifact_claim_short_blocker() -> String {
    format!(
        "link_artifacts:{}:{}",
        link_artifact_evidence_status(),
        link_artifact_claim_blockers()
    )
}

fn local_performance_claim_source() -> &'static str {
    "benchmark-stdout-best-ms-plus-local-artifact-freshness"
}

fn local_vram_claim_source() -> &'static str {
    "nvidia-smi-local-csv-plus-status-artifact"
}

fn local_pareas_claim_source() -> &'static str {
    "local-pareas-source-output-stdout-compiler-hash-provenance-only"
}

fn claim_readiness_required_evidence_classes() -> BTreeSet<String> {
    string_set([
        "local_performance",
        "local_performance_claim",
        "local_readback",
        "local_vram",
        "local_pareas",
        "local_pareas_vram",
        "resource_usage",
        "responsiveness",
        "source_control",
        "freshness",
        "repeatability",
        "workload_generalization",
        "link_artifacts",
        "paper_pass_alignment",
        "parallel_pass_contracts",
        "scaling_claim",
    ])
}

fn timeout_scope() -> &'static str {
    "wrapper-process-wall-clock-bound"
}

fn timeout_source() -> &'static str {
    "LANIUS_PERF_COMMAND_TIMEOUT_MS"
}

fn timeout_enforced_by() -> &'static str {
    "timeout"
}

fn required_artifact_names() -> BTreeSet<String> {
    string_set([
        "lanius_stdout",
        "perfetto_trace",
        "readback_summary",
        "vram_csv",
        "source_replay",
        "source_sha256",
        "bench_binary_sha256",
        "hardware_identity",
        "command_environment",
        "command_status",
        "responsiveness_probe",
        "resource_usage",
        "measurement_summary",
    ])
}

fn optional_comparison_artifact_names() -> BTreeSet<String> {
    string_set([
        "pareas_source",
        "pareas_source_sha256",
        "pareas_binary_sha256",
        "pareas_output",
        "pareas_stdout",
        "pareas_vram_csv",
    ])
}

fn required_artifact_manifest_field_names() -> BTreeSet<String> {
    string_set([
        "checkpoint",
        "name",
        "required",
        "path",
        "producer",
        "status_field",
        "status_artifact",
        "claim",
        "claim_source",
        "claim_fields",
        "claim_boundary",
    ])
}

fn required_claim_provenance_field_names() -> BTreeSet<String> {
    string_set([
        "claim_provenance_schema",
        "baseline_separation_schema",
        "paper_baseline_policy",
        "paper_baseline_numbers_status",
        "paper_baseline_claim_status",
        "local_evidence_status_policy",
        "cold_gpu_pipeline_init_policy",
        "steady_compile_latency_claim_source",
        "steady_readback_claim_source",
        "runtime_validation_policy",
        "workload_shape_policy",
        "workload_shape_scope",
        "workload_generalization_status",
        "workload_generalization_blockers",
        "link_artifact_evidence_policy",
        "link_artifact_evidence_schema",
        "link_artifact_required_evidence_classes",
        "link_artifact_evidence_status",
        "link_artifact_claim_blockers",
        "local_performance_claim_policy",
        "local_performance_claim_source",
        "local_performance_claim_exclusions",
        "local_performance_claim_status",
        "local_performance_claim_blockers",
        "local_vram_claim_source",
        "local_pareas_claim_source",
        "scaling_claim_policy",
        "scaling_claim_source",
        "scaling_claim_status",
        "scaling_claim_blockers",
    ])
}

fn expected_claim_fields_for_artifact(name: &str) -> BTreeSet<String> {
    match name {
        "lanius_stdout" => string_set(["best_ms", "throughput_lines_per_second"]),
        "perfetto_trace" | "readback_summary" => string_set([
            "readback_span_count",
            "readback_total_ms",
            "readback_max_span_ms",
        ]),
        "vram_csv" => string_set(["max_vram_bytes", "nvidia_smi_exit_status"]),
        "source_replay" => string_set(["source_replay_path", "source_replay_line_count"]),
        "source_sha256" => string_set(["source_sha256"]),
        "bench_binary_sha256" => string_set(["bench_binary_sha256"]),
        "hardware_identity" => string_set(["hardware_identity_sha256"]),
        "command_environment" => string_set([
            "command_environment_sha256",
            "source_control_state",
            "source_control_revision",
            "paper_baseline_numbers_status",
            "paper_baseline_claim_status",
            "local_evidence_status_policy",
            "cold_gpu_pipeline_init_policy",
            "steady_compile_latency_claim_source",
            "steady_readback_claim_source",
            "workload_shape_policy",
            "workload_shape_scope",
            "workload_generalization_status",
            "workload_generalization_blockers",
            "link_artifact_evidence_policy",
            "link_artifact_evidence_schema",
            "link_artifact_required_evidence_classes",
            "link_artifact_evidence_status",
            "link_artifact_claim_blockers",
            "local_performance_claim_status",
            "local_performance_claim_blockers",
            "scaling_claim_status",
            "scaling_claim_blockers",
        ]),
        "command_status" => string_set([
            "lanius_exit_status",
            "timed_out",
            "lanius_wall_elapsed_ms",
            "measurement_timing_policy",
            "cold_start_policy",
            "cold_gpu_pipeline_init_policy",
            "compile_latency_claim_source",
            "steady_compile_latency_claim_source",
            "steady_readback_claim_source",
            "runtime_validation_policy",
            "link_artifact_evidence_policy",
            "link_artifact_evidence_schema",
            "link_artifact_required_evidence_classes",
            "link_artifact_evidence_status",
            "link_artifact_claim_blockers",
            "timeout_provenance_schema",
            "timeout_scope",
            "timeout_ms",
            "timeout_seconds",
            "timeout_source",
            "timeout_enforced_by",
            "timeout_exit_code",
            "timeout_exit_code_means_timed_out",
            "nvidia_smi_exit_status",
            "pareas_exit_status",
            "pareas_wall_elapsed_ms",
            "machine_responsive_after",
            "resource_usage_status",
        ]),
        "responsiveness_probe" => {
            string_set(["machine_responsive_after", "responsiveness_probe_status"])
        }
        "resource_usage" => string_set([
            "resource_user_seconds",
            "resource_system_seconds",
            "resource_max_rss_kb",
            "resource_usage_status",
        ]),
        "measurement_summary" => string_set([
            "production_readiness_evidence_complete",
            "production_readiness_blockers",
            "claim_readiness_status",
            "claimable_measurement_claims",
            "claim_readiness_blockers",
            "measurement_timing_policy",
            "cold_start_policy",
            "cold_gpu_pipeline_init_policy",
            "compile_latency_claim_source",
            "steady_compile_latency_claim_source",
            "steady_readback_claim_source",
            "runtime_validation_policy",
            "workload_shape_policy",
            "workload_shape_scope",
            "workload_generalization_status",
            "workload_generalization_blockers",
            "link_artifact_evidence_policy",
            "link_artifact_evidence_schema",
            "link_artifact_required_evidence_classes",
            "link_artifact_evidence_status",
            "link_artifact_claim_blockers",
            "claim_provenance_schema",
            "baseline_separation_schema",
            "paper_baseline_policy",
            "paper_baseline_numbers_status",
            "paper_baseline_claim_status",
            "local_evidence_status_policy",
            "local_performance_claim_policy",
            "local_performance_claim_source",
            "local_performance_claim_exclusions",
            "local_performance_claim_status",
            "local_performance_claim_blockers",
            "local_vram_claim_source",
            "local_pareas_claim_source",
            "scaling_claim_policy",
            "scaling_claim_source",
            "scaling_claim_status",
            "scaling_claim_blockers",
            "timeout_provenance_schema",
            "timeout_scope",
            "timeout_ms",
            "timeout_seconds",
            "timeout_source",
            "timeout_enforced_by",
            "timeout_exit_code",
            "timeout_exit_code_means_timed_out",
        ]),
        "pareas_source" => string_set(["pareas_source_path", "pareas_source_line_count"]),
        "pareas_source_sha256" => string_set(["pareas_source_sha256"]),
        "pareas_binary_sha256" => string_set(["pareas_binary_sha256"]),
        "pareas_output" => string_set(["pareas_exit_status"]),
        "pareas_stdout" => string_set(["pareas_wall_elapsed_ms", "lanius_pareas_wall_ratio"]),
        "pareas_vram_csv" => string_set(["pareas_max_vram_bytes", "pareas_nvidia_smi_exit_status"]),
        other => panic!("no claim fields contract for artifact {other:?}"),
    }
}

fn required_readback_summary_field_names() -> BTreeSet<String> {
    string_set([
        "readback_summary_schema",
        "line_count",
        "source",
        "phase",
        "target",
        "trace_path",
        "readback_timeout_ms",
        "steady_readback_claim_source",
        "span_count",
        "total_ms",
        "max_span_ms",
    ])
}

fn required_vram_csv_columns() -> BTreeSet<String> {
    string_set([
        "timestamp",
        "index",
        "name",
        "memory.used",
        "memory.total",
        "utilization.gpu",
    ])
}

fn required_hardware_identity_field_names() -> BTreeSet<String> {
    string_set([
        "hardware_identity_schema",
        "target",
        "uname",
        "nvidia_smi_status",
    ])
}

fn required_command_environment_field_names() -> BTreeSet<String> {
    string_set([
        "command_environment_schema",
        "timestamp_utc",
        "cwd",
        "line_count",
        "source",
        "phase",
        "target",
        "iterations",
        "measurement_timing_policy",
        "cold_start_policy",
        "cold_gpu_pipeline_init_policy",
        "compile_latency_claim_source",
        "steady_compile_latency_claim_source",
        "steady_readback_claim_source",
        "runtime_validation_policy",
        "workload_shape_policy",
        "workload_shape_scope",
        "workload_generalization_status",
        "workload_generalization_blockers",
        "link_artifact_evidence_policy",
        "link_artifact_evidence_schema",
        "link_artifact_required_evidence_classes",
        "link_artifact_evidence_status",
        "link_artifact_claim_blockers",
        "baseline_separation_schema",
        "local_evidence_status_policy",
        "claim_provenance_schema",
        "paper_baseline_policy",
        "paper_baseline_numbers_status",
        "paper_baseline_claim_status",
        "local_performance_claim_policy",
        "local_performance_claim_source",
        "local_performance_claim_status",
        "local_performance_claim_blockers",
        "local_vram_claim_source",
        "local_pareas_claim_source",
        "scaling_claim_policy",
        "scaling_claim_source",
        "scaling_claim_status",
        "scaling_claim_blockers",
        "timeout_provenance_schema",
        "timeout_scope",
        "timeout_source",
        "timeout_ms",
        "timeout_seconds",
        "readback_timeout_ms",
        "vram_sample_interval_ms",
        "source_seed",
        "responsiveness_probe_timeout_ms",
        "responsiveness_probe_timeout_seconds",
        "git_head",
        "rustc_version",
        "cargo_version",
        "slangc_version",
    ])
}

fn required_timeout_provenance_field_names() -> BTreeSet<String> {
    string_set([
        "timeout_provenance_schema",
        "timeout_scope",
        "timeout_ms",
        "timeout_seconds",
        "timeout_source",
        "timeout_enforced_by",
        "timeout_exit_code",
        "timeout_exit_code_means_timed_out",
    ])
}

fn required_responsiveness_probe_field_names() -> BTreeSet<String> {
    string_set([
        "responsiveness_probe_schema",
        "line_count",
        "source",
        "phase",
        "target",
        "timeout_ms",
        "timeout_seconds",
        "probe_command",
        "probe_exit_status",
        "responsive",
        "elapsed_ms",
    ])
}

fn required_evidence_status_field_names() -> BTreeSet<String> {
    string_set([
        "evidence_status_schema",
        "local_performance_evidence_status",
        "local_readback_evidence_status",
        "local_vram_evidence_status",
        "local_pareas_evidence_status",
        "local_pareas_vram_evidence_status",
        "link_artifact_evidence_schema",
        "link_artifact_required_evidence_classes",
        "link_artifact_evidence_status",
        "link_artifact_claim_blockers",
        "local_performance_claim_status",
        "local_performance_claim_blockers",
        "scaling_claim_status",
        "scaling_claim_blockers",
        "production_readiness_evidence_complete",
        "production_readiness_blockers",
    ])
}

fn required_evidence_freshness_field_names() -> BTreeSet<String> {
    string_set([
        "evidence_freshness_schema",
        "evidence_freshness_status",
        "stale_artifacts",
        "stale_artifact_checks",
    ])
}

fn required_claim_readiness_field_names() -> BTreeSet<String> {
    string_set([
        "claim_readiness_schema",
        "claim_readiness_policy",
        "claim_readiness_required_evidence_classes",
        "claim_readiness_required_statuses",
        "claim_readiness_status",
        "claimable_measurement_claims",
        "claim_readiness_blockers",
    ])
}

fn required_status_field_names() -> BTreeSet<String> {
    string_set([
        "command_status_schema",
        "lanius_exit_status",
        "lanius_wall_elapsed_ms",
        "measurement_timing_policy",
        "cold_start_policy",
        "cold_gpu_pipeline_init_policy",
        "compile_latency_claim_source",
        "steady_compile_latency_claim_source",
        "steady_readback_claim_source",
        "runtime_validation_policy",
        "link_artifact_evidence_policy",
        "link_artifact_evidence_schema",
        "link_artifact_required_evidence_classes",
        "link_artifact_evidence_status",
        "link_artifact_claim_blockers",
        "timeout_provenance_schema",
        "timeout_scope",
        "timeout_ms",
        "timeout_seconds",
        "timeout_source",
        "timeout_enforced_by",
        "timeout_exit_code",
        "timeout_exit_code_means_timed_out",
        "line_count",
        "source",
        "phase",
        "target",
        "source_seed",
        "iterations",
        "readback_timeout_ms",
        "machine_responsive_after",
        "responsiveness_probe_status",
        "responsiveness_probe_path",
        "lanius_stdout_path",
        "perfetto_trace_path",
        "resource_usage_status",
        "resource_usage_path",
    ])
}

fn optional_status_field_names() -> BTreeSet<String> {
    string_set([
        "nvidia_smi_exit_status",
        "vram_sample_interval_ms",
        "vram_output_path",
        "pareas_exit_status",
        "pareas_wall_elapsed_ms",
        "pareas_bin_path",
        "pareas_source_path",
        "pareas_output_path",
        "pareas_stdout_path",
        "pareas_nvidia_smi_exit_status",
        "pareas_vram_output_path",
    ])
}

fn required_summary_field_names() -> BTreeSet<String> {
    string_set([
        "measurement_summary_schema",
        "line_count",
        "source",
        "phase",
        "target",
        "evidence_provenance",
        "measurement_evidence_policy",
        "paper_numbers_accepted",
        "baseline_separation_schema",
        "comparison_baseline_policy",
        "local_evidence_status_policy",
        "freshness_policy",
        "measurement_timing_policy",
        "cold_start_policy",
        "cold_gpu_pipeline_init_policy",
        "compile_latency_claim_source",
        "steady_compile_latency_claim_source",
        "steady_readback_claim_source",
        "runtime_validation_policy",
        "workload_shape_policy",
        "workload_shape_scope",
        "workload_generalization_status",
        "workload_generalization_blockers",
        "link_artifact_evidence_policy",
        "link_artifact_evidence_schema",
        "link_artifact_required_evidence_classes",
        "link_artifact_evidence_status",
        "link_artifact_claim_blockers",
        "claim_provenance_schema",
        "paper_baseline_policy",
        "paper_baseline_numbers_status",
        "paper_baseline_claim_status",
        "local_performance_claim_policy",
        "local_performance_claim_source",
        "local_performance_claim_exclusions",
        "local_performance_claim_status",
        "local_performance_claim_blockers",
        "local_vram_claim_source",
        "local_pareas_claim_source",
        "scaling_claim_policy",
        "scaling_claim_source",
        "scaling_claim_status",
        "scaling_claim_blockers",
        "timeout_provenance_schema",
        "timeout_scope",
        "timeout_source",
        "timeout_enforced_by",
        "timeout_exit_code",
        "timeout_exit_code_means_timed_out",
        "source_control_policy",
        "source_control_state",
        "source_control_revision",
        "repeatability_policy",
        "minimum_iterations_for_claim",
        "repeatability_status",
        "required_artifacts_complete",
        "missing_required_artifacts",
        "evidence_status_schema",
        "local_performance_evidence_status",
        "local_readback_evidence_status",
        "local_vram_evidence_status",
        "local_pareas_evidence_status",
        "local_pareas_vram_evidence_status",
        "link_artifact_evidence_status",
        "link_artifact_claim_blockers",
        "production_readiness_evidence_complete",
        "production_readiness_blockers",
        "evidence_freshness_schema",
        "evidence_freshness_status",
        "stale_artifacts",
        "stale_artifact_checks",
        "claim_readiness_schema",
        "claim_readiness_policy",
        "claim_readiness_required_evidence_classes",
        "claim_readiness_required_statuses",
        "claim_readiness_status",
        "claimable_measurement_claims",
        "claim_readiness_blockers",
        "claim_scope_policy",
        "claim_scope_key",
        "source_seed",
        "iterations",
        "timeout_ms",
        "timeout_seconds",
        "readback_timeout_ms",
        "vram_sample_interval_ms",
        "lanius_exit_status",
        "timed_out",
        "lanius_wall_elapsed_ms",
        "best_ms",
        "throughput_lines_per_second",
        "readback_span_count",
        "readback_total_ms",
        "readback_max_span_ms",
        "max_vram_bytes",
        "nvidia_smi_exit_status",
        "pareas_max_vram_bytes",
        "pareas_nvidia_smi_exit_status",
        "resource_user_seconds",
        "resource_system_seconds",
        "resource_max_rss_kb",
        "resource_usage_status",
        "source_replay_line_count",
        "source_sha256",
        "bench_binary_sha256",
        "hardware_identity_sha256",
        "command_environment_sha256",
        "machine_responsive_after",
        "responsiveness_probe_status",
        "pareas_exit_status",
        "pareas_timed_out",
        "pareas_wall_elapsed_ms",
        "pareas_source_line_count",
        "pareas_source_sha256",
        "pareas_binary_sha256",
        "lanius_pareas_wall_ratio",
        "lanius_stdout_path",
        "perfetto_trace_path",
        "readback_summary_path",
        "vram_output_path",
        "source_replay_path",
        "source_sha256_path",
        "bench_binary_sha256_path",
        "hardware_output_path",
        "command_env_path",
        "command_status_path",
        "responsiveness_probe_path",
        "resource_usage_path",
        "pareas_source_path",
        "pareas_source_sha256_path",
        "pareas_binary_sha256_path",
        "pareas_output_path",
        "pareas_stdout_path",
        "pareas_vram_output_path",
    ])
}

fn parallel_pass_contract_groups() -> BTreeSet<String> {
    string_set([
        "record_invariant",
        "semantic_contract",
        "execution_contract",
        "measurement_scaffold",
    ])
}

fn required_parallel_pass_contract_field_names() -> BTreeSet<String> {
    string_set([
        "contract_schema",
        "pass_group",
        "paper_pass_stage",
        "record_boundary",
        "parallel_primitives",
        "evidence_shape",
        "loop_status",
        "fallback_status",
        "claim_boundary",
    ])
}

fn required_pass_contract_status_field_names() -> BTreeSet<String> {
    string_set([
        "pass_contract_status_schema",
        "pass_contract_loop_policy",
        "pass_contract_loop_status",
        "pass_contract_fallback_status",
        "pass_contract_claim_status",
        "pass_contract_claim_blockers",
        "pass_contract_readiness_status",
    ])
}

fn parallel_pass_artifact_field_names() -> BTreeSet<String> {
    string_set([
        "paper_pass_order_schema",
        "paper_pass_order_source",
        "paper_pass_order",
        "paper_pass_alignment_policy",
        "paper_pass_alignment_status",
        "paper_pass_alignment_blockers",
        "parallel_pass_contract_schema",
        "parallel_pass_contract_policy",
        "parallel_pass_contract_groups",
        "parallel_pass_contract_order_policy",
        "parallel_pass_contract_execution_order",
        "pass_contract_status_schema",
        "pass_contract_loop_policy",
        "pass_contract_loop_status",
        "pass_contract_fallback_status",
        "pass_contract_claim_status",
        "pass_contract_claim_blockers",
        "pass_contract_readiness_status",
        "shader_loop_audit_summary",
        "shader_loop_audit_blocker",
    ])
}

#[test]
fn compiler_acceptance_readiness_check_plan_validates_measurement_inventory() {
    let output = run_acceptance_script(&["--tier", "readiness", "--check-plan"], |_| {});
    let status = parse_acceptance_plan_status(&output);

    assert_eq!(required_plan_field(&status, "status"), "ok");
    assert_eq!(required_plan_field(&status, "tier"), "readiness");
    assert_eq!(required_plan_field(&status, "mode"), "no-run");

    for name in [
        "invalid_tests",
        "missing_tests",
        "missing_commands",
        "evidence_inventory_errors",
        "language_slice_errors",
    ] {
        assert_zero_plan_counter(&status, name);
    }

    for name in [
        "checked_tests",
        "checked_commands",
        "focused_evidence",
        "smoke_evidence",
        "properties_evidence",
        "language_slice_rows",
        "language_slice_public_boundary_evidence",
        "language_slice_artifact_contract_evidence",
        "language_slice_record_invariant_evidence",
        "language_slice_semantic_contract_evidence",
        "language_slice_execution_contract_evidence",
        "language_slice_fail_closed_evidence",
        "language_slice_measurement_scaffold_evidence",
        "language_slice_parser_type_relation_evidence",
        "language_slice_performance_claim_guards",
        "language_slice_external_tooling_gate_evidence",
    ] {
        assert_positive_plan_counter(&status, name);
    }

    for name in [
        "property_boundary_evidence",
        "property_record_evidence",
        "property_execution_evidence",
        "property_semantic_evidence",
    ] {
        assert_eq!(
            plan_counter(&status, name),
            1,
            "{name} should be covered by the properties lane inventory"
        );
    }
}

#[test]
fn compiler_acceptance_readiness_rejects_planned_object_link_pipeline_evidence_fixture() {
    let _guard = acceptance_script_mutex()
        .lock()
        .expect("acceptance script lock should not be poisoned");
    let fixture = TemporaryLanguageSliceFixture::replace_row(
        "linking",
        "object-link-pipeline",
        [
            "linking",
            "object-link-pipeline",
            "planned",
            "integration:source_pack_package_boundaries",
            "source_pack_link_execution_resume_requires_final_page_sidecar_evidence",
            "artifact-contract",
            "descriptor contract records exist but real object/relocation/native link emission remains incomplete",
        ],
    );

    let failure =
        run_acceptance_script_failure_locked(&["--tier", "readiness", "--check-plan"], |_| {});
    drop(fixture);

    assert!(
        failure
            .stderr
            .contains("linking/object-link-pipeline has status 'planned' but cites evidence"),
        "readiness gate should reject evidence attached to the planned link-pipeline row\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure
            .stderr
            .contains("planned rows cannot cite production evidence"),
        "planned rows must not be counted as production evidence\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure
            .stderr
            .contains("promote to bounded only with behavior-facing link-pipeline evidence"),
        "link-pipeline promotion should require behavior-facing evidence\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[test]
fn compiler_acceptance_readiness_rejects_lsp_capabilities_without_claim_boundaries_fixture() {
    let _guard = acceptance_script_mutex()
        .lock()
        .expect("acceptance script lock should not be poisoned");
    let fixture = TemporaryLanguageSliceFixture::replace_row(
        "tooling",
        "lsp-capabilities",
        [
            "tooling",
            "lsp-capabilities",
            "bounded",
            "integration:cli_lsp",
            "cli_lsp_capabilities_reports_no_run_diagnostic_contract",
            "public-boundary",
            "LSP capability metadata exposes diagnostic registry source severity UTF-16 position contract distribution release boundary JSON-RPC error-data schema identity stdio handshake methods explicit no-run guards including source-scanning false and single-open-document pull-diagnostic scope with no workspace publish result-id source-root or stdlib-root claims",
        ],
    );

    let failure =
        run_acceptance_script_failure_locked(&["--tier", "readiness", "--check-plan"], |_| {});
    drop(fixture);

    assert!(
        failure.stderr.contains(
            "tooling/lsp-capabilities LSP capabilities evidence must publish explicit non-performance and non-production claim boundaries"
        ),
        "readiness gate should reject LSP capability evidence without claim-boundary metadata\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[test]
fn compiler_acceptance_generated_run_requires_scale_opt_in() {
    let failure = run_acceptance_script_failure(&["--tier", "generated", "--run"], |_| {});
    assert!(
        failure.stdout.is_empty(),
        "scale opt-in rejection should happen before printing runnable commands\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure
            .stderr
            .contains("requires --allow-scale or LANIUS_ACCEPTANCE_ALLOW_SCALE=1 with --run"),
        "generated execution should require an explicit scale opt-in\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[test]
fn compiler_acceptance_readiness_run_is_always_no_run_inventory() {
    let failure = run_acceptance_script_failure(&["--tier", "readiness", "--run"], |_| {});
    assert!(
        failure.stdout.is_empty(),
        "readiness execution rejection should happen before printing runnable commands\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
    assert!(
        failure
            .stderr
            .contains("tier 'readiness' is a no-run tracking inventory"),
        "readiness tier must stay no-run instead of executing the full inventory\nstdout:\n{}\nstderr:\n{}",
        failure.stdout,
        failure.stderr
    );
}

#[derive(Debug, Eq, PartialEq)]
struct ParseMetrics {
    token_count: u64,
    parser_tree_capacity: u64,
    parser_emit_len: u64,
    semantic_hir_count: u64,
}

fn parse_metric_line(line: &str) -> ParseMetrics {
    ParseMetrics {
        token_count: parse_u64_field(line, "token_count").expect("token_count"),
        parser_tree_capacity: parse_u64_field(line, "parser_tree_capacity")
            .expect("parser_tree_capacity"),
        parser_emit_len: parse_u64_field(line, "parser_emit_len").expect("parser_emit_len"),
        semantic_hir_count: parse_u64_field(line, "semantic_hir_count")
            .expect("semantic_hir_count"),
    }
}

fn parse_metrics_for_source(output: &str, source: &str) -> ParseMetrics {
    let marker = format!("source={source}");
    let mut previous_metrics = None;
    for line in output.lines() {
        if line.contains("phase=parse token_count=") {
            previous_metrics = Some(parse_metric_line(line));
        } else if line.contains(&marker) {
            return previous_metrics
                .take()
                .unwrap_or_else(|| panic!("missing parse metrics before {marker}"));
        }
    }
    panic!("suite output should include {marker}");
}

fn run_success(bin: &Path, args: &[&str]) -> String {
    run_success_timed(bin, args).stdout
}

struct TimedOutput {
    stdout: String,
}

fn run_success_timed(bin: &Path, args: &[&str]) -> TimedOutput {
    run_success_timed_owned(
        bin,
        &args.iter().map(|arg| (*arg).into()).collect::<Vec<_>>(),
    )
}

fn run_success_timed_owned(bin: &Path, args: &[OsString]) -> TimedOutput {
    let command = Command::new(bin);
    run_command_success_timed(command, bin, args)
}

fn run_acceptance_script(args: &[&str], configure: impl FnOnce(&mut Command)) -> String {
    let _guard = acceptance_script_mutex()
        .lock()
        .expect("acceptance script lock should not be poisoned");
    run_acceptance_script_locked(args, configure)
}

fn run_acceptance_script_locked(args: &[&str], configure: impl FnOnce(&mut Command)) -> String {
    let bash = PathBuf::from("/bin/bash");
    let script = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tools/compiler_acceptance.sh");
    let mut command = Command::new(&bash);
    clear_acceptance_environment(&mut command);
    configure(&mut command);
    let mut owned_args = Vec::with_capacity(args.len() + 1);
    owned_args.push(script.as_os_str().to_owned());
    owned_args.extend(args.iter().map(OsString::from));
    run_command_success_timed(command, &bash, &owned_args).stdout
}

struct ScriptFailure {
    stdout: String,
    stderr: String,
}

fn run_acceptance_script_failure(
    args: &[&str],
    configure: impl FnOnce(&mut Command),
) -> ScriptFailure {
    let _guard = acceptance_script_mutex()
        .lock()
        .expect("acceptance script lock should not be poisoned");
    run_acceptance_script_failure_locked(args, configure)
}

fn run_acceptance_script_failure_locked(
    args: &[&str],
    configure: impl FnOnce(&mut Command),
) -> ScriptFailure {
    let bash = PathBuf::from("/bin/bash");
    let script = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tools/compiler_acceptance.sh");
    let mut command = Command::new(&bash);
    clear_acceptance_environment(&mut command);
    configure(&mut command);
    let mut owned_args = Vec::with_capacity(args.len() + 1);
    owned_args.push(script.as_os_str().to_owned());
    owned_args.extend(args.iter().map(OsString::from));
    let output = command
        .args(&owned_args)
        .output()
        .unwrap_or_else(|err| panic!("run {}: {err}", bash.display()));
    assert!(
        !output.status.success(),
        "{} {:?} unexpectedly succeeded\nstdout:\n{}\nstderr:\n{}",
        bash.display(),
        owned_args,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    ScriptFailure {
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    }
}

struct TemporaryLanguageSliceFixture {
    path: PathBuf,
    original: String,
}

impl TemporaryLanguageSliceFixture {
    fn replace_row(kind: &str, id: &str, replacement_fields: [&str; 7]) -> Self {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("docs")
            .join("language_slice_unstable_alpha.tsv");
        let original = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read language-slice fixture {}: {err}", path.display()));
        let mut replaced = false;
        let mut updated = String::new();
        for line in original.lines() {
            if !updated.is_empty() {
                updated.push('\n');
            }
            let fields = line.split('\t').collect::<Vec<_>>();
            if fields.len() >= 2 && fields[0] == kind && fields[1] == id {
                updated.push_str(&replacement_fields.join("\t"));
                replaced = true;
            } else {
                updated.push_str(line);
            }
        }
        if original.ends_with('\n') {
            updated.push('\n');
        }
        assert!(
            replaced,
            "language-slice row {kind}/{id} should exist in {}",
            path.display()
        );
        fs::write(&path, updated)
            .unwrap_or_else(|err| panic!("write language-slice fixture {}: {err}", path.display()));
        Self { path, original }
    }
}

impl Drop for TemporaryLanguageSliceFixture {
    fn drop(&mut self) {
        if let Err(err) = fs::write(&self.path, &self.original) {
            eprintln!(
                "failed to restore language-slice fixture {}: {err}",
                self.path.display()
            );
        }
    }
}

fn acceptance_script_mutex() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn run_bash_command_line_success(command_line: &str) {
    let output = Command::new("/bin/bash")
        .arg("-lc")
        .arg(command_line)
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .expect("run generated no-run shell command");
    assert!(
        output.status.success(),
        "generated no-run shell command failed with status {:?}\ncommand:\n{}\nstdout:\n{}\nstderr:\n{}",
        output.status.code(),
        command_line,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn clear_acceptance_environment(command: &mut Command) {
    for name in [
        "NVIDIA_SMI",
        "LANIUS_REQUIRE_NVIDIA_SMI",
        "PAREAS_BIN",
        "LANIUS_REQUIRE_PAREAS",
        "LANIUS_ALLOW_LARGE_GENERATED_TESTS",
        "LANIUS_ACCEPTANCE_ALLOW_SCALE",
        "LANIUS_PERF_CHECKPOINT_LINES",
        "LANIUS_PERF_LINES",
        "LANIUS_PERF_SEED",
        "LANIUS_PERF_ITERS",
        "LANIUS_PERF_COMMAND_TIMEOUT_MS",
        "LANIUS_X86_READBACK_TIMEOUT_MS",
        "LANIUS_VRAM_SAMPLE_INTERVAL_MS",
        "LANIUS_RESPONSIVENESS_PROBE_TIMEOUT_MS",
        "LANIUS_PERF_SOURCE",
        "LANIUS_PERF_PHASE",
        "LANIUS_PERF_OUTPUT_PATH",
        "LANIUS_PERFETTO_TRACE",
        "LANIUS_READBACK_SUMMARY_OUTPUT_PATH",
        "LANIUS_VRAM_OUTPUT_PATH",
        "LANIUS_SOURCE_REPLAY_OUTPUT_PATH",
        "LANIUS_SOURCE_SHA256_OUTPUT_PATH",
        "LANIUS_BENCH_SHA256_OUTPUT_PATH",
        "LANIUS_HARDWARE_OUTPUT_PATH",
        "LANIUS_COMMAND_ENV_OUTPUT_PATH",
        "LANIUS_COMMAND_STATUS_OUTPUT_PATH",
        "LANIUS_RESPONSIVENESS_OUTPUT_PATH",
        "LANIUS_RESOURCE_USAGE_OUTPUT_PATH",
        "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH",
        "LANIUS_PAREAS_SOURCE_PATH",
        "LANIUS_PAREAS_SOURCE_SHA256_OUTPUT_PATH",
        "LANIUS_PAREAS_BINARY_SHA256_OUTPUT_PATH",
        "LANIUS_PAREAS_OUTPUT_PATH",
        "LANIUS_PAREAS_STDOUT_PATH",
        "LANIUS_PAREAS_VRAM_OUTPUT_PATH",
    ] {
        command.env_remove(name);
    }
}

fn run_command_success_timed(mut command: Command, bin: &Path, args: &[OsString]) -> TimedOutput {
    if env::var_os("LANIUS_X86_READBACK_TIMEOUT_MS").is_none() {
        command.env(
            "LANIUS_X86_READBACK_TIMEOUT_MS",
            GENERATED_X86_READBACK_TIMEOUT_MS,
        );
    }
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let timeout = generated_gate_command_timeout();
    let start = Instant::now();
    let mut child = command
        .args(args)
        .spawn()
        .unwrap_or_else(|err| panic!("run {}: {err}", bin.display()));
    let mut stdout = child
        .stdout
        .take()
        .unwrap_or_else(|| panic!("capture {} stdout", bin.display()));
    let mut stderr = child
        .stderr
        .take()
        .unwrap_or_else(|| panic!("capture {} stderr", bin.display()));
    let stdout_reader = thread::spawn(move || {
        let mut output = Vec::new();
        stdout
            .read_to_end(&mut output)
            .expect("read command stdout");
        output
    });
    let stderr_reader = thread::spawn(move || {
        let mut output = Vec::new();
        stderr
            .read_to_end(&mut output)
            .expect("read command stderr");
        output
    });

    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(err) => panic!("wait for {}: {err}", bin.display()),
        }

        if start.elapsed() >= timeout {
            if let Err(err) = child.kill() {
                eprintln!(
                    "failed to terminate timed-out generated gate command {}: {err}",
                    bin.display()
                );
            }
            let status = child
                .wait()
                .unwrap_or_else(|err| panic!("collect timed-out {} status: {err}", bin.display()));
            let stdout = stdout_reader
                .join()
                .expect("stdout reader thread should not panic");
            let stderr = stderr_reader
                .join()
                .expect("stderr reader thread should not panic");
            panic!(
                "{} {:?} timed out after {} ms with status {:?}\nstdout:\n{}\nstderr:\n{}",
                bin.display(),
                args,
                timeout.as_millis(),
                status.code(),
                String::from_utf8_lossy(&stdout),
                String::from_utf8_lossy(&stderr)
            );
        }

        thread::sleep(Duration::from_millis(CHILD_PROCESS_POLL_INTERVAL_MS));
    };
    let stdout = stdout_reader
        .join()
        .expect("stdout reader thread should not panic");
    let stderr = stderr_reader
        .join()
        .expect("stderr reader thread should not panic");
    assert!(
        status.success(),
        "{} {:?} failed with status {:?}\nstdout:\n{}\nstderr:\n{}",
        bin.display(),
        args,
        status.code(),
        String::from_utf8_lossy(&stdout),
        String::from_utf8_lossy(&stderr)
    );
    TimedOutput {
        stdout: String::from_utf8_lossy(&stdout).into_owned(),
    }
}

fn parse_u64_field(text: &str, name: &str) -> Option<u64> {
    parse_field(text, name)?.parse().ok()
}

fn parse_u64_values(text: &str, name: &str) -> Vec<u64> {
    text.lines()
        .filter_map(|line| parse_u64_field(line, name))
        .collect()
}

fn parse_bool_field(text: &str, name: &str) -> Option<bool> {
    match parse_field(text, name)? {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

fn line_containing<'a>(text: &'a str, marker: &str) -> &'a str {
    text.lines()
        .find(|line| line.contains(marker))
        .unwrap_or_else(|| panic!("output should include {marker:?}"))
}

fn parse_field<'a>(text: &'a str, name: &str) -> Option<&'a str> {
    let prefix = format!("{name}=");
    text.split_ascii_whitespace()
        .find_map(|word| word.strip_prefix(&prefix))
}

fn generated_lines() -> String {
    bounded_positive_usize_env(
        "LANIUS_GENERATED_LINES",
        DEFAULT_GENERATED_LINES,
        MAX_GENERATED_LINES_WITHOUT_OPT_IN,
    )
    .to_string()
}

fn capacity_stress_lines() -> String {
    bounded_positive_usize_env(
        "LANIUS_CAPACITY_STRESS_LINES",
        DEFAULT_CAPACITY_STRESS_LINES,
        MAX_CAPACITY_STRESS_LINES_WITHOUT_OPT_IN,
    )
    .to_string()
}

fn capacity_stress_source() -> String {
    env::var("LANIUS_CAPACITY_STRESS_SOURCE")
        .unwrap_or_else(|_| DEFAULT_CAPACITY_STRESS_SOURCE.to_string())
}

fn max_capacity_stress_compile_floor_bytes() -> u64 {
    env::var("LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES")
        .map(|value| parse_u64_env_value("LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES", &value))
        .unwrap_or(DEFAULT_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES)
}

fn generated_gate_command_timeout() -> Duration {
    env::var("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS")
        .map(|value| {
            let milliseconds =
                parse_u64_env_value("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS", &value);
            assert!(
                milliseconds > 0,
                "LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS must be greater than zero"
            );
            Duration::from_millis(milliseconds)
        })
        .unwrap_or_else(|_| Duration::from_millis(DEFAULT_GENERATED_GATE_COMMAND_TIMEOUT_MS))
}

fn parse_usize_env_value(name: &str, value: &str) -> usize {
    value
        .parse()
        .unwrap_or_else(|_| panic!("{name} must be an integer, got {value:?}"))
}

fn bounded_positive_usize_env(name: &str, default_value: &str, max_without_opt_in: usize) -> usize {
    let value = env::var(name).unwrap_or_else(|_| default_value.to_string());
    let count = parse_usize_env_value(name, &value);
    assert!(count > 0, "{name} must be greater than zero");
    assert!(
        count <= max_without_opt_in || env_truthy(ALLOW_LARGE_GENERATED_TESTS_ENV),
        "{name}={count} exceeds the default test guardrail {max_without_opt_in}; set {ALLOW_LARGE_GENERATED_TESTS_ENV}=1 to run an intentionally larger generated gate"
    );
    count
}

fn parse_u64_env_value(name: &str, value: &str) -> u64 {
    value
        .parse()
        .unwrap_or_else(|_| panic!("{name} must be an integer, got {value:?}"))
}

fn gpu_compile_bench_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_gpu_compile_bench")
        .map(PathBuf::from)
        .or_else(debug_gpu_compile_bench_bin)
        .or_else(release_gpu_compile_bench_bin)
        .unwrap_or_else(|| PathBuf::from("target/debug/gpu_compile_bench"))
}

fn debug_gpu_compile_bench_bin() -> Option<PathBuf> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/gpu_compile_bench");
    path.exists().then_some(path)
}

fn release_gpu_compile_bench_bin() -> Option<PathBuf> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/release/gpu_compile_bench");
    path.exists().then_some(path)
}

fn pareas_bin() -> Option<PathBuf> {
    if let Ok(path) = env::var("PAREAS_BIN") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Some(path);
        }
    }
    let home = env::var("HOME").ok().map(PathBuf::from)?;
    [
        home.join("code/pareas/build-laniusc-cuda-futhark025/pareas"),
        home.join("code/pareas/build-laniusc-cuda/pareas"),
        home.join("code/pareas/build-laniusc-c/pareas"),
        home.join("code/pareas/build/pareas"),
        home.join("code/pareas/build/src/pareas"),
        home.join("code/pareas/builddir/pareas"),
        home.join("code/pareas/builddir/src/pareas"),
    ]
    .into_iter()
    .find(|path| path.exists())
}

fn unique_temp_path(stem: &str, ext: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_nanos();
    env::temp_dir().join(format!("{stem}_{}_{}.{}", std::process::id(), nanos, ext))
}

fn unique_temp_dir(stem: &str) -> PathBuf {
    let path = unique_temp_path(stem, "dir");
    fs::create_dir_all(&path).expect("create temp dir");
    path
}

fn install_cat_on_path(dir: &Path) {
    install_command_on_path(dir, "cat");
    install_system_command_on_path(dir, "awk");
    install_system_command_on_path(dir, "sort");
}

fn install_command_on_path(dir: &Path, name: &str) {
    let cat = ["/bin/cat", "/usr/bin/cat"]
        .into_iter()
        .map(Path::new)
        .find(|path| path.is_file())
        .expect("cat command should exist for shell heredocs");
    std::os::unix::fs::symlink(cat, dir.join(name)).expect("link command into isolated PATH");
}

fn install_system_command_on_path(dir: &Path, name: &str) {
    let command = [format!("/bin/{name}"), format!("/usr/bin/{name}")]
        .into_iter()
        .map(PathBuf::from)
        .find(|path| path.is_file())
        .unwrap_or_else(|| panic!("{name} command should exist for measurement-plan tests"));
    std::os::unix::fs::symlink(&command, dir.join(name))
        .unwrap_or_else(|err| panic!("link {} into isolated PATH: {err}", command.display()));
}

fn env_truthy(name: &str) -> bool {
    env::var(name).is_ok_and(|value| {
        matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        )
    })
}
