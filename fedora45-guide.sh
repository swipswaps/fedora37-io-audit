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
