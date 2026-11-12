#!/usr/bin/env bash
# deploy.sh — one-shot, idempotent, scope-anchored to $PWD.
# Emits every repo file via heredoc, builds Vite/React, pushes to GitHub,
# enables Pages, monitors the workflow, opens the page.
# Also emits flash-fedora.sh (not executed here).
# Constraints: no sed, no set -e, no exit 1, no subprocess.run.
# 2>/dev/null is avoided in this script; flash-fedora.sh uses it only for
# expected umount noise, which is documented in its header.

set +e
set +H

OPEN_BROWSER=1
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN_BROWSER=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-open]"
      echo "  --no-open   skip xdg-open after deployment"
      exit 0 ;;
  esac
done

main() {
  local ERRORS=0
  local REPO_NAME="fedora37-io-audit"
  local WORKDIR
  WORKDIR="$(pwd)"
  local GH_OWNER=""
  local PAGES_URL=""

  fail() { echo "ERROR: $1"; ERRORS=$((ERRORS + 1)); }
  ok()   { echo "OK: $1"; }
  info() { echo "INFO: $1"; }
  warn() { echo "WARN: $1"; }
  step() { echo ""; echo "== $1 =="; }

  step "1. Prerequisites"
  local missing=0
  local cmd
  for cmd in gh git npm node curl; do
    if ! command -v "$cmd" >/dev/null; then
      echo "missing command: $cmd"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    fail "install missing commands and re-run"
    return 1
  fi

  local NODE_MAJOR
  NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo "0")
  if [ "$NODE_MAJOR" -lt 18 ]; then
    fail "Node $NODE_MAJOR found; Vite 6 requires Node 18 or newer"
    return 1
  fi
  ok "commands present; Node $NODE_MAJOR"

  if ! gh auth status >/dev/null; then
    fail "gh not authenticated; run gh auth login"
    return 1
  fi
  ok "gh authenticated"

  GH_OWNER=$(gh api user --jq '.login')
  if [ -z "$GH_OWNER" ]; then
    fail "could not determine GitHub login"
    return 1
  fi
  info "GitHub owner is $GH_OWNER"

  step "2. Write repository files"
  mkdir -p "$WORKDIR/src" "$WORKDIR/.github/workflows"

  cat > "$WORKDIR/vite.config.js" <<'VITE_END'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({ plugins: [react()], base: '/fedora37-io-audit/' })
VITE_END

  cat > "$WORKDIR/package.json" <<'PKG_END'
{"name":"fedora37-io-audit","private":true,"version":"1.0.0","type":"module","scripts":{"dev":"vite","build":"vite build","preview":"vite preview"},"dependencies":{"react":"^18.3.1","react-dom":"^18.3.1"},"devDependencies":{"@vitejs/plugin-react":"^4.3.4","vite":"^6.0.0"}}
PKG_END

  cat > "$WORKDIR/index.html" <<'HTML_END'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1.0">
    <title>Fedora 37 I/O Audit</title>
    <style>
      :root{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:16px;line-height:1.6;color:#1a1a1a;background:#f4f5f7}
      *{box-sizing:border-box}
      body{margin:0;padding:2rem 1rem}
      main{max-width:920px;margin:0 auto;background:#fff;padding:2.5rem;border:1px solid #d8dbe0;border-radius:6px}
      header{margin-bottom:2rem;padding-bottom:1.5rem;border-bottom:1px solid #d8dbe0}
      h1{font-size:1.75rem;font-weight:600;margin:0 0 .5rem}
      h2{font-size:1.2rem;font-weight:600;margin:2rem 0 .75rem;padding-bottom:.35rem;border-bottom:1px solid #e6e8eb}
      p{margin:0 0 .9rem}
      nav{margin:1rem 0 2rem;padding:.75rem 1rem;background:#eef0f3;border:1px solid #d8dbe0;border-radius:4px;font-size:.9rem}
      nav a{margin-right:1rem}
      table{width:100%;border-collapse:collapse;margin:.5rem 0 1.25rem;font-size:.925rem}
      th,td{text-align:left;padding:.55rem .75rem;border:1px solid #d8dbe0;vertical-align:top}
      thead th{background:#eef0f3;font-weight:600}
      caption{text-align:left;font-size:.85rem;color:#5a6270;margin-bottom:.4rem}
      .table-wrap{overflow-x:auto}
      pre{background:#f6f8fa;border:1px solid #d8dbe0;border-left:3px solid #4b5563;border-radius:4px;padding:.9rem 1rem;overflow-x:auto;font-size:.85rem;margin:.5rem 0 1rem}
      code{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.88em}
      p code,li code,td code{background:#eef0f3;padding:.05em .35em;border-radius:3px}
      a{color:#0b5ed7;text-decoration:none}
      a:hover{text-decoration:underline}
      footer{margin-top:2.5rem;padding-top:1rem;border-top:1px solid #d8dbe0;font-size:.85rem;color:#5a6270}
      .code-block{border:1px solid #d8dbe0;border-radius:4px;overflow:hidden;margin:.5rem 0 1rem;background:#f6f8fa}
      .code-header{display:flex;justify-content:space-between;align-items:center;padding:.35rem .75rem;background:#eef0f3;border-bottom:1px solid #d8dbe0;font-size:.8rem;color:#5a6270}
      .code-actions{display:flex;gap:.35rem}
      .code-actions button{font:inherit;font-size:.75rem;padding:.2rem .55rem;background:#fff;border:1px solid #c9ced6;border-radius:3px;cursor:pointer}
      .code-actions button:hover{background:#f0f2f5}
      .code-actions button.copied{background:#e6f4ea;border-color:#86c298;color:#1e6b33}
      h3{font-size:1rem;font-weight:600;margin:1.5rem 0 .5rem}
      h4{font-size:.85rem;font-weight:600;margin:1rem 0 .35rem;text-transform:uppercase;letter-spacing:.04em;color:#5a6270}
      .warn-box{background:#fff8e6;border:1px solid #d4a72c;border-left:4px solid #d4a72c;border-radius:4px;padding:.9rem 1rem;margin:.75rem 0 1.25rem;font-size:.925rem;line-height:1.55}
      .warn-box strong:first-child{color:#7a4a00;display:block;margin-bottom:.4rem;font-size:.95rem}
      .warn-box ul{margin:.5rem 0 .5rem;padding-left:1.25rem}
      .warn-box li{margin:.2rem 0}
      .warn-box p{margin:.5rem 0 0}
      .warn-box.danger{background:#fef2f2;border-color:#e53e3e}
      .warn-box.danger strong:first-child{color:#8b0000}
      @media(max-width:640px){body{padding:0}main{border:0;border-radius:0;padding:1.25rem}}
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>

HTML_END

  cat > "$WORKDIR/src/main.jsx" <<'MAIN_END'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
ReactDOM.createRoot(document.getElementById('root')).render(<React.StrictMode><App /></React.StrictMode>)
MAIN_END

  cat > "$WORKDIR/src/App.jsx" <<'APP_END'
import React, { useState } from 'react'
import flashScript from '../flash-fedora.sh?raw'

const references = [
  { id: 1, publisher: 'docs.fedoraproject.org', title: 'Fedora Project - End of Life Releases', url: 'https://docs.fedoraproject.org/en-US/releases/eol/', note: 'Fedora Linux 37 reached end of life on 2023-12-05.' },
  { id: 2, publisher: 'rpmfusion.org', title: 'RPM Fusion - Frequently Asked Questions', url: 'https://rpmfusion.org/FAQ', note: 'RPM Fusion repositories follow upstream Fedora end-of-life.' },
  { id: 3, publisher: 'Linux kernel documentation', title: 'PSI - Pressure Stall Information', url: 'https://docs.kernel.org/accounting/psi.html', note: 'Definitions of some and full stall metrics.' },
  { id: 4, publisher: 'smartmontools.org', title: 'smartctl(8) manual page', url: 'https://www.smartmontools.org/browser/trunk/smartmontools/smartctl.8.in', note: 'SMART control and monitoring utility.' },
  { id: 5, publisher: 'GitHub', title: 'PackageKit/PackageKit', url: 'https://github.com/PackageKit/PackageKit', note: 'D-Bus abstraction layer for package management.' },
  { id: 6, publisher: 'GitHub', title: 'actions/deploy-pages', url: 'https://github.com/actions/deploy-pages', note: 'Deploys Actions artifacts to GitHub Pages. v4 used here; v5 (Node 24) exists.' },
  { id: 7, publisher: 'GitHub CLI manual', title: 'gh repo create', url: 'https://cli.github.com/manual/gh_repo_create', note: '--source and --push flags used in deploy.sh.' },
  { id: 8, publisher: 'GitHub CLI manual', title: 'gh run list', url: 'https://cli.github.com/manual/gh_run_list', note: '--workflow and --json status,conclusion used in deploy.sh.' }
]

const findings = [
  { id: 1, title: 'PackageKit was not the memory bottleneck', evidence: 'PackageKit stopped, yet memory PSI was about 79 percent. I/O PSI was 91.69 percent. 2.7 GiB RAM free. 106 MiB swap used.', correction: 'Investigate storage I/O and D-state tasks. Do not increase swap. Do not kill GPG agents.', refs: [5, 3] },
  { id: 2, title: 'Package name misspelling', evidence: 'smarctl was used four times. dnf returned no match.', correction: 'Install smartmontools. The binary it provides is smartctl.', refs: [4] },
  { id: 3, title: 'RPM Fusion 404 is end-of-life behavior', evidence: 'Fedora 37 reached end of life on 2023-12-05. RPM Fusion follows upstream end-of-life.', correction: 'Set enabled=0 and skip_if_unavailable=True. Do not rewrite metalink URLs.', refs: [1, 2] },
  { id: 4, title: 'System disk SMART passed', evidence: 'smartctl -H returned PASSED. Reallocated 11. Pending 0. Offline uncorrectable 0.', correction: 'Do not run fsck on the mounted root. Do not replace the disk.', refs: [4] },
  { id: 5, title: 'Script lacked gh preflight and remote guards', evidence: 'No gh auth status check. Remote failures would abort under a no-exit-1 constraint.', correction: 'Add gh auth status preflight. Guard each remote call. Return nonzero from main only.', refs: [7, 8] }
]

const metrics = [
  { metric: 'Memory PSI, some avg10', observed: '78.95 percent after PackageKit stop', interpretation: 'Memory pressure remained', refs: [3] },
  { metric: 'I/O PSI, some avg10', observed: '91.69 percent', interpretation: 'Dominant pressure source', refs: [3] },
  { metric: 'Available RAM', observed: '2.7 GiB', interpretation: 'Not exhausted', refs: [] },
  { metric: 'Swap used', observed: '106 MiB', interpretation: 'Not exhausted', refs: [] },
  { metric: 'CPU I/O wait', observed: '25 to 50 percent', interpretation: 'Storage contention', refs: [] },
  { metric: 'Blocked tasks', observed: 'tracker-extract, kworker', interpretation: 'Blocked on I/O', refs: [] },
  { metric: 'SMART health', observed: 'PASSED', interpretation: 'Disk is not failing', refs: [4] }
]

const rpmConfig = `# /etc/yum.repos.d/rpmfusion-nonfree.repo
[rpmfusion-nonfree-nvidia-driver]
enabled=0
skip_if_unavailable=True

[rpmfusion-nonfree-steam]
enabled=0
skip_if_unavailable=True`

const verifyCmds = `systemctl is-active packagekit.service
cat /proc/pressure/memory
cat /proc/pressure/io
vmstat 1 5
sudo smartctl -H -A /dev/sda
sudo dnf --disablerepo=rpmfusion-nonfree-nvidia-driver \\
         --disablerepo=rpmfusion-nonfree-steam \\
         install smartmontools
gh run list --workflow="Deploy to GitHub Pages" --limit 3`

function CopyButton({ text }) {
  const [copied, setCopied] = useState(false)
  const doCopy = async () => {
    let ok = false
    if (navigator.clipboard && window.isSecureContext) {
      try { await navigator.clipboard.writeText(text); ok = true } catch (e) { ok = false }
    }
    if (!ok) {
      const ta = document.createElement('textarea')
      ta.value = text; ta.setAttribute('readonly',''); ta.style.position = 'fixed'; ta.style.top = '-9999px'
      document.body.appendChild(ta); ta.select()
      try { ok = document.execCommand('copy') } catch (e) { ok = false }
      document.body.removeChild(ta)
    }
    if (ok) { setCopied(true); setTimeout(() => setCopied(false), 1600) }
  }
  return <button type="button" onClick={doCopy} className={copied ? 'copied' : ''}>{copied ? 'Copied' : 'Copy'}</button>
}

function DownloadButton({ text, filename, mime }) {
  const doDownload = () => {
    const blob = new Blob([text], { type: mime || 'text/plain;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = filename; a.style.display = 'none'
    document.body.appendChild(a); a.click(); document.body.removeChild(a)
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  return <button type="button" onClick={doDownload}>Download</button>
}

function CodeBlock({ code, filename, mime }) {
  return (
    <div className="code-block">
      <div className="code-header">
        <span>{filename}</span>
        <div className="code-actions">
          <CopyButton text={code} />
          <DownloadButton text={code} filename={filename} mime={mime} />
        </div>
      </div>
      <pre><code>{code}</code></pre>
    </div>
  )
}

function Refs({ ids }) {
  if (!ids || ids.length === 0) return <span>none</span>
  return ids.map((id, i) => {
    const r = references.find(x => x.id === id)
    return <React.Fragment key={id}>{i > 0 ? ', ' : ''}<a href={r.url} title={r.title}>[{id}]</a></React.Fragment>
  })
}

export default function App() {
  return (
    <main>
      <header>
        <h1>Fedora 37 I/O Audit</h1>
        <p>Diagnostic audit of a Fedora 37 troubleshooting session, with corrected repository configuration and deployment tooling.</p>
        <div className="table-wrap">
          <table>
            <caption>Document control</caption>
            <tbody>
              <tr><th scope="row">Audit date</th><td>2026-11-11</td></tr>
              <tr><th scope="row">Host</th><td>Fedora 37, kernel 5.19.7</td></tr>
              <tr><th scope="row">Scope</th><td>Local diagnosis, RPM Fusion configuration, Pages deployment, USB flash tooling</td></tr>
            </tbody>
          </table>
        </div>
      </header>

      <nav>
        <strong>Contents:</strong>{' '}
        <a href="#findings">Findings</a>
        <a href="#evidence">Evidence</a>
        <a href="#config">RPM Fusion config</a>
        <a href="#verify">Verification</a>
        <a href="#flash">USB flash</a>
        <a href="#references">References</a>
      </nav>

      <section id="findings">
        <h2>Audit findings</h2>
        <div className="table-wrap">
          <table>
            <caption>Five diagnostic errors and their corrections</caption>
            <thead>
              <tr><th>No.</th><th>Finding</th><th>Evidence</th><th>Correction</th><th>Refs</th></tr>
            </thead>
            <tbody>
              {findings.map(f => (
                <tr key={f.id}><td>{f.id}</td><td>{f.title}</td><td>{f.evidence}</td><td>{f.correction}</td><td><Refs ids={f.refs} /></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section id="evidence">
        <h2>Diagnostic evidence</h2>
        <div className="table-wrap">
          <table>
            <caption>Observed values and their interpretation</caption>
            <thead><tr><th>Metric</th><th>Observed</th><th>Interpretation</th><th>Refs</th></tr></thead>
            <tbody>
              {metrics.map((m, i) => (
                <tr key={i}><td>{m.metric}</td><td>{m.observed}</td><td>{m.interpretation}</td><td><Refs ids={m.refs} /></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section id="config">
        <h2>Corrected RPM Fusion configuration</h2>
        <p>Fedora 37 reached end of life on 2023-12-05, and RPM Fusion follows upstream end-of-life. The two failing repositories should be disabled locally rather than redirected to another release.</p>
        <CodeBlock code={rpmConfig} filename="rpmfusion-nonfree.repo" />
      </section>

      <section id="verify">
        <h2>Verification commands</h2>
        <p>Run these on the affected host to confirm the diagnosis and the corrected configuration.</p>
        <CodeBlock code={verifyCmds} filename="verify.sh" mime="application/x-sh;charset=utf-8" />
      </section>

      <section id="flash">
        <h2>USB flash tooling</h2>

        <h3>How this tool came to exist</h3>
        <p>This page documents the diagnosis of a Fedora 37 laptop with severe I/O stalls. Six findings converged on one conclusion: the installation was past end-of-life, and the USB carrying its replacement had to be written by something more careful than a one-liner.</p>
        <ol>
          <li>I/O PSI at 91.69 percent while 2.7 GiB RAM was free, so memory was not the bottleneck.</li>
          <li>The optical drive <code>/dev/sr0</code> failed reads every few seconds; ejecting it dropped I/O pressure to 0.03 percent.</li>
          <li><code>tracker-extract</code> was blocked in D-state on the root filesystem; user services were masked.</li>
          <li><code>dnf-makecache.timer</code> polled dead RPM Fusion mirrors every few hours; disabled.</li>
          <li>PackageKit was holding 1.5 GiB in its service cgroup; stopped.</li>
          <li>Fedora 37 reached end of life on 2023-12-05. Fedora supports upgrades across one release at a time and the target was Fedora 45, so a clean install from USB was the safest path.</li>
        </ol>
        <p>The earlier <code>curl</code>-and-<code>dd</code> attempt is what motivated this script. Plain <code>curl</code> saved a 262-byte HTML 404 page as the ISO; <code>wget -c</code> then treated that HTML as valid ISO data and resumed from byte 262; and <code>set +e</code> combined with a filename mismatch let execution fall through to <code>dd</code> with <code>of=/dev/</code>. The only thing that stopped the write was a manual <code>n</code> at the confirmation prompt. This script adds the gates that were missing.</p>

        <h3>What the script does</h3>
        <ol>
          <li>Pre-authenticates sudo and keeps the ticket alive across the whole run so <code>dd</code> never prompts mid-write.</li>
          <li>Prompts for version, edition, build, and arch, with defaults 45 / Workstation / 1.4 / x86_64.</li>
          <li>Reuses an existing ISO matching either Fedora filename convention, otherwise downloads with resume, retry, and stall detection.</li>
          <li>Probes three checksum filename patterns on the mirror and verifies SHA-256, with a manual-hash fallback.</li>
          <li>Loop-mounts the image and checks for <code>LiveOS/squashfs.img</code> or <code>images/install.img</code>.</li>
          <li>Lists disks, refuses the whole-disk backing the running root, warns on non-USB transport.</li>
          <li>Requires the literal word <code>ERASE</code> before <code>dd</code> fires.</li>
          <li>Runs <code>dd</code> with <code>conv=fsync</code>, then <code>sync</code>, then reports the resulting partition layout.</li>
        </ol>

        <h3>Warnings</h3>
        <div className="warn-box danger">
          <strong>Destructive write operation</strong>
          <code>dd</code> rewrites the target disk sector by sector. Partitions, filesystems, bootloaders, and data on that disk become unrecoverable. There is no undo and no confirmation dialog after the write starts.
          <ul>
            <li>The script refuses to write to the disk hosting <code>/</code>.</li>
            <li>The script refuses partitions and loop devices by checking <code>lsblk -dno TYPE</code> equals <code>disk</code>.</li>
            <li>The script warns and asks again if <code>lsblk -dno TRAN</code> is not <code>usb</code>.</li>
            <li>The script requires the literal word <code>ERASE</code> at the final prompt.</li>
            <li><code>--dry-run</code> walks every step, including device validation, and stops before <code>dd</code>.</li>
          </ul>
          <p>Verify the target by transport and by capacity before confirming. A 15 GB USB stick shown as <code>sdb</code> is not the 931 GB internal disk shown as <code>sda</code>.</p>
        </div>
        <div className="warn-box">
          <strong>Network and checksum</strong>
          Fedora mirror redirectors occasionally return HTML error pages. The script probes three checksum filename patterns and falls back to a manual-hash prompt. Verify the SHA-256 before flashing, because a truncated ISO produces a USB that boots to a grub prompt and nothing else.
        </div>

        <h3>Using it</h3>
        <p>Three ways, in order from quickest to most inspectable.</p>

        <h4>1. Download and run</h4>
        <CodeBlock
          code={`curl -fL -o flash-fedora.sh https://swipswaps.github.io/fedora37-io-audit/flash-fedora.sh
chmod +x flash-fedora.sh
./flash-fedora.sh`}
          filename="quickstart.sh"
          mime="application/x-sh;charset=utf-8"
        />

        <h4>2. Dry run first</h4>
        <p>Walk every step, including device selection and the <code>ERASE</code> confirmation, and stop before <code>dd</code> fires. Use this on a first run to see exactly what the script intends.</p>
        <CodeBlock
          code={`./flash-fedora.sh --dry-run`}
          filename="dry-run.sh"
          mime="application/x-sh;charset=utf-8"
        />

        <h4>3. Reuse an existing ISO</h4>
        <p>If you already have a verified <code>Fedora-Workstation-Live-45-1.4.x86_64.iso</code> in the current directory, the script detects it, skips the download, and goes straight to checksum, loop-mount, and device selection.</p>
        <CodeBlock
          code={`cd /path/to/iso/directory
/path/to/flash-fedora.sh`}
          filename="reuse.sh"
          mime="application/x-sh;charset=utf-8"
        />

        <h3>Source</h3>
        <p>The full script, exactly as deployed to this site and to the repository. The Copy and Download buttons in the header work on the current content.</p>
        <CodeBlock code={flashScript} filename="flash-fedora.sh" mime="application/x-sh;charset=utf-8" />

        <h3>Other download paths</h3>
        <p>
          <a href={`${import.meta.env.BASE_URL}flash-fedora.sh`} download="flash-fedora.sh">Download flash-fedora.sh (Pages)</a>
          {' '}|{' '}
          <a href="https://raw.githubusercontent.com/swipswaps/fedora37-io-audit/main/flash-fedora.sh">Raw on GitHub</a>
          {' '}|{' '}
          <a href="https://github.com/swipswaps/fedora37-io-audit/blob/main/flash-fedora.sh" target="_blank" rel="noopener noreferrer">Browse on GitHub</a>
        </p>
      </section>

      <section>
        <h2>Deployment notes</h2>
        <p>Pages deployment uses <code>actions/deploy-pages@v4</code> with <code>actions/upload-pages-artifact@v3</code>. The legacy <code>pages/builds/latest</code> endpoint is not used because it does not reflect Actions-based deployments. Status is read from <code>gh run list --workflow="Deploy to GitHub Pages"</code>.</p>
      </section>

      <section id="references">
        <h2>References</h2>
        <p>Links verified 2026-11-12.</p>
        <ol>
          {references.map(r => (
            <li key={r.id}>{r.publisher}. <a href={r.url}>{r.title}</a>. {r.note}</li>
          ))}
        </ol>
      </section>

      <footer>
        <p>Static HTML. No external CSS framework. Generated by deploy.sh.</p>
      </footer>
    </main>
  )
}

APP_END

  cat > "$WORKDIR/.github/workflows/deploy.yml" <<'WF_END'
name: Deploy to GitHub Pages
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: false
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm install
      - run: npm run build
      - uses: actions/upload-pages-artifact@v3
        with:
          path: dist
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
WF_END

  cat > "$WORKDIR/.gitignore" <<'GI_END'
node_modules/
dist/
.DS_Store
GI_END

  cat > "$WORKDIR/flash-fedora.sh" <<'FLASH_END'
#!/usr/bin/env bash
# flash-fedora.sh — interactive Fedora ISO download, verify, USB flash.
# Handles both filename conventions:
#   Fedora-Workstation-Live-45-1.4.x86_64.iso   (Fedora 45 and later)
#   Fedora-Workstation-Live-x86_64-45-1.4.iso   (older releases)
# 2>/dev/null is used only for expected umount noise.

set +e
set +u
set +o pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo "  --dry-run   stop before dd"
      exit 0 ;;
  esac
done

P="[flash-fedora]"
DEFAULT_VER="45"
DEFAULT_ED="Workstation"
DEFAULT_BUILD="1.4"
DEFAULT_ARCH="x86_64"

echo "$P Pre-authenticating sudo..."
sudo -v || { echo "$P Sudo failed."; exit 1; }
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

echo "$P Interactive setup (Enter accepts default)"
read -r -p "$P Fedora version [$DEFAULT_VER]: " VER; VER=${VER:-$DEFAULT_VER}
read -r -p "$P Edition [$DEFAULT_ED]: " ED; ED=${ED:-$DEFAULT_ED}
read -r -p "$P Build [$DEFAULT_BUILD]: " BUILD; BUILD=${BUILD:-$DEFAULT_BUILD}
read -r -p "$P Architecture [$DEFAULT_ARCH]: " ARCH; ARCH=${ARCH:-$DEFAULT_ARCH}

ISO_NEW="Fedora-${ED}-Live-${VER}-${BUILD}.${ARCH}.iso"
ISO_OLD="Fedora-${ED}-Live-${ARCH}-${VER}-${BUILD}.iso"
BASE_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/${VER}/${ED}/${ARCH}/iso"

ISO_FILE=""
for cand in "$ISO_NEW" "$ISO_OLD"; do
  if [ -f "$cand" ]; then
    ISO_FILE="$cand"
    echo "$P Found existing: $cand ($(stat -c %s "$cand") bytes)"
    break
  fi
done

if [ -z "$ISO_FILE" ]; then
  for cand in "$ISO_NEW" "$ISO_OLD"; do
    URL="$BASE_URL/$cand"
    echo "$P Trying $URL"
    until curl -fL -C - --retry 20 --retry-delay 10 --speed-limit 500 --speed-time 30 -o "$cand" "$URL"; do
      echo "$P Stalled. Resuming in 5s (Ctrl-C to abort)."
      sleep 5
    done
    if [ -f "$cand" ]; then ISO_FILE="$cand"; break; fi
  done
fi

if [ -z "$ISO_FILE" ]; then
  echo "$P Both patterns 404. Check $BASE_URL/"
  exit 1
fi

echo "$P Locating checksum (best effort)"
ISO_BASE="${ISO_FILE%.iso}"
for c in "${ISO_BASE}-CHECKSUM" "Fedora-${ED}-${VER}-${BUILD}-${ARCH}-CHECKSUM" "Fedora-${ED}-${VER}-${BUILD}.${ARCH}-CHECKSUM"; do
  if curl -fL -s -o "/tmp/fedora-checksum.$$" "$BASE_URL/$c"; then
    if [ -s "/tmp/fedora-checksum.$$" ] && ! head -c 400 "/tmp/fedora-checksum.$$" | grep -qi '<html'; then
      CHECKSUM_FILE="/tmp/fedora-checksum.$$"
      echo "$P Got checksum: $c"
      break
    fi
  fi
done

VERIFY_OK=0
if [ -n "$CHECKSUM_FILE" ]; then
  if sha256sum -c "$CHECKSUM_FILE" --ignore-missing 2>/dev/null | grep -q ': OK'; then
    VERIFY_OK=1; echo "$P Checksum PASSED"
  else
    echo "$P Checksum FAILED"
    read -r -p "$P Continue anyway? [y/N]: " a
    case "$a" in y|Y) VERIFY_OK=1 ;; esac
  fi
  rm -f "$CHECKSUM_FILE"
else
  echo "$P No checksum file reachable."
  read -r -p "$P Paste SHA-256 (Enter to skip): " MANUAL_HASH
  if [ -n "$MANUAL_HASH" ]; then
    echo "$MANUAL_HASH  $ISO_FILE" | sha256sum -c - && VERIFY_OK=1
  else
    VERIFY_OK=1
  fi
fi

if [ "$VERIFY_OK" -ne 1 ]; then
  echo "$P Refusing to flash unverified image."
  exit 1
fi

echo "$P Loop-mounting..."
MDIR=$(mktemp -d)
if sudo mount -o loop,ro "$ISO_FILE" "$MDIR"; then
  if [ -f "$MDIR/LiveOS/squashfs.img" ] || [ -f "$MDIR/images/install.img" ]; then
    echo "$P Payload structure OK"
  else
    echo "$P WARN: payload markers missing"
  fi
  sudo umount "$MDIR"
else
  echo "$P WARN: loop-mount failed; continuing"
fi
rmdir "$MDIR" 2>/dev/null

echo "$P Available disks:"
lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL

ROOT_SRC=$(findmnt -no SOURCE / 2>/dev/null)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1)
[ -n "$ROOT_DISK" ] && echo "$P Root is on /dev/$ROOT_DISK (will refuse)"

TARGET=""
while [ -z "$TARGET" ]; do
  read -r -p "$P Target disk (e.g. sdb): " in
  in=${in#/dev/}
  [ -z "$in" ] && { echo "$P No input."; continue; }
  [ ! -b "/dev/$in" ] && { echo "$P /dev/$in not a block device."; continue; }
  T=$(lsblk -dno TYPE "/dev/$in")
  [ "$T" != "disk" ] && { echo "$P /dev/$in is '$T', not 'disk'."; continue; }
  [ -n "$ROOT_DISK" ] && [ "$in" = "$ROOT_DISK" ] && { echo "$P /dev/$in hosts root. Refusing."; continue; }
  TR=$(lsblk -dno TRAN "/dev/$in")
  if [ "$TR" != "usb" ]; then
    echo "$P WARN: transport is '$TR', not 'usb'."
    read -r -p "$P Continue? [y/N]: " a
    case "$a" in y|Y) TARGET="$in" ;; *) continue ;; esac
  else
    TARGET="$in"
  fi
done

echo "$P Target: /dev/$TARGET"
lsblk "/dev/$TARGET"
echo "$P WARNING: all data on /dev/$TARGET will be destroyed."
read -r -p "$P Type ERASE to confirm: " WORD
[ "$WORD" != "ERASE" ] && { echo "$P Aborted."; exit 0; }

for part in $(lsblk -lno NAME "/dev/$TARGET" | tail -n +2); do
  sudo umount "/dev/$part" 2>/dev/null && echo "$P Unmounted /dev/$part"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "$P Dry run: would run dd if=$ISO_FILE of=/dev/$TARGET bs=4M status=progress oflag=sync conv=fsync"
  exit 0
fi

echo "$P Writing..."
sudo dd if="$ISO_FILE" of="/dev/$TARGET" bs=4M status=progress oflag=sync conv=fsync
RC=$?
sync
if [ "$RC" -ne 0 ]; then echo "$P dd failed ($RC)."; exit 1; fi

echo "$P Flash complete."
lsblk "/dev/$TARGET"
FLASH_END
  chmod +x "$WORKDIR/flash-fedora.sh"

  mkdir -p "$WORKDIR/public"
  cp "$WORKDIR/flash-fedora.sh" "$WORKDIR/public/flash-fedora.sh"
  chmod +x "$WORKDIR/public/flash-fedora.sh"
  ok "files written to $WORKDIR (flash-fedora.sh in root and public/)"

  step "3. Build"
  cd "$WORKDIR"
  if [ -f package-lock.json ]; then
    npm ci --legacy-peer-deps >/tmp/audit-ci.log 2>&1 || npm install --legacy-peer-deps >/tmp/audit-install.log 2>&1
  else
    npm install --legacy-peer-deps >/tmp/audit-install.log 2>&1
  fi
  npm run build >/tmp/audit-build.log 2>&1
  if [ "$?" -ne 0 ] || [ ! -f "$WORKDIR/dist/index.html" ]; then
    fail "build failed; see /tmp/audit-build.log"; return 1
  fi
  ok "build succeeded"

  step "4. Git and repository"
  if [ ! -d "$WORKDIR/.git" ]; then
    git init -b main || { fail "git init failed"; return 1; }
  fi
  git add -A
  git -c user.name="Audit Bot" -c user.email="audit@local" commit -m "Update audit site" >/tmp/audit-commit.log 2>&1
  [ "$?" -ne 0 ] && info "nothing to commit or commit skipped"

  if gh repo view "$GH_OWNER/$REPO_NAME" >/dev/null; then
    info "repo exists; pushing"
    if git remote remove origin >/dev/null; then info "removed old origin"; fi
    git remote add origin "https://github.com/$GH_OWNER/$REPO_NAME.git" || { fail "remote add failed"; return 1; }
    git push -u origin main || { fail "push failed"; return 1; }
  else
    gh repo create "$GH_OWNER/$REPO_NAME" --public --source=. --remote=origin --push || { fail "repo create failed"; return 1; }
  fi
  ok "pushed"

  step "5. Enable Pages"
  if gh api "repos/$GH_OWNER/$REPO_NAME/pages" --jq '.html_url' >/dev/null; then
    ok "Pages already enabled"
  else
    gh api "repos/$GH_OWNER/$REPO_NAME/pages" -X POST -f build_type=workflow || warn "Pages POST failed; set Source to GitHub Actions manually"
  fi

  step "6. Monitor workflow"
  sleep 5
  local attempt=0 run_status="" run_conclusion="" page_url=""
  while [ "$attempt" -lt 30 ]; do
    attempt=$((attempt + 1))
    run_status=$(gh run list --workflow="Deploy to GitHub Pages" --limit 1 --json status --jq '.[0].status')
    run_conclusion=$(gh run list --workflow="Deploy to GitHub Pages" --limit 1 --json conclusion --jq '.[0].conclusion')
    page_url=$(gh api "repos/$GH_OWNER/$REPO_NAME/pages" --jq '.html_url')
    if [ -z "$run_status" ] || [ "$run_status" = "null" ]; then
      info "attempt $attempt/30: not registered yet"; sleep 10; continue
    fi
    info "attempt $attempt/30: status=$run_status conclusion=$run_conclusion"
    case "$run_status" in
      completed)
        if [ "$run_conclusion" = "success" ]; then PAGES_URL="$page_url"; ok "workflow success"
        else fail "workflow: $run_conclusion"; fi
        break ;;
      in_progress|queued|requested|waiting|pending) sleep 10 ;;
      *) warn "unknown: $run_status"; sleep 10 ;;
    esac
  done
  [ -z "$PAGES_URL" ] && { PAGES_URL="https://$GH_OWNER.github.io/$REPO_NAME/"; warn "using inferred URL"; }

  step "7. Open"
  info "page: $PAGES_URL"
  if [ "$OPEN_BROWSER" -eq 1 ] && command -v xdg-open >/dev/null; then
    xdg-open "$PAGES_URL" >/dev/null &
  fi

  step "Summary"
  echo "Working dir: $WORKDIR"
  echo "Repo:        https://github.com/$GH_OWNER/$REPO_NAME"
  echo "Page:        $PAGES_URL"
  echo "Flash tool:  $WORKDIR/flash-fedora.sh (not run)"
  [ "$ERRORS" -eq 0 ] && { echo "RESULT: success"; return 0; } || { echo "RESULT: $ERRORS error(s)"; return 1; }
}

main "$@"
