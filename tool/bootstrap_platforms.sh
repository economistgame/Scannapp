#!/usr/bin/env bash
# Genera android/ e ios/ si faltan y aplica los ajustes que necesita la app
# (permiso de cámara, mailto para email, versiones mínimas).
# Es idempotente: se puede ejecutar varias veces.
set -euo pipefail

if [ ! -d android ] || [ ! -d ios ]; then
  # flutter create puede pisar lib/ y pubspec.yaml: los protegemos.
  tmp="$(mktemp -d)"
  cp -r lib "$tmp/lib"
  cp pubspec.yaml "$tmp/pubspec.yaml"
  flutter create . --org com.scannapp --project-name caja_scanner --platforms=android,ios
  rm -rf lib && cp -r "$tmp/lib" lib
  cp "$tmp/pubspec.yaml" pubspec.yaml
  rm -rf test   # el test de plantilla referencia MyApp, que no existe aquí
fi

python3 - <<'PY'
import plistlib, re, pathlib

# ---- Android: permiso de cámara + consulta mailto -------------------------
mf = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = mf.read_text()
if "android.permission.CAMERA" not in s:
    s = s.replace("<application",
        '<uses-permission android:name="android.permission.CAMERA"/>\n    <application', 1)
if 'android:scheme="mailto"' not in s:
    q = ('<queries>\n        <intent>\n'
         '            <action android:name="android.intent.action.SENDTO"/>\n'
         '            <data android:scheme="mailto"/>\n'
         '        </intent>\n    </queries>\n    ')
    # <queries> debe ir dentro de <manifest>, antes de <application>
    s = s.replace("<application", q + "<application", 1)
mf.write_text(s)

# ---- Android: minSdk 23 (mobile_scanner) ----------------------------------
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    p = pathlib.Path(name)
    if p.exists():
        t = p.read_text()
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", t)
        p.write_text(t)

# ---- iOS: Info.plist -------------------------------------------------------
ip = pathlib.Path("ios/Runner/Info.plist")
with ip.open("rb") as f:
    d = plistlib.load(f)
d["NSCameraUsageDescription"] = "Se usa la cámara para escanear códigos de barras."
d["LSApplicationQueriesSchemes"] = ["mailto"]
with ip.open("wb") as f:
    plistlib.dump(d, f)

# ---- iOS: versión mínima 15.5 (ML Kit) ------------------------------------
pod = pathlib.Path("ios/Podfile")
if pod.exists():
    t = pod.read_text()
    if re.search(r"^\s*#?\s*platform :ios,", t, re.M):
        t = re.sub(r"^\s*#?\s*platform :ios,.*$", "platform :ios, '15.5'", t, count=1, flags=re.M)
    else:
        t = "platform :ios, '15.5'\n" + t
    pod.write_text(t)
proj = pathlib.Path("ios/Runner.xcodeproj/project.pbxproj")
if proj.exists():
    t = proj.read_text()
    t = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", t)
    proj.write_text(t)
PY
echo "Plataformas listas."
