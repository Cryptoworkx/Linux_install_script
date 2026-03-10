#!/usr/bin/env bash
set -euo pipefail

log(){  echo -e "\033[1;36m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err(){  echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

# ── Vorbedingungen ───────────────────────────────────────────────────────────────
if [[ -z "${DISPLAY:-}" ]]; then
  err "Bitte IM laufenden XFCE-Desktop starten (kein TTY/SSH)."
  exit 1
fi
if [[ "${EUID}" -eq 0 ]]; then
  err "Nicht als root starten. Das Script nutzt sudo nur für Systempfade."
  exit 1
fi

THEMES_SRC="/opt/kali-themes/share/themes"
THEMES_DST="/usr/share/themes"

# ── Pakete ───────────────────────────────────────────────────────────────────────
log "Pakete installieren/aktualisieren…"
sudo apt update
sudo apt install -y \
  xfce4-panel xfconf xfce4-settings \
  xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin xfce4-indicator-plugin \
  plank git curl wget gtk2-engines-murrine

# ── Theme anwenden (aus /opt/kali-themes) ───────────────────────────────────────
PREFS=( "Kali-Purple-Dark" "Kali-Slate-Dark" "Kali-Red-Dark" "Kali-Teal-Dark" "Kali-Yellow-Dark" "Kali-Pink-Dark" )
KALI_THEME=""
if [[ -d "$THEMES_SRC" ]]; then
  for t in "${PREFS[@]}"; do
    if [[ -d "$THEMES_SRC/$t" ]]; then KALI_THEME="$t"; break; fi
  done
fi
if [[ -z "$KALI_THEME" ]]; then
  err "Kein Theme in $THEMES_SRC gefunden (ist /opt/kali-themes korrekt geklont?)."
  exit 1
fi

log "Verwende Theme: $KALI_THEME"
sudo rm -rf "$THEMES_DST/$KALI_THEME" || true
sudo mkdir -p "$THEMES_DST"
sudo cp -a "$THEMES_SRC/$KALI_THEME" "$THEMES_DST/"
xfconf-query -c xsettings -p /Net/ThemeName -s "$KALI_THEME" --create -t string
xfconf-query -c xfwm4    -p /general/theme  -s "$KALI_THEME" --create -t string
log "Theme installiert & aktiviert."

# ── OFFIZIELLE Kali-Wallpapers laden → entpacken (Fallback) ─────────────────────
tmp_wall="$(mktemp -d)"
trap 'rm -rf "$tmp_wall"' EXIT
cd "$tmp_wall"
YEARS=(2026 2025 2024 2023)
GOT=""
for Y in "${YEARS[@]}"; do
  URL="https://http.kali.org/pool/main/k/kali-wallpapers/kali-wallpapers-${Y}_${Y}.1.0_all.deb"
  if wget -q --spider "$URL"; then
    log "Lade Kali-Wallpapers ${Y}…"
    wget -q -O "kali-wallpapers-${Y}.deb" "$URL" || true
    GOT="kali-wallpapers-${Y}.deb"
    break
  fi
done

if [[ -n "$GOT" && -s "$GOT" ]]; then
  log "Entpacke Wallpaper-Paket…"
  dpkg-deb -x "$GOT" . || true
  sudo mkdir -p /usr/share/backgrounds/kali
  # mögliche Pfade im .deb abdecken
  sudo cp -a usr/share/backgrounds/kali/. /usr/share/backgrounds/kali/ 2>/dev/null || true
  sudo cp -a usr/share/wallpapers/Kali/contents/images/. /usr/share/backgrounds/kali/ 2>/dev/null || true
  sudo cp -a usr/share/wallpapers/. /usr/share/backgrounds/kali/ 2>/dev/null || true
else
  warn "Kein Wallpaper-Paket erreichbar – Schritt übersprungen."
fi

# ── Spezifisches Wallpaper laden & priorisiert setzen ───────────────────────────
SPEC_URL="https://www.kali.org/wallpapers/images/2025/kali-tiles.jpg"
SPEC_DST_DIR="/usr/share/backgrounds/kali"
SPEC_FILE="${SPEC_DST_DIR}/kali-tiles.jpg"

log "Lade spezifisches Kali-Wallpaper: ${SPEC_URL}"
sudo mkdir -p "${SPEC_DST_DIR}"
if command -v wget >/dev/null 2>&1; then
  wget -q -O "/tmp/kali-tiles.jpg" "${SPEC_URL}" || true
else
  curl -fsSL -o "/tmp/kali-tiles.jpg" "${SPEC_URL}" || true
fi

if [[ -s "/tmp/kali-tiles.jpg" ]]; then
  sudo mv -f "/tmp/kali-tiles.jpg" "${SPEC_FILE}"
  sudo chmod 644 "${SPEC_FILE}"
  WALL="${SPEC_FILE}"
  log "Spezifisches Wallpaper gespeichert: ${WALL}"
else
  warn "Download des spezifischen Wallpapers fehlgeschlagen – nutze Fallback (erstes gefundenes Bild)."
  WALL="$(ls ${SPEC_DST_DIR}/*.{png,jpg,jpeg} 2>/dev/null | head -n 1 || true)"
fi

# ── Wallpaper auf allen Monitoren SICHER setzen ─────────────────────────────────
if [[ -n "${WALL:-}" && -f "$WALL" ]]; then
  log "Setze Wallpaper: $WALL"

  # vorhandene Keys ermitteln
  mapfile -t W_KEYS < <(xfconf-query -c xfce4-desktop -l | grep -E '/backdrop/.*image-path$' || true)

  # Falls XFCE noch keine Keys hat → eine generische Matrix erzeugen
  if [[ ${#W_KEYS[@]} -eq 0 ]]; then
    log "Keine Wallpaper-Keys gefunden – generiere Standard-Keys…"
    for S in {0..2}; do
      for M in {0..3}; do
        W_KEYS+=("/backdrop/screen${S}/monitor${M}/image-path")
      done
    done
  fi

  # Alle relevanten Werte setzen (inkl. last-image)
  for KEY in "${W_KEYS[@]}"; do
    base="${KEY%image-path}"
    xfconf-query -c xfce4-desktop -p "$KEY"                 -s "$WALL" --create -t string || true
    xfconf-query -c xfce4-desktop -p "${base}image-show"    -s true    --create -t bool   || true
    xfconf-query -c xfce4-desktop -p "${base}image-style"   -s 3       --create -t int    || true  # 3 = skaliert
    xfconf-query -c xfce4-desktop -p "${base}last-image"    -s "$WALL" --create -t string || true
  done

  # xfdesktop neu starten, damit das Bild sofort sichtbar wird
  pkill -f xfdesktop || true
  setsid -f xfdesktop >/dev/null 2>&1 &
  log "Wallpaper installiert & gesetzt."
else
  err "Wallpaper konnte nicht gesetzt werden – Datei nicht gefunden: ${WALL:-<leer>}."
fi

# ── Panels nach oben (ohne /panels-Array zu überschreiben) ──────────────────────
log "Bringe alle vorhandenen Panels nach oben…"
panel_ids="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)"
if [[ -z "${panel_ids// }" ]]; then
  panel_ids="$(xfconf-query -c xfce4-panel -lv | awk -F'[/-]' '/^\/panels\/panel-[0-9]+\/size/{print $4}' | sort -u || true)"
fi

if [[ -z "${panel_ids// }" ]]; then
  warn "Keine Panel-IDs gefunden. Starte Panel neu."
else
  for id in $panel_ids; do
    log "Panel-$id → oben, 100% Breite, 28px"
    xfconf-query -c xfce4-panel -p "/panels/panel-${id}/position"         -s "p=10;x=0;y=0" --create -t string || true
    xfconf-query -c xfce4-panel -p "/panels/panel-${id}/length"           -s 100            --create -t int    || true
    xfconf-query -c xfce4-panel -p "/panels/panel-${id}/size"             -s 28             --create -t int    || true
    xfconf-query -c xfce4-panel -p "/panels/panel-${id}/position-locked"  -s true           --create -t bool   || true
    xfconf-query -c xfce4-panel -p "/panels/panel-${id}/disable-struts"   -s false          --create -t bool   || true
  done
fi
xfce4-panel -q || true
setsid -f xfce4-panel >/dev/null 2>&1 &
sleep 1

# ── Plank Dock in Autostart ─────────────────────────────────────────────────────
mkdir -p "${HOME}/.config/autostart"
cat > "${HOME}/.config/autostart/plank.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Exec=plank
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Plank
Comment=Dock starten
EOF

log "FERTIG! Panel oben, Theme aktiv, spezifisches Kali-Wallpaper geladen & angewendet."