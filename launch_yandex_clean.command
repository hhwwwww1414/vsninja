#!/bin/bash
# Install and start the exact Yandex app from the DMG in Downloads.
# This script uses a separate folder and does not inspect or change other apps.
set -Eeuo pipefail

DMG="$HOME/Downloads/Yandex_with_voice_assistant_Alice-aarch64.dmg"
APP_NAME="Yandex with voice assistant Alice.app"
BASE="$HOME/Applications/RDGen-Yandex"
DEST="$BASE/$APP_NAME"
LOG="$HOME/Downloads/yandex_launch_debug.log"
WORK="$(mktemp -d "${TMPDIR:-/tmp/}yandex-launch.XXXXXX")"
MOUNT="$WORK/mount"
ATTACHED=0

cleanup() {
  if [ "$ATTACHED" -eq 1 ]; then
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$MOUNT" "$BASE"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

fail() {
  printf 'Ошибка: %s\n' "$1"
  printf 'Журнал установки: %s\n' "$LOG"
  exit 1
}

printf '\n=== Установка и запуск Yandex ===\n'
[ -f "$DMG" ] || fail 'Файл Yandex_with_voice_assistant_Alice-aarch64.dmg не найден в Загрузках.'

printf '[1/5] Подключаю установочный диск...\n'
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" "$DMG" -quiet >/dev/null 2>&1 \
  || fail 'Не удалось подключить установочный диск.'
ATTACHED=1

printf '[2/5] Проверяю приложение...\n'
SOURCE="$(find "$MOUNT" -maxdepth 3 -type d -name "$APP_NAME" -print -quit)"
[ -n "$SOURCE" ] || fail 'Внутри диска не найдено ожидаемое приложение.'
PLIST="$SOURCE/Contents/Info.plist"
[ -f "$PLIST" ] || fail 'У приложения отсутствует файл настроек.'
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || true)"
[ -n "$EXECUTABLE" ] || fail 'Не удалось определить исполняемый файл.'
[ -f "$SOURCE/Contents/MacOS/$EXECUTABLE" ] || fail 'Исполняемый файл не найден.'
[ -f "$SOURCE/Contents/MacOS/custom_.txt" ] || fail 'В сборке отсутствует файл кастомной конфигурации.'
printf 'Приложение найдено, конфигурация на месте.\n'

printf '[3/5] Обновляю отдельную копию при необходимости...\n'
HASH="$(shasum -a 256 "$DMG" | awk '{print $1}')"
STAMP="$BASE/.installed_dmg_sha256"
OLD_HASH="$(cat "$STAMP" 2>/dev/null || true)"
if [ ! -d "$DEST" ] || [ "$HASH" != "$OLD_HASH" ]; then
  STAGE="$(mktemp -d "$BASE/.stage.XXXXXX")"
  ditto "$SOURCE" "$STAGE/$APP_NAME" >/dev/null 2>&1 || fail 'Не удалось скопировать приложение.'
  HAD_OLD=0
  if [ -d "$DEST" ]; then
    mv "$DEST" "$WORK/old-yandex.app" || fail 'Не удалось подготовить обновление.'
    HAD_OLD=1
  fi
  if ! mv "$STAGE/$APP_NAME" "$DEST"; then
    if [ "$HAD_OLD" -eq 1 ]; then
      mv "$WORK/old-yandex.app" "$DEST" || true
    fi
    fail 'Не удалось установить новую копию.'
  fi
  rmdir "$STAGE" >/dev/null 2>&1 || true
  printf '%s\n' "$HASH" > "$STAMP"
  printf 'Копия установлена. Исходное название сохранено.\n'
else
  printf 'Актуальная копия уже установлена.\n'
fi

printf '[4/5] Подготавливаю запуск...\n'
BIN="$DEST/Contents/MacOS/$EXECUTABLE"
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
chmod u+x "$BIN" >/dev/null 2>&1 || fail 'Не удалось установить права на запуск.'
if codesign --verify --deep --strict "$DEST" >/dev/null 2>&1; then
  printf 'Проверка подписи пройдена.\n'
else
  printf 'Предупреждение: проверка подписи не пройдена.\n'
fi

printf '[5/5] Запускаю Yandex...\n'
if open -n -a "$DEST" >/dev/null 2>&1; then
  sleep 4
  if pgrep -f "$BIN" >/dev/null 2>&1; then
    printf 'Yandex запущен.\n'
  else
    printf 'Проверяю альтернативный способ запуска...\n'
    (cd "$DEST/Contents/MacOS" && nohup "./$EXECUTABLE" >/dev/null 2>&1 < /dev/null &)
    sleep 3
    if pgrep -f "$BIN" >/dev/null 2>&1; then
      printf 'Yandex запущен.\n'
    else
      printf 'Не удалось подтвердить запуск. Возможно, в сборке есть ошибка.\n'
    fi
  fi
else
  printf 'Система не разрешила запуск приложения.\n'
fi
printf 'Журнал запуска: %s\n' "$LOG"
