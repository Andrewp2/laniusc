//! Host-only transport/schedule tests. No compiler, shader, device, or GPU run.
//! Integrate as a child module of dispatch after BatchPlan is added.
//! These fixtures validate row spans and storage schedules, not semantic rows.

use super::*;

fn transport_catalog(atom_prefix: u32) -> Arc<FrozenCatalog> {
    let mut catalog = FrozenCatalog::freeze(&[]).unwrap();
    if atom_prefix != 0 {
        let c = Arc::get_mut(&mut catalog).unwrap();
        let mut words = c.words.to_vec();
        c.slices[1] = Slice {
            offset: words.len() as u32,
            count: atom_prefix,
            capacity: atom_prefix,
        };
        c.tables.words[1] = vec![0; atom_prefix as usize * WIDTHS[1] as usize];
        words.extend_from_slice(&c.tables.words[1]);
        // Rehouse the atom-sized index while preserving the actual empty
        // catalog's status row. Unused old storage remains outside the views.
        for (table, count) in [
            (6, atom_prefix),
            (7, buckets(atom_prefix).unwrap()),
            (12, buckets(atom_prefix).unwrap()),
        ] {
            c.outputs[table] = Slice {
                offset: words.len() as u32,
                count,
                capacity: count,
            };
            words.resize(words.len() + (count * OUTPUT_WIDTHS[table]) as usize, 0);
        }
        c.words = words.into();
    }
    catalog
}

fn transport_tables(counts: [u32; TABLE_COUNT]) -> Tables {
    let mut tables = Tables::default();
    for table in 0..TABLE_COUNT {
        tables.words[table].resize((counts[table] * WIDTHS[table]) as usize, 0);
    }
    tables
}

fn transport_submission(
    catalog: &FrozenCatalog,
    prior: [u32; TABLE_COUNT],
    next: [u32; TABLE_COUNT],
) -> (OutputLayout, Submission) {
    let mut input = AppendArena::default();
    input.prepare(&transport_tables(prior)).unwrap();
    let (copies, mut writes) = input.prepare(&transport_tables(next)).unwrap();
    let output_counts = |counts: [u32; TABLE_COUNT]| {
        let index = catalog.slices[1].count.max(catalog.slices[9].count);
        [
            1,
            catalog.slices[9].count,
            counts[13],
            counts[16],
            counts[15],
            counts[16],
            index,
            buckets(index).unwrap(),
            counts[14],
            buckets(counts[14]).unwrap(),
            1,
            catalog.slices[9].count,
            buckets(index).unwrap(),
        ]
    };
    let mut output = OutputArena::default();
    output.prepare(output_counts(prior)).unwrap();
    let (output_copies, mut initialize_outputs) = output.prepare(output_counts(next)).unwrap();
    let rebuild = buckets(prior[14]).unwrap() != buckets(next[14]).unwrap();
    if rebuild {
        initialize_outputs.retain(|range| range.table != 8 && range.table != 9);
        initialize_outputs.push(OutputRange {
            table: 8,
            first_row: 0,
            row_count: next[14],
        });
        initialize_outputs.push(OutputRange {
            table: 9,
            first_row: 0,
            row_count: buckets(next[14]).unwrap(),
        });
    }
    let serial = 9;
    let (mut header, _) = catalog_bootstrap(catalog).unwrap();
    header[4] = serial;
    for table in 0..TABLE_COUNT {
        let start = DIRECTORY_WORD as usize + table * 6;
        let slice = input.slices[table];
        header[start + 2..start + 5].copy_from_slice(&[slice.offset, slice.count, slice.capacity]);
    }
    for table in [2, 3, 4, 5, 8, 9, 10] {
        let start = OUTPUT_DIRECTORY_WORD as usize + table * 5;
        let slice = output.slices[table];
        header[start..start + 5].copy_from_slice(&[
            1,
            slice.offset,
            slice.count,
            slice.capacity,
            OUTPUT_WIDTHS[table],
        ]);
    }
    writes.push(ArenaWrite {
        first_word: 0,
        words: header,
    });
    let delta = |table: usize| Span::new(prior[table], next[table] - prior[table]).unwrap();
    let submission = Submission {
        epoch: catalog.epoch,
        arena_id: 7,
        serial,
        context_span: delta(13),
        call_span: delta(15),
        obligation_span: delta(16),
        assumption_index_span: if rebuild {
            Span::new(0, next[14]).unwrap()
        } else {
            delta(14)
        },
        plan: UploadPlan {
            copies,
            writes,
            output_copies,
            initialize_outputs,
            input_word_count: input.next_word,
            output_word_count: output.next_word,
        },
    };
    let layout = OutputLayout::from_submission(catalog, &submission).unwrap();
    (layout, submission)
}

fn span_pair(span: Span) -> (u32, u32) {
    (span.first, span.count)
}

#[test]
fn host_batch_plan_admits_only_new_suffix_rows_after_the_catalog_prefix() {
    let catalog = transport_catalog(3);
    let mut prior = [0; TABLE_COUNT];
    prior[1] = 2;
    prior[5] = 1;
    prior[13] = 2;
    prior[15] = 3;
    prior[16] = 4;
    let mut next = prior;
    next[1] = 5;
    next[5] = 3;
    next[13] = 3;
    next[15] = 5;
    next[16] = 7;
    let (layout, submission) = transport_submission(&catalog, prior, next);
    let plan = BatchPlan::new(&catalog, &layout, prior, &submission).unwrap();
    assert_eq!(
        span_pair(plan.input_spans[1]),
        (5, 3),
        "catalog atoms plus old suffix precede admission"
    );
    assert_eq!(span_pair(plan.input_spans[5]), (1, 2));
    assert_eq!(span_pair(plan.input_spans[13]), (2, 1));
    assert_eq!(span_pair(plan.input_spans[15]), (3, 2));
    assert_eq!(span_pair(plan.input_spans[16]), (4, 3));
    for table in CATALOG_ONLY {
        assert_eq!(span_pair(plan.input_spans[table]), (0, 0));
    }
}

#[test]
fn host_batch_plan_normalizes_empty_spans_even_with_existing_rows() {
    let catalog = transport_catalog(3);
    let mut prior = [0; TABLE_COUNT];
    prior[1] = 2;
    prior[13] = 2;
    prior[14] = 3;
    prior[15] = 4;
    prior[16] = 5;
    let (layout, submission) = transport_submission(&catalog, prior, prior);
    let plan = BatchPlan::new(&catalog, &layout, prior, &submission).unwrap();
    assert!(
        plan.input_spans
            .iter()
            .all(|span| span_pair(*span) == (0, 0))
    );
    assert_eq!(span_pair(submission.assumption_index_span), (0, 0));
    let mut noncanonical = submission.clone();
    noncanonical.call_span = Span {
        first: prior[15],
        count: 0,
    };
    assert!(
        BatchPlan::new(&catalog, &layout, prior, &noncanonical).is_err(),
        "a stale nonzero empty span must not be treated as the exact submitted range"
    );
}

#[test]
fn host_batch_plan_rejects_mismatched_context_call_and_obligation_ranges() {
    let catalog = transport_catalog(0);
    let prior = [0; TABLE_COUNT];
    let mut next = prior;
    next[13] = 2;
    next[15] = 3;
    next[16] = 4;
    let (layout, submission) = transport_submission(&catalog, prior, next);
    BatchPlan::new(&catalog, &layout, prior, &submission).unwrap();
    for field in ["context", "call", "obligation"] {
        let mut mismatched = submission.clone();
        let span = match field {
            "context" => &mut mismatched.context_span,
            "call" => &mut mismatched.call_span,
            _ => &mut mismatched.obligation_span,
        };
        span.count -= 1;
        assert!(
            BatchPlan::new(&catalog, &layout, prior, &mismatched).is_err(),
            "omitted {field} row"
        );
    }
}

#[test]
fn host_batch_plan_rejects_shrinking_shared_and_batch_suffixes() {
    let catalog = transport_catalog(3);
    let prior = [0; TABLE_COUNT];
    let (layout, submission) = transport_submission(&catalog, prior, prior);
    for table in [1, 5, 13, 15, 16] {
        let mut impossible_prior = prior;
        impossible_prior[table] = 1;
        assert!(
            BatchPlan::new(&catalog, &layout, impossible_prior, &submission).is_err(),
            "table {table} cannot lose a previously admitted suffix row"
        );
    }
}

#[test]
fn host_batch_plan_rebuilds_all_assumptions_only_when_bucket_count_changes() {
    let catalog = transport_catalog(0);
    for (old, new, expected, wrong) in [
        (3, 4, (3, 1), (0, 4)), // Eight buckets remain eight: insert new row only.
        (4, 5, (0, 5), (4, 1)), // Eight buckets grow to sixteen: reinsert all rows.
    ] {
        let mut prior = [0; TABLE_COUNT];
        prior[14] = old;
        let mut next = prior;
        next[14] = new;
        let (layout, submission) = transport_submission(&catalog, prior, next);
        assert_eq!(span_pair(submission.assumption_index_span), expected);
        let plan = BatchPlan::new(&catalog, &layout, prior, &submission).unwrap();
        assert_eq!(span_pair(plan.assumption_index), expected);
        assert_eq!(
            span_pair(plan.input_spans[14]),
            (old, new - old),
            "reindexing old assumptions does not readmit old input rows"
        );
        let mut mismatched = submission.clone();
        mismatched.assumption_index_span = Span::new(wrong.0, wrong.1).unwrap();
        assert!(BatchPlan::new(&catalog, &layout, prior, &mismatched).is_err());
    }
}

#[test]
fn host_batch_output_reset_requires_one_fresh_receipt_for_an_empty_delta() {
    let catalog = transport_catalog(0);
    let counts = [0; TABLE_COUNT];
    let (layout, submission) = transport_submission(&catalog, counts, counts);
    BatchPlan::new(&catalog, &layout, counts, &submission).unwrap();
    let resets = layout.reset_writes(&submission).unwrap();
    assert_eq!(resets.len(), 1, "empty delta still resets its receipt");
    assert_eq!(resets[0].first_word, layout.slices[10].offset);
    assert_eq!(
        resets[0].words,
        [0, 0, INVALID, INVALID, 0, 0, submission.serial, 0]
    );

    let mut missing = submission.clone();
    missing
        .plan
        .initialize_outputs
        .retain(|range| range.table != 10);
    assert!(layout.reset_writes(&missing).is_err());
    assert!(BatchPlan::new(&catalog, &layout, counts, &missing).is_err());
    let mut duplicate = submission.clone();
    duplicate.plan.initialize_outputs.push(OutputRange {
        table: 10,
        first_row: 0,
        row_count: 1,
    });
    assert!(layout.reset_writes(&duplicate).is_err());
    assert!(BatchPlan::new(&catalog, &layout, counts, &duplicate).is_err());
}

#[test]
fn host_batch_plan_rejects_reset_gaps_duplicates_and_old_result_overwrites() {
    let catalog = transport_catalog(0);
    let mut prior = [0; TABLE_COUNT];
    prior[13] = 2;
    let mut next = prior;
    next[13] = 4;
    let (layout, submission) = transport_submission(&catalog, prior, next);
    BatchPlan::new(&catalog, &layout, prior, &submission).unwrap();
    for corruption in ["gap", "duplicate", "old result"] {
        let mut broken = submission.clone();
        let reset = broken
            .plan
            .initialize_outputs
            .iter_mut()
            .find(|range| range.table == 2)
            .unwrap();
        match corruption {
            "gap" => reset.row_count -= 1,
            "old result" => {
                reset.first_row = 0;
                reset.row_count = 4;
            }
            _ => broken.plan.initialize_outputs.push(OutputRange {
                table: 2,
                first_row: 2,
                row_count: 1,
            }),
        }
        assert!(
            BatchPlan::new(&catalog, &layout, prior, &broken).is_err(),
            "{corruption}"
        );
    }
}

#[test]
fn host_batch_diagnostic_prefers_the_receipts_named_failure_rows() {
    let catalog = transport_catalog(0);
    let mut prior = [0; TABLE_COUNT];
    prior[13] = 2;
    prior[15] = 3;
    prior[16] = 4;
    let mut next = prior;
    next[13] = 4;
    next[15] = 5;
    next[16] = 7;
    let (_, submission) = transport_submission(&catalog, prior, next);
    let valid = [1, 0, INVALID, INVALID, 0, 0, 0, 0];
    let named_call = [6, 41, 4, 6, 0, 0, 0, 0];
    let unrelated_limit = [4, 51, 5, INVALID, 65, 64, 0, 0];
    let named_obligation = [3, 61, 6, INVALID, 0, 0, 0, 0];
    let receipt = [6, 0, 4, 6, 0, 0, submission.serial, 0];
    let failure = EvidenceDispatchFailure::new(
        &submission,
        valid,
        receipt,
        &[valid, valid],
        &[[0; 8], named_call],
        &[[0; 8], unrelated_limit, named_obligation],
    );
    assert_eq!(failure.context, None);
    assert_eq!(failure.call, Some((4, named_call)));
    assert_eq!(
        failure.obligation,
        Some((6, named_obligation)),
        "the named obligation wins over an earlier unprocessed row and another terminal failure"
    );
    assert_eq!(
        (failure.epoch, failure.arena_id, failure.serial),
        (submission.epoch, submission.arena_id, submission.serial)
    );
}
