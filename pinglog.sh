#!/bin/bash

# Инициализация переменных по умолчанию
IP_ADDRESS=""
CLEAR_LOGS=false
NO_LOG=false
PING_LOG="ping_log.txt"
ERROR_LOG="error_log.txt"
TIMEOUT=1  # Таймаут в секундах

# Функция вывода справки
show_help() {
    echo "Usage: $0 [IP address] [options]"
    echo ""
    echo "Options:"
    echo "  -c, --clear              Clear previous logs before starting"
    echo "  --no-log                 Disable logging (console output only)"
    echo "  -l <filename>            Set custom log file for successful pings"
    echo "  -e <filename>            Set custom error log file"
    echo "  -t <seconds>             Set timeout for each ping (default: 1)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 8.8.8.8"
    echo "  $0 8.8.8.8 -c"
    echo "  $0 8.8.8.8 -l my_pings.txt -e my_errors.txt"
    echo "  $0 8.8.8.8 --no-log"
    echo "  $0 8.8.8.8 -t 2"
    echo "  $0 -c 8.8.8.8 -l pings.txt"
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
        -l)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -l requires a filename argument"
                exit 1
            fi
            PING_LOG="$2"
            shift 2
            ;;
        -e)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -e requires a filename argument"
                exit 1
            fi
            ERROR_LOG="$2"
            shift 2
            ;;
        -t)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -t requires a timeout value"
                exit 1
            fi
            TIMEOUT="$2"
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

# Очистка логов, если указан флаг (только если логирование включено)
if [ "$CLEAR_LOGS" = true ] && [ "$NO_LOG" = false ]; then
    > "$PING_LOG"
    > "$ERROR_LOG"
    echo "Previous logs cleared"
fi

# Вывод информации о запуске
echo "========================================"
echo "Ping Logger Started"
echo "Target IP: $IP_ADDRESS"
echo "Timeout: ${TIMEOUT}s per ping"
if [ "$NO_LOG" = true ]; then
    echo "Logging: DISABLED (console output only)"
else
    echo "Logging: ENABLED"
    echo "Success log: $PING_LOG"
    echo "Error log: $ERROR_LOG"
    if [ "$CLEAR_LOGS" = true ]; then
        echo "Logs cleared on start"
    else
        echo "Appending to existing logs"
    fi
fi
echo "========================================"
echo "Press Ctrl+C to stop"
echo ""

# Функция для логирования
log_message() {
    local type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] $message"
    
    # Вывод в консоль
    echo "$log_entry"
    
    # Запись в файл, если логирование включено
    if [ "$NO_LOG" = false ]; then
        if [ "$type" = "success" ]; then
            echo "$log_entry" >> "$PING_LOG"
        else
            echo "$log_entry" >> "$ERROR_LOG"
        fi
    fi
}

# Запуск непрерывного ping
# -O опция: выводить сообщение при отсутствии ответа (поддерживается не везде)
# Используем timeout для каждого пакета, но сохраняем непрерывную сессию
ping -O -i 1 -W "$TIMEOUT" "$IP_ADDRESS" 2>&1 | while IFS= read -r line; do
    # Если строка содержит "no answer yet" или "Request timeout" - это ошибка
    if echo "$line" | grep -q "no answer yet\|Request timeout\|Destination Host Unreachable\|Network is unreachable"; then
        # Извлекаем номер последовательности
        SEQ=$(echo "$line" | grep -o "icmp_seq=[0-9]*" | cut -d'=' -f2)
        if [ -z "$SEQ" ]; then
            SEQ="?"
        fi
        log_message "error" "ERROR: ICMP_SEQ=$SEQ - Timeout (no response)"
    
    # Успешный ответ
    elif echo "$line" | grep -q "icmp_seq="; then
        SEQ=$(echo "$line" | grep -o "icmp_seq=[0-9]*" | cut -d'=' -f2)
        TIME=$(echo "$line" | grep -o "time=[0-9.]* ms" | cut -d'=' -f2)
        if [ -z "$TIME" ]; then
            TIME="<1 ms"
        fi
        log_message "success" "ICMP_SEQ=$SEQ TIME=$TIME"
    
    # Другие сообщения (статистика, предупреждения) - логируем как ошибки
    else
        # Пропускаем пустые строки и строки со статистикой
        if [ -n "$line" ] && ! echo "$line" | grep -q "packets transmitted\|round-trip"; then
            log_message "error" "OTHER: $line"
        fi
    fi
done
