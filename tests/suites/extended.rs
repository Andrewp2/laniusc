//! The tests of the extended library, built as one test binary.
//!
//! Each module below is one file in `tests/`. Cargo does not discover test
//! files in this package, so a new file runs only after it is listed here.
//! `every_test_file_is_in_a_suite` in `compiler.rs` fails for a file that no
//! suite lists.

#[path = "../common/mod.rs"]
pub mod common;

#[path = "../extended_agent_fetch_execution.rs"]
mod extended_agent_fetch_execution;
#[path = "../extended_archive_extraction_execution.rs"]
mod extended_archive_extraction_execution;
#[path = "../extended_archive_index_execution.rs"]
mod extended_archive_index_execution;
#[path = "../extended_archive_plan_execution.rs"]
mod extended_archive_plan_execution;
#[path = "../extended_archive_profile_execution.rs"]
mod extended_archive_profile_execution;
#[path = "../extended_archive_source_execution.rs"]
mod extended_archive_source_execution;
#[path = "../extended_audio_execution.rs"]
mod extended_audio_execution;
#[path = "../extended_big_int_execution.rs"]
mod extended_big_int_execution;
#[path = "../extended_big_uint_execution.rs"]
mod extended_big_uint_execution;
#[path = "../extended_bigcalc_execution.rs"]
mod extended_bigcalc_execution;
#[path = "../extended_cbor_execution.rs"]
mod extended_cbor_execution;
#[path = "../extended_cbor_stream_execution.rs"]
mod extended_cbor_stream_execution;
#[path = "../extended_certificate_info_execution.rs"]
mod extended_certificate_info_execution;
#[path = "../extended_cli_bash_execution.rs"]
mod extended_cli_bash_execution;
#[path = "../extended_cli_commands_execution.rs"]
mod extended_cli_commands_execution;
#[path = "../extended_cli_complete_execution.rs"]
mod extended_cli_complete_execution;
#[path = "../extended_cli_completion_resources_execution.rs"]
mod extended_cli_completion_resources_execution;
#[path = "../extended_cli_completion_shell_execution.rs"]
mod extended_cli_completion_shell_execution;
#[path = "../extended_cli_execution.rs"]
mod extended_cli_execution;
#[path = "../extended_cli_response_execution.rs"]
mod extended_cli_response_execution;
#[path = "../extended_cli_response_files_execution.rs"]
mod extended_cli_response_files_execution;
#[path = "../extended_compress_bytes_execution.rs"]
mod extended_compress_bytes_execution;
#[path = "../extended_compression_execution.rs"]
mod extended_compression_execution;
#[path = "../extended_config_execution.rs"]
mod extended_config_execution;
#[path = "../extended_csv_execution.rs"]
mod extended_csv_execution;
#[path = "../extended_csv_rewrite_execution.rs"]
mod extended_csv_rewrite_execution;
#[path = "../extended_csv_stream_execution.rs"]
mod extended_csv_stream_execution;
#[path = "../extended_csv_table_execution.rs"]
mod extended_csv_table_execution;
#[path = "../extended_csv_write_execution.rs"]
mod extended_csv_write_execution;
#[path = "../extended_data_analyze_execution.rs"]
mod extended_data_analyze_execution;
#[path = "../extended_decimal_execution.rs"]
mod extended_decimal_execution;
#[path = "../extended_decimal_ledger_execution.rs"]
mod extended_decimal_ledger_execution;
#[path = "../extended_deflate_execution.rs"]
mod extended_deflate_execution;
#[path = "../extended_dependency_order_execution.rs"]
mod extended_dependency_order_execution;
#[path = "../extended_der_execution.rs"]
mod extended_der_execution;
#[path = "../extended_diff_patch_execution.rs"]
mod extended_diff_patch_execution;
#[path = "../extended_discrete_distributions_execution.rs"]
mod extended_discrete_distributions_execution;
#[path = "../extended_distributions_execution.rs"]
mod extended_distributions_execution;
#[path = "../extended_dns_client_execution.rs"]
mod extended_dns_client_execution;
#[path = "../extended_dns_execution.rs"]
mod extended_dns_execution;
#[path = "../extended_expr_calc_execution.rs"]
mod extended_expr_calc_execution;
#[path = "../extended_fetch_many_execution.rs"]
mod extended_fetch_many_execution;
#[path = "../extended_fetch_url_execution.rs"]
mod extended_fetch_url_execution;
#[path = "../extended_form_execution.rs"]
mod extended_form_execution;
#[path = "../extended_form_model_execution.rs"]
mod extended_form_model_execution;
#[path = "../extended_form_resources_execution.rs"]
mod extended_form_resources_execution;
#[path = "../extended_geometry_execution.rs"]
mod extended_geometry_execution;
#[path = "../extended_glob_execution.rs"]
mod extended_glob_execution;
#[path = "../extended_gpu_execution.rs"]
mod extended_gpu_execution;
#[path = "../extended_graph_components_execution.rs"]
mod extended_graph_components_execution;
#[path = "../extended_graph_components_model_execution.rs"]
mod extended_graph_components_model_execution;
#[path = "../extended_graph_components_resource_execution.rs"]
mod extended_graph_components_resource_execution;
#[path = "../extended_graph_diffuse_execution.rs"]
mod extended_graph_diffuse_execution;
#[path = "../extended_graph_execution.rs"]
mod extended_graph_execution;
#[path = "../extended_graph_model_execution.rs"]
mod extended_graph_model_execution;
#[path = "../extended_graph_resource_execution.rs"]
mod extended_graph_resource_execution;
#[path = "../extended_graph_walk_execution.rs"]
mod extended_graph_walk_execution;
#[path = "../extended_higher_statistics_execution.rs"]
mod extended_higher_statistics_execution;
#[path = "../extended_hpack_execution.rs"]
mod extended_hpack_execution;
#[path = "../extended_http2_execution.rs"]
mod extended_http2_execution;
#[path = "../extended_http2_server_execution.rs"]
mod extended_http2_server_execution;
#[path = "../extended_http_agent_execution.rs"]
mod extended_http_agent_execution;
#[path = "../extended_http_batch_execution.rs"]
mod extended_http_batch_execution;
#[path = "../extended_http_client_execution.rs"]
mod extended_http_client_execution;
#[path = "../extended_http_cursor_execution.rs"]
mod extended_http_cursor_execution;
#[path = "../extended_http_exchange_execution.rs"]
mod extended_http_exchange_execution;
#[path = "../extended_http_execution.rs"]
mod extended_http_execution;
#[path = "../extended_http_message_execution.rs"]
mod extended_http_message_execution;
#[path = "../extended_http_protocol_execution.rs"]
mod extended_http_protocol_execution;
#[path = "../extended_http_proxy_execution.rs"]
mod extended_http_proxy_execution;
#[path = "../extended_http_server_exchange_execution.rs"]
mod extended_http_server_exchange_execution;
#[path = "../extended_http_server_execution.rs"]
mod extended_http_server_execution;
#[path = "../extended_http_service_execution.rs"]
mod extended_http_service_execution;
#[path = "../extended_http_url_execution.rs"]
mod extended_http_url_execution;
#[path = "../extended_https_batch_execution.rs"]
mod extended_https_batch_execution;
#[path = "../extended_https_fetch_execution.rs"]
mod extended_https_fetch_execution;
#[path = "../extended_https_mutual_tls_execution.rs"]
mod extended_https_mutual_tls_execution;
#[path = "../extended_https_server_exchange_execution.rs"]
mod extended_https_server_exchange_execution;
#[path = "../extended_https_server_execution.rs"]
mod extended_https_server_execution;
#[path = "../extended_image_execution.rs"]
mod extended_image_execution;
#[path = "../extended_image_resize_execution.rs"]
mod extended_image_resize_execution;
#[path = "../extended_image_resize_model_execution.rs"]
mod extended_image_resize_model_execution;
#[path = "../extended_image_resize_resources_execution.rs"]
mod extended_image_resize_resources_execution;
#[path = "../extended_image_resize_tool_execution.rs"]
mod extended_image_resize_tool_execution;
#[path = "../extended_image_tool_execution.rs"]
mod extended_image_tool_execution;
#[path = "../extended_inflate_execution.rs"]
mod extended_inflate_execution;
#[path = "../extended_json_check_execution.rs"]
mod extended_json_check_execution;
#[path = "../extended_json_execution.rs"]
mod extended_json_execution;
#[path = "../extended_json_stream_execution.rs"]
mod extended_json_stream_execution;
#[path = "../extended_json_streaming_execution.rs"]
mod extended_json_streaming_execution;
#[path = "../extended_kv_execution.rs"]
mod extended_kv_execution;
#[path = "../extended_lex_scan_execution.rs"]
mod extended_lex_scan_execution;
#[path = "../extended_lexer_execution.rs"]
mod extended_lexer_execution;
#[path = "../extended_linalg_execution.rs"]
mod extended_linalg_execution;
#[path = "../extended_merge3_execution.rs"]
mod extended_merge3_execution;
#[path = "../extended_msgpack_execution.rs"]
mod extended_msgpack_execution;
#[path = "../extended_openssl_digest_execution.rs"]
mod extended_openssl_digest_execution;
#[path = "../extended_openssl_hash_execution.rs"]
mod extended_openssl_hash_execution;
#[path = "../extended_openssl_mutual_tls_execution.rs"]
mod extended_openssl_mutual_tls_execution;
#[path = "../extended_openssl_tls_duplex_execution.rs"]
mod extended_openssl_tls_duplex_execution;
#[path = "../extended_openssl_tls_execution.rs"]
mod extended_openssl_tls_execution;
#[path = "../extended_openssl_tls_server_execution.rs"]
mod extended_openssl_tls_server_execution;
#[path = "../extended_openssl_tls_server_shutdown_execution.rs"]
mod extended_openssl_tls_server_shutdown_execution;
#[path = "../extended_parse_execution.rs"]
mod extended_parse_execution;
#[path = "../extended_patchset_execution.rs"]
mod extended_patchset_execution;
#[path = "../extended_path_filter_execution.rs"]
mod extended_path_filter_execution;
#[path = "../extended_percent_execution.rs"]
mod extended_percent_execution;
#[path = "../extended_png_execution.rs"]
mod extended_png_execution;
#[path = "../extended_pratt_execution.rs"]
mod extended_pratt_execution;
#[path = "../extended_progress_execution.rs"]
mod extended_progress_execution;
#[path = "../extended_reactive_execution.rs"]
mod extended_reactive_execution;
#[path = "../extended_regex_execution.rs"]
mod extended_regex_execution;
#[path = "../extended_regex_oracle_execution.rs"]
mod extended_regex_oracle_execution;
#[path = "../extended_regex_text_execution.rs"]
mod extended_regex_text_execution;
#[path = "../extended_regex_workspace_execution.rs"]
mod extended_regex_workspace_execution;
#[path = "../extended_route_cost_execution.rs"]
mod extended_route_cost_execution;
#[path = "../extended_sample_counts_execution.rs"]
mod extended_sample_counts_execution;
#[path = "../extended_sample_distribution_execution.rs"]
mod extended_sample_distribution_execution;
#[path = "../extended_sample_moments_execution.rs"]
mod extended_sample_moments_execution;
#[path = "../extended_schema_execution.rs"]
mod extended_schema_execution;
#[path = "../extended_sed_execution.rs"]
mod extended_sed_execution;
#[path = "../extended_seqdiff_execution.rs"]
mod extended_seqdiff_execution;
#[path = "../extended_server_concurrency_execution.rs"]
mod extended_server_concurrency_execution;
#[path = "../extended_server_poll_execution.rs"]
mod extended_server_poll_execution;
#[path = "../extended_server_poll_limits_execution.rs"]
mod extended_server_poll_limits_execution;
#[path = "../extended_server_poll_nondestroy_execution.rs"]
mod extended_server_poll_nondestroy_execution;
#[path = "../extended_server_poll_ownership_execution.rs"]
mod extended_server_poll_ownership_execution;
#[path = "../extended_settings_execution.rs"]
mod extended_settings_execution;
#[path = "../extended_shape_hull_execution.rs"]
mod extended_shape_hull_execution;
#[path = "../extended_signal_execution.rs"]
mod extended_signal_execution;
#[path = "../extended_sparse_cg_contract_execution.rs"]
mod extended_sparse_cg_contract_execution;
#[path = "../extended_sparse_cg_model_execution.rs"]
mod extended_sparse_cg_model_execution;
#[path = "../extended_sparse_cg_scale_execution.rs"]
mod extended_sparse_cg_scale_execution;
#[path = "../extended_sparse_contract_execution.rs"]
mod extended_sparse_contract_execution;
#[path = "../extended_sparse_model_execution.rs"]
mod extended_sparse_model_execution;
#[path = "../extended_sparse_paths_execution.rs"]
mod extended_sparse_paths_execution;
#[path = "../extended_sparse_product_contract_execution.rs"]
mod extended_sparse_product_contract_execution;
#[path = "../extended_sparse_product_model_execution.rs"]
mod extended_sparse_product_model_execution;
#[path = "../extended_sparse_product_scale_execution.rs"]
mod extended_sparse_product_scale_execution;
#[path = "../extended_sparse_scale_execution.rs"]
mod extended_sparse_scale_execution;
#[path = "../extended_sqlite_allocation_execution.rs"]
mod extended_sqlite_allocation_execution;
#[path = "../extended_sqlite_execution.rs"]
mod extended_sqlite_execution;
#[path = "../extended_sqlite_program_execution.rs"]
mod extended_sqlite_program_execution;
#[path = "../extended_sqlite_statement_execution.rs"]
mod extended_sqlite_statement_execution;
#[path = "../extended_statistics_execution.rs"]
mod extended_statistics_execution;
#[path = "../extended_statistics_scaling_execution.rs"]
mod extended_statistics_scaling_execution;
#[path = "../extended_streaming_deflate_execution.rs"]
mod extended_streaming_deflate_execution;
#[path = "../extended_streaming_deflate_model_execution.rs"]
mod extended_streaming_deflate_model_execution;
#[path = "../extended_table_execution.rs"]
mod extended_table_execution;
#[path = "../extended_tar_bytes_execution.rs"]
mod extended_tar_bytes_execution;
#[path = "../extended_tar_execution.rs"]
mod extended_tar_execution;
#[path = "../extended_terminal_execution.rs"]
mod extended_terminal_execution;
#[path = "../extended_text_case_execution.rs"]
mod extended_text_case_execution;
#[path = "../extended_text_grep_execution.rs"]
mod extended_text_grep_execution;
#[path = "../extended_text_grep_recursive_execution.rs"]
mod extended_text_grep_recursive_execution;
#[path = "../extended_text_normalize_execution.rs"]
mod extended_text_normalize_execution;
#[path = "../extended_text_patch_execution.rs"]
mod extended_text_patch_execution;
#[path = "../extended_text_sentences_execution.rs"]
mod extended_text_sentences_execution;
#[path = "../extended_text_wrap_execution.rs"]
mod extended_text_wrap_execution;
#[path = "../extended_textutils_execution.rs"]
mod extended_textutils_execution;
#[path = "../extended_tgz_execution.rs"]
mod extended_tgz_execution;
#[path = "../extended_timezone_execution.rs"]
mod extended_timezone_execution;
#[path = "../extended_timezone_tool_execution.rs"]
mod extended_timezone_tool_execution;
#[path = "../extended_toml_execution.rs"]
mod extended_toml_execution;
#[path = "../extended_toml_normalize_execution.rs"]
mod extended_toml_normalize_execution;
#[path = "../extended_toml_oracle_execution.rs"]
mod extended_toml_oracle_execution;
#[path = "../extended_toml_streaming_execution.rs"]
mod extended_toml_streaming_execution;
#[path = "../extended_toml_streaming_model_execution.rs"]
mod extended_toml_streaming_model_execution;
#[path = "../extended_unicode_case_execution.rs"]
mod extended_unicode_case_execution;
#[path = "../extended_unicode_graphemes_execution.rs"]
mod extended_unicode_graphemes_execution;
#[path = "../extended_unicode_lines_execution.rs"]
mod extended_unicode_lines_execution;
#[path = "../extended_unicode_normalize_execution.rs"]
mod extended_unicode_normalize_execution;
#[path = "../extended_unicode_sentences_execution.rs"]
mod extended_unicode_sentences_execution;
#[path = "../extended_unicode_uconv_execution.rs"]
mod extended_unicode_uconv_execution;
#[path = "../extended_unicode_words_execution.rs"]
mod extended_unicode_words_execution;
#[path = "../extended_unpack_execution.rs"]
mod extended_unpack_execution;
#[path = "../extended_uri_component_execution.rs"]
mod extended_uri_component_execution;
#[path = "../extended_uri_execution.rs"]
mod extended_uri_execution;
#[path = "../extended_uri_resolve_execution.rs"]
mod extended_uri_resolve_execution;
#[path = "../extended_uri_resolve_program_execution.rs"]
mod extended_uri_resolve_program_execution;
#[path = "../extended_url_adoption_execution.rs"]
mod extended_url_adoption_execution;
#[path = "../extended_url_client_execution.rs"]
mod extended_url_client_execution;
#[path = "../extended_url_connect_execution.rs"]
mod extended_url_connect_execution;
#[path = "../extended_url_execution.rs"]
mod extended_url_execution;
#[path = "../extended_wave_execution.rs"]
mod extended_wave_execution;
#[path = "../extended_wave_spectrum_execution.rs"]
mod extended_wave_spectrum_execution;
#[path = "../extended_wave_tool_execution.rs"]
mod extended_wave_tool_execution;
#[path = "../extended_websocket_client_execution.rs"]
mod extended_websocket_client_execution;
#[path = "../extended_websocket_echo_execution.rs"]
mod extended_websocket_echo_execution;
#[path = "../extended_websocket_execution.rs"]
mod extended_websocket_execution;
#[path = "../extended_websocket_once_execution.rs"]
mod extended_websocket_once_execution;
#[path = "../extended_websocket_server_execution.rs"]
mod extended_websocket_server_execution;
#[path = "../extended_websocket_service_execution.rs"]
mod extended_websocket_service_execution;
#[path = "../extended_websocket_transport_execution.rs"]
mod extended_websocket_transport_execution;
#[path = "../extended_websocket_upgrade_app_execution.rs"]
mod extended_websocket_upgrade_app_execution;
#[path = "../extended_websocket_upgrade_execution.rs"]
mod extended_websocket_upgrade_execution;
#[path = "../extended_websocket_wire_execution.rs"]
mod extended_websocket_wire_execution;
#[path = "../extended_weighted_graph_execution.rs"]
mod extended_weighted_graph_execution;
#[path = "../extended_weighted_graph_model_execution.rs"]
mod extended_weighted_graph_model_execution;
#[path = "../extended_weighted_graph_resources_execution.rs"]
mod extended_weighted_graph_resources_execution;
#[path = "../extended_weighted_statistics_execution.rs"]
mod extended_weighted_statistics_execution;
#[path = "../extended_wordiff_execution.rs"]
mod extended_wordiff_execution;
#[path = "../extended_x509_execution.rs"]
mod extended_x509_execution;
#[path = "../extended_zip_bytes_execution.rs"]
mod extended_zip_bytes_execution;
#[path = "../extended_zip_execution.rs"]
mod extended_zip_execution;
#[path = "../extended_zip_manifest_execution.rs"]
mod extended_zip_manifest_execution;
#[path = "../extended_zip_metadata_execution.rs"]
mod extended_zip_metadata_execution;
#[path = "../extended_zstd_execution.rs"]
mod extended_zstd_execution;

#[path = "../extended_window_execution.rs"]
mod extended_window_execution;
