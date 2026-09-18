# Nuvio PC / SFilm3 — PlayTorrio Header A/B

This package tests one narrow Windows compatibility hypothesis.

It changes only the native Windows player bridge:
- Connection: keep-alive
- Accept: */*
- browser User-Agent
- addon-provided headers keep priority

It does NOT change SFilm3, episode IDs, duration, EOF, auto-next, UI, account or addon settings.

Test:
1. Close Nuvio completely.
2. Run APPLY.cmd and approve UAC.
3. Start the existing Nuvio installation.
4. Open one SFilm3 series episode that previously jumped to the end.
5. SFilm2 series is the control.
6. Close Nuvio and run ROLLBACK.cmd if needed.

Safety:
- finds the actual app JAR by verifying native/windows/player_bridge.dll exists inside
- refuses to patch while Nuvio is running
- refuses signed JARs
- creates and verifies an untouched full JAR backup before changing one entry
- rollback restores the original JAR
- user AppData/configuration is not modified

Base upstream: 796f10dddfceabdd6ab7e06a7e43b283f28fd2aa
Native A/B branch: solyan-ab-playtorrio-native-headers
