#!/bin/bash
# Bot Warfare Analysis Script
# Easy way to analyze bot logs from Docker container

set -e

echo "🤖 Bot Warfare Analysis Tool"
echo "============================"

# Check if we have recent logs to analyze
echo "📊 Fetching recent bot logs from Docker container..."

# Get the last 1000 lines of logs and filter for bot actions
docker logs cod4 --tail 1000 | grep "BOT_ACTION" > /tmp/bot_actions.log

# Check if we have any bot actions
if [ ! -s /tmp/bot_actions.log ]; then
    echo "❌ No bot actions found in recent logs."
    echo "   Make sure the server is running and bots are active."
    echo "   You can also manually specify a log file:"
    echo "   ./bot_analysis.py your_log_file.txt"
    exit 1
fi

echo "✅ Found bot actions in logs."
echo "📈 Analyzing bot behavior..."

# Run the analysis
./bot_analysis.py /tmp/bot_actions.log --output bot_analysis_$(date +%Y%m%d_%H%M%S).json

echo ""
echo "🎯 Quick Analysis Options:"
echo "   ./bot_analysis.py /tmp/bot_actions.log --summary"
echo "   ./bot_analysis.py /tmp/bot_actions.log --problems"
echo "   ./bot_analysis.py /tmp/bot_actions.log --recommendations"
echo ""
echo "📄 Log file saved to: /tmp/bot_actions.log"
echo "📊 Full analysis saved to: bot_analysis_*.json"
