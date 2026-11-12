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
