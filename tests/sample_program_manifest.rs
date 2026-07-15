mod common;

use std::collections::HashMap;

#[test]
fn checked_sample_catalog_covers_required_runtime_facilities() {
    let samples = common::sample_programs::load_sample_programs();
    let samples_by_name = samples
        .iter()
        .map(|sample| (sample.name(), sample))
        .collect::<HashMap<_, _>>();

    let required_facility_samples = [
        ("stdio", "host_runtime_input"),
        ("filesystem", "filesystem_mutations"),
        ("environment", "host_runtime_input"),
        ("process arguments", "host_runtime_input"),
        ("process exit", "process_exit"),
        ("random", "random_fill"),
        ("time", "clock_exact"),
        ("allocation", "allocator_realloc"),
        ("PPM raytracer", "raytracer_ppm"),
    ];

    for (facility, sample_name) in required_facility_samples {
        let sample = samples_by_name.get(sample_name).unwrap_or_else(|| {
            panic!("required {facility} sample {sample_name} is missing from the checked catalog")
        });
        for target in ["x86_64", "wasm"] {
            assert!(
                sample.checked_for_target(target),
                "required {facility} sample {sample_name} must compile and run on {target}"
            );
        }
    }
}
