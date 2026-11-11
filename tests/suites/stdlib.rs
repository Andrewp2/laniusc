//! The tests of the standard library, built as one test binary.
//!
//! Each module below is one file in `tests/`. Cargo does not discover test
//! files in this package, so a new file runs only after it is listed here.
//! `every_test_file_is_in_a_suite` in `compiler.rs` fails for a file that no
//! suite lists.

#[path = "../common/mod.rs"]
pub mod common;

#[path = "../stdlib_address_filter_execution.rs"]
mod stdlib_address_filter_execution;
#[path = "../stdlib_adler32_execution.rs"]
mod stdlib_adler32_execution;
#[path = "../stdlib_alloc_deque_execution.rs"]
mod stdlib_alloc_deque_execution;
#[path = "../stdlib_alloc_vec_execution.rs"]
mod stdlib_alloc_vec_execution;
#[path = "../stdlib_allocator_failure_execution.rs"]
mod stdlib_allocator_failure_execution;
#[path = "../stdlib_allocator_metadata_execution.rs"]
mod stdlib_allocator_metadata_execution;
#[path = "../stdlib_arena_execution.rs"]
mod stdlib_arena_execution;
#[path = "../stdlib_arena_words_execution.rs"]
mod stdlib_arena_words_execution;
#[path = "../stdlib_array_i32_view_execution.rs"]
mod stdlib_array_i32_view_execution;
#[path = "../stdlib_array_u8_4_execution.rs"]
mod stdlib_array_u8_4_execution;
#[path = "../stdlib_assert_execution.rs"]
mod stdlib_assert_execution;
#[path = "../stdlib_atomic_file_execution.rs"]
mod stdlib_atomic_file_execution;
#[path = "../stdlib_base64_boundary_execution.rs"]
mod stdlib_base64_boundary_execution;
#[path = "../stdlib_base64_bytes_execution.rs"]
mod stdlib_base64_bytes_execution;
#[path = "../stdlib_base64_execution.rs"]
mod stdlib_base64_execution;
#[path = "../stdlib_base64_model_execution.rs"]
mod stdlib_base64_model_execution;
#[path = "../stdlib_bc_execution.rs"]
mod stdlib_bc_execution;
#[path = "../stdlib_binary_heap_execution.rs"]
mod stdlib_binary_heap_execution;
#[path = "../stdlib_binary_wide_i64_execution.rs"]
mod stdlib_binary_wide_i64_execution;
#[path = "../stdlib_binary_wide_u64_execution.rs"]
mod stdlib_binary_wide_u64_execution;
#[path = "../stdlib_bitset_execution.rs"]
mod stdlib_bitset_execution;
#[path = "../stdlib_bitset_owned_execution.rs"]
mod stdlib_bitset_owned_execution;
#[path = "../stdlib_borrowed_lookup_execution.rs"]
mod stdlib_borrowed_lookup_execution;
#[path = "../stdlib_borrowed_lookup_model_execution.rs"]
mod stdlib_borrowed_lookup_model_execution;
#[path = "../stdlib_borrowed_lookup_resources_execution.rs"]
mod stdlib_borrowed_lookup_resources_execution;
#[path = "../stdlib_btree_map_execution.rs"]
mod stdlib_btree_map_execution;
#[path = "../stdlib_buffered_execution.rs"]
mod stdlib_buffered_execution;
#[path = "../stdlib_buffered_seek_execution.rs"]
mod stdlib_buffered_seek_execution;
#[path = "../stdlib_byte_summary_execution.rs"]
mod stdlib_byte_summary_execution;
#[path = "../stdlib_calendar_execution.rs"]
mod stdlib_calendar_execution;
#[path = "../stdlib_calendar_keys_execution.rs"]
mod stdlib_calendar_keys_execution;
#[path = "../stdlib_caller_buffered_execution.rs"]
mod stdlib_caller_buffered_execution;
#[path = "../stdlib_caller_buffered_model_execution.rs"]
mod stdlib_caller_buffered_model_execution;
#[path = "../stdlib_caller_buffered_resources_execution.rs"]
mod stdlib_caller_buffered_resources_execution;
#[path = "../stdlib_cast_store_execution.rs"]
mod stdlib_cast_store_execution;
#[path = "../stdlib_char_array_literal_execution.rs"]
mod stdlib_char_array_literal_execution;
#[path = "../stdlib_char_high_bit_execution.rs"]
mod stdlib_char_high_bit_execution;
#[path = "../stdlib_checked_sample_migration_execution.rs"]
mod stdlib_checked_sample_migration_execution;
#[path = "../stdlib_child_usage_execution.rs"]
mod stdlib_child_usage_execution;
#[path = "../stdlib_clone_binary_heap_execution.rs"]
mod stdlib_clone_binary_heap_execution;
#[path = "../stdlib_clone_deque_execution.rs"]
mod stdlib_clone_deque_execution;
#[path = "../stdlib_clone_execution.rs"]
mod stdlib_clone_execution;
#[path = "../stdlib_clone_hash_map_execution.rs"]
mod stdlib_clone_hash_map_execution;
#[path = "../stdlib_clone_hash_set_execution.rs"]
mod stdlib_clone_hash_set_execution;
#[path = "../stdlib_clone_tree_map_execution.rs"]
mod stdlib_clone_tree_map_execution;
#[path = "../stdlib_clone_tree_set_execution.rs"]
mod stdlib_clone_tree_set_execution;
#[path = "../stdlib_clone_values_execution.rs"]
mod stdlib_clone_values_execution;
#[path = "../stdlib_cmp_execution.rs"]
mod stdlib_cmp_execution;
#[path = "../stdlib_collection_iterator_execution.rs"]
mod stdlib_collection_iterator_execution;
#[path = "../stdlib_column_sum_execution.rs"]
mod stdlib_column_sum_execution;
#[path = "../stdlib_command_capture_execution.rs"]
mod stdlib_command_capture_execution;
#[path = "../stdlib_command_execution.rs"]
mod stdlib_command_execution;
#[path = "../stdlib_command_group_execution.rs"]
mod stdlib_command_group_execution;
#[path = "../stdlib_compare_series_execution.rs"]
mod stdlib_compare_series_execution;
#[path = "../stdlib_comparison_execution.rs"]
mod stdlib_comparison_execution;
#[path = "../stdlib_compress_file_execution.rs"]
mod stdlib_compress_file_execution;
#[path = "../stdlib_concat_bytes_execution.rs"]
mod stdlib_concat_bytes_execution;
#[path = "../stdlib_concurrency_execution.rs"]
mod stdlib_concurrency_execution;
#[path = "../stdlib_copy_execution.rs"]
mod stdlib_copy_execution;
#[path = "../stdlib_copy_file_execution.rs"]
mod stdlib_copy_file_execution;
#[path = "../stdlib_crc32_execution.rs"]
mod stdlib_crc32_execution;
#[path = "../stdlib_decimal_execution.rs"]
mod stdlib_decimal_execution;
#[path = "../stdlib_decimal_number_execution.rs"]
mod stdlib_decimal_number_execution;
#[path = "../stdlib_decompress_file_execution.rs"]
mod stdlib_decompress_file_execution;
#[path = "../stdlib_delimited_io_execution.rs"]
mod stdlib_delimited_io_execution;
#[path = "../stdlib_delimited_io_model_execution.rs"]
mod stdlib_delimited_io_model_execution;
#[path = "../stdlib_deque_execution.rs"]
mod stdlib_deque_execution;
#[path = "../stdlib_deque_stateful_execution.rs"]
mod stdlib_deque_stateful_execution;
#[path = "../stdlib_development_execution.rs"]
mod stdlib_development_execution;
#[path = "../stdlib_directory_at_execution.rs"]
mod stdlib_directory_at_execution;
#[path = "../stdlib_directory_cursor_execution.rs"]
mod stdlib_directory_cursor_execution;
#[path = "../stdlib_directory_execution.rs"]
mod stdlib_directory_execution;
#[path = "../stdlib_dns_stub_execution.rs"]
mod stdlib_dns_stub_execution;
#[path = "../stdlib_endian_execution.rs"]
mod stdlib_endian_execution;
#[path = "../stdlib_entropy_bounded_execution.rs"]
mod stdlib_entropy_bounded_execution;
#[path = "../stdlib_env_execution.rs"]
mod stdlib_env_execution;
#[path = "../stdlib_event_loop_execution.rs"]
mod stdlib_event_loop_execution;
#[path = "../stdlib_exact_size_iterator_execution.rs"]
mod stdlib_exact_size_iterator_execution;
#[path = "../stdlib_f32.rs"]
mod stdlib_f32;
#[path = "../stdlib_f32_imported_constants_execution.rs"]
mod stdlib_f32_imported_constants_execution;
#[path = "../stdlib_file_binary_execution.rs"]
mod stdlib_file_binary_execution;
#[path = "../stdlib_file_binary_wide_i64_execution.rs"]
mod stdlib_file_binary_wide_i64_execution;
#[path = "../stdlib_file_binary_wide_u64_execution.rs"]
mod stdlib_file_binary_wide_u64_execution;
#[path = "../stdlib_file_copy_execution.rs"]
mod stdlib_file_copy_execution;
#[path = "../stdlib_file_execution.rs"]
mod stdlib_file_execution;
#[path = "../stdlib_file_hex_execution.rs"]
mod stdlib_file_hex_execution;
#[path = "../stdlib_file_hex_wide_i64_execution.rs"]
mod stdlib_file_hex_wide_i64_execution;
#[path = "../stdlib_file_hex_wide_u64_execution.rs"]
mod stdlib_file_hex_wide_u64_execution;
#[path = "../stdlib_file_lock_execution.rs"]
mod stdlib_file_lock_execution;
#[path = "../stdlib_file_lock_model_execution.rs"]
mod stdlib_file_lock_model_execution;
#[path = "../stdlib_file_lock_process_execution.rs"]
mod stdlib_file_lock_process_execution;
#[path = "../stdlib_file_operations_execution.rs"]
mod stdlib_file_operations_execution;
#[path = "../stdlib_file_patch_execution.rs"]
mod stdlib_file_patch_execution;
#[path = "../stdlib_file_positional_execution.rs"]
mod stdlib_file_positional_execution;
#[path = "../stdlib_file_resize_execution.rs"]
mod stdlib_file_resize_execution;
#[path = "../stdlib_file_seek_execution.rs"]
mod stdlib_file_seek_execution;
#[path = "../stdlib_filesystem_links_execution.rs"]
mod stdlib_filesystem_links_execution;
#[path = "../stdlib_fixed_capacity_execution.rs"]
mod stdlib_fixed_capacity_execution;
#[path = "../stdlib_fixed_capacity_lru_model_execution.rs"]
mod stdlib_fixed_capacity_lru_model_execution;
#[path = "../stdlib_flatten_sum_execution.rs"]
mod stdlib_flatten_sum_execution;
#[path = "../stdlib_float_decimal_execution.rs"]
mod stdlib_float_decimal_execution;
#[path = "../stdlib_float_execution.rs"]
mod stdlib_float_execution;
#[path = "../stdlib_float_format_execution.rs"]
mod stdlib_float_format_execution;
#[path = "../stdlib_float_oracle_execution.rs"]
mod stdlib_float_oracle_execution;
#[path = "../stdlib_float_precision_execution.rs"]
mod stdlib_float_precision_execution;
#[path = "../stdlib_form_select_execution.rs"]
mod stdlib_form_select_execution;
#[path = "../stdlib_format_report_execution.rs"]
mod stdlib_format_report_execution;
#[path = "../stdlib_format_strings_execution.rs"]
mod stdlib_format_strings_execution;
#[path = "../stdlib_format_write_execution.rs"]
mod stdlib_format_write_execution;
#[path = "../stdlib_format_write_failures.rs"]
mod stdlib_format_write_failures;
#[path = "../stdlib_foundation_execution.rs"]
mod stdlib_foundation_execution;
#[path = "../stdlib_fs_read_i32_execution.rs"]
mod stdlib_fs_read_i32_execution;
#[path = "../stdlib_generic_containers_execution.rs"]
mod stdlib_generic_containers_execution;
#[path = "../stdlib_generic_enum_declaration_execution.rs"]
mod stdlib_generic_enum_declaration_execution;
#[path = "../stdlib_generic_interface.rs"]
mod stdlib_generic_interface;
#[path = "../stdlib_generic_payload_templates_execution.rs"]
mod stdlib_generic_payload_templates_execution;
#[path = "../stdlib_generic_predicates_execution.rs"]
mod stdlib_generic_predicates_execution;
#[path = "../stdlib_generic_vec_flat_execution.rs"]
mod stdlib_generic_vec_flat_execution;
#[path = "../stdlib_hash_map_execution.rs"]
mod stdlib_hash_map_execution;
#[path = "../stdlib_heap_iterator_execution.rs"]
mod stdlib_heap_iterator_execution;
#[path = "../stdlib_hex_wide_i64_execution.rs"]
mod stdlib_hex_wide_i64_execution;
#[path = "../stdlib_hex_wide_u64_execution.rs"]
mod stdlib_hex_wide_u64_execution;
#[path = "../stdlib_host_clocks_execution.rs"]
mod stdlib_host_clocks_execution;
#[path = "../stdlib_host_execution.rs"]
mod stdlib_host_execution;
#[path = "../stdlib_i32.rs"]
mod stdlib_i32;
#[path = "../stdlib_i64.rs"]
mod stdlib_i64;
#[path = "../stdlib_i64_checked.rs"]
mod stdlib_i64_checked;
#[path = "../stdlib_imported_aggregate_execution.rs"]
mod stdlib_imported_aggregate_execution;
#[path = "../stdlib_imported_local_shadow_execution.rs"]
mod stdlib_imported_local_shadow_execution;
#[path = "../stdlib_index_words_execution.rs"]
mod stdlib_index_words_execution;
#[path = "../stdlib_infallible_nested_bounds.rs"]
mod stdlib_infallible_nested_bounds;
#[path = "../stdlib_infallible_nested_iteration_execution.rs"]
mod stdlib_infallible_nested_iteration_execution;
#[path = "../stdlib_infallible_nested_ownership_execution.rs"]
mod stdlib_infallible_nested_ownership_execution;
#[path = "../stdlib_inflate_stream_execution.rs"]
mod stdlib_inflate_stream_execution;
#[path = "../stdlib_inflate_stream_model_execution.rs"]
mod stdlib_inflate_stream_model_execution;
#[path = "../stdlib_inflate_stream_resource_execution.rs"]
mod stdlib_inflate_stream_resource_execution;
#[path = "../stdlib_input_stats_execution.rs"]
mod stdlib_input_stats_execution;
#[path = "../stdlib_integer_text_execution.rs"]
mod stdlib_integer_text_execution;
#[path = "../stdlib_io_adapters_execution.rs"]
mod stdlib_io_adapters_execution;
#[path = "../stdlib_io_adapters_model_execution.rs"]
mod stdlib_io_adapters_model_execution;
#[path = "../stdlib_io_adapters_resource_execution.rs"]
mod stdlib_io_adapters_resource_execution;
#[path = "../stdlib_io_binary_execution.rs"]
mod stdlib_io_binary_execution;
#[path = "../stdlib_io_binary_wide_i64_execution.rs"]
mod stdlib_io_binary_wide_i64_execution;
#[path = "../stdlib_io_binary_wide_u64_execution.rs"]
mod stdlib_io_binary_wide_u64_execution;
#[path = "../stdlib_io_byte_execution.rs"]
mod stdlib_io_byte_execution;
#[path = "../stdlib_io_checked_execution.rs"]
mod stdlib_io_checked_execution;
#[path = "../stdlib_io_decimal_input_execution.rs"]
mod stdlib_io_decimal_input_execution;
#[path = "../stdlib_io_hex_execution.rs"]
mod stdlib_io_hex_execution;
#[path = "../stdlib_io_hex_wide_i64_execution.rs"]
mod stdlib_io_hex_wide_i64_execution;
#[path = "../stdlib_io_hex_wide_u64_execution.rs"]
mod stdlib_io_hex_wide_u64_execution;
#[path = "../stdlib_io_line_execution.rs"]
mod stdlib_io_line_execution;
#[path = "../stdlib_io_utf8_execution.rs"]
mod stdlib_io_utf8_execution;
#[path = "../stdlib_io_write_i32_execution.rs"]
mod stdlib_io_write_i32_execution;
#[path = "../stdlib_iterator_adapter_execution.rs"]
mod stdlib_iterator_adapter_execution;
#[path = "../stdlib_iterator_collection_sink_bounds.rs"]
mod stdlib_iterator_collection_sink_bounds;
#[path = "../stdlib_iterator_collection_sink_execution.rs"]
mod stdlib_iterator_collection_sink_execution;
#[path = "../stdlib_iterator_collection_sink_faults.rs"]
mod stdlib_iterator_collection_sink_faults;
#[path = "../stdlib_iterator_comparison_execution.rs"]
mod stdlib_iterator_comparison_execution;
#[path = "../stdlib_iterator_comparison_model_execution.rs"]
mod stdlib_iterator_comparison_model_execution;
#[path = "../stdlib_iterator_comparison_resource_execution.rs"]
mod stdlib_iterator_comparison_resource_execution;
#[path = "../stdlib_iterator_consumer_execution.rs"]
mod stdlib_iterator_consumer_execution;
#[path = "../stdlib_iterator_execution.rs"]
mod stdlib_iterator_execution;
#[path = "../stdlib_iterator_fold_dependency_execution.rs"]
mod stdlib_iterator_fold_dependency_execution;
#[path = "../stdlib_iterator_fold_execution.rs"]
mod stdlib_iterator_fold_execution;
#[path = "../stdlib_iterator_fold_model_execution.rs"]
mod stdlib_iterator_fold_model_execution;
#[path = "../stdlib_iterator_fold_owner_execution.rs"]
mod stdlib_iterator_fold_owner_execution;
#[path = "../stdlib_iterator_lookahead_execution.rs"]
mod stdlib_iterator_lookahead_execution;
#[path = "../stdlib_iterator_selection_assignment.rs"]
mod stdlib_iterator_selection_assignment;
#[path = "../stdlib_iterator_selection_bounds.rs"]
mod stdlib_iterator_selection_bounds;
#[path = "../stdlib_iterator_selection_execution.rs"]
mod stdlib_iterator_selection_execution;
#[path = "../stdlib_iterator_sources_execution.rs"]
mod stdlib_iterator_sources_execution;
#[path = "../stdlib_iterator_transfer_bounds.rs"]
mod stdlib_iterator_transfer_bounds;
#[path = "../stdlib_iterator_transfer_execution.rs"]
mod stdlib_iterator_transfer_execution;
#[path = "../stdlib_iterator_transfer_faults.rs"]
mod stdlib_iterator_transfer_faults;
#[path = "../stdlib_json_normalize_execution.rs"]
mod stdlib_json_normalize_execution;
#[path = "../stdlib_latest_values_execution.rs"]
mod stdlib_latest_values_execution;
#[path = "../stdlib_layout_execution.rs"]
mod stdlib_layout_execution;
#[path = "../stdlib_layout_model_execution.rs"]
mod stdlib_layout_model_execution;
#[path = "../stdlib_layout_records_execution.rs"]
mod stdlib_layout_records_execution;
#[path = "../stdlib_lazy_map_execution.rs"]
mod stdlib_lazy_map_execution;
#[path = "../stdlib_lazy_map_model_execution.rs"]
mod stdlib_lazy_map_model_execution;
#[path = "../stdlib_lazy_map_resources_execution.rs"]
mod stdlib_lazy_map_resources_execution;
#[path = "../stdlib_lazy_outcomes_execution.rs"]
mod stdlib_lazy_outcomes_execution;
#[path = "../stdlib_lazy_outcomes_model_execution.rs"]
mod stdlib_lazy_outcomes_model_execution;
#[path = "../stdlib_lazy_outcomes_resources_execution.rs"]
mod stdlib_lazy_outcomes_resources_execution;
#[path = "../stdlib_legacy_collection_migration_execution.rs"]
mod stdlib_legacy_collection_migration_execution;
#[path = "../stdlib_line_report_execution.rs"]
mod stdlib_line_report_execution;
#[path = "../stdlib_line_summary_execution.rs"]
mod stdlib_line_summary_execution;
#[path = "../stdlib_linux_execution.rs"]
mod stdlib_linux_execution;
#[path = "../stdlib_literal_arithmetic_execution.rs"]
mod stdlib_literal_arithmetic_execution;
#[path = "../stdlib_literal_rewrite_execution.rs"]
mod stdlib_literal_rewrite_execution;
#[path = "../stdlib_locked_file_patch_execution.rs"]
mod stdlib_locked_file_patch_execution;
#[path = "../stdlib_look_words_execution.rs"]
mod stdlib_look_words_execution;
#[path = "../stdlib_map_update_execution.rs"]
mod stdlib_map_update_execution;
#[path = "../stdlib_map_update_model_execution.rs"]
mod stdlib_map_update_model_execution;
#[path = "../stdlib_map_update_resources_execution.rs"]
mod stdlib_map_update_resources_execution;
#[path = "../stdlib_math_execution.rs"]
mod stdlib_math_execution;
#[path = "../stdlib_mem_execution.rs"]
mod stdlib_mem_execution;
#[path = "../stdlib_mem_generic_execution.rs"]
mod stdlib_mem_generic_execution;
#[path = "../stdlib_mktemp_dir_execution.rs"]
mod stdlib_mktemp_dir_execution;
#[path = "../stdlib_move_rows_execution.rs"]
mod stdlib_move_rows_execution;
#[path = "../stdlib_narrow_execution.rs"]
mod stdlib_narrow_execution;
#[path = "../stdlib_narrow_integers_execution.rs"]
mod stdlib_narrow_integers_execution;
#[path = "../stdlib_native_endian_execution.rs"]
mod stdlib_native_endian_execution;
#[path = "../stdlib_native_endian_memory_execution.rs"]
mod stdlib_native_endian_memory_execution;
#[path = "../stdlib_native_endian_model_execution.rs"]
mod stdlib_native_endian_model_execution;
#[path = "../stdlib_native_integers_execution.rs"]
mod stdlib_native_integers_execution;
#[path = "../stdlib_nested_clone_execution.rs"]
mod stdlib_nested_clone_execution;
#[path = "../stdlib_nested_iteration_execution.rs"]
mod stdlib_nested_iteration_execution;
#[path = "../stdlib_nested_iterator_ownership_execution.rs"]
mod stdlib_nested_iterator_ownership_execution;
#[path = "../stdlib_net_execution.rs"]
mod stdlib_net_execution;
#[path = "../stdlib_numeric_migration_execution.rs"]
mod stdlib_numeric_migration_execution;
#[path = "../stdlib_option_bool_execution.rs"]
mod stdlib_option_bool_execution;
#[path = "../stdlib_option_generic_payload_execution.rs"]
mod stdlib_option_generic_payload_execution;
#[path = "../stdlib_option_result_methods_execution.rs"]
mod stdlib_option_result_methods_execution;
#[path = "../stdlib_option_scalar_execution.rs"]
mod stdlib_option_scalar_execution;
#[path = "../stdlib_option_slice_execution.rs"]
mod stdlib_option_slice_execution;
#[path = "../stdlib_optional_sum_execution.rs"]
mod stdlib_optional_sum_execution;
#[path = "../stdlib_ordered_navigation_execution.rs"]
mod stdlib_ordered_navigation_execution;
#[path = "../stdlib_ordered_navigation_model_execution.rs"]
mod stdlib_ordered_navigation_model_execution;
#[path = "../stdlib_ordering.rs"]
mod stdlib_ordering;
#[path = "../stdlib_ordering_wide.rs"]
mod stdlib_ordering_wide;
#[path = "../stdlib_outcome_composition_execution.rs"]
mod stdlib_outcome_composition_execution;
#[path = "../stdlib_outcome_composition_memory_execution.rs"]
mod stdlib_outcome_composition_memory_execution;
#[path = "../stdlib_outcome_composition_model_execution.rs"]
mod stdlib_outcome_composition_model_execution;
#[path = "../stdlib_owned_delimited_execution.rs"]
mod stdlib_owned_delimited_execution;
#[path = "../stdlib_owned_delimited_model_execution.rs"]
mod stdlib_owned_delimited_model_execution;
#[path = "../stdlib_owned_delimited_resource_execution.rs"]
mod stdlib_owned_delimited_resource_execution;
#[path = "../stdlib_owned_file_execution.rs"]
mod stdlib_owned_file_execution;
#[path = "../stdlib_owned_input_execution.rs"]
mod stdlib_owned_input_execution;
#[path = "../stdlib_owned_input_model_execution.rs"]
mod stdlib_owned_input_model_execution;
#[path = "../stdlib_owned_input_resource_execution.rs"]
mod stdlib_owned_input_resource_execution;
#[path = "../stdlib_owned_sets_execution.rs"]
mod stdlib_owned_sets_execution;
#[path = "../stdlib_owning_hash_execution.rs"]
mod stdlib_owning_hash_execution;
#[path = "../stdlib_owning_heap_execution.rs"]
mod stdlib_owning_heap_execution;
#[path = "../stdlib_owning_iterator_bounds.rs"]
mod stdlib_owning_iterator_bounds;
#[path = "../stdlib_owning_iterator_execution.rs"]
mod stdlib_owning_iterator_execution;
#[path = "../stdlib_owning_iterator_faults.rs"]
mod stdlib_owning_iterator_faults;
#[path = "../stdlib_owning_tree_execution.rs"]
mod stdlib_owning_tree_execution;
#[path = "../stdlib_panic_execution.rs"]
mod stdlib_panic_execution;
#[path = "../stdlib_parallel_checksums_execution.rs"]
mod stdlib_parallel_checksums_execution;
#[path = "../stdlib_path.rs"]
mod stdlib_path;
#[path = "../stdlib_path_execution.rs"]
mod stdlib_path_execution;
#[path = "../stdlib_poll_execution.rs"]
mod stdlib_poll_execution;
#[path = "../stdlib_positional_io_execution.rs"]
mod stdlib_positional_io_execution;
#[path = "../stdlib_positional_io_model_execution.rs"]
mod stdlib_positional_io_model_execution;
#[path = "../stdlib_primes_execution.rs"]
mod stdlib_primes_execution;
#[path = "../stdlib_random_budget_execution.rs"]
mod stdlib_random_budget_execution;
#[path = "../stdlib_random_budget_model_execution.rs"]
mod stdlib_random_budget_model_execution;
#[path = "../stdlib_random_budget_owner_execution.rs"]
mod stdlib_random_budget_owner_execution;
#[path = "../stdlib_random_execution.rs"]
mod stdlib_random_execution;
#[path = "../stdlib_random_wide_execution.rs"]
mod stdlib_random_wide_execution;
#[path = "../stdlib_range.rs"]
mod stdlib_range;
#[path = "../stdlib_range_dot_execution.rs"]
mod stdlib_range_dot_execution;
#[path = "../stdlib_range_f32_methods_execution.rs"]
mod stdlib_range_f32_methods_execution;
#[path = "../stdlib_range_full_method_execution.rs"]
mod stdlib_range_full_method_execution;
#[path = "../stdlib_range_overlap_execution.rs"]
mod stdlib_range_overlap_execution;
#[path = "../stdlib_range_stats_execution.rs"]
mod stdlib_range_stats_execution;
#[path = "../stdlib_raw_host_width_execution.rs"]
mod stdlib_raw_host_width_execution;
#[path = "../stdlib_record_summary_execution.rs"]
mod stdlib_record_summary_execution;
#[path = "../stdlib_repack_records_execution.rs"]
mod stdlib_repack_records_execution;
#[path = "../stdlib_replacement_sink_bounds.rs"]
mod stdlib_replacement_sink_bounds;
#[path = "../stdlib_replacement_sink_ownership_execution.rs"]
mod stdlib_replacement_sink_ownership_execution;
#[path = "../stdlib_replacement_sinks_execution.rs"]
mod stdlib_replacement_sinks_execution;
#[path = "../stdlib_resolve_execution.rs"]
mod stdlib_resolve_execution;
#[path = "../stdlib_resolve_host_execution.rs"]
mod stdlib_resolve_host_execution;
#[path = "../stdlib_result_generic_execution.rs"]
mod stdlib_result_generic_execution;
#[path = "../stdlib_result_methods_execution.rs"]
mod stdlib_result_methods_execution;
#[path = "../stdlib_reverse_iterator_execution.rs"]
mod stdlib_reverse_iterator_execution;
#[path = "../stdlib_reverse_records_execution.rs"]
mod stdlib_reverse_records_execution;
#[path = "../stdlib_run_group_execution.rs"]
mod stdlib_run_group_execution;
#[path = "../stdlib_runtime_contract.rs"]
mod stdlib_runtime_contract;
#[path = "../stdlib_runtime_metadata_execution.rs"]
mod stdlib_runtime_metadata_execution;
#[path = "../stdlib_sample_bytes_execution.rs"]
mod stdlib_sample_bytes_execution;
#[path = "../stdlib_sample_integers_execution.rs"]
mod stdlib_sample_integers_execution;
#[path = "../stdlib_scope_execution.rs"]
mod stdlib_scope_execution;
#[path = "../stdlib_search_execution.rs"]
mod stdlib_search_execution;
#[path = "../stdlib_seek_dependency_execution.rs"]
mod stdlib_seek_dependency_execution;
#[path = "../stdlib_seek_execution.rs"]
mod stdlib_seek_execution;
#[path = "../stdlib_seek_model_execution.rs"]
mod stdlib_seek_model_execution;
#[path = "../stdlib_select_field_execution.rs"]
mod stdlib_select_field_execution;
#[path = "../stdlib_select_records_execution.rs"]
mod stdlib_select_records_execution;
#[path = "../stdlib_select_value_execution.rs"]
mod stdlib_select_value_execution;
#[path = "../stdlib_signal_delivery_execution.rs"]
mod stdlib_signal_delivery_execution;
#[path = "../stdlib_signal_execution.rs"]
mod stdlib_signal_execution;
#[path = "../stdlib_signed_bit_report_program.rs"]
mod stdlib_signed_bit_report_program;
#[path = "../stdlib_signed_byte_frequency_execution.rs"]
mod stdlib_signed_byte_frequency_execution;
#[path = "../stdlib_signed_radix_report_program.rs"]
mod stdlib_signed_radix_report_program;
#[path = "../stdlib_slice_generic_execution.rs"]
mod stdlib_slice_generic_execution;
#[path = "../stdlib_slice_iteration_execution.rs"]
mod stdlib_slice_iteration_execution;
#[path = "../stdlib_slice_iterator_integration_execution.rs"]
mod stdlib_slice_iterator_integration_execution;
#[path = "../stdlib_slice_ordering_dependency_execution.rs"]
mod stdlib_slice_ordering_dependency_execution;
#[path = "../stdlib_slice_ordering_execution.rs"]
mod stdlib_slice_ordering_execution;
#[path = "../stdlib_slice_ordering_model_execution.rs"]
mod stdlib_slice_ordering_model_execution;
#[path = "../stdlib_slice_ordering_owner_execution.rs"]
mod stdlib_slice_ordering_owner_execution;
#[path = "../stdlib_slice_segmentation_execution.rs"]
mod stdlib_slice_segmentation_execution;
#[path = "../stdlib_slice_segmentation_model_execution.rs"]
mod stdlib_slice_segmentation_model_execution;
#[path = "../stdlib_slice_segmentation_resources_execution.rs"]
mod stdlib_slice_segmentation_resources_execution;
#[path = "../stdlib_slice_selection_execution.rs"]
mod stdlib_slice_selection_execution;
#[path = "../stdlib_slice_selection_model_execution.rs"]
mod stdlib_slice_selection_model_execution;
#[path = "../stdlib_slice_selection_owner_execution.rs"]
mod stdlib_slice_selection_owner_execution;
#[path = "../stdlib_slice_view_execution.rs"]
mod stdlib_slice_view_execution;
#[path = "../stdlib_socket_execution.rs"]
mod stdlib_socket_execution;
#[path = "../stdlib_sort_algorithms_model_execution.rs"]
mod stdlib_sort_algorithms_model_execution;
#[path = "../stdlib_sort_rows_execution.rs"]
mod stdlib_sort_rows_execution;
#[path = "../stdlib_sort_words_execution.rs"]
mod stdlib_sort_words_execution;
#[path = "../stdlib_stable_sort_execution.rs"]
mod stdlib_stable_sort_execution;
#[path = "../stdlib_stable_sort_model_execution.rs"]
mod stdlib_stable_sort_model_execution;
#[path = "../stdlib_stable_sort_resource_execution.rs"]
mod stdlib_stable_sort_resource_execution;
#[path = "../stdlib_stream_encoding_resources_execution.rs"]
mod stdlib_stream_encoding_resources_execution;
#[path = "../stdlib_stream_execution.rs"]
mod stdlib_stream_execution;
#[path = "../stdlib_string_byte_transfer_execution.rs"]
mod stdlib_string_byte_transfer_execution;
#[path = "../stdlib_string_execution.rs"]
mod stdlib_string_execution;
#[path = "../stdlib_tcp_exchange_execution.rs"]
mod stdlib_tcp_exchange_execution;
#[path = "../stdlib_temp_dir_execution.rs"]
mod stdlib_temp_dir_execution;
#[path = "../stdlib_temp_file_execution.rs"]
mod stdlib_temp_file_execution;
#[path = "../stdlib_text_bidirectional_execution.rs"]
mod stdlib_text_bidirectional_execution;
#[path = "../stdlib_text_bidirectional_model_execution.rs"]
mod stdlib_text_bidirectional_model_execution;
#[path = "../stdlib_text_bidirectional_resources_execution.rs"]
mod stdlib_text_bidirectional_resources_execution;
#[path = "../stdlib_text_composition_execution.rs"]
mod stdlib_text_composition_execution;
#[path = "../stdlib_text_execution.rs"]
mod stdlib_text_execution;
#[path = "../stdlib_text_partitions_execution.rs"]
mod stdlib_text_partitions_execution;
#[path = "../stdlib_text_replacement_execution.rs"]
mod stdlib_text_replacement_execution;
#[path = "../stdlib_text_replacement_model_execution.rs"]
mod stdlib_text_replacement_model_execution;
#[path = "../stdlib_text_split_iterator_execution.rs"]
mod stdlib_text_split_iterator_execution;
#[path = "../stdlib_thread_channel_allocation_execution.rs"]
mod stdlib_thread_channel_allocation_execution;
#[path = "../stdlib_thread_lifecycle_execution.rs"]
mod stdlib_thread_lifecycle_execution;
#[path = "../stdlib_thread_pool_lifecycle_execution.rs"]
mod stdlib_thread_pool_lifecycle_execution;
#[path = "../stdlib_thread_sort_lifecycle_execution.rs"]
mod stdlib_thread_sort_lifecycle_execution;
#[path = "../stdlib_time_execution.rs"]
mod stdlib_time_execution;
#[path = "../stdlib_time_wide_execution.rs"]
mod stdlib_time_wide_execution;
#[path = "../stdlib_timeline_tail_execution.rs"]
mod stdlib_timeline_tail_execution;
#[path = "../stdlib_timers_execution.rs"]
mod stdlib_timers_execution;
#[path = "../stdlib_transcode_execution.rs"]
mod stdlib_transcode_execution;
#[path = "../stdlib_tree_map_execution.rs"]
mod stdlib_tree_map_execution;
#[path = "../stdlib_unicode_execution.rs"]
mod stdlib_unicode_execution;
#[path = "../stdlib_unique_words_execution.rs"]
mod stdlib_unique_words_execution;
#[path = "../stdlib_unix_request_execution.rs"]
mod stdlib_unix_request_execution;
#[path = "../stdlib_unix_stream_address_execution.rs"]
mod stdlib_unix_stream_address_execution;
#[path = "../stdlib_unix_stream_effects_execution.rs"]
mod stdlib_unix_stream_effects_execution;
#[path = "../stdlib_unix_stream_execution.rs"]
mod stdlib_unix_stream_execution;
#[path = "../stdlib_unsigned_ranges.rs"]
mod stdlib_unsigned_ranges;
#[path = "../stdlib_utf16_bytes_execution.rs"]
mod stdlib_utf16_bytes_execution;
#[path = "../stdlib_utf16_execution.rs"]
mod stdlib_utf16_execution;
#[path = "../stdlib_utf8_bytes_execution.rs"]
mod stdlib_utf8_bytes_execution;
#[path = "../stdlib_varint_boundary_execution.rs"]
mod stdlib_varint_boundary_execution;
#[path = "../stdlib_varint_execution.rs"]
mod stdlib_varint_execution;
#[path = "../stdlib_varint_frames_execution.rs"]
mod stdlib_varint_frames_execution;
#[path = "../stdlib_varint_model_execution.rs"]
mod stdlib_varint_model_execution;
#[path = "../stdlib_varint_number_execution.rs"]
mod stdlib_varint_number_execution;
#[path = "../stdlib_vec_alloc_failure_execution.rs"]
mod stdlib_vec_alloc_failure_execution;
#[path = "../stdlib_vec_edit_execution.rs"]
mod stdlib_vec_edit_execution;
#[path = "../stdlib_vec_edit_model_execution.rs"]
mod stdlib_vec_edit_model_execution;
#[path = "../stdlib_vec_edit_resources_execution.rs"]
mod stdlib_vec_edit_resources_execution;
#[path = "../stdlib_vec_transfer_execution.rs"]
mod stdlib_vec_transfer_execution;
#[path = "../stdlib_vec_transfer_model_execution.rs"]
mod stdlib_vec_transfer_model_execution;
#[path = "../stdlib_vec_transfer_resources_execution.rs"]
mod stdlib_vec_transfer_resources_execution;
#[path = "../stdlib_void_return_execution.rs"]
mod stdlib_void_return_execution;
#[path = "../stdlib_weighted_view_import_execution.rs"]
mod stdlib_weighted_view_import_execution;
#[path = "../stdlib_wide_fingerprint_program.rs"]
mod stdlib_wide_fingerprint_program;
#[path = "../stdlib_wide_i64_bits_execution.rs"]
mod stdlib_wide_i64_bits_execution;
#[path = "../stdlib_wide_i64_checked_execution.rs"]
mod stdlib_wide_i64_checked_execution;
#[path = "../stdlib_wide_i64_execution.rs"]
mod stdlib_wide_i64_execution;
#[path = "../stdlib_wide_median_programs_execution.rs"]
mod stdlib_wide_median_programs_execution;
#[path = "../stdlib_wide_signed_sum_program.rs"]
mod stdlib_wide_signed_sum_program;
#[path = "../stdlib_wide_u64_bits_execution.rs"]
mod stdlib_wide_u64_bits_execution;
#[path = "../stdlib_wide_u64_checked_execution.rs"]
mod stdlib_wide_u64_checked_execution;
#[path = "../stdlib_wide_u64_execution.rs"]
mod stdlib_wide_u64_execution;
#[path = "../stdlib_wide_unsigned_sum_program.rs"]
mod stdlib_wide_unsigned_sum_program;
#[path = "../stdlib_word_concordance_execution.rs"]
mod stdlib_word_concordance_execution;
#[path = "../stdlib_workload_generator_execution.rs"]
mod stdlib_workload_generator_execution;
