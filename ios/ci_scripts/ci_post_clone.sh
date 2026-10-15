#!/bin/sh
# Xcode Cloud post-clone script for Flutter iOS archive.
# It prepares Flutter, refreshes generated iOS plugin files, installs Pods,
# and fails early when the cloud checkout is missing a plugin required by
# GeneratedPluginRegistrant.m.
set -eu

log() {
  echo ">>> ci_post_clone: $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

run_with_retries() {
  label="$1"
  max_attempts="$2"
  shift 2

  attempt=1
  while [ "$attempt" -le "$max_attempts" ]; do
    log "${label}：第 ${attempt}/${max_attempts} 次"
    if "$@"; then
      return 0
    fi

    if [ "$attempt" -eq "$max_attempts" ]; then
      die "${label} 连续失败 ${max_attempts} 次"
    fi

    sleep_seconds=$((attempt * 15))
    log "${label} 失败，${sleep_seconds}s 后重试"
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

find_repo_root() {
  if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] && [ -f "${CI_PRIMARY_REPOSITORY_PATH}/pubspec.yaml" ]; then
    printf '%s\n' "${CI_PRIMARY_REPOSITORY_PATH}"
    return
  fi

  if [ -n "${CI_WORKSPACE:-}" ] && [ -f "${CI_WORKSPACE}/repository/pubspec.yaml" ]; then
    printf '%s\n' "${CI_WORKSPACE}/repository"
    return
  fi

  if [ -n "${CI_WORKSPACE:-}" ] && [ -f "${CI_WORKSPACE}/pubspec.yaml" ]; then
    printf '%s\n' "${CI_WORKSPACE}"
    return
  fi

  if [ -f "pubspec.yaml" ]; then
    pwd
    return
  fi

  die "无法定位 Flutter 仓库根目录"
}

install_flutter_if_needed() {
  FLUTTER_HOME="${HOME}/flutter"
  if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
    log "安装 Flutter SDK 到 ${FLUTTER_HOME}"
    rm -rf "${FLUTTER_HOME}"
    if ! git clone https://github.com/flutter/flutter.git --depth 1 -b stable "${FLUTTER_HOME}"; then
      log "浅克隆失败，改为完整克隆"
      git clone https://github.com/flutter/flutter.git -b stable "${FLUTTER_HOME}"
    fi
  fi
  export PATH="${PATH}:${FLUTTER_HOME}/bin"
}

ensure_cocoapods() {
  if has_command pod; then
    return
  fi

  log "未找到 pod，尝试 brew install cocoapods"
  if ! has_command brew; then
    die "未找到 brew，无法安装 CocoaPods"
  fi
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
}

ensure_plist_gem() {
  log "确保 Ruby gem plist 可用"
  if ruby -rplist -e '' 2>/dev/null; then
    log "plist 已可用"
    return
  fi

  VENDORED_GEM="${ROOT}/ios/ci_scripts/vendor/plist-3.7.2.gem"
  if [ -f "${VENDORED_GEM}" ]; then
    log "从仓库离线安装 plist-3.7.2"
    gem install --local "${VENDORED_GEM}" --user-install --no-document \
      || gem install --local "${VENDORED_GEM}" --no-document
  else
    log "未找到离线 plist gem，尝试 rubygems.org"
    n=0
    ok=0
    while [ "$n" -lt 3 ]; do
      if gem install plist --user-install --no-document 2>/dev/null || gem install plist --no-document 2>/dev/null; then
        ok=1
        break
      fi
      n=$((n + 1))
      log "plist 安装失败，重试 $n/3"
      sleep 4
    done

    if [ "$ok" != 1 ]; then
      log "尝试镜像 gems.ruby-china.com"
      gem install plist --user-install --no-document --clear-sources --source "https://gems.ruby-china.com" \
        || gem install plist --no-document --clear-sources --source "https://gems.ruby-china.com" || true
    fi
  fi

  ruby -rplist -e '' 2>/dev/null || die "plist 仍不可用，fluwx/tobias 的 Pod 脚本会失败"
}

refresh_flutter_ios_config() {
  log "清理 Flutter iOS 生成缓存"
  rm -f .flutter-plugins .flutter-plugins-dependencies
  rm -rf ios/.symlinks
  rm -f ios/Flutter/Generated.xcconfig ios/Flutter/flutter_export_environment.sh

  log "关闭 Flutter Swift Package Manager（本项目使用 CocoaPods）"
  flutter config --no-enable-swift-package-manager

  log "flutter pub get"
  run_with_retries "flutter pub get" 3 flutter pub get

  # pubspec.lock may advance an iOS plugin without updating the checked-in
  # Podfile.lock. Flutter runs CocoaPods as part of --config-only, so refresh
  # the CDN index and discard that stale snapshot before invoking Flutter.
  # This only affects Xcode Cloud's disposable checkout; pod install below
  # recreates a matching lock file.
  log "刷新 CocoaPods 索引并清理过期 Podfile.lock"
  (
    cd ios
    run_with_retries "pod repo update" 3 pod repo update
    rm -f Podfile.lock
  )

  log "flutter build ios --config-only --release"
  run_with_retries "flutter build ios --config-only --release" 4 flutter build ios --config-only --release
}

validate_flutter_ios_plugins() {
  log "校验 Flutter iOS 插件列表"
  python3 - <<'PY'
import json
import re
from pathlib import Path

registrant = Path("ios/Runner/GeneratedPluginRegistrant.m")
plugins_file = Path(".flutter-plugins-dependencies")

if not registrant.exists():
    raise SystemExit("ERROR: ios/Runner/GeneratedPluginRegistrant.m 不存在")
if not plugins_file.exists():
    raise SystemExit("ERROR: .flutter-plugins-dependencies 不存在")

registrant_modules = set(re.findall(r"@import\s+([A-Za-z0-9_]+)\s*;", registrant.read_text()))
data = json.loads(plugins_file.read_text())
dependency_modules = {plugin["name"] for plugin in data.get("plugins", {}).get("ios", [])}

print("GeneratedPluginRegistrant:", ", ".join(sorted(registrant_modules)))
print(".flutter-plugins-dependencies:", ", ".join(sorted(dependency_modules)))

missing = sorted(registrant_modules - dependency_modules)
if missing:
    raise SystemExit("ERROR: registrant 中的插件未进入 Flutter iOS 依赖列表: " + ", ".join(missing))

required = {
    "AMap3DMap",
    "amap_map",
    "agora_rtc_engine",
    "image_picker_ios",
    "iris_method_channel",
    "permission_handler_apple",
    "share_plus",
    "shared_preferences_foundation",
    "url_launcher_ios",
    "video_player_avfoundation",
}
missing_required = sorted(required - dependency_modules - {"AMap3DMap"})
if missing_required:
    raise SystemExit("ERROR: 缺少关键 iOS Flutter 插件: " + ", ".join(missing_required))
PY
}

install_pods() {
  [ -f "${ROOT}/ios/Podfile" ] || die "ios/Podfile 不存在"

  if ! grep -q "pod 'AMap3DMap', '11.1.000'" "${ROOT}/ios/Podfile"; then
    die "Podfile 未锁定 AMap3DMap 11.1.000"
  fi

  log "pod install"
  cd "${ROOT}/ios"
  run_with_retries "pod install" 4 pod install

  log "校验 Pods Manifest"
  python3 - <<'PY'
from pathlib import Path

manifest = Path("Pods/Manifest.lock")
if not manifest.exists():
    raise SystemExit("ERROR: Pods/Manifest.lock 不存在")

text = manifest.read_text()
required = [
    "AMap3DMap",
    "agora_rtc_engine",
    "image_picker_ios",
    "iris_method_channel",
    "share_plus",
    "shared_preferences_foundation",
    "url_launcher_ios",
    "video_player_avfoundation",
]
missing = [name for name in required if name not in text]
if missing:
    raise SystemExit("ERROR: Pod install 后仍缺少 Pods: " + ", ".join(missing))

print("Pods Manifest OK")
PY

  log "校验支付宝回调配置"
  python3 - <<'PY'
import plistlib
from pathlib import Path

with Path("Runner/Info.plist").open("rb") as source:
    info = plistlib.load(source)
# Tobias looks up the URL type by name, not just by scheme.
valid = any(
    entry.get("CFBundleURLName") == "alipay"
    and entry.get("CFBundleURLSchemes", [])[:1] == ["xuanyupay"]
    for entry in info.get("CFBundleURLTypes", [])
)
if not valid:
    raise SystemExit("ERROR: 支付宝回调缺失，应配置 alipay / xuanyupay")
print("Alipay callback configuration OK")
PY
}

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

ROOT="$(find_repo_root)"
log "ROOT=${ROOT}"
cd "${ROOT}"
log "pwd=$(pwd)"

install_flutter_if_needed

log "flutter 版本"
flutter --version

log "flutter precache --ios"
flutter precache --ios

ensure_cocoapods

log "pod 版本"
pod --version

ensure_plist_gem
refresh_flutter_ios_config
validate_flutter_ios_plugins
install_pods

log "完成"
