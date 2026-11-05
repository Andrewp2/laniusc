#!/bin/bash
# lb.sh LOG: one leanslot lake build pass (<= 288 s) of the gate's targets in the regen worktree; prints rc,
# errors and the number of modules built. Exit code is lake's.
cd /home/andrew-peterson/code/laniusc-wt/regen/formal
LOG=$1
HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 288 ~/.elan/bin/lake build runAll extract floatTest x86ModelTest srcDump topAxioms LaniusMini Lanius LaniusOpen Lanius.Mini.FrontLex Lanius.Mini.MutPilotCorrect Lanius.Machines.SqliteStatementCorrect Lanius.Machines.TlsLifecycleCorrect Lanius.Machines.RunLowering Lanius.Faithful.SelfBounded Lanius.Faithful.SelfPre > $LOG 2>&1
rc=$?
echo "rc=$rc built=$(grep -c Built $LOG)"
grep -E "^error: [A-Za-z]|error: .*lean:" $LOG | grep -v "Lean exited\|build failed" | head -15 | cut -c1-300
exit $rc
