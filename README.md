Fedora 37 I/O Audit and GitHub Pages Deployment

This repository contains an audit of a Fedora 37 troubleshooting session,
the corrected RPM Fusion repository configuration, and a script that emits
and deploys this site to GitHub Pages under strict shell constraints.

Audit findings

Finding 1. PackageKit was not the memory bottleneck.
PackageKit was stopped, yet memory pressure remained near 79 percent while
2.7 GiB RAM was free and swap usage was 106 MiB. Disk I/O pressure reached
91.69 percent. The optical drive /dev/sr0 was repeatedly failing reads and
keeping processes in D state, driving CPU I/O wait to 25 to 50 percent.

Finding 2. Package name misspelling.
The command attempted to install smarctl four times. The correct package is
smartmontools, and the binary it provides is smartctl.

Finding 3. RPM Fusion 404 is expected end of life behavior.
Fedora 37 is end of life and RPM Fusion no longer serves Fedora 37
repositories. The correct local change is enabled=0 and
skip_if_unavailable=True. Do not rewrite metalink URLs to pretend the
machine is a newer release.

Finding 4. System disk SMART passed.
smartctl -H returned PASSED. Reallocated sectors are 11 with 2 events,
pending sectors and offline uncorrectable sectors are zero. The Hitachi
drive is not failing. Do not run fsck on the mounted root.

Finding 5. Script must guard remote operations.
The original script had no gh auth status preflight and would abort silently
on remote failures under a no-exit-1 constraint. This script records errors
and returns nonzero from main only.

Corrected RPM Fusion configuration

rpmfusion-nonfree-nvidia-driver
enabled=0
skip_if_unavailable=True

rpmfusion-nonfree-steam
enabled=0
skip_if_unavailable=True

Fedora 37 is archived upstream. Migrate to a supported release separately.
Do not mix repository metadata across releases on this installed system.

Script constraints

No sed, no set -e, no exit 1, no 2>/dev/null, no subprocess.run.
Every repository file is written through a heredoc.
gh auth status is checked before any remote operation.
gh repo create --source=. --push is used for the initial push.
Pages is enabled and monitored through gh api.
xdg-open is called on the Pages URL after build completion.
The script is anchored to the directory it is run from and creates no files
outside that directory.

Usage

cd <the directory that should host the repo>
chmod +x deploy_audit_site.sh
./deploy_audit_site.sh

Prerequisites

GitHub CLI authenticated with gh auth login.
Node.js 18 or newer and npm.
Network access to GitHub and the npm registry.
