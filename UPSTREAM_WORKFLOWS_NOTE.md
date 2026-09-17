# Upstream workflows archive

The upstream `.github/workflows` files are preserved verbatim under `.upstream-github/workflows/`.
They are moved out of the active GitHub Actions path only because the repository token is not allowed to create/update workflow files from a workflow run.
Source code, build files, LFS content, native runtime files and the rest of the upstream tree remain in their original paths.
