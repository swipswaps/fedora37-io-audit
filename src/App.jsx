import React from 'react'

const references = [
  { id: 1, title: 'Fedora Project - End of Life Releases', publisher: 'docs.fedoraproject.org', url: 'https://docs.fedoraproject.org/en-US/releases/eol/', note: 'Fedora Linux 37 EOL since 2023-12-05' },
  { id: 2, title: 'RPM Fusion - Frequently Asked Questions', publisher: 'rpmfusion.org', url: 'https://rpmfusion.org/FAQ', note: 'RPM Fusion repositories follow upstream EOL' },
  { id: 3, title: 'PSI - Pressure Stall Information', publisher: 'Linux kernel documentation', url: 'https://git.kernel.org/pub/scm/linux/kernel/git/chunkuang.hu/linux.git/plain/Documentation/accounting/psi.rst?id=7b43af7f4b48c1abb6df811dbaa644a0c7800366', note: 'some and full stall definitions' },
  { id: 4, title: 'smartctl(8) manual page', publisher: 'smartmontools.org', url: 'https://www.smartmontools.org/browser/trunk/smartmontools/smartctl.8.in', note: 'SMART control and monitoring utility' },
  { id: 5, title: 'PackageKit', publisher: 'GitHub - PackageKit/PackageKit', url: 'https://github.com/PackageKit/PackageKit', note: 'D-Bus abstraction layer for package management' },
  { id: 6, title: 'actions/deploy-pages', publisher: 'GitHub', url: 'https://github.com/actions/deploy-pages', note: 'Deploys Actions artifacts to GitHub Pages' },
  { id: 7, title: 'gh repo create', publisher: 'GitHub CLI manual', url: 'https://cli.github.com/manual/gh_repo_create', note: '--source and --push flags' },
  { id: 8, title: 'gh run list', publisher: 'GitHub CLI manual', url: 'https://cli.github.com/manual/gh_run_list', note: 'workflow filter and status/conclusion fields' }
]

const findings = [
  {
    id: 1,
    title: 'PackageKit was not the memory bottleneck',
    evidence: 'PackageKit stopped; memory PSI about 79 percent; I/O PSI 91.69 percent; 2.7 GiB RAM free; 106 MiB swap used.',
    correction: 'Investigate storage I/O and D-state tasks. Do not increase swap or kill GPG agents.',
    refs: [5, 3]
  },
  {
    id: 2,
    title: 'Package name misspelling',
    evidence: 'smarctl was used four times. dnf returned no match.',
    correction: 'Install smartmontools. The binary it provides is smartctl.',
    refs: [4]
  },
  {
    id: 3,
    title: 'RPM Fusion 404 is EOL behavior',
    evidence: 'Fedora 37 EOL 2023-12-05. RPM Fusion follows upstream EOL.',
    correction: 'Set enabled=0 and skip_if_unavailable=True. Do not rewrite metalink URLs.',
    refs: [1, 2]
  },
  {
    id: 4,
    title: 'System disk SMART passed',
    evidence: 'smartctl -H PASSED. Reallocated 11. Pending 0. Offline_Uncorrectable 0.',
    correction: 'Do not run fsck on the mounted root. Do not replace the disk.',
    refs: [4]
  },
  {
    id: 5,
    title: 'Script lacked gh preflight and remote guards',
    evidence: 'No gh auth status check. Remote failures would abort under a no-exit-1 constraint.',
    correction: 'Add gh auth status preflight. Guard each remote call. Return nonzero from main only.',
    refs: [7, 8]
  }
]

const metrics = [
  { metric: 'Memory PSI some avg10', observed: '78.95 percent after PackageKit stop', interpretation: 'Memory pressure remained', refs: [3] },
  { metric: 'I/O PSI some avg10', observed: '91.69 percent', interpretation: 'Dominant pressure source', refs: [3] },
  { metric: 'Available RAM', observed: '2.7 GiB', interpretation: 'Not exhausted', refs: [] },
  { metric: 'Swap used', observed: '106 MiB', interpretation: 'Not exhausted', refs: [] },
  { metric: 'CPU I/O wait', observed: '25 to 50 percent', interpretation: 'Storage contention', refs: [] },
  { metric: 'Blocked tasks', observed: 'tracker-extract, kworker', interpretation: 'Blocked on I/O', refs: [] },
  { metric: 'SMART health', observed: 'PASSED', interpretation: 'Disk not failing', refs: [4] }
]

function RefLinks({ ids }) {
  if (!ids || ids.length === 0) return <span>none</span>
  return ids.map((id, i) => {
    const r = references.find(x => x.id === id)
    return (
      <React.Fragment key={id}>
        {i > 0 ? ', ' : ''}
        <a href={r.url}>[{id}]</a>
      </React.Fragment>
    )
  })
}

export default function App() {
  return (
    <main>
      <header>
        <h1>Fedora 37 I/O Audit</h1>
        <p>Diagnostic audit of a Fedora 37 troubleshooting session, with corrected repository configuration and a GitHub Pages deployment script.</p>
        <table>
          <caption>Document control</caption>
          <tbody>
            <tr><th scope="row">Audit date</th><td>2026-11-11</td></tr>
            <tr><th scope="row">Host</th><td>Fedora 37, kernel 5.19.7</td></tr>
            <tr><th scope="row">Scope</th><td>Local diagnosis, RPM Fusion configuration, Pages deployment script</td></tr>
          </tbody>
        </table>
      </header>

      <section>
        <h2>Audit findings</h2>
        <table>
          <caption>Five diagnostic errors and their corrections</caption>
          <thead>
            <tr><th scope="col">No.</th><th scope="col">Finding</th><th scope="col">Evidence</th><th scope="col">Correction</th><th scope="col">Refs</th></tr>
          </thead>
          <tbody>
            {findings.map(f => (
              <tr key={f.id}>
                <td>{f.id}</td>
                <td>{f.title}</td>
                <td>{f.evidence}</td>
                <td>{f.correction}</td>
                <td><RefLinks ids={f.refs} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Diagnostic evidence</h2>
        <table>
          <caption>Observed values and interpretation</caption>
          <thead>
            <tr><th scope="col">Metric</th><th scope="col">Observed</th><th scope="col">Interpretation</th><th scope="col">Refs</th></tr>
          </thead>
          <tbody>
            {metrics.map((m, i) => (
              <tr key={i}>
                <td>{m.metric}</td>
                <td>{m.observed}</td>
                <td>{m.interpretation}</td>
                <td><RefLinks ids={m.refs} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Corrected RPM Fusion configuration</h2>
        <p>Fedora 37 reached end of life on 2023-12-05, and RPM Fusion follows upstream EOL. The two failing repositories should be disabled locally, not redirected to another release.</p>
        <pre><code>{`# /etc/yum.repos.d/rpmfusion-nonfree.repo
[rpmfusion-nonfree-nvidia-driver]
enabled=0
skip_if_unavailable=True

[rpmfusion-nonfree-steam]
enabled=0
skip_if_unavailable=True`}</code></pre>
      </section>

      <section>
        <h2>Verification commands</h2>
        <p>Run these on the affected host to confirm the diagnosis and the corrected configuration.</p>
        <pre><code>{`systemctl is-active packagekit.service
cat /proc/pressure/memory
cat /proc/pressure/io
vmstat 1 5
sudo smartctl -H -A /dev/sda
sudo dnf --disablerepo=rpmfusion-nonfree-nvidia-driver \\
         --disablerepo=rpmfusion-nonfree-steam \\
         install smartmontools
gh run list --workflow="Deploy to GitHub Pages" --limit 3`}</code></pre>
      </section>

      <section>
        <h2>Deployment notes</h2>
        <p>Pages deployment uses actions/deploy-pages, which publishes an artifact uploaded by actions/upload-pages-artifact. The legacy builds endpoint is not used because it does not reflect Actions-based deployments. Status is read from the workflow run through gh run list.</p>
      </section>

      <section>
        <h2>References</h2>
        <ol>
          {references.map(r => (
            <li key={r.id}>
              {r.publisher}. <a href={r.url}>{r.title}</a>. {r.note}.
            </li>
          ))}
        </ol>
      </section>

      <footer>
        <p>Generated by deploy.sh. ASCII only. No CSS.</p>
      </footer>
    </main>
  )
}
