read the file at .prompt/system_prompt_addon.txt

Run `LANIUS_READBACK=0 LANIUS_GPU_TIMING=1 cargo run --bin perf_one --release` to test performance
Run `LANIUS_GPU_TIMING=1 cargo run --bin fuzz_lex` to test correctness
You may find the above commands do not work in the sandbox - just escalate to the user, and they can click "Always Allow" to allow you to run them.