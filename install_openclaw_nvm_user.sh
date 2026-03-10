#!/usr/bin/env bash
# install_openclaw_nvm_user.sh
# Xubuntu/Ubuntu (22.04/24.04) – User-Space-Installation mit nvm (kein sudo)

set -euo pipefail

### ---------------------------
### Konfiguration (anpassbar)
### ---------------------------
INSTALL_NVM_VERSION="${INSTALL_NVM_VERSION:-v0.39.7}"  # stabile nvm-Version
NODE_MAJOR="${NODE_MAJOR:-22}"                          # OpenClaw verlangt Node >=22
RUN_ONBOARD="${RUN_ONBOARD:-yes}"                      # 'yes' -> openclaw onboard starten
CREATE_USER_SYSTEMD="${CREATE_USER_SYSTEMD:-no}"       # 'yes' -> systemd --user Dienst anlegen
PRESEED_ENV_PATH="${PRESEED_ENV_PATH:-}"               # optionaler Pfad zu .env-Preseed (Telegram/Discord)

### ---------------------------
### Helper
### ---------------------------
log(){ printf "\n\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\n\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){ printf "\n\033[1;31m[x] %s\033[0m\n" "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || return 1; }

### ---------------------------
### Vorbereitungen
### ---------------------------
log "Pakete aktualisieren (nur user-space Tools benötigt)…"
# Optional: Basis-Tools für Komfort (kein sudo -> nur falls vorhanden überspringen)
if need apt; then
  warn "Apt-Updates werden ohne sudo übersprungen. Stelle sicher, dass curl/git vorhanden sind."
fi

# curl / git prüfen
need curl || { err "curl fehlt. Bitte 'sudo apt install curl' ausführen und Script erneut starten."; exit 1; }
need git  || { err "git fehlt.  Bitte 'sudo apt install git'  ausführen und Script erneut starten."; exit 1; }

### ---------------------------
### nvm installieren
### ---------------------------
if [ -z "${NVM_DIR:-}" ]; then
  export NVM_DIR="$HOME/.nvm"
fi

if [ ! -d "$NVM_DIR" ]; then
  log "Installiere nvm (${INSTALL_NVM_VERSION}) im Benutzerkonto…"
  # Offizielles nvm-Installscript
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${INSTALL_NVM_VERSION}/install.sh" | bash
else
  log "nvm ist bereits vorhanden: $NVM_DIR"
fi

# Shell-Umgebung laden (für bash/zsh)
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
else
  err "nvm.sh nicht gefunden unter $NVM_DIR. Abbruch."
  exit 1
fi

### ---------------------------
### Node.js 22 installieren & aktivieren
### ---------------------------
log "Installiere Node.js ${NODE_MAJOR} (nvm) und setze als default…"
nvm install "${NODE_MAJOR}"
nvm alias default "${NODE_MAJOR}"
nvm use default

log "Node-Version:"
node --version   # Erwartung: v22.x
npm --version

# Hinweis: OpenClaw verlangt Node 22+ (siehe Doku) 
# Quelle: Linux/NVM-Guide & Install-Doku
# (Zitate s. Antworttext/Citations)

### ---------------------------
### OpenClaw im User-Space installieren
### ---------------------------
log "Installiere OpenClaw-CLI im User-Kontext (npm)…"
npm install -g openclaw@latest

log "OpenClaw-Version & Diagnose:"
openclaw --version || true
openclaw doctor || true

### ---------------------------
### Optional: .env Preseed (Telegram/Discord Tokens)
### ---------------------------
if [ -n "$PRESEED_ENV_PATH" ] && [ -f "$PRESEED_ENV_PATH" ]; then
  log "Übernehme Preseed .env nach ~/.openclaw/…"
  mkdir -p "$HOME/.openclaw"
  cp -f "$PRESEED_ENV_PATH" "$HOME/.openclaw/.env"
  # Achtung: WhatsApp kann NICHT automatisiert werden (QR-Login erforderlich).
  # Telegram/Discord Tokens können vorab hinterlegt werden.
fi

### ---------------------------
### Onboarding starten (interaktiv)
### ---------------------------
if [ "$RUN_ONBOARD" = "yes" ]; then
  log "Starte Onboarding (Telegram/WhatsApp/Discord verbinden)…"
  echo
  echo "Hinweise:"
  echo " - WhatsApp: QR-Code-Scan erforderlich (nicht automatisierbar)."
  echo " - Telegram: Bot-Token von @BotFather eingeben."
  echo " - Discord : Bot-Token eingeben & Bot dem Server hinzufügen."
  echo
  read -r -p "Weiter mit ENTER…" _
  openclaw onboard
else
  warn "Onboarding übersprungen (RUN_ONBOARD=no). Später ausführbar mit: openclaw onboard"
fi

### ---------------------------
### Optional: systemd --user Dienst (Autostart nach Login)
### ---------------------------
if [ "$CREATE_USER_SYSTEMD" = "yes" ]; then
  log "Erzeuge systemd --user Dienst für OpenClaw (Autostart nach Login)…"
  SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_USER_DIR/openclaw-gateway.service" <<'EOF'
[Unit]
Description=OpenClaw Gateway (user)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=OPENCLAW_HOME=%h/.openclaw
# Start ohne Browser-Popup; CLI 'openclaw dashboard' öffnet UI bei Bedarf
ExecStart=/usr/bin/env bash -lc 'openclaw start --no-browser'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now openclaw-gateway.service

  log "Dienststatus (user):"
  systemctl --user --no-pager --full status openclaw-gateway.service || true

  echo
  echo "Nützliche Befehle:"
  echo "  systemctl --user restart openclaw-gateway.service"
  echo "  journalctl --user -u openclaw-gateway.service -f"
  echo "  openclaw status | openclaw dashboard | openclaw logs --follow"
fi

log "Fertig. Viel Erfolg mit OpenClaw!"