#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::VecDeque,
    process::{Command, Stdio},
};

#[test]
fn mixed_ring_edits_match_an_independent_deque_model() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/alloc_deque_model.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("deque model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .expect("compile deque model");
    let exe = common::TempArtifact::new("laniusc_deque", "model", None);
    exe.write_bytes(&bytes);
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let input = common::TempArtifact::new("laniusc_deque", "input", None);
    let mut seed = 0xdec0_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut model = VecDeque::<i32>::new();
    let mut data = Vec::new();
    let mut expected = Vec::new();
    let mut covered = [false; 29];
    for step in 0..6000 {
        let mut op = (random() % 29) as u8;
        if step % 17 < 6 {
            op = (step % 2) as u8;
        }
        if step % 193 == 0 {
            op = 27;
        }
        if (op == 20 || op == 21) && model.len() > 128 {
            op = 2;
        }
        let mut index = (random() % (model.len() as u32 + 3)) as i32 - 1;
        let mut value = random() as i32;
        if step % 7 == 0 {
            value = 7;
        }
        if step % 17 == 0 {
            value = i32::MIN;
        }
        if step % 23 == 0 {
            value = i32::MAX;
        }
        if op == 9 {
            value = (random() % (model.len() as u32 + 3)) as i32 - 1;
        }
        if op == 10 {
            index = (random() % 42) as i32 - 2;
        }
        if op == 12 {
            index = match step % 5 {
                0 => -1,
                1 => i32::MAX,
                _ => (random() % 129) as i32,
            };
        }
        covered[op as usize] = true;
        data.push(op);
        data.extend_from_slice(&index.to_le_bytes());
        data.extend_from_slice(&value.to_le_bytes());
        let mut tag = 0;
        let mut answer = 0;
        let mut removed = None;
        let valid = index >= 0 && (index as usize) < model.len();
        match op {
            0 => model.push_back(value),
            1 => model.push_front(value),
            2 => removed = model.pop_front(),
            3 => removed = model.pop_back(),
            4 => {
                if valid {
                    removed = Some(std::mem::replace(&mut model[index as usize], value));
                } else {
                    tag = 2;
                }
            }
            5 => {
                if index >= 0 && index as usize <= model.len() {
                    model.insert(index as usize, value);
                } else {
                    tag = 2;
                }
            }
            6 => {
                if valid {
                    removed = model.remove(index as usize);
                } else {
                    tag = 2;
                }
            }
            7 => {
                if valid {
                    removed = model.swap_remove_front(index as usize);
                } else {
                    tag = 2;
                }
            }
            8 => {
                if valid {
                    removed = model.swap_remove_back(index as usize);
                } else {
                    tag = 2;
                }
            }
            9 => {
                if valid && value >= 0 && (value as usize) < model.len() {
                    model.swap(index as usize, value as usize);
                } else {
                    tag = 2;
                }
            }
            10 => {
                if index < 0 {
                    tag = 2;
                } else {
                    model.resize(index as usize, value);
                }
            }
            11 => {
                if index < 0 {
                    tag = 2;
                } else {
                    model.truncate(index as usize);
                }
            }
            12 => {
                if index < 0 {
                    tag = 3;
                } else if index == i32::MAX {
                    tag = 4;
                }
            }
            13 | 26 | 28 => {}
            14 => model = model.into_iter().rev().collect(),
            15 | 16 => {
                if index < 0 || index as usize > model.len() {
                    tag = 2;
                } else if op == 15 {
                    model.rotate_left(index as usize);
                } else {
                    model.rotate_right(index as usize);
                }
            }
            17 | 27 => model.clear(),
            18 => {
                for entry in [value / 2, 0, value] {
                    model.push_front(entry);
                }
            }
            19 => model.extend([value, 0, value / 2]),
            20 | 21 => model.extend(model.clone()),
            22 => removed = model.front().copied(),
            23 => {
                if index < 0 || index as usize > model.len() {
                    tag = 2;
                } else {
                    removed = model.split_off(index as usize).pop_front();
                }
            }
            24 => {
                if valid {
                    removed = Some(model[index as usize]);
                }
            }
            25 => {
                removed = Some(
                    model
                        .iter()
                        .position(|n| *n == value)
                        .map_or(-1, |i| i as i32),
                )
            }
            _ => unreachable!(),
        }
        if let Some(value) = removed {
            tag = 1;
            answer = value;
        }
        let mut row = vec![tag, answer, model.len() as i32];
        row.extend(model.iter());
        expected.push(row);
    }
    assert!(covered.into_iter().all(|hit| hit));
    input.write_bytes(&data);
    let output = common::process_output_with_timeout(
        "deque model complete states",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
        std::time::Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty());
    let actual: Vec<Vec<i32>> = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| {
            line.split_ascii_whitespace()
                .map(|n| n.parse().unwrap())
                .collect()
        })
        .collect();
    assert_eq!(actual.len(), expected.len());
    for (step, (actual, expected)) in actual.iter().zip(&expected).enumerate() {
        assert_eq!(actual, expected, "seed=0xdec02026 step={step}");
    }
}
