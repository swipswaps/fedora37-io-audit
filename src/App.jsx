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

