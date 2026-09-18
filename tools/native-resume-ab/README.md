# Nuvio PC / SFilm3 — Windows Initial Resume A/B

Purpose: determine whether Nuvio Windows is opening SFilm3 episodes at EOF because the native bridge passes saved resume position to mpv as loadfile start=....

Change:
- Windows native player bridge only.
- Ignores initialPositionMs at mpv load time.
- Playback always starts from 0 for this diagnostic build.
- No HTTP header change.
- No EOF/auto-next change.
- No SFilm3 change.

Before applying:
- If you previously applied the PlayTorrio-header A/B, run its ROLLBACK.cmd first.
- This Apply script checks the previous backup and refuses to stack on top of it.

Test:
1. Close Nuvio.
2. Run APPLY.cmd.
3. Open the same SFilm3 episode that jumped directly to the end.
4. If it now starts at 00:00 and plays normally, resume-state/native start= is the cause.
5. If it still jumps to the end, resume is eliminated and we move to HLS/mpv timeline/EOF.
6. Run ROLLBACK.cmd after the test.

Base upstream: 796f10dddfceabdd6ab7e06a7e43b283f28fd2aa
A/B branch: solyan-ab-disable-windows-initial-resume
Native source commit: 85e6719853fa4a75a4ef3d45a05b44997206144f
