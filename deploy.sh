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
import x11Script from '../fix-x11-forwarding.sh?raw'
import guideScript from '../fedora45-guide.sh?raw'

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
        <a href="#x11">X11 forwarding</a>
        <a href="#guide">Fedora 45 guide</a>
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

      <section id="x11">
        <h2>X11 forwarding over SSH</h2>

        <h3>Why this tool exists</h3>
        <p>The first <code>ssh -Y</code> into the freshly upgraded Fedora 45 host printed <code>/usr/bin/xauth: file /home/owner/.Xauthority does not exist</code>. That single line identifies the failure: sshd negotiated X11 forwarding, allocated the synthetic display <code>localhost:10.0</code>, but had no <code>xauth</code> binary to write the authorization cookie into <code>~/.Xauthority</code>. The SSH channel was established in a state that no later action can retroactively correct.</p>
        <p>On Fedora 45 Workstation, <code>xorg-x11-xauth</code> is not part of the default install. Installing it fixes every future session; the current one cannot be repaired from inside itself.</p>

        <h3>What the script does</h3>
        <ol>
          <li>Reports diagnostic state before any change: <code>DISPLAY</code>, <code>SSH_CONNECTION</code>, presence and size of <code>~/.Xauthority</code>, and whether <code>xauth</code> is installed.</li>
          <li>Pre-authenticates sudo once.</li>
          <li>Installs <code>xorg-x11-xauth</code> if missing and marks the session as requiring a reconnect.</li>
          <li>Asserts that <code>sshd -T</code> is usable (nonzero exit, at least five lines, a <code>Port</code> directive). If not, prints the first ten lines and exits rather than misdiagnosing.</li>
          <li>Parses <code>X11Forwarding</code>, <code>X11UseLocalhost</code>, and <code>XauthLocation</code> case-insensitively. Fedora 45's <code>sshd -T</code> emits capitalized keys; lowercase-only patterns return empty.</li>
          <li>Writes <code>/etc/ssh/sshd_config.d/60-x11-forwarding.conf</code> only if <code>X11Forwarding</code> is not already <code>yes</code>; validates with <code>sshd -t</code>; reloads; re-parses to verify the change.</li>
          <li>Re-runs <code>sshd -T -C user=...,host=...,addr=...</code> to catch a <code>Match</code> block that overrides the global setting for this user.</li>
          <li>Matches the X11 cookie by display number, accepting both <code>hostname:NN</code> and <code>hostname/unix:NN</code> - the two forms sshd actually writes. The literal string <code>localhost:10</code> is never written to <code>.Xauthority</code>.</li>
          <li>Returns one of three verdicts: <code>SUCCESS</code>, <code>CONFIG_FIXED_RECONNECT_REQUIRED</code>, or <code>FAILED</code>.</li>
        </ol>

        <h3>Warnings</h3>
        <div className="warn-box danger">
          <strong>Existing sessions cannot be repaired retroactively</strong>
          The X11 cookie is written by sshd during the connection handshake, before the remote shell exists. Installing <code>xorg-x11-xauth</code> after the fact fixes all future sessions but does not add a cookie to the current one. If the script reports <code>CONFIG_FIXED_RECONNECT_REQUIRED</code>, the only path forward is <code>exit</code> followed by <code>ssh -Y</code>.
          <ul>
            <li><code>xauth list</code> shows a cookie: this session is ready.</li>
            <li><code>xauth list</code> empty: reconnect is required.</li>
            <li>Neither is fixed by running the script twice.</li>
          </ul>
        </div>
        <div className="warn-box">
          <strong>sshd -T is case-sensitive to parsers and to sudo</strong>
          Fedora 45's <code>sshd -T</code> emits capitalized keys (<code>Port 22</code>, <code>X11Forwarding yes</code>). Parsers that match only lowercase silently report <code>unknown</code>. The script normalizes with <code>tolower()</code> in awk. Similarly, <code>sudo</code> resets environment by default, and <code>sudo which sshd</code> can fail if <code>/usr/sbin</code> is not in the secure path - the script uses an absolute path to <code>/usr/sbin/sshd</code> to avoid this.
        </div>
        <div className="warn-box">
          <strong>Cookie matching depends on sshd's hostname choice</strong>
          sshd writes cookies under the server's own hostname with a Unix family suffix - <code>fedora/unix:10</code> on this host, not <code>localhost:10</code>. A <code>grep</code> for <code>localhost:10</code> will miss every cookie sshd writes. The script matches on <code>[:/]NN</code> where <code>NN</code> is the display number, accepting both forms.
        </div>
        <div className="warn-box">
          <strong>xorg-x11-apps is not available on Fedora 45</strong>
          The package split; <code>xeyes</code> is now its own package. A script that tries <code>dnf install xorg-x11-apps</code> to verify forwarding end to end will fail with <code>No match for argument</code>. This script performs no graphical test at all: the presence of a valid cookie in <code>~/.Xauthority</code> is the definitive server-side proof that forwarding is wired up.
        </div>

        <h3>Using it</h3>
        <h4>1. Download and run</h4>
        <CodeBlock
          code={`curl -fL -o fix-x11-forwarding.sh https://swipswaps.github.io/fedora37-io-audit/fix-x11-forwarding.sh
chmod +x fix-x11-forwarding.sh
./fix-x11-forwarding.sh`}
          filename="quickstart.sh"
          mime="application/x-sh;charset=utf-8"
        />

        <h4>2. On a session that predates the fix</h4>
        <p>If <code>xorg-x11-xauth</code> was missing when the session was established, the script installs it and reports <code>CONFIG_FIXED_RECONNECT_REQUIRED</code>. Exit and reconnect, then run again. On the second run the cookie check succeeds and the verdict flips to <code>SUCCESS</code>. That transition - no cookie to cookie - is the definitive proof the fix took.</p>
        <CodeBlock
          code={`./fix-x11-forwarding.sh
# RESULT: CONFIG_FIXED_RECONNECT_REQUIRED
exit
ssh -Y owner@host
./fix-x11-forwarding.sh
# RESULT: SUCCESS`}
          filename="reconnect-flow.sh"
          mime="application/x-sh;charset=utf-8"
        />

        <h3>Source</h3>
        <p>The full script, exactly as deployed to this site and to the repository.</p>
        <CodeBlock code={x11Script} filename="fix-x11-forwarding.sh" mime="application/x-sh;charset=utf-8" />

        <h3>Other download paths</h3>
        <p>
          <a href={`${import.meta.env.BASE_URL}fix-x11-forwarding.sh`} download="fix-x11-forwarding.sh">Download fix-x11-forwarding.sh (Pages)</a>
          {' '}|{' '}
          <a href="https://raw.githubusercontent.com/swipswaps/fedora37-io-audit/main/fix-x11-forwarding.sh">Raw on GitHub</a>
          {' '}|{' '}
          <a href="https://github.com/swipswaps/fedora37-io-audit/blob/main/fix-x11-forwarding.sh" target="_blank" rel="noopener noreferrer">Browse on GitHub</a>
        </p>
      </section>

      <section id="guide">
        <h2>Fedora 45 interactive guide</h2>
        <p>Interactive menu for GNOME performance tuning, DNF5 tuning, a post-install review that offers a firewalld fix when firewalld is installed but not running, systemd service health, git sync, and optional XFCE installation. Every action prints its exact command before asking. Re-running is safe.</p>

        <h3>What it covers</h3>
        <ul>
          <li><strong>D-Bus auto-attach.</strong> Preflight exports <code>XDG_RUNTIME_DIR</code> and <code>DBUS_SESSION_BUS_ADDRESS</code> if <code>/run/user/$(id -u)/bus</code> exists, so <code>gsettings</code> and <code>gnome-extensions</code> work over SSH.</li>
          <li><strong>Firewalld remediation.</strong> Review detects firewalld installed but not running, offers <code>systemctl enable --now firewalld</code>, verifies with <code>firewall-cmd --state</code>, and prints diagnostics if it does not start.</li>
          <li><strong>Service health.</strong> Option 10 lists firewalld, sshd, chronyd, systemd-timesyncd, gdm, NetworkManager, cups, bluetooth with <code>active=</code> and <code>enabled=</code>.</li>
          <li><strong>Git sync.</strong> Option 11 pulls when <code>.git</code> exists, or clones from <code>github.com/swipswaps/fedora37-io-audit</code> when the directory is empty.</li>
          <li><strong>Comma-separated input.</strong> Typing <code>1,3,4,5</code> at the menu runs those four in order; each asks its own confirmation.</li>
        </ul>

        <div className="warn-box">
          <strong>Bus required for GNOME options over SSH</strong>
          Options 1, 2, 3, and 9 need a reachable graphical session bus. <code>/run/user/1000/bus</code> exists as long as a graphical user is logged in on the console. If that session has been logged out, preflight prints a one-line instruction instead of failing mid-run.
        </div>
        <div className="warn-box danger">
          <strong>XFCE is a 1 GiB install that adds an Xorg server</strong>
          XFCE is optional. It pulls 369 packages, adds Xorg to a Wayland-only Workstation install, and requires a reboot before the session appears in GDM. After first login, <code>xdg-desktop-portal</code> needs <code>systemctl --user stop/start xdg-desktop-portal.service</code>.
        </div>

        <h3>Usage</h3>
        <CodeBlock
          code={`# fresh Fedora 45 target: curl from Pages and run
curl -fL -o fedora45-guide.sh https://swipswaps.github.io/fedora37-io-audit/fedora45-guide.sh
chmod +x fedora45-guide.sh
./fedora45-guide.sh
# at the menu, type 8 for the recommended sequence,
# or 1,3,4,5 to run those four, or a single digit`}
          filename="run.sh"
          mime="application/x-sh;charset=utf-8"
        />

        <h3>Source</h3>
        <CodeBlock code={guideScript} filename="fedora45-guide.sh" mime="application/x-sh;charset=utf-8" />

        <h3>Other download paths</h3>
        <p>
          <a href={`${import.meta.env.BASE_URL}fedora45-guide.sh`} download="fedora45-guide.sh">Download fedora45-guide.sh (Pages)</a>
          {' '}|{' '}
          <a href="https://raw.githubusercontent.com/swipswaps/fedora37-io-audit/main/fedora45-guide.sh">Raw on GitHub</a>
          {' '}|{' '}
          <a href="https://github.com/swipswaps/fedora37-io-audit/blob/main/fedora45-guide.sh" target="_blank" rel="noopener noreferrer">Browse on GitHub</a>
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

  cat > "$WORKDIR/fix-x11-forwarding.sh" <<'FIX_X11_END'
#!/usr/bin/env bash
# fix-x11-forwarding.sh - run on the Fedora host that receives ssh -Y.
# Idempotent. Gated: each step asserts its precondition or fails with a
# concrete next diagnostic. No xeyes, no xorg-x11-apps (absent on F45).
set +e
set +u
set +o pipefail

P="[fix-x11]"

sshd_kv() {
  awk -v k="$2" 'tolower($1)==tolower(k){print $2; exit}' <<< "$1"
}

main() {
  local ERRORS=0
  local RECONNECT_NEEDED=0

  fail() { echo "$P FAIL: $1"; ERRORS=$((ERRORS + 1)); }
  ok()   { echo "$P OK:   $1"; }
  info() { echo "$P INFO: $1"; }
  warn() { echo "$P WARN: $1"; }
  step() { echo ""; echo "== $1 =="; }

  step "0. Diagnostics"
  info "user=$USER host=$(hostname) kernel=$(uname -r)"
  info "DISPLAY=${DISPLAY:-<unset>}"
  info "SSH_CONNECTION=${SSH_CONNECTION:-<not an SSH session>}"
  if [ -e "$HOME/.Xauthority" ]; then
    info ".Xauthority present ($(stat -c %s "$HOME/.Xauthority") bytes)"
  else
    info ".Xauthority absent"
  fi
  if command -v xauth >/dev/null; then
    ok "xauth: $(command -v xauth)"
  else
    warn "xauth missing"
  fi

  step "1. sudo"
  sudo -v
  if [ "$?" -ne 0 ]; then fail "sudo authentication"; return 1; fi
  ok "sudo ticket acquired"

  step "2. xauth install"
  if command -v xauth >/dev/null; then
    ok "already present"
  else
    info "installing xorg-x11-xauth"
    sudo dnf install -y xorg-x11-xauth >/tmp/xauth-install.$$ 2>&1
    if ! command -v xauth >/dev/null; then
      fail "install did not provide xauth"
      awk '{print "    " $0}' /tmp/xauth-install.$$
      rm -f /tmp/xauth-install.$$
      return 1
    fi
    rm -f /tmp/xauth-install.$$
    ok "installed"
    RECONNECT_NEEDED=1
  fi

  step "3. sshd -T usable; parse effective config"
  local SSHD_BIN=""
  local c
  for c in /usr/sbin/sshd /usr/local/sbin/sshd; do
    if [ -x "$c" ]; then SSHD_BIN="$c"; break; fi
  done
  if [ -z "$SSHD_BIN" ]; then
    local via_path
    via_path=$(command -v sshd)
    if [ -n "$via_path" ] && [ -x "$via_path" ]; then SSHD_BIN="$via_path"; fi
  fi
  if [ -z "$SSHD_BIN" ]; then fail "sshd binary not found"; return 1; fi
  info "sshd: $SSHD_BIN"

  local SSHD_T_OUT RC LINES
  SSHD_T_OUT=$(sudo "$SSHD_BIN" -T 2>&1)
  RC=$?
  LINES=$(printf '%s\n' "$SSHD_T_OUT" | wc -l)
  if [ "$RC" -ne 0 ] || [ "$LINES" -lt 5 ] || ! printf '%s\n' "$SSHD_T_OUT" | grep -qi '^port '; then
    fail "sshd -T unusable (rc=$RC lines=$LINES)"
    info "first 10 lines:"
    printf '%s\n' "$SSHD_T_OUT" | head -10 | awk '{print "    " $0}'
    info "inspect:  sudo $SSHD_BIN -t"
    return 1
  fi
  ok "sshd -T produced $LINES lines"

  local X11F X11L XAUTH
  X11F=$(sshd_kv "$SSHD_T_OUT" x11forwarding)
  X11L=$(sshd_kv "$SSHD_T_OUT" x11uselocalhost)
  XAUTH=$(sshd_kv "$SSHD_T_OUT" xauthlocation)
  info "x11forwarding=${X11F:-<absent>} x11uselocalhost=${X11L:-<absent>} xauthlocation=${XAUTH:-<absent>}"

  step "4. Ensure X11Forwarding yes (re-verify after apply)"
  if [ "$X11F" = "yes" ]; then
    ok "already yes"
  else
    info "writing /etc/ssh/sshd_config.d/60-x11-forwarding.conf"
    sudo mkdir -p /etc/ssh/sshd_config.d
    sudo tee /etc/ssh/sshd_config.d/60-x11-forwarding.conf > /dev/null <<'DROPIN_END'
X11Forwarding yes
X11UseLocalhost yes
DROPIN_END
    local SYN
    SYN=$(sudo "$SSHD_BIN" -t 2>&1)
    if [ -n "$SYN" ]; then
      fail "sshd -t rejected drop-in: $SYN"
      return 1
    fi
    sudo systemctl reload sshd
    SSHD_T_OUT=$(sudo "$SSHD_BIN" -T 2>&1)
    X11F=$(sshd_kv "$SSHD_T_OUT" x11forwarding)
    if [ "$X11F" != "yes" ]; then
      fail "reload succeeded but x11forwarding still '${X11F:-absent}'"
      info "a Match block or later Include is overriding"
      info "inspect:  sudo grep -rn '^Match\|X11Forwarding' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/"
      return 1
    fi
    ok "drop-in applied and re-verified"
  fi

  step "5. Per-connection X11Forwarding for $USER"
  local PC_OUT PER_USER
  PC_OUT=$(sudo "$SSHD_BIN" -T -C user="$USER",host=localhost,addr=127.0.0.1 2>&1)
  PER_USER=$(sshd_kv "$PC_OUT" x11forwarding)
  info "per-connection=${PER_USER:-<absent>}"
  if [ "$PER_USER" != "yes" ]; then
    fail "per-connection X11Forwarding not yes"
    info "inspect:  sudo grep -rn '^Match\|X11Forwarding' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/"
    return 1
  fi
  ok "per-connection=yes"

  step "6. X11 cookie for current session"
  if [ -z "$DISPLAY" ]; then
    warn "DISPLAY unset - not an SSH -Y session"
    info "reconnect from client:  ssh -Y $USER@<this-host>"
  else
    local NUM COOKIE
    NUM="${DISPLAY##*:}"
    NUM="${NUM%%.*}"
    info "display number: :$NUM"
    COOKIE=$(xauth list | grep -E "[:/]${NUM}([[:space:]]|$)")
    if [ -n "$COOKIE" ]; then
      ok "cookie present:"
      printf '%s\n' "$COOKIE" | awk '{print "    " $0}'
    else
      warn "no cookie for :$NUM - session predates xauth install"
      info "existing sessions cannot be repaired retroactively"
      RECONNECT_NEEDED=1
    fi
  fi

  step "7. Optional key-based auth"
  info "on the client:"
  info "  ssh-keygen -t ed25519   (if you do not already have a key)"
  info "  ssh-copy-id $USER@<this-host>"

  step "8. Optional Cockpit MOTD"
  if [ -e /etc/motd.d/cockpit ] || [ -e /etc/motd.d/50-cockpit ]; then
    info "Cockpit MOTD present"
    info "  enable Cockpit:  sudo systemctl enable --now cockpit.socket"
    info "  or hide it:      sudo ln -sfn /dev/null /etc/motd.d/cockpit"
  else
    ok "no Cockpit MOTD"
  fi

  step "Summary"
  if [ "$ERRORS" -gt 0 ]; then
    echo "$P RESULT: FAILED ($ERRORS error(s)); see messages above"
    return 1
  fi
  if [ "$RECONNECT_NEEDED" -eq 1 ]; then
    echo "$P RESULT: CONFIG_FIXED_RECONNECT_REQUIRED"
    info "next:  exit ; ssh -Y $USER@<this-host> ; ./fix-x11-forwarding.sh"
    return 0
  fi
  echo "$P RESULT: SUCCESS - cookie present, X11Forwarding=yes for $USER, session ready"
  return 0
}

main "$@"
FIX_X11_END
  chmod +x "$WORKDIR/fix-x11-forwarding.sh"

  cat > "$WORKDIR/fedora45-guide.sh" <<'FEDORA45_GUIDE_END'
#!/usr/bin/env bash
# fedora45-guide.sh — interactive, idempotent guide for Fedora 45 Workstation.
# Auto-attaches to the graphical D-Bus bus if reachable so gsettings,
# gnome-extensions, and systemctl --user work over SSH.
set +e
set +u
set +o pipefail

GUIDE_VERSION="3"
P="[guide]"
say()  { echo "$P $*"; }
step() { echo ""; echo "-- $* --"; }
have() { command -v "$1" >/dev/null 2>&1; }
ask()  { read -r -p "$P $1 [y/N]: " a; case "$a" in y|Y) return 0;; *) return 1;; esac; }

dbus_attach() {
  if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    say "D-Bus already reachable (inherited from environment)"
    return 0
  fi
  local bus="/run/user/$(id -u)/bus"
  if [ -S "$bus" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$bus"
    say "attached to graphical session bus at $bus"
    return 0
  fi
  say "no graphical session bus at $bus"
  say "  options 1, 2, 3, 9 require a running GNOME session"
  say "  log in on the physical display, keep it alive, re-run over SSH"
  return 1
}

preflight() {
  step "Preflight"
  if grep -q 'Fedora release 45' /etc/fedora-release 2>/dev/null; then
    say "Fedora 45: $(cat /etc/fedora-release)"
  else
    say "WARN: not Fedora 45"
  fi
  if [ "$(id -u)" -eq 0 ]; then say "do not run as root"; return 1; fi
  sudo -v || { say "sudo failed"; return 1; }
  say "sudo ticket acquired for $(whoami)"
  dbus_attach || say "continuing without bus; graphical options will warn"
  return 0
}

gnome_state() {
  step "GNOME current state"
  if ! have gsettings; then say "gsettings not installed"; return 1; fi
  say "animations:          $(gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null || echo '?')"
  say "slowdown factor:     $(grep -h '^GNOME_SHELL_SLOWDOWN_FACTOR=' /etc/environment 2>/dev/null || echo 'unset')"
  say "shell version:       $(gnome-shell --version 2>/dev/null || echo '?')"
  say "session type:        ${XDG_SESSION_TYPE:-unknown}"
  if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    local n
    n=$(gnome-extensions list --enabled 2>/dev/null | wc -l)
    say "extensions enabled:  $n"
    gnome-extensions list --enabled 2>/dev/null | head -20 | awk '{print "  - " $0}'
  else
    say "extensions enabled:  <bus unavailable>"
  fi
}

require_bus() {
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    say "requires graphical D-Bus bus; see preflight message above"
    return 1
  fi
  return 0
}

gnome_disable_animations() {
  require_bus || return 1
  step "Disable GNOME animations"
  local cur
  cur=$(gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null)
  if [ "$cur" = "false" ]; then say "already disabled"; return 0; fi
  say "sets org.gnome.desktop.interface enable-animations false"
  say "revert: gsettings set org.gnome.desktop.interface enable-animations true"
  if ask "Apply?"; then
    gsettings set org.gnome.desktop.interface enable-animations false
    say "done; verify: gsettings get org.gnome.desktop.interface enable-animations"
  fi
}

gnome_slowdown_factor() {
  step "Speed up animations (0.4x)"
  if grep -q '^GNOME_SHELL_SLOWDOWN_FACTOR=' /etc/environment 2>/dev/null; then
    say "already set: $(grep -h '^GNOME_SHELL_SLOWDOWN_FACTOR=' /etc/environment)"
    return 0
  fi
  say "writes GNOME_SHELL_SLOWDOWN_FACTOR=0.4 to /etc/environment"
  say "log out and back in for the shell to pick it up"
  if ask "Apply?"; then
    sudo touch /etc/environment
    sudo chmod 644 /etc/environment
    echo 'GNOME_SHELL_SLOWDOWN_FACTOR=0.4' | sudo tee -a /etc/environment >/dev/null
    say "done"
  fi
}

gnome_audit_extensions() {
  require_bus || return 1
  step "Audit GNOME extensions"
  local enabled
  enabled=$(gnome-extensions list --enabled 2>/dev/null)
  if [ -z "$enabled" ]; then say "no extensions enabled"; return 0; fi
  echo "$enabled" | awk '{print "  - " $0}'
  say ""
  say "extensions run inside gnome-shell; one bad extension degrades the whole desktop"
  if ! ask "Disable all user extensions to isolate?"; then return 0; fi
  local save="/tmp/guide-extensions-disabled.$$"
  printf '%s\n' "$enabled" > "$save"
  gsettings set org.gnome.shell disable-user-extensions true
  say "saved disabled list to $save"
  say "re-enable one:   gnome-extensions enable <id>"
  say "re-enable all:   gsettings set org.gnome.shell disable-user-extensions false"
}

dnf_read() {
  local key="$1"
  if [ -r /etc/dnf/dnf.conf ]; then
    grep -E "^${key}[[:space:]]*=" /etc/dnf/dnf.conf 2>/dev/null | head -1
  fi
}

dnf_tuning() {
  step "DNF5 tuning"
  local mp dy
  mp=$(dnf_read max_parallel_downloads)
  dy=$(dnf_read defaultyes)
  say "max_parallel_downloads: ${mp:-<default = 3>}"
  say "defaultyes:             ${dy:-<default = False>}"
  if [ -z "$mp" ] || ! echo "$mp" | grep -q '= *10'; then
    say "set max_parallel_downloads=10 (default is 3)"
    if ask "Apply?"; then sudo dnf5 config-manager setopt max_parallel_downloads=10; fi
  else
    say "max_parallel_downloads already 10"
  fi
  if [ -z "$dy" ] || ! echo "$dy" | grep -qi '= *true'; then
    say "set defaultyes=True (Enter means yes at prompts)"
    if ask "Apply?"; then sudo dnf5 config-manager setopt defaultyes=True; fi
  else
    say "defaultyes already True"
  fi
}

review() {
  step "Post-install review"
  say "system update:  sudo dnf5 upgrade --refresh -y"
  say "last package:   $(rpm -qa --last 2>/dev/null | head -1 | cut -c1-70)"
  local selinux ptrace
  if have getenforce; then selinux=$(getenforce 2>/dev/null || echo unknown); else selinux="selinux tools not installed"; fi
  ptrace=$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || echo unknown)
  say "SELinux:        $selinux"
  say "ptrace scope:   $ptrace  (1 = restricted, F45 default)"
  if have flatpak; then
    flatpak remotes --columns=name 2>/dev/null | awk '{print "flatpak remote: " $0}'
  else
    say "flatpak:        not installed"
  fi
  say ""
  say "recommended (each is one command, not run here):"
  say "  sudo dnf5 upgrade --refresh -y"
  say "  fwupdmgr refresh && fwupdmgr get-updates"
  say "  sudo dnf5 install gnome-tweaks"
  say "  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
  if have firewall-cmd; then
    local fw_state
    fw_state=$(firewall-cmd --state 2>/dev/null)
    if [ "$fw_state" = "running" ]; then
      say ""
      say "firewalld:      running"
    else
      say ""
      say "firewalld:      installed, NOT running"
      say "  Fedora 45 Workstation enables firewalld by default; not running means it was"
      say "  stopped, disabled, or failed at boot. This is a real security gap."
      if ask "Enable firewalld now (systemctl enable --now firewalld)?"; then
        sudo systemctl enable --now firewalld
        local post
        post=$(firewall-cmd --state 2>/dev/null)
        if [ "$post" = "running" ]; then
          say "firewalld now running"
          sudo firewall-cmd --list-services 2>/dev/null | awk '{print "  services: " $0}'
        else
          say "firewalld still not running; diagnose with:"
          say "  systemctl status firewalld --no-pager"
          say "  journalctl -u firewalld -b --no-pager | tail -30"
        fi
      fi
    fi
  fi
}

xfce_after_install_note() {
  say ""
  say "next steps, in order:"
  say "  1. reboot:  sudo systemctl reboot"
  say "  2. at GDM, click the gear next to your username, choose 'Xfce Session'"
  say "  3. open a terminal in the XFCE session and run:"
  say "       systemctl --user stop xdg-desktop-portal.service"
  say "       systemctl --user start xdg-desktop-portal.service"
  say "     without this, Flatpak apps cannot open files or links"
}

xfce_install() {
  step "Install XFCE alongside GNOME"
  if rpm -q xfce4-session >/dev/null 2>&1; then
    say "XFCE already installed"
    xfce_after_install_note
    return 0
  fi
  say "groups:"
  say "  1) @xfce-desktop-environment  369 pkgs, 393 MiB dl, 1 GiB installed (includes apps)"
  say "  2) @xfce-desktop              230 pkgs, 290 MiB dl, 765 MiB installed (panel+Thunar only)"
  say ""
  say "consequences:"
  say "  - Fedora 45 Workstation is Wayland-only; this adds an Xorg server"
  say "  - GDM stays the login screen; LightDM installed but disabled"
  say "  - reboot is required before the session appears in GDM"
  say "  - after first XFCE login, xdg-desktop-portal needs a restart (shown below)"
  read -r -p "$P group [1/2/0=skip]: " g
  case "$g" in
    1) ask "Install @xfce-desktop-environment (1 GiB)?" && sudo dnf5 install -y @xfce-desktop-environment && xfce_after_install_note ;;
    2) ask "Install @xfce-desktop (765 MiB)?" && sudo dnf5 install -y @xfce-desktop && xfce_after_install_note ;;
    *) say "skipped" ;;
  esac
}

xfce_remove() {
  step "Remove XFCE"
  if ! rpm -q xfce4-session >/dev/null 2>&1; then say "XFCE not installed"; return 0; fi
  say "removes the XFCE group; GNOME untouched; GDM stays"
  if ask "Remove?"; then
    sudo dnf5 group remove @xfce-desktop-environment 2>/dev/null || sudo dnf5 group remove @xfce-desktop 2>/dev/null
    say "removed; consider: sudo dnf5 autoremove"
  fi
}

services() {
  step "Systemd service health (read-only)"
  local svc unit state enabled
  for svc in firewalld sshd chronyd systemd-timesyncd gdm NetworkManager cups bluetooth; do
    unit="$svc.service"
    if ! systemctl list-unit-files "$unit" 2>/dev/null | grep -q "$unit"; then
      continue
    fi
    state=$(systemctl is-active "$unit" 2>/dev/null || echo inactive)
    enabled=$(systemctl is-enabled "$unit" 2>/dev/null || echo unknown)
    printf '  %-24s active=%-10s enabled=%s\n' "$unit" "$state" "$enabled"
  done
  say ""
  say "expected for a default Fedora 45 Workstation:"
  say "  firewalld.service        active=enabled  (security baseline)"
  say "  gdm.service              active=enabled"
  say "  NetworkManager.service   active=enabled"
  say "  sshd.service             optional; active only if you enabled it"
  say "  chronyd OR systemd-timesyncd  exactly one should be active"
}

git_sync() {
  step "Git sync (clone or pull)"
  if [ -d .git ]; then
    say ".git present in $(pwd)"
    local remote
    remote=$(git remote get-url origin 2>/dev/null)
    if [ -n "$remote" ]; then say "origin: $remote"; fi
    say "working tree:"
    git status --short 2>/dev/null | head -20 | awk '{print "  " $0}'
    say ""
    if ask "Run git pull --ff-only?"; then
      git fetch --all 2>/dev/null
      git pull --ff-only
    fi
    say ""
    say "to push local changes:  git add -A && git commit -m 'msg' && git push"
    return 0
  fi
  if [ -n "$(ls -A 2>/dev/null)" ]; then
    say "directory is not empty; git refuses to clone in place"
    say "  clone to a sibling:"
    say "    git clone https://github.com/swipswaps/fedora37-io-audit.git ~/fedora37-io-audit"
    say "  or move files out first, then from this empty dir:"
    say "    git clone https://github.com/swipswaps/fedora37-io-audit.git ."
    return 0
  fi
  say "empty directory; ready to clone"
  if ask "Clone https://github.com/swipswaps/fedora37-io-audit.git into this directory?"; then
    if git clone https://github.com/swipswaps/fedora37-io-audit.git .; then
      say "cloned"
      if [ -f deploy.sh ]; then
        say "deploy.sh arrived; re-run ./bootstrap-fedora45.sh to patch it"
      fi
    else
      say "clone failed; check network and GitHub access"
    fi
  fi
}

menu() {
  cat <<'MENU_END'

  Fedora 45 interactive guide  (v3)
  ---------------------------------
  1) GNOME: disable animations
  2) GNOME: speed up animations (0.4x)
  3) GNOME: audit/disable extensions
  4) DNF5: parallel downloads + defaultyes
  5) Post-install review (offers firewalld fix)
  6) Install XFCE alongside GNOME
  7) Remove XFCE
  8) Recommended: 1, 3, 4, 5
  9) Show GNOME current state
  10) Systemd service health (read-only)
  11) Git sync (clone or pull)
  0) Exit

  Input: single digit, comma/space list (e.g. 1,3,4,5), or "8" for recommended

MENU_END
}

dispatch() {
  case "$1" in
    1) gnome_disable_animations ;;
    2) gnome_slowdown_factor ;;
    3) gnome_audit_extensions ;;
    4) dnf_tuning ;;
    5) review ;;
    6) xfce_install ;;
    7) xfce_remove ;;
    8) gnome_disable_animations; gnome_audit_extensions; dnf_tuning; review ;;
    9) gnome_state ;;
    10) services ;;
    11) git_sync ;;
    0) return 2 ;;
    "") return 0 ;;
    *) say "unknown: $1" ;;
  esac
  return 0
}

main() {
  preflight || return 1
  while true; do
    menu
    read -r -p "$P choice: " line
    if [ -z "$line" ]; then continue; fi
    local tok rc
    for tok in $(echo "$line" | tr ',' ' '); do
      dispatch "$tok"
      rc=$?
      if [ "$rc" -eq 2 ]; then say "exit"; return 0; fi
    done
  done
}

main "$@"
FEDORA45_GUIDE_END
  chmod +x "$WORKDIR/fedora45-guide.sh"

  mkdir -p "$WORKDIR/public"
  cp "$WORKDIR/flash-fedora.sh" "$WORKDIR/public/flash-fedora.sh"
  cp "$WORKDIR/fix-x11-forwarding.sh" "$WORKDIR/public/fix-x11-forwarding.sh"
  cp "$WORKDIR/fedora45-guide.sh" "$WORKDIR/public/fedora45-guide.sh"
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
