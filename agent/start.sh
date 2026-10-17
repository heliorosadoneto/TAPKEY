#!/bin/sh
# Reinicia o agente em segundo plano
pkill -f "python3 .*agent.py" 2>/dev/null
sleep 1
nohup /usr/bin/python3 "$(dirname "$0")/agent.py" > /tmp/meu_notebook_agent.log 2>&1 &
sleep 2; head -8 /tmp/meu_notebook_agent.log
