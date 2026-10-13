set debuginfod enabled off
set pagination off
break *0x40051c
commands
silent
printf "println data=%p len=%u return=%p\n", $rdi, $esi, *(void**)$rsp
continue
end
run
