#[derive(Clone, Copy, Debug, Eq, PartialEq)]
/// Declared read/write boundary for one WASM recording stage.
pub struct WasmRecordBoundary {
    pub stage: &'static str,
    pub reads: &'static [&'static str],
    pub writes: &'static [&'static str],
}

const WASM_RECORD_BOUNDARIES: &[WasmRecordBoundary] = &[
    WasmRecordBoundary {
        stage: "agg_layout_clear",
        reads: &["wasm_params"],
        writes: &["aggregate_layout_records"],
    },
    WasmRecordBoundary {
        stage: "agg_layout",
        reads: &["hir_records", "struct_records", "aggregate_layout_records"],
        writes: &["aggregate_layout_records"],
    },
    WasmRecordBoundary {
        stage: "const_values",
        reads: &["hir_status", "hir_expr_records", "hir_stmt_records"],
        writes: &["wasm_const_value_records"],
    },
    WasmRecordBoundary {
        stage: "hir_body_let_init_clear",
        reads: &["wasm_params"],
        writes: &["wasm_body_let_init_expr_by_decl_token"],
    },
    WasmRecordBoundary {
        stage: "hir_body_let_init",
        reads: &["hir_status", "hir_records", "hir_stmt_records"],
        writes: &["wasm_body_let_init_expr_by_decl_token"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_clear",
        reads: &["wasm_params"],
        writes: &["wasm_function_records"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_mark",
        reads: &["hir_records", "hir_param_records", "typecheck_records"],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_reach",
        reads: &[
            "hir_records",
            "call_records",
            "path_records",
            "typecheck_records",
            "wasm_function_records",
        ],
        writes: &["wasm_function_records"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_count",
        reads: &["wasm_function_records"],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_func_scan_local",
        reads: &["wasm_function_flags"],
        writes: &[
            "wasm_function_scan_local_prefix",
            "wasm_function_scan_block_sum",
        ],
    },
    WasmRecordBoundary {
        stage: "hir_func_scan_blocks",
        reads: &[
            "wasm_function_scan_block_sum",
            "wasm_function_scan_prefix_a",
            "wasm_function_scan_prefix_b",
        ],
        writes: &["wasm_function_scan_prefix_a", "wasm_function_scan_prefix_b"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_scatter",
        reads: &["wasm_function_flags", "wasm_function_scan_prefixes"],
        writes: &["wasm_function_slots"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_collect",
        reads: &[
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_const_value_records",
        ],
        writes: &["wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_validate",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_const_value_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_agg_direct_call",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_agg_struct",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_arrays",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_functions",
        reads: &["wasm_function_records", "wasm_body_plan"],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_finalize",
        reads: &["wasm_body_plan"],
        writes: &["wasm_body_plan", "wasm_body_status", "wasm_status"],
    },
    WasmRecordBoundary {
        stage: "hir_body_clear",
        reads: &["wasm_params"],
        writes: &[
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_plan",
        ],
    },
    WasmRecordBoundary {
        stage: "hir_body_counts",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_const_value_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &[
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
        ],
    },
    WasmRecordBoundary {
        stage: "hir_body_scan_local",
        reads: &["wasm_body_fragment_len"],
        writes: &["wasm_body_scan_local_prefix", "wasm_body_scan_block_sum"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scan_blocks",
        reads: &[
            "wasm_body_scan_block_sum",
            "wasm_body_scan_prefix_a",
            "wasm_body_scan_prefix_b",
        ],
        writes: &["wasm_body_scan_prefix_a", "wasm_body_scan_prefix_b"],
    },
    WasmRecordBoundary {
        stage: "hir_body_status",
        reads: &["wasm_body_scan_block_prefix", "wasm_status"],
        writes: &["wasm_body_status", "wasm_status"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_expr_control",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_agg_range_control",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_let_direct",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_direct_nested_call",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_host_io",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_host",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_arrays",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_agg_copy",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_array_lean",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_agg_direct_call",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_binary_direct_call",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_agg_body",
        reads: &["wasm_status"],
        writes: &[],
    },
    WasmRecordBoundary {
        stage: "hir_enum_match_records",
        reads: &["hir_match_records"],
        writes: &["wasm_enum_match_records"],
    },
    WasmRecordBoundary {
        stage: "module_status",
        reads: &["wasm_params", "wasm_body_status", "wasm_status"],
        writes: &["wasm_status"],
    },
    WasmRecordBoundary {
        stage: "module",
        reads: &[
            "wasm_params",
            "wasm_body_words",
            "wasm_body_status",
            "wasm_status",
        ],
        writes: &["wasm_module_words"],
    },
    WasmRecordBoundary {
        stage: "hir_assert_module",
        reads: &["wasm_status"],
        writes: &[],
    },
    WasmRecordBoundary {
        stage: "pack_output",
        reads: &["wasm_module_words", "wasm_status"],
        writes: &["wasm_packed_words", "wasm_status"],
    },
];

/// Returns the current WASM recording stages and their buffer read/write roles.
pub fn wasm_record_boundaries() -> &'static [WasmRecordBoundary] {
    WASM_RECORD_BOUNDARIES
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn recording_stage_names_are_unique_and_nonempty() {
        let mut names = HashSet::new();

        for boundary in wasm_record_boundaries() {
            assert!(!boundary.stage.is_empty());
            assert!(
                names.insert(boundary.stage),
                "duplicate stage {}",
                boundary.stage
            );
            assert!(
                !boundary.reads.is_empty() || !boundary.writes.is_empty(),
                "stage {} declares no buffer boundary",
                boundary.stage
            );
        }
    }
}
