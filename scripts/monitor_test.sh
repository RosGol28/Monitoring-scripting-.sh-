set -u

# Конфигурация
PROCESS_NAME="test"
MONITOR_URL="https://test.com/monitoring/test/api"
LOG_FILE="/var/monitoring.log"
STATE_DIR="/var/lib/monitoring_test"
STATE_FILE="$STATE_DIR/last_pids"
TMP_LOCK="/var/lock/monitor_test.lock"
CURL_TIMEOUT=10

mkdir -p "$STATE_DIR"
# Проверяю, что лог и каталоги имеют верные права (для первого запуска)
if [ ! -e "$LOG_FILE" ]; then
  touch "$LOG_FILE" || true
fi

# Делаю блокировку, чтобы избежать параллельных запусков
exec 9>"$TMP_LOCK" || exit 0
if ! flock -n 9; then
  # Если скрипт уже запущен
  exit 0
fi

timestamp() {
  date --iso-8601=seconds
}

log() {
  echo "[$(timestamp)] $*" >> "$LOG_FILE"
}

# Получаю список PID процесса
# pgrep -x возвращает код 1 если ничего не найдено
if pids=$(pgrep -x "$PROCESS_NAME" 2>/dev/null | sort -n | tr '\n' ',' | sed 's/,$//'); then
  if [ -z "$pids" ]; then
    # pgrep может вернуть пустую строку, это значит, что процесса нет
    process_running=false
  else
    process_running=true
  fi
else
  process_running=false
fi

if [ "$process_running" = true ]; then
  # Смотрю предыдущее состояние
  if [ -f "$STATE_FILE" ]; then
    old_pids=$(cat "$STATE_FILE" 2>/dev/null || true)
  else
    old_pids=""
  fi

  # Если PID изменились , считаем, что процесс перезапущен
  if [ "$old_pids" != "$pids" ]; then
    # Записываю в лог про перезапуск
    if [ -n "$old_pids" ]; then
      log "Process '$PROCESS_NAME' restarted: old_pids=$old_pids new_pids=$pids"
    else
      # Первый найденный запуск после отсутствия состояния считаю стартом
      log "Process '$PROCESS_NAME' started: pids=$pids"
    fi
  fi

  # Сохраняю текущее состояние
  echo "$pids" > "$STATE_FILE"

  # Делаю HTTPS запрос
  # Использую curl, ждем не более CURL_TIMEOUT
  # Получаем код ответа и статус curl
  http_code=""
  curl_output=$(curl -sS -m "$CURL_TIMEOUT" -w "%{http_code}" -o /dev/null "$MONITOR_URL" 2>&1) || curl_status=$?
  # Если curl вернул код, в curl_output будет либо пусто, либо текст ошибки
  if [ -z "${curl_status+x}" ]; then
    # curl завершился успешно
    http_code="$curl_output"
    # treat 2xx as OK
    case "$http_code" in
      2??)
        # OK — ничего не логируем
        :
        ;;
      *)
        log "Monitoring server returned HTTP $http_code for $MONITOR_URL"
        ;;
    esac
  else
    # curl не смог достучаться
    log "Monitoring server unreachable for $MONITOR_URL: curl exit=$curl_status output='${curl_output//"/\"'}'"
  fi

else
  # Процесс не запущен — значит ничего не логируем ( условие тестового)
  # Также удалю состояние, чтобы при следующем старте мы смогли зафиксировать старт
  if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE" || true
  fi
fi

# Release lock (file descriptor 9 будет закрыт при выходе)
exit 0
