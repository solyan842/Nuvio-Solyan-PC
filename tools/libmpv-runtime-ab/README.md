# Nuvio PC / SFilm3 — PlayTorrio libmpv Runtime A/B

Purpose
-------
Test whether the SFilm3/VSMOV series bug is caused by Nuvio's older bundled Windows libmpv/FFmpeg runtime.

Observed control:
- SFilm3 fails in Nuvio PC.
- SFilm3 works on other Nuvio platforms.
- SFilm2 works in Nuvio PC.
- SFilm3 works in PlayTorrio on Windows.
- Header A/B did not fix it.
- Initial-resume A/B did not fix it.

This A/B changes ONE thing only:
- replaces native/windows/libmpv-2.dll inside the installed Nuvio application JAR
- leaves player_bridge.dll untouched
- leaves Nuvio Kotlin/UI/EOF/auto-next logic untouched
- leaves SFilm3 untouched

Runtime used:
- Predidit/media-kit Windows libmpv build
- release: 202609151348
- file: mpv-dev-x86_64-20260915-git-0b7ed67.7z
- archive SHA256: 8adceab30b6bcc5503fa9d3823b68f4acd15ee1c41d6dc2492826f373531c10a
- this is the Windows runtime source used by current PlayTorrio media_kit dependency

Original Nuvio upstream libmpv:
- LFS SHA256: 07c68bb211f23a218ded0a36eb12207dc3aeb44e5318ffca6ce9dcc7c3173906
- unchanged in Nuvio repository since 2026-06-16

Before applying
---------------
If either previous A/B patch is still active, run its ROLLBACK.cmd first.
The script also checks the known player_bridge hashes and refuses to stack patches.

Test
----
1. Close Nuvio completely.
2. Run APPLY.cmd and approve UAC.
3. Start the same installed Nuvio.
4. Open the same SFilm3 series episode.
5. If it now plays normally, the fault is isolated to Nuvio's Windows libmpv/FFmpeg runtime.
6. If it still jumps to EOF, run ROLLBACK.cmd; runtime version is eliminated and the next A/B should target Nuvio's HLS/cache/demuxer options.

Safety
------
- validates the installed Nuvio libmpv hash before changing anything
- full application JAR is backed up first
- backup hash is verified before patching
- replaces one JAR entry only
- rollback restores the exact original JAR
- AppData/account/addon configuration is untouched
