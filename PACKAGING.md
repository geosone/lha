# Disconnected by Peer AT package builds

The `debian` branch adds packaging to upstream revision
16619b066b189ef289bb8b07b37d1c38d550da99 (1.14i-ac20260723).
Upstream retains its original, non-OSI licence. Do not relabel LHA as GPL or
publish binary-only packages. The complete source, documentation and notices
are included in each DEB/MSI. See debian/copyright and upstream man/lha.n.

The single MinGW patch guards an otherwise unused symlink helper with the same
condition already used by its call site. Unix symlink behavior is unchanged;
Windows POSIX symlink support is not invented.

## Debian

Build with `docker build --target build -f packaging/Dockerfile.debian .`.
The oldest supported suite, Bookworm, is the build base. The same binary package
is tested on Debian 12 and 13, without distribution-specific package variants.
Source format is 3.0 (quilt); the upstream branch is master, the packaging branch
is debian. Create the matching upstream orig tarball when building a source
package outside the container.

Package lha-unix installs /usr/bin/lha.unix and registers the lha alternative
at priority 100. It does not own or overwrite Lhasa's executable. Existing
manual selections remain manual. Removing lha-unix selects a remaining provider
when the group is in automatic mode.

The upstream regular test suite runs during the build. Its default driver
excludes the removed stdin-file-list feature, the upstream incomplete test and
optional multi-gigabyte stress tests; this package does not weaken that driver.
The GitHub matrix builds amd64/arm64/armhf and tests each package on both suites.

## Windows

build_windows.ps1 invokes MinGW and wixl on Linux. It requires a fresh build and
output directory, Autotools-prepared unconfigured source and a matching complete
source archive. A Debian build followed by make distclean provides those inputs.
The workflow automates this preparation. Programs are named lha.exe on both
architectures and installed in Program Files/LHa for UNIX, with an MSI-owned appended system PATH entry.
The MSI includes source.tar.gz, original licence text and compiler notices.

Example:

```powershell
./build_windows.ps1 -Architecture x64 -SourceDirectory /tmp/prepared-source -SourceArchive /tmp/matching-source.tar.gz -BuildDirectory /tmp/lha-build -OutputDirectory /tmp/lha-output
```

The MSI version is 1.14.9703: its third field is the upstream date counted in
days since 2000-01-01 plus the packaging revision (9700 + 3). The package has stable architecture-specific component
and upgrade GUIDs. Windows filename Unicode support is not yet qualified.

## Bare names with -i when archiving

`debian/patches/add-ignore-directory.patch` extends the `i` option (ignore
directory path) from extraction to a/u/c: only the last path element is
stored, and on Windows a backslash or drive prefix also ends an element.
Directory entries are not stored, their files are. Mystic's archive records
call `lha -a -i "%1" "%2"`; on Windows our 1.14i-ac20260723-2 stored the full
`C:/.../FILE_ID.DIZ` path. Without `i` nothing changes. Release
1.14i-ac20260723-3 carries the patch.

dpkg-buildpackage unapplies the quilt series after the Debian build, so the
workflow re-applies it (`dpkg-source --before-build`) before packing the
prepared source, and `build_windows.ps1` refuses a tree whose applied
patches differ from the series. Earlier Windows builds, 1.14i-ac20260723-1
and -2 included, were compiled without the series; their only patch then
was the MinGW symlink guard, which hosted GCC did not need. Their embedded
source.tar.gz did contain the patches.

## Wildcard file arguments when archiving

Mystic packs QWK REP packets as `lha -a -i "%1" "%2"` with `%2` a quoted
`<root>/tempqwk/*`. No shell expands it, and cmd.exe never expands
wildcards, so 1.14i-ac20260723-3 created no packet on Linux or Windows.
`debian/patches/expand-add-wildcards.patch` makes lha expand, when
archiving, an argument that names no existing file but contains `*` or `?`
(glob on Unix, `_findfirst` on Windows). Existing files and patterns without
a match behave as before. Release 1.14i-ac20260723-4 carries the patch.

## Actual qualification on 2026-11-04

Debian amd64: regular upstream suite passed. The same DEB passed LHA/LZH round
trips and Lhasa coexistence on Debian 12/13, including manual alternatives,
automatic selection and uninstall fallback. x86/x64 MinGW executables depend
only on Windows KERNEL32.dll and msvcrt.dll. Both MSIs passed installation,
LHA/LZH round trips, embedded source/notice checks and uninstall on the native
Windows 10 x86/x64 lab hosts. No production BBS was modified.

The qualification scripts use relative stored filenames, as needed for later
FILE_ID.DIZ basename selection. Archive and output directory paths contain
spaces. Native Mystic archive.dat configuration is a separate installer step;
these tests must not be described as an already deployed BBS configuration.

GitHub matrix results extend the above evidence only after the corresponding
jobs pass. A successfully prepared workflow alone does not qualify ARM.

Installing the Windows MSI appends its own directory to machine PATH. Restart existing shells and services to inherit the change. Native tests verify CMD/PowerShell discovery and that uninstall restores the previous PATH. Portable archives do not change PATH.
