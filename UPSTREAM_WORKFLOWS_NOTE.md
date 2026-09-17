# Upstream workflows archive

The upstream `.github/workflows` files are preserved verbatim under `.upstream-github/workflows/`.
They are moved out of the active GitHub Actions path only because GitHub does not allow this workflow token to create/update workflow definitions on another branch.

All application source, Gradle configuration, vendor source, native Windows bridge, runtime files, assets and LFS objects remain at their upstream paths.
