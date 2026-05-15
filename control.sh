#!/bin/bash
# EveBox 控制脚本 (Git Bash / MSYS2)
# 委托给 Windows .bat 文件处理进程管理
# 用法: ./control.sh start|stop|restart|status

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

show_status() {
    banner "EveBox 系统状态"
    echo ""

    # Elasticsearch
    echo -n "  Elasticsearch : "
    if curl -s --connect-timeout 2 "http://localhost:9200" >/dev/null 2>&1; then
        local ver=$(curl -s "http://localhost:9200" 2>/dev/null | python -c "import sys,json;print(json.load(sys.stdin)['version']['number'])" 2>/dev/null || echo "?")
        local docs=$(curl -s "http://localhost:9200/_cat/count/evebox*?format=json" 2>/dev/null | python -c "import sys,json;print(json.load(sys.stdin)[0]['count'])" 2>/dev/null || echo "?")
        echo -e "${GREEN}运行中 (ES $ver, $docs docs)${NC}"
    else
        echo -e "${RED}未运行${NC}"
    fi

    # EveBox - scan ports
    echo -n "  EveBox        : "
    local found=0
    for port in 5636 15636 15637 15638 5637 5638 5639; do
        local config=$(curl -s --connect-timeout 2 "http://127.0.0.1:$port/api/config" 2>/dev/null)
        if [ -n "$config" ]; then
            local ds=$(echo "$config" | python -c "import sys,json;print(json.load(sys.stdin)['datastore'])" 2>/dev/null)
            if [ "$ds" = "elasticsearch" ]; then
                echo -e "${GREEN}运行中 (端口 $port, $ds)${NC}"
                found=1
                break
            fi
        fi
    done
    [ $found -eq 0 ] && echo -e "${RED}未运行${NC}"

    # Suricata data
    echo -n "  Suricata 数据   : "
    local out="data/suricata-eve.json"
    if [ -f "$out" ]; then
        local count=$(wc -l < "$out" 2>/dev/null | tr -d ' ')
        local size=$(du -h "$out" 2>/dev/null | cut -f1)
        echo -e "${GREEN}$count 条事件 ($size)${NC}"
    else
        echo -e "${RED}数据文件不存在${NC}"
    fi

    # Simulator running?
    echo -n "  Suricata 模拟器 : "
    local sim_pid=$(C:/Windows/System32/tasklist.exe 2>/dev/null | grep -i "python" | wc -l)
    if [ "$sim_pid" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}运行中 ($sim_pid python 进程)${NC}"
    else
        echo -e "${YELLOW}未运行${NC}"
    fi

    echo ""
    echo "  ${CYAN}控制命令:${NC}"
    echo "    ./control.sh start    一键启动"
    echo "    ./control.sh stop     一键停止"
    echo "    start-all.bat         Windows 一键启动"
    echo "    stop-all.bat          Windows 一键停止"
    echo ""
}

case "${1:-}" in
    start)
        banner "EveBox 一键启动"
        echo ""
        echo "  程序将在新的 Windows 终端窗口中启动"
        echo "  (Elasticsearch / Suricata模拟器 / EveBox)"
        echo ""
        # Use Windows batch file
        C:/Windows/System32/cmd.exe //c "start \"EveBox-Launcher\" /min \"$ROOT\\start-all.bat\"" 2>/dev/null &
        echo -e "${GREEN}  已触发启动，请查看弹出的终端窗口${NC}"
        echo ""
        ;;
    stop)
        banner "EveBox 一键停止"
        C:/Windows/System32/cmd.exe //c "cd /d \"$ROOT\" && call stop-all.bat" 2>/dev/null
        sleep 3
        show_status
        ;;
    restart)
        "$0" stop
        sleep 5
        "$0" start
        ;;
    status|"")
        show_status
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
