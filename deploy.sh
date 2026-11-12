#!/usr/bin/env bash
set +e
set +H

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
  for cmd in gh git npm node curl xdg-open; do
    if ! command -v "$cmd" >/dev/null; then
      echo "missing command: $cmd"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    fail "install missing commands and re-run"
    return 1
  fi
  ok "commands present"

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
      :root {
        font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        font-size: 16px;
        line-height: 1.6;
        color: #1a1a1a;
        background: #f4f5f7;
      }
      * { box-sizing: border-box; }
      body { margin: 0; padding: 2rem 1rem; }
      main {
        max-width: 920px;
        margin: 0 auto;
        background: #ffffff;
        padding: 2.5rem 2.5rem 2rem;
        border: 1px solid #d8dbe0;
        border-radius: 6px;
      }
      header { margin-bottom: 2rem; padding-bottom: 1.5rem; border-bottom: 1px solid #d8dbe0; }
      h1 { font-size: 1.75rem; font-weight: 600; margin: 0 0 0.5rem; letter-spacing: -0.01em; }
      h2 { font-size: 1.2rem; font-weight: 600; margin: 2rem 0 0.75rem; padding-bottom: 0.35rem; border-bottom: 1px solid #e6e8eb; }
      h3 { font-size: 1rem; font-weight: 600; margin: 1.25rem 0 0.5rem; }
      p { margin: 0 0 0.9rem; }
      section { margin-bottom: 1.5rem; }
      table { width: 100%; border-collapse: collapse; margin: 0.5rem 0 1.25rem; font-size: 0.925rem; }
      th, td { text-align: left; padding: 0.55rem 0.75rem; border: 1px solid #d8dbe0; vertical-align: top; }
      thead th { background: #eef0f3; font-weight: 600; }
      caption { text-align: left; font-size: 0.85rem; color: #5a6270; margin-bottom: 0.4rem; caption-side: top; }
      pre { background: #f6f8fa; border: 1px solid #d8dbe0; border-left: 3px solid #4b5563; border-radius: 4px; padding: 0.9rem 1rem; overflow-x: auto; font-size: 0.85rem; line-height: 1.5; margin: 0.5rem 0 1rem; }
      code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.88em; }
      p code, li code, td code { background: #eef0f3; padding: 0.05em 0.35em; border-radius: 3px; border: 1px solid #e2e5ea; }
      a { color: #0b5ed7; text-decoration: none; }
      a:hover { text-decoration: underline; }
      ol, ul { padding-left: 1.5rem; margin: 0.5rem 0 1rem; }
      li { margin: 0.3rem 0; }
      footer { margin-top: 2.5rem; padding-top: 1rem; border-top: 1px solid #d8dbe0; font-size: 0.85rem; color: #5a6270; }
      .refs { font-variant-numeric: tabular-nums; }
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
import React from 'react'

const references = [
  { id: 1, publisher: 'docs.fedoraproject.org', title: 'Fedora Project - End of Life Releases', url: 'https://docs.fedoraproject.org/en-US/releases/eol/', note: 'Fedora Linux 37 reached end of life on 2023-12-05.' },
  { id: 2, publisher: 'rpmfusion.org', title: 'RPM Fusion - Frequently Asked Questions', url: 'https://rpmfusion.org/FAQ', note: 'RPM Fusion repositories follow upstream Fedora end-of-life.' },
  { id: 3, publisher: 'Linux kernel documentation', title: 'PSI - Pressure Stall Information', url: 'https://docs.kernel.org/accounting/psi.html', note: 'Definitions of some and full stall metrics.' },
  { id: 4, publisher: 'smartmontools.org', title: 'smartctl(8) manual page', url: 'https://www.smartmontools.org/browser/trunk/smartmontools/smartctl.8.in', note: 'SMART control and monitoring utility.' },
  { id: 5, publisher: 'GitHub', title: 'PackageKit/PackageKit', url: 'https://github.com/PackageKit/PackageKit', note: 'D-Bus abstraction layer for package management.' },
  { id: 6, publisher: 'GitHub', title: 'actions/deploy-pages', url: 'https://github.com/actions/deploy-pages', note: 'Deploys Actions artifacts to GitHub Pages.' },
  { id: 7, publisher: 'GitHub CLI manual', title: 'gh repo create', url: 'https://cli.github.com/manual/gh_repo_create', note: 'Source and push flags used in this script.' },
  { id: 8, publisher: 'GitHub CLI manual', title: 'gh run list', url: 'https://cli.github.com/manual/gh_run_list', note: 'Workflow filter and status/conclusion fields.' }
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

function Refs({ ids }) {
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
            <tr>
              <th scope="col">No.</th>
              <th scope="col">Finding</th>
              <th scope="col">Evidence</th>
              <th scope="col">Correction</th>
              <th scope="col">Refs</th>
            </tr>
          </thead>
          <tbody>
            {findings.map(f => (
              <tr key={f.id}>
                <td>{f.id}</td>
                <td>{f.title}</td>
                <td>{f.evidence}</td>
                <td>{f.correction}</td>
                <td className="refs"><Refs ids={f.refs} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Diagnostic evidence</h2>
        <table>
          <caption>Observed values and their interpretation</caption>
          <thead>
            <tr>
              <th scope="col">Metric</th>
              <th scope="col">Observed</th>
              <th scope="col">Interpretation</th>
              <th scope="col">Refs</th>
            </tr>
          </thead>
          <tbody>
            {metrics.map((m, i) => (
              <tr key={i}>
                <td>{m.metric}</td>
                <td>{m.observed}</td>
                <td>{m.interpretation}</td>
                <td className="refs"><Refs ids={m.refs} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2>Corrected RPM Fusion configuration</h2>
        <p>Fedora 37 reached end of life on 2023-12-05, and RPM Fusion follows upstream end-of-life. The two failing repositories should be disabled locally rather than redirected to another release.</p>
        <pre><code>{rpmConfig}</code></pre>
      </section>

      <section>
        <h2>Verification commands</h2>
        <p>Run these on the affected host to confirm the diagnosis and the corrected configuration.</p>
        <pre><code>{verifyCmds}</code></pre>
      </section>

      <section>
        <h2>Deployment notes</h2>
        <p>Pages deployment uses <code>actions/deploy-pages</code>, which publishes an artifact uploaded by <code>actions/upload-pages-artifact</code>. The legacy builds endpoint is not used because it does not reflect Actions-based deployments. Status is read from the workflow run through <code>gh run list</code>.</p>
      </section>

      <section>
        <h2>References</h2>
        <ol>
          {references.map(r => (
            <li key={r.id}>
              {r.publisher}. <a href={r.url}>{r.title}</a>. {r.note}
            </li>
          ))}
        </ol>
      </section>

      <footer>
        <p>Generated by deploy.sh. ASCII only.</p>
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

  ok "repository files written to $WORKDIR"

  step "3. Local build"
  cd "$WORKDIR"
  if [ -f package-lock.json ]; then
    npm ci >/tmp/audit-ci.log 2>&1
    if [ "$?" -ne 0 ]; then
      warn "npm ci failed; falling back to npm install"
      npm install >/tmp/audit-install.log 2>&1
      if [ "$?" -ne 0 ]; then
        fail "npm install failed; see /tmp/audit-install.log"
        return 1
      fi
    fi
  else
    npm install >/tmp/audit-install.log 2>&1
    if [ "$?" -ne 0 ]; then
      fail "npm install failed; see /tmp/audit-install.log"
      return 1
    fi
  fi
  npm run build >/tmp/audit-build.log 2>&1
  if [ "$?" -ne 0 ] || [ ! -f "$WORKDIR/dist/index.html" ]; then
    fail "vite build failed; see /tmp/audit-build.log"
    return 1
  fi
  ok "local build succeeded"

  step "4. Git and repository"
  if [ ! -d "$WORKDIR/.git" ]; then
    git init -b main
    if [ "$?" -ne 0 ]; then
      fail "git init failed"
      return 1
    fi
  fi

  git add -A
  git -c user.name="Audit Bot" -c user.email="audit@local" commit -m "Update audit report site" >/tmp/audit-commit.log 2>&1
  if [ "$?" -ne 0 ]; then
    info "nothing to commit or commit skipped"
  fi

  if gh repo view "$GH_OWNER/$REPO_NAME" >/dev/null; then
    info "repository $GH_OWNER/$REPO_NAME already exists"
    git remote remove origin >/dev/null
    git remote add origin "https://github.com/$GH_OWNER/$REPO_NAME.git"
    git push -u origin main
    if [ "$?" -ne 0 ]; then
      fail "git push failed"
      return 1
    fi
  else
    gh repo create "$GH_OWNER/$REPO_NAME" --public --source=. --remote=origin --push
    if [ "$?" -ne 0 ]; then
      fail "gh repo create failed"
      return 1
    fi
  fi
  ok "repository pushed"

  step "5. Enable GitHub Pages"
  if gh api "repos/$GH_OWNER/$REPO_NAME/pages" --jq '.html_url' >/dev/null; then
    ok "Pages already enabled"
  else
    gh api "repos/$GH_OWNER/$REPO_NAME/pages" -X POST -f build_type=workflow
    if [ "$?" -ne 0 ]; then
      warn "Pages POST failed; wait a moment and re-run"
    else
      ok "Pages enabled with Actions source"
    fi
  fi

  step "6. Monitor Pages workflow"
  local attempt=0
  local run_status=""
  local run_conclusion=""
  local page_url=""

  while [ "$attempt" -lt 30 ]; do
    attempt=$((attempt + 1))
    sleep 10

    run_status=$(gh run list --workflow="Deploy to GitHub Pages" --limit 1 --json status --jq '.[0].status')
    run_conclusion=$(gh run list --workflow="Deploy to GitHub Pages" --limit 1 --json conclusion --jq '.[0].conclusion')
    page_url=$(gh api "repos/$GH_OWNER/$REPO_NAME/pages" --jq '.html_url')

    if [ -z "$run_status" ] || [ "$run_status" = "null" ]; then
      info "attempt $attempt/30: workflow run not yet registered"
      continue
    fi

    info "attempt $attempt/30: status=$run_status conclusion=$run_conclusion"

    case "$run_status" in
      completed)
        if [ "$run_conclusion" = "success" ]; then
          PAGES_URL="$page_url"
          ok "Pages workflow completed successfully"
        else
          fail "Pages workflow completed with: $run_conclusion"
        fi
        break
        ;;
      in_progress|queued|requested|waiting|pending)
        :
        ;;
      *)
        warn "unknown workflow status: $run_status"
        ;;
    esac
  done

  if [ -z "$PAGES_URL" ]; then
    PAGES_URL="https://$GH_OWNER.github.io/$REPO_NAME/"
    warn "workflow did not complete within polling window; using inferred URL"
    warn "check https://github.com/$GH_OWNER/$REPO_NAME/actions for the actual result"
  fi

  step "7. Open page"
  info "opening $PAGES_URL"
  xdg-open "$PAGES_URL" >/dev/null 2>&1 &

  step "Summary"
  echo "Working directory: $WORKDIR"
  echo "Repository:        https://github.com/$GH_OWNER/$REPO_NAME"
  echo "Page:              $PAGES_URL"
  if [ "$ERRORS" -eq 0 ]; then
    echo "RESULT: success"
    return 0
  else
    echo "RESULT: $ERRORS error(s)"
    return 1
  fi
}

main "$@"
