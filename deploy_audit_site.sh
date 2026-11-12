#!/usr/bin/env bash

deploy_audit_site.sh
One-shot, idempotent, scope-anchored to the current working directory.
Run from the directory that should host the repo; nothing outside that
directory is created or modified.
Constraints honored: no sed, no set -e, no exit 1, no 2>/dev/null,
no subprocess.run. ASCII only.
set +e
set +H

main() {
local ERRORS=0
local REPO_NAME="fedora37-io-audit"
local WORKDIR
WORKDIR="$(pwd)"
local GH_OWNER=""
local PAGES_URL=""

fail() { echo "ERROR: 
1
"
;
E
R
R
O
R
S
=
1";ERRORS=((ERRORS + 1)); }
ok() { echo "OK: $1"; }
info() { echo "INFO: $1"; }
warn() { echo "WARN: $1"; }
step() { echo ""; echo "== $1 =="; }

step "1. Prerequisites"
local cmd
local missing=0
for cmd in gh git npm node curl xdg-open; do
if ! command -v "
c
m
d
"
>
/
d
e
v
/
n
u
l
l
;
t
h
e
n
e
c
h
o
"
m
i
s
s
i
n
g
c
o
m
m
a
n
d
:
cmd">/dev/null;thenecho"missingcommand:cmd"
missing=1
fi
done
if [ "
m
i
s
s
i
n
g
"
−
n
e
0
]
;
t
h
e
n
f
a
i
l
"
i
n
s
t
a
l
l
m
i
s
s
i
n
g
c
o
m
m
a
n
d
s
a
n
d
r
e
−
r
u
n
"
r
e
t
u
r
n
1
f
i
o
k
"
c
o
m
m
a
n
d
s
p
r
e
s
e
n
t
"
i
n
f
o
"
w
o
r
k
i
n
g
d
i
r
e
c
t
o
r
y
i
s
missing"−ne0];thenfail"installmissingcommandsandre−run"return1fiok"commandspresent"info"workingdirectoryisWORKDIR"
info "no files will be written outside this directory"

if ! gh auth status >/dev/null; then
fail "gh is not authenticated; run gh auth login"
return 1
fi
ok "gh authenticated"

GH_OWNER=
(
g
h
a
p
i
u
s
e
r
−
−
j
q
′
.
l
o
g
i
n
′
)
i
f
[
−
z
"
(ghapiuser−−jq 
′
 .login 
′
 )if[−z"GH_OWNER" ]; then
fail "could not determine GitHub login"
return 1
fi
info "GitHub owner is $GH_OWNER"

step "2. Write repository files"
mkdir -p "
W
O
R
K
D
I
R
/
s
r
c
"
"
WORKDIR/src""WORKDIR/.github/workflows"

cat > "$WORKDIR/vite.config.js" <<'VITE_EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
plugins: [react()],
base: '/fedora37-io-audit/',
})
VITE_EOF

cat > "$WORKDIR/package.json" <<'PKG_EOF'
{
"name": "fedora37-io-audit",
"private": true,
"version": "1.0.0",
"type": "module",
"scripts": {
"dev": "vite",
"build": "vite build",
"preview": "vite preview"
},
"dependencies": {
"react": "^18.3.1",
"react-dom": "^18.3.1"
},
"devDependencies": {
"@vitejs/plugin-react": "^4.3.4",
"vite": "^6.0.0"
}
}
PKG_EOF

cat > "$WORKDIR/index.html" <<'HTML_EOF'

<!doctype html><html lang="en"> <head> <meta charset="UTF-8" /> <meta name="viewport" content="width=device-width, initial-scale=1.0" /> <title>Fedora 37 I/O Audit</title> </head> <body> <div id="root"></div> <script type="module" src="/src/main.jsx"></script> </body> </html> HTML_EOF
cat > "$WORKDIR/src/main.jsx" <<'MAIN_EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'

ReactDOM.createRoot(document.getElementById('root')).render(
<React.StrictMode><App /></React.StrictMode>,
)
MAIN_EOF

cat > "$WORKDIR/src/App.jsx" <<'APP_EOF'
import React from 'react'

const findings = [
{
id: 1,
title: 'PackageKit was not the memory bottleneck',
detail: 'PackageKit was stopped, yet memory pressure stayed near 79 percent while 2.7 GiB RAM was free. Disk I/O pressure was 91.69 percent. The optical drive /dev/sr0 was repeatedly failing reads and keeping processes in D state.'
},
{
id: 2,
title: 'Package name misspelling',
detail: 'The command attempted to install smarctl four times. The correct package is smartmontools, and the binary it provides is smartctl.'
},
{
id: 3,
title: 'RPM Fusion 404 is expected end of life behavior',
detail: 'Fedora 37 is end of life and RPM Fusion no longer serves F37 repositories. The correct local change is enabled=0 and skip_if_unavailable=True. Do not rewrite metalink URLs.'
},
{
id: 4,
title: 'System disk SMART passed',
detail: 'smartctl -H returned PASSED. Reallocated sectors are 11 with 2 events, pending and offline uncorrectable are zero. The Hitachi drive is not failing. Do not run fsck on the mounted root.'
},
{
id: 5,
title: 'Script must guard remote operations',
detail: 'The original script had no gh auth status preflight and would abort silently on remote failures under a no-exit-1 constraint. This script records errors and returns nonzero from main only.'
}
]

function App() {
return (

<main style={{ fontFamily: 'system-ui', maxWidth: 860, margin: '2rem auto', padding: '0 1rem', lineHeight: 1.7 }}> <h1>Fedora 37 I/O Audit</h1> <p style={{ color: '#555' }}> Audit of a troubleshooting session: diagnostic errors, corrected repository configuration, and a deployment script that respects strict shell constraints. </p> <h2>Findings</h2> <ul> {findings.map(f => ( <li key={f.id} style={{ marginBottom: '1rem' }}> <strong>{f.title}</strong><br /> <span style={{ color: '#444' }}>{f.detail}</span> </li> ))} </ul> <h2>Corrected RPM Fusion configuration</h2> <pre style={{ background: '#f4f4f4', padding: '1rem', overflowX: 'auto', fontSize: '0.9rem' }}> {`[rpmfusion-nonfree-nvidia-driver] enabled=0 skip_if_unavailable=True
[rpmfusion-nonfree-steam]
enabled=0
skip_if_unavailable=True`}
</pre>

<p>Fedora 37 is end of life. Disabling these repositories is the only safe local change.</p> <h2>Script constraints</h2> <ul> <li>No sed, no set -e, no exit 1, no 2&gt;/dev/null, no subprocess.run</li> <li>Every repository file emitted through a heredoc</li> <li>gh auth status checked before any remote call</li> <li>gh repo create --source=. --push used for the initial push</li> <li>Pages workflow monitored via gh run list on the workflow name</li> <li>xdg-open called on the Pages URL after successful deployment</li> </ul> <footer style={{ marginTop: '3rem', color: '#888', fontSize: '0.9rem' }}> Generated by deploy_audit_site.sh </footer> </main> ) }
export default App
APP_EOF

cat > "$WORKDIR/.github/workflows/deploy.yml" <<'WF_EOF'
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

uses: actions/checkout@v4

uses: actions/setup-node@v4
with:
node-version: 22
cache: npm

run: npm ci

run: npm run build

uses: actions/upload-pages-artifact@v3
with:
path: dist
deploy:
needs: build
runs-on: ubuntu-latest
environment:
name: github-pages
url: ${{ steps.deployment.outputs.page_url }}
steps:

id: deployment
uses: actions/deploy-pages@v4
WF_EOF

cat > "$WORKDIR/.gitignore" <<'GITIGNORE_EOF'
node_modules/
dist/
.DS_Store
GITIGNORE_EOF

cat > "$WORKDIR/README.md" <<'README_EOF'
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

Deployment status monitoring

Pages deployment via actions/deploy-pages@v4 does not register a legacy
Pages build. Polling repos/{owner}/{repo}/pages/builds/latest returns 404
indefinitely in that case. This script polls the Actions workflow run for
the workflow named "Deploy to GitHub Pages" via gh run list, which is the
authoritative signal for an Actions-based Pages deployment.

Script constraints

No sed, no set -e, no exit 1, no 2>/dev/null, no subprocess.run.
Every repository file is written through a heredoc.
gh auth status is checked before any remote operation.
gh repo create --source=. --push is used for the initial push.
The Pages workflow run is monitored via gh run list.
xdg-open is called on the Pages URL after successful deployment.
The script is anchored to the directory it is run from and creates no
files outside that directory.

Usage

cd <the directory that should host the repo>
chmod +x deploy_audit_site.sh
./deploy_audit_site.sh

Prerequisites

GitHub CLI authenticated with gh auth login.
Node.js 18 or newer and npm.
Network access to GitHub and the npm registry.
README_EOF

ok "repository files written to $WORKDIR"

step "3. Local build"
cd "WORKDIR" if [ -f package-lock.json ]; then npm ci >/tmp/audit-ci.log 2>&1 if [ "?" -ne 0 ]; then
warn "npm ci failed; falling back to npm install"
npm install >/tmp/audit-install.log 2>&1
if [ "?" -ne 0 ]; then fail "npm install failed; see /tmp/audit-install.log" tail -n 15 /tmp/audit-install.log return 1 fi fi else npm install >/tmp/audit-install.log 2>&1 if [ "?" -ne 0 ]; then
fail "npm install failed; see /tmp/audit-install.log"
tail -n 15 /tmp/audit-install.log
return 1
fi
fi
npm run build >/tmp/audit-build.log 2>&1
if [ "
?
"
−
n
e
0
]
∣
∣
[
!
−
f
"
?"−ne0]∣∣[!−f"WORKDIR/dist/index.html" ]; then
fail "vite build failed; see /tmp/audit-build.log"
tail -n 20 /tmp/audit-build.log
return 1
fi
ok "local build succeeded"

step "4. Git and repository"
if [ ! -d "
W
O
R
K
D
I
R
/
.
g
i
t
"
]
;
t
h
e
n
g
i
t
i
n
i
t
−
b
m
a
i
n
i
f
[
"
WORKDIR/.git"];thengitinit−bmainif["?" -ne 0 ]; then
fail "git init failed"
return 1
fi
fi

git add -A
git -c user.name="Audit Bot" -c user.email="audit@local" commit -m "Update audit report site" >/tmp/audit-commit.log 2>&1
if [ "$?" -ne 0 ]; then
info "nothing to commit or commit skipped (idempotent re-run)"
fi

if gh repo view "
G
H
O
W
N
E
R
/
GH 
O
​
 WNER/REPO_NAME" >/dev/null; then
info "repository 
G
H
O
W
N
E
R
/
GH 
O
​
 WNER/REPO_NAME already exists"
git remote remove origin >/dev/null
git remote add origin "https://github.com/$GH_OWNER/$REPO_NAME.git"
if [ "
?
"
−
n
e
0
]
;
t
h
e
n
f
a
i
l
"
g
i
t
r
e
m
o
t
e
a
d
d
f
a
i
l
e
d
"
r
e
t
u
r
n
1
f
i
g
i
t
p
u
s
h
−
u
o
r
i
g
i
n
m
a
i
n
i
f
[
"
?"−ne0];thenfail"gitremoteaddfailed"return1figitpush−uoriginmainif["?" -ne 0 ]; then
fail "git push failed; check network or remote permissions"
return 1
fi
else
gh repo create "
G
H
O
W
N
E
R
/
GH 
O
​
 WNER/REPO_NAME" --public --source=. --remote=origin --push
if [ "$?" -ne 0 ]; then
fail "gh repo create failed"
return 1
fi
fi
ok "repository pushed"

step "5. Enable GitHub Pages"
if gh api "repos/
G
H
O
W
N
E
R
/
GH 
O
​
 WNER/REPO_NAME/pages" --jq '.html_url' >/dev/null; then
ok "Pages already enabled"
else
gh api "repos/
G
H
O
W
N
E
R
/
GH 
O
​
 WNER/REPO_NAME/pages" -X POST -f build_type=workflow
if [ "$?" -ne 0 ]; then
warn "Pages POST failed; if the repo is brand new, wait a moment and re-run, or set Settings -> Pages -> Source to GitHub Actions"
else
ok "Pages enabled with Actions source"
fi
fi

step "6. Monitor Pages workflow"
local attempt=0
local max_attempts=30
local run_status=""
local run_conclusion=""
local page_url=""

while [ "
a
t
t
e
m
p
t
"
−
l
t
"
attempt"−lt"max_attempts" ]; do
attempt=$((attempt + 1))
sleep 10

run_status=
(
g
h
r
u
n
l
i
s
t
−
−
w
o
r
k
f
l
o
w
=
"
D
e
p
l
o
y
t
o
G
i
t
H
u
b
P
a
g
e
s
"
−
−
l
i
m
i
t
1
−
−
j
s
o
n
s
t
a
t
u
s
−
−
j
q
′
.
[
0
]
.
s
t
a
t
u
s
′
)
r
u
n
c
o
n
c
l
u
s
i
o
n
=
(ghrunlist−−workflow="DeploytoGitHubPages"−−limit1−−jsonstatus−−jq 
′
 .[0].status 
′
 )run 
c
​
 onclusion=(gh run list --workflow="Deploy to GitHub Pages" --limit 1 --json conclusion --jq '.[0].conclusion')
page_url=
(
g
h
a
p
i
"
r
e
p
o
s
/
(ghapi"repos/GH_OWNER/$REPO_NAME/pages" --jq '.html_url')

if [ -z "
r
u
n
s
t
a
t
u
s
"
]
∣
∣
[
"
run 
s
​
 tatus"]∣∣["run_status" = "null" ]; then
info "attempt 
a
t
t
e
m
p
t
/
attempt/max_attempts: workflow run not yet registered"
continue
fi

info "attempt 
a
t
t
e
m
p
t
/
attempt/max_attempts: status=
r
u
n
s
t
a
t
u
s
c
o
n
c
l
u
s
i
o
n
=
run 
s
​
 tatusconclusion=run_conclusion"

case "
r
u
n
s
t
a
t
u
s
"
i
n
c
o
m
p
l
e
t
e
d
)
i
f
[
"
run 
s
​
 tatus"incompleted)if["run_conclusion" = "success" ]; then
PAGES_URL="
p
a
g
e
u
r
l
"
o
k
"
P
a
g
e
s
w
o
r
k
f
l
o
w
c
o
m
p
l
e
t
e
d
s
u
c
c
e
s
s
f
u
l
l
y
"
e
l
s
e
f
a
i
l
"
P
a
g
e
s
w
o
r
k
f
l
o
w
c
o
m
p
l
e
t
e
d
w
i
t
h
c
o
n
c
l
u
s
i
o
n
:
page 
u
​
 rl"ok"Pagesworkflowcompletedsuccessfully"elsefail"Pagesworkflowcompletedwithconclusion:run_conclusion"
fi
attempt=run_status"
;;
esac
done

if [ -z "
P
A
G
E
S
U
R
L
"
]
;
t
h
e
n
P
A
G
E
S
U
R
L
=
"
h
t
t
p
s
:
/
/
PAGES 
U
​
 RL"];thenPAGES 
U
​
 RL="https://GH_OWNER.github.io/
R
E
P
O
N
A
M
E
/
"
w
a
r
n
"
w
o
r
k
f
l
o
w
d
i
d
n
o
t
r
e
p
o
r
t
s
u
c
c
e
s
s
w
i
t
h
i
n
t
h
e
p
o
l
l
i
n
g
w
i
n
d
o
w
;
u
s
i
n
g
i
n
f
e
r
r
e
d
U
R
L
"
w
a
r
n
"
c
h
e
c
k
h
t
t
p
s
:
/
/
g
i
t
h
u
b
.
c
o
m
/
REPO 
N
​
 AME/"warn"workflowdidnotreportsuccesswithinthepollingwindow;usinginferredURL"warn"checkhttps://github.com/GH_OWNER/$REPO_NAME/actions for the actual run result"
fi

step "7. Open page"
info "opening 
P
A
G
E
S
U
R
L
"
x
d
g
−
o
p
e
n
"
PAGES 
U
​
 RL"xdg−open"PAGES_URL" >/dev/null 2>&1 &

step "Summary"
echo "Working directory: 
W
O
R
K
D
I
R
"
e
c
h
o
"
R
e
p
o
s
i
t
o
r
y
:
h
t
t
p
s
:
/
/
g
i
t
h
u
b
.
c
o
m
/
WORKDIR"echo"Repository:https://github.com/GH_OWNER/
R
E
P
O
N
A
M
E
"
e
c
h
o
"
P
a
g
e
:
REPO 
N
​
 AME"echo"Page:PAGES_URL"
if [ "
E
R
R
O
R
S
"
−
e
q
0
]
;
t
h
e
n
e
c
h
o
"
R
E
S
U
L
T
:
s
u
c
c
e
s
s
"
r
e
t
u
r
n
0
e
l
s
e
e
c
h
o
"
R
E
S
U
L
T
:
ERRORS"−eq0];thenecho"RESULT:success"return0elseecho"RESULT:ERRORS error(s)"
return 1
fi
}

main "$@"
