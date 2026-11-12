Fedora 37 I/O Audit and GitHub Pages Deployment

This repository contains an audit of a Fedora 37 troubleshooting session,
the corrected RPM Fusion repository configuration, and a script that emits
and deploys the site to GitHub Pages.

Audit findings

1. PackageKit was not the memory bottleneck. PackageKit stopped, yet memory
   PSI stayed near 79 percent while 2.7 GiB RAM was free. I/O PSI was 91.69
   percent. The optical drive /dev/sr0 was repeatedly failing reads.
2. Package name misspelling. smarctl was used four times. The correct package
   is smartmontools, and the binary is smartctl.
3. RPM Fusion 404 is EOL behavior. Fedora 37 EOL was 2023-12-05, and RPM Fusion
   follows upstream EOL. Set enabled=0 and skip_if_unavailable=True.
4. System disk SMART passed. smartctl -H returned PASSED. Pending and offline
   uncorrectable sectors are zero.
5. Script lacked gh preflight. gh auth status is now checked before remote
   operations, and failures are logged rather than forced to exit.

References

Fedora End of Life Releases
https://docs.fedoraproject.org/en-US/releases/eol/

RPM Fusion FAQ
https://rpmfusion.org/FAQ

Linux kernel PSI documentation
https://git.kernel.org/pub/scm/linux/kernel/git/chunkuang.hu/linux.git/plain/Documentation/accounting/psi.rst?id=7b43af7f4b48c1abb6df811dbaa644a0c7800366

smartctl manual page
https://www.smartmontools.org/browser/trunk/smartmontools/smartctl.8.in

PackageKit
https://github.com/PackageKit/PackageKit

actions/deploy-pages
https://github.com/actions/deploy-pages

gh repo create
https://cli.github.com/manual/gh_repo_create

gh run list
https://cli.github.com/manual/gh_run_list
