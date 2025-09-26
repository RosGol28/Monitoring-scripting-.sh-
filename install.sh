#!/usr/bin/env bash
set -euo pipefail


echo "Installing monitor-test..."
# Копирую скрипт
install -d /usr/local/bin
install -m 0755 scripts/monitor_test.sh /usr/local/bin/monitor_test.sh


# Копирую systemd-юниты
install -d /etc/systemd/system
install -m 0644 systemd/monitor-test.service /etc/systemd/system/monitor-test.service
install -m 0644 systemd/monitor-test.timer /etc/systemd/system/monitor-test.timer


# Создаю директории и лог
install -d /var/lib/monitoring_test
touch /var/monitoring.log || true
chown root:root /var/monitoring.log
chmod 0644 /var/monitoring.log


# Перезагружаю systemd и включаю таймер
systemctl daemon-reload
systemctl enable --now monitor-test.timer


echo "Installed. Log: /var/monitoring.log"