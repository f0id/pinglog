#!/bin/bash

# Инициализация переменных по умолчанию
IP_ADDRESS=""
CLEAR_LOGS=false
NO_LOG=false
LOG_FILE="log.txt"
HIGH_THRESHOLD=100  # Порог высокого времени отклика в мс

# Функция вывода справки
show_help() {
    echo "Usage: $0 [IP address] [options]"
    echo ""
    echo "Options:"
    echo "  -c, --clear              Clear previous log before starting"
    echo "  --no-log                 Disable logging (console output only)"
    echo "  -w <filename>            Set custom log file (default: log.txt)"
    echo "  --high <ms>              Set high response time threshold in ms (default: 100)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 8.8.8.8"
    echo "  $0 8.8.8.8 -c"
    echo "  $0 8.8.8.8 -w my_log.txt"
    echo "  $0 8.8.8.8 --high 50"
    echo "  $0 8.8.8.8 --no-log"
    echo "  $0 -c 8.8.8.8 -w my_log.txt --high 150"
    exit 0
}

# Обработка аргументов в любом порядке
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--clear)
            CLEAR_LOGS=true
            shift
            ;;
        --no-log)
            NO_LOG=true
            shift
            ;;
        -w)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -w requires a filename argument"
                exit 1
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        --high)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: --high requires a value in milliseconds"
                exit 1
            fi
            HIGH_THRESHOLD="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            if [ -z "$IP_ADDRESS" ]; then
                IP_ADDRESS="$1"
            else
                echo "Error: Multiple IP addresses specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# Проверка наличия IP адреса
if [ -z "$IP_ADDRESS" ]; then
    echo "Error: IP address is required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Очистка лога, если указан флаг (только если логирование включено)
if [ "$CLEAR_LOGS" = true ] && [ "$NO_LOG" = false ]; then
    > "$LOG_FILE"
    echo "Previous log cleared"
fi

# Вывод информации о запуске
echo "========================================"
echo "Ping Logger Started"
echo "Target IP: $IP_ADDRESS"
echo "High response time threshold: ${HIGH_THRESHOLD}ms"
if [ "$NO_LOG" = true ]; then
    echo "Logging: DISABLED (console output only)"
else
    echo "Logging: ENABLED"
    echo "Log file: $LOG_FILE"
    if [ "$CLEAR_LOGS" = true ]; then
        echo "Log cleared on start"
    else
        echo "Appending to existing log"
    fi
fi
echo "========================================"
echo "Press Ctrl+C to stop"
echo ""

# Функция для логирования
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] $message"
    
    # Вывод в консоль
    echo "$log_entry"
    
    # Запись в файл, если логирование включено
    if [ "$NO_LOG" = false ]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

# Запуск непрерывного ping
# Используем -O для вывода сообщений о таймаутах (если поддерживается)
ping -O -i 1 "$IP_ADDRESS" 2>&1 | while IFS= read -r line; do
    # Проверяем на ошибки (таймаут, недоступность и т.д.)
    if echo "$line" | grep -q "no answer yet\|Request timeout\|Destination Host Unreachable\|Network is unreachable\|Host is unreachable\|No route to host\|Name or service not known"; then
        # Извлекаем номер последовательности
        SEQ=$(echo "$line" | grep -o "icmp_seq=[0-9]*" | cut -d'=' -f2)
        if [ -z "$SEQ" ]; then
            SEQ="?"
        fi
        log_message "ERROR: ICMP_SEQ=$SEQ - Timeout/Network error"
    
    # Успешный ответ
    elif echo "$line" | grep -q "icmp_seq="; then
        SEQ=$(echo "$line" | grep -o "icmp_seq=[0-9]*" | cut -d'=' -f2)
        TIME=$(echo "$line" | grep -o "time=[0-9.]* ms" | cut -d'=' -f2)
        
        if [ -z "$TIME" ]; then
            TIME="<1"
        else
            # Убираем " ms" для числового сравнения
            TIME_NUM=$(echo "$TIME" | sed 's/ ms//')
        fi
        
        # Проверяем, превышает ли время отклика порог
        if [ -n "$TIME_NUM" ] && [ "$(echo "$TIME_NUM > $HIGH_THRESHOLD" | bc -l)" -eq 1 ]; then
            log_message "ERROR: ICMP_SEQ=$SEQ TIME=${TIME}ms (HIGH LATENCY > ${HIGH_THRESHOLD}ms)"
        else
            log_message "ICMP_SEQ=$SEQ TIME=${TIME}ms"
        fi
    
    # Другие сообщения (статистика) - пропускаем
    else
        # Пропускаем пустые строки и строки со статистикой
        if [ -n "$line" ] && ! echo "$line" | grep -q "packets transmitted\|round-trip\|---"; then
            log_message "INFO: $line"
        fi
    fi
done
