use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that scatters ranked match arms into match-local ranges.
pub struct HirMatchArmScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchArmScatterPass,
    label: "hir_match_arm_scatter",
    shader: "parser/hir/match/arm/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMatchArmScatterPass {
    const NAME: &'static str = "hir_match_arm_scatter";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gHirMatch".into(),
                b.hir_enum_match_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "hir_match_arm_owner_a".into(),
                b.hir_match_arm_owner_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_a".into(),
                b.hir_match_arm_rank_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_previous".into(),
                b.hir_match_arm_previous.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_a".into(),
                b.hir_match_payload_owner_a.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_a".into(),
                b.hir_match_payload_rank_a.as_entire_binding(),
            ),
            (
                "hir_match_arm_start".into(),
                b.hir_match_arm_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_count".into(),
                b.hir_match_arm_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_next".into(),
                b.hir_match_arm_next.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_start".into(),
                b.hir_match_arm_payload_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_count".into(),
                b.hir_match_arm_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_arm".into(),
                b.hir_match_payload_owner_arm.as_entire_binding(),
            ),
            (
                "hir_match_payload_match_node".into(),
                b.hir_match_payload_match_node.as_entire_binding(),
            ),
            (
                "hir_match_payload_ordinal".into(),
                b.hir_match_payload_ordinal.as_entire_binding(),
            ),
        ])
    }
}

#[cfg(test)]
mod tests {
    use crate::gpu::{
        buffers::{readback_bytes, storage_ro_from_u32s, storage_rw_for_array, uniform_from_val},
        device,
        passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
    };

    fn production(name: &str) -> u32 {
        let generated = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../shaders/parser/generated_parse_production_ids.slang"
        ));
        let prefix = format!("static const uint PROD_{name} = ");
        generated
            .lines()
            .find_map(|line| line.strip_prefix(&prefix))
            .unwrap()
            .trim_end_matches("u;")
            .parse()
            .unwrap()
    }

    #[test]
    fn physical_gpu_match_payload_ownership_ignores_reused_storage() {
        assert!(
            !crate::options::get().allow_software_adapter,
            "this regression requires a physical GPU"
        );
        let gpu = device::global();
        let invalid = u32::MAX;
        // Node 2 belongs to arm 1 of match 0. Nodes 3 and 4 are patterns
        // without an enclosing match (including the rejected-owner path).
        // Node 5 is outside this job's active prefix of a retained buffer.
        let inputs = [
            ("tree_count_status", [0, 0, 0, 0, 0, 5]),
            (
                "node_kind",
                [
                    production("MATCH_EXPR"),
                    production("MATCH_ARM"),
                    production("PATTERN_IDENT"),
                    production("PATTERN_IDENT"),
                    production("PATTERN_IDENT"),
                    production("PATTERN_IDENT"),
                ],
            ),
            (
                "hir_match_arm_owner_a",
                [invalid, 0, invalid, invalid, invalid, invalid],
            ),
            ("hir_match_arm_rank_a", [0, 2, 0, 0, 0, 0]),
            ("hir_match_arm_previous", [invalid; 6]),
            (
                "hir_match_payload_owner_a",
                [invalid, invalid, 1, invalid, 0, invalid],
            ),
            ("hir_match_payload_rank_a", [0; 6]),
        ]
        .map(|(name, values)| (name, storage_ro_from_u32s(&gpu.device, name, &values)));
        let outputs = [
            "hir_match_arm_start",
            "hir_match_arm_count",
            "hir_match_arm_next",
            "hir_match_arm_payload_start",
            "hir_match_arm_payload_count",
            "hir_match_payload_owner_arm",
            "hir_match_payload_match_node",
            "hir_match_payload_ordinal",
        ]
        .map(|name| (name, storage_rw_for_array::<u32>(&gpu.device, name, 6)));
        let pass = make_pass_data_from_shader_key(
            &gpu.device,
            "match payload ownership",
            "main",
            "parser/hir/match/arm/scatter",
        )
        .unwrap();
        let readback = readback_bytes(&gpu.device, "match payload ownership", 72, 18);
        #[derive(encase::ShaderType)]
        struct Params {
            n: u32,
            uses_status_count: u32,
            family_flags: u32,
            retain_debug_rows: u32,
        }

        for debug in [0, 1] {
            for counted in [0, 1] {
                for poison in [0u32, 1, invalid] {
                    let poisoned_bytes: Vec<u8> =
                        [poison; 6].into_iter().flat_map(u32::to_le_bytes).collect();
                    for (_, buffer) in &outputs {
                        buffer.write(&gpu.queue, 0, &poisoned_bytes);
                    }
                    let params = uniform_from_val(
                        &gpu.device,
                        "match payload params",
                        &Params {
                            n: if counted == 0 { 5 } else { 6 },
                            uses_status_count: counted,
                            family_flags: u32::MAX,
                            retain_debug_rows: debug,
                        },
                    );
                    let mut entries = vec![("gHirMatch", params.as_entire_binding())];
                    entries.extend(
                        inputs
                            .iter()
                            .chain(&outputs)
                            .map(|(name, buffer)| (*name, buffer.as_entire_binding())),
                    );
                    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries)
                        .unwrap();
                    let group = passes_core::bind_group::create_bind_group_from_bindings(
                        &gpu.device,
                        Some("match payload ownership"),
                        &pass,
                        0,
                        &entries,
                    )
                    .unwrap();
                    let mut encoder = gpu.device.create_command_encoder(&Default::default());
                    {
                        let mut compute = passes_core::begin_counted_compute_pass(
                            &mut encoder,
                            &wgpu::ComputePassDescriptor {
                                label: Some("match payload ownership"),
                                timestamp_writes: None,
                            },
                        );
                        compute.set_pipeline(&pass.pipeline);
                        compute.set_bind_group(0, Some(&group), &[]);
                        passes_core::record_compute_dispatch();
                        if !passes_core::debug_operation_skipped() {
                            compute.dispatch_workgroups(1, 1, 1);
                        }
                    }
                    for (i, (_, buffer)) in outputs[5..].iter().enumerate() {
                        buffer.copy_to(&mut encoder, 0, &readback, (i * 24) as u64, 24);
                    }
                    gpu.queue.submit(Some(encoder.finish()));
                    let slice = readback.slice(..);
                    map_readback_blocking(&gpu.device, &slice, "match payload ownership".into()).unwrap();
                    let mapped = slice.get_mapped_range();
                    let words: Vec<u32> = mapped
                        .chunks_exact(4)
                        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
                        .collect();
                    drop(mapped);
                    readback.unmap();
                    let expected = [
                        [invalid, invalid, 1, invalid, invalid, poison],
                        [invalid, 0, 0, invalid, invalid, poison],
                        [invalid, 2, 0, invalid, invalid, poison],
                    ];
                    assert_eq!(
                        words,
                        expected.concat(),
                        "debug={debug}, counted={counted}, poison={poison:#x}"
                    );
                }
            }
        }
    }
}
