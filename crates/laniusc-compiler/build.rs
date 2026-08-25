use std::{
    collections::BTreeMap,
    env,
    fs,
    io,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

fn main() {
    const DEFAULT_SLANGC_VERSION_TIMEOUT_MS: u64 = 2_000;
    const DEFAULT_SHADER_COMPILE_TIMEOUT_MS: u64 = 120_000;

    println!("cargo:rerun-if-env-changed=CARGO_TARGET_DIR");
    println!("cargo:rerun-if-env-changed=SLANGC");
    println!("cargo:rerun-if-env-changed=LANIUS_SLANGC_VERSION_TIMEOUT_MS");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_COMPILE_TIMEOUT_MS");

    let workspace_root = workspace_root();
    generate_lowering_ir_opcodes(&workspace_root);
    let slangc_version_timeout = timeout_from_env_ms(
        "LANIUS_SLANGC_VERSION_TIMEOUT_MS",
        DEFAULT_SLANGC_VERSION_TIMEOUT_MS,
    );
    let shader_compile_timeout = timeout_from_env_ms(
        "LANIUS_SHADER_COMPILE_TIMEOUT_MS",
        DEFAULT_SHADER_COMPILE_TIMEOUT_MS,
    );
    let slangc_version = find_slangc()
        .map(|slangc| slangc_version(&slangc, slangc_version_timeout))
        .unwrap_or_else(|| "unknown".to_string());

    println!(
        "cargo:rerun-if-changed={}",
        workspace_root.join("Cargo.lock").display()
    );
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rustc-env=LANIUS_SLANGC_VERSION={slangc_version}");
    println!(
        "cargo:rustc-env=LANIUS_SLANGC_VERSION_TIMEOUT_MS={}",
        timeout_metadata_value(slangc_version_timeout)
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_COMPILE_TIMEOUT_MS={}",
        timeout_metadata_value(shader_compile_timeout)
    );
    println!(
        "cargo:rustc-env=LANIUS_WGPU_VERSION={}",
        cargo_lock_package_version(&workspace_root, "wgpu")
            .unwrap_or_else(|| "unknown".to_string())
    );
    println!(
        "cargo:rustc-env=LANIUS_BUILD_PROFILE={}",
        env::var("PROFILE").unwrap_or_else(|_| "unknown".to_string())
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_ROOT={}",
        shader_artifact_root(&workspace_root).display()
    );
}

fn generate_lowering_ir_opcodes(workspace_root: &Path) {
    let source = workspace_root.join("shaders/codegen/lowering_ir.slang");
    println!("cargo:rerun-if-changed={}", source.display());
    let text = fs::read_to_string(&source)
        .unwrap_or_else(|err| panic!("read lowering IR schema {}: {err}", source.display()));
    let mut generated = String::from("// Generated from shaders/codegen/lowering_ir.slang.\n");
    let lines = text.lines().map(str::trim).collect::<Vec<_>>();
    let mut marked = false;
    let mut count = 0usize;
    let mut semantic_opcodes = BTreeMap::<u32, String>::new();
    let mut semantic_opcode_count = None;
    for &line in &lines {
        if line == "// IR_OPCODE" {
            marked = true;
            continue;
        }
        if !marked {
            continue;
        }
        marked = false;
        let declaration = line
            .strip_prefix("static const uint ")
            .unwrap_or_else(|| panic!("IR_OPCODE must precede a uint constant, found {line:?}"));
        let (name, value) = declaration
            .split_once('=')
            .unwrap_or_else(|| panic!("malformed lowering IR opcode {line:?}"));
        let name = name.trim();
        let value = value
            .trim()
            .strip_suffix(';')
            .and_then(|value| value.strip_suffix('u'))
            .unwrap_or_else(|| panic!("lowering IR opcode must end in `u;`: {line:?}"));
        generated.push_str(&format!("pub const {name}: u32 = {value};\n"));
        if name == "SEMANTIC_LIR_OP_COUNT" {
            semantic_opcode_count = Some(parse_schema_u32(value, name));
        } else if name.starts_with("SEMANTIC_LIR_OP_") && !name.starts_with("SEMANTIC_LIR_OP_FLAG_")
        {
            let value = parse_schema_u32(value, name);
            assert!(
                semantic_opcodes.insert(value, name.to_string()).is_none(),
                "duplicate semantic LIR opcode value {value}"
            );
        }
        count += 1;
    }
    assert!(count > 0, "lowering IR schema contains no marked opcodes");

    let semantic_opcode_count =
        semantic_opcode_count.expect("lowering IR schema must define SEMANTIC_LIR_OP_COUNT");
    assert_eq!(
        semantic_opcodes.len(),
        semantic_opcode_count as usize,
        "semantic opcode count does not cover the declared opcode namespace"
    );
    for value in 0..semantic_opcode_count {
        assert!(
            semantic_opcodes.contains_key(&value),
            "semantic opcode namespace is missing value {value}"
        );
    }

    let mut properties = BTreeMap::<u32, [u32; 8]>::new();
    for (index, line) in lines.iter().enumerate() {
        let Some(name) = line.strip_prefix("// IR_SEMANTIC_OP ") else {
            continue;
        };
        let (&opcode, _) = semantic_opcodes
            .iter()
            .find(|(_, opcode_name)| opcode_name.as_str() == name)
            .unwrap_or_else(|| panic!("semantic property row names unknown opcode {name}"));
        let record = lines
            .get(index + 1)
            .unwrap_or_else(|| panic!("semantic property row {name} has no record"));
        let record = record
            .strip_prefix('{')
            .and_then(|record| record.strip_suffix("},"))
            .unwrap_or_else(|| {
                panic!("semantic property row {name} must be one `{{ ... }},` line")
            });
        let fields = record
            .split(',')
            .map(str::trim)
            .filter(|field| !field.is_empty())
            .collect::<Vec<_>>();
        assert_eq!(
            fields.len(),
            8,
            "semantic property row {name} must contain eight uint fields"
        );
        let mut values = [0u32; 8];
        for (destination, field) in values.iter_mut().zip(fields) {
            *destination = parse_schema_u32(
                field
                    .strip_suffix('u')
                    .unwrap_or_else(|| panic!("semantic property value must end in `u`: {field}")),
                name,
            );
        }
        assert!(
            properties.insert(opcode, values).is_none(),
            "duplicate semantic property row for {name}"
        );
    }
    assert_eq!(
        properties.len(),
        semantic_opcode_count as usize,
        "every semantic opcode must have exactly one IR_SEMANTIC_OP property row"
    );

    generated.push_str(
        "\n#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]\n\
         pub struct SemanticLirOpProperties {\n\
         \x20   pub flags: u32,\n\
         \x20   pub operand_roles: u32,\n\
         \x20   pub result_kind: u32,\n\
         \x20   pub type_rule: u32,\n\
         \x20   pub control_role: u32,\n\
         \x20   pub effect: u32,\n\
         \x20   pub variadic_kind: u32,\n\
         \x20   pub arithmetic: u32,\n\
         }\n\n\
         impl SemanticLirOpProperties {\n\
         \x20   pub const fn has_flag(self, flag: u32) -> bool {\n\
         \x20       self.flags & flag != 0\n\
         \x20   }\n\n\
         \x20   pub const fn operand_role(self, ordinal: u32) -> u32 {\n\
         \x20       if ordinal < 3 {\n\
         \x20           (self.operand_roles >> (ordinal * 4)) & 0xf\n\
         \x20       } else {\n\
         \x20           SEMANTIC_LIR_OPERAND_NONE\n\
         \x20       }\n\
         \x20   }\n\
         }\n\n",
    );
    generated.push_str(&format!(
        "pub const SEMANTIC_LIR_OP_PROPERTIES: [SemanticLirOpProperties; {}] = [\n",
        semantic_opcode_count
    ));
    for opcode in 0..semantic_opcode_count {
        let name = &semantic_opcodes[&opcode];
        let [
            flags,
            operand_roles,
            result_kind,
            type_rule,
            control_role,
            effect,
            variadic_kind,
            arithmetic,
        ] = properties[&opcode];
        generated.push_str(&format!(
            "    SemanticLirOpProperties {{ flags: {flags}, operand_roles: {operand_roles}, result_kind: {result_kind}, type_rule: {type_rule}, control_role: {control_role}, effect: {effect}, variadic_kind: {variadic_kind}, arithmetic: {arithmetic} }}, // {name}\n"
        ));
    }
    generated.push_str("];\n\n");
    generated.push_str(&format!(
        "pub const SEMANTIC_LIR_OP_NAMES: [&str; {}] = [\n",
        semantic_opcode_count
    ));
    for opcode in 0..semantic_opcode_count {
        generated.push_str(&format!("    \"{}\",\n", semantic_opcodes[&opcode]));
    }
    generated.push_str(
        "];\n\n\
         pub const fn semantic_lir_op_properties(op: u32) -> SemanticLirOpProperties {\n\
         \x20   let index = if op < SEMANTIC_LIR_OP_COUNT { op } else { SEMANTIC_LIR_OP_INVALID };\n\
         \x20   SEMANTIC_LIR_OP_PROPERTIES[index as usize]\n\
         }\n",
    );
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR not set"));
    fs::write(out_dir.join("lowering_ir_opcodes.rs"), generated)
        .expect("write generated lowering IR opcodes");
}

fn parse_schema_u32(value: &str, name: &str) -> u32 {
    if let Some(value) = value.strip_prefix("0x") {
        u32::from_str_radix(value, 16)
            .unwrap_or_else(|err| panic!("invalid hexadecimal value for {name}: {err}"))
    } else {
        value
            .parse::<u32>()
            .unwrap_or_else(|err| panic!("invalid uint value for {name}: {err}"))
    }
}

fn workspace_root() -> PathBuf {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .expect("laniusc-compiler should live under crates/")
}

fn shader_artifact_root(workspace_root: &Path) -> PathBuf {
    let target_dir = env::var_os("CARGO_TARGET_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| workspace_root.join("target"));
    let profile = env::var("PROFILE").unwrap_or_else(|_| "debug".to_string());
    target_dir
        .join("laniusc-shader-artifacts")
        .join(profile)
        .join("shaders")
}

fn timeout_from_env_ms(name: &str, default_ms: u64) -> Option<Duration> {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(_) => return Some(Duration::from_millis(default_ms)),
    };
    let value = value.trim();
    if value.is_empty() {
        return Some(Duration::from_millis(default_ms));
    }
    let Ok(parsed) = value.parse::<u64>() else {
        return Some(Duration::from_millis(default_ms));
    };
    (parsed != 0).then_some(Duration::from_millis(parsed))
}

fn timeout_metadata_value(timeout: Option<Duration>) -> String {
    timeout
        .map(|timeout| timeout.as_millis().to_string())
        .unwrap_or_else(|| "disabled".to_string())
}

fn find_slangc() -> Option<PathBuf> {
    if let Ok(path) = env::var("SLANGC") {
        let path = PathBuf::from(path);
        if path.is_file() {
            return Some(path);
        }
    }
    which::which("slangc").ok()
}

fn slangc_version(slangc: &PathBuf, timeout: Option<Duration>) -> String {
    let mut command = Command::new(slangc);
    command.arg("-version");
    match command_output_with_timeout(&mut command, timeout) {
        Ok(out) if out.status.success() => {
            let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !stdout.is_empty() {
                return stdout;
            }
            let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
            if !stderr.is_empty() {
                return stderr;
            }
            "unknown".to_string()
        }
        Err(err) if err.kind() == io::ErrorKind::TimedOut => timeout
            .map(|timeout| format!("timeout_after_{}ms", timeout.as_millis()))
            .unwrap_or_else(|| "timeout".to_string()),
        _ => "unknown".to_string(),
    }
}

fn command_output_with_timeout(
    command: &mut Command,
    timeout: Option<Duration>,
) -> io::Result<std::process::Output> {
    let Some(timeout) = timeout else {
        return command.output();
    };

    let mut child = command
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;
    let start = std::time::Instant::now();
    loop {
        if child.try_wait()?.is_some() {
            return child.wait_with_output();
        }
        if start.elapsed() >= timeout {
            if let Err(err) = child.kill()
                && err.kind() != io::ErrorKind::InvalidInput
            {
                return Err(err);
            }
            let _ = child.wait_with_output();
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("command timed out after {} ms", timeout.as_millis()),
            ));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn cargo_lock_package_version(workspace_root: &Path, package_name: &str) -> Option<String> {
    let text = fs::read_to_string(workspace_root.join("Cargo.lock")).ok()?;
    let mut in_package = false;
    let mut saw_name = false;
    for line in text.lines() {
        let line = line.trim();
        if line == "[[package]]" {
            in_package = true;
            saw_name = false;
            continue;
        }
        if !in_package {
            continue;
        }
        if let Some(name) = quoted_field(line, "name") {
            saw_name = name == package_name;
            continue;
        }
        if saw_name && let Some(version) = quoted_field(line, "version") {
            return Some(version.to_string());
        }
    }
    None
}

fn quoted_field<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(key)?.trim_start();
    let rest = rest.strip_prefix('=')?.trim_start();
    rest.strip_prefix('"')?.split('"').next()
}
