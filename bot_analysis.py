#!/usr/bin/env python3
"""
Bot Warfare Analysis Script
Analyzes bot action logs to understand behavior patterns and identify improvement areas.
"""

import re
import sys
import argparse
from collections import defaultdict, Counter
from datetime import datetime
import json
from typing import Dict, List, Tuple, Any

class BotActionLog:
    def __init__(self, timestamp: str, bot_name: str, action: str, details: List[str]):
        self.timestamp = timestamp
        self.bot_name = bot_name
        self.action = action
        self.details = details
        self.full_details = " - ".join(details) if details else ""

class BotAnalyzer:
    def __init__(self):
        self.actions = []
        self.bots = set()
        self.action_types = set()
        
    def parse_log_line(self, line: str) -> BotActionLog:
        """Parse a single log line into a BotActionLog object."""
        # Handle Docker log format: "timestamp INFO Say BotName: BOT_ACTION: BotName - action - detail1 - detail2..."
        # Also handle wrapped lines that might be split across multiple lines
        
        # First, try to extract the BOT_ACTION part
        bot_action_match = re.search(r'BOT_ACTION: (\w+) - ([^-]+)(?: - (.+))?', line)
        if not bot_action_match:
            return None
            
        bot_name = bot_action_match.group(1)
        action = bot_action_match.group(2).strip()
        details_str = bot_action_match.group(3) if bot_action_match.group(3) else ""
        
        # Split details by " - " but handle cases where details might contain dashes
        details = []
        if details_str:
            # Simple split for now - could be improved for complex cases
            details = [d.strip() for d in details_str.split(" - ")]
        
        return BotActionLog("", bot_name, action, details)
    
    def load_logs(self, log_content: str):
        """Load and parse log content."""
        lines = log_content.split('\n')
        for line in lines:
            if 'BOT_ACTION:' in line:
                action = self.parse_log_line(line)
                if action:
                    self.actions.append(action)
                    self.bots.add(action.bot_name)
                    self.action_types.add(action.action)
    
    def get_basic_stats(self) -> Dict[str, Any]:
        """Get basic statistics about the bot actions."""
        total_actions = len(self.actions)
        unique_bots = len(self.bots)
        unique_actions = len(self.action_types)
        
        # Action frequency
        action_counts = Counter(action.action for action in self.actions)
        
        # Bot activity
        bot_activity = Counter(action.bot_name for action in self.actions)
        
        return {
            'total_actions': total_actions,
            'unique_bots': unique_bots,
            'unique_action_types': unique_actions,
            'action_frequency': dict(action_counts.most_common()),
            'bot_activity': dict(bot_activity.most_common()),
            'action_types': sorted(list(self.action_types))
        }
    
    def analyze_movement_patterns(self) -> Dict[str, Any]:
        """Analyze bot movement and navigation patterns."""
        movement_actions = ['follow', 'follow_threat', 'stuck', 'sprint', 'walk']
        
        movement_data = {
            'total_movement_actions': 0,
            'movement_breakdown': defaultdict(int),
            'stuck_analysis': defaultdict(int),
            'follow_patterns': defaultdict(int),
            'bot_movement_stats': defaultdict(lambda: defaultdict(int))
        }
        
        for action in self.actions:
            if action.action in movement_actions:
                movement_data['total_movement_actions'] += 1
                movement_data['movement_breakdown'][action.action] += 1
                movement_data['bot_movement_stats'][action.bot_name][action.action] += 1
                
                if action.action == 'stuck':
                    movement_data['stuck_analysis'][action.bot_name] += 1
                elif action.action in ['follow', 'follow_threat']:
                    detail = action.details[0] if action.details else 'unknown'
                    movement_data['follow_patterns'][f"{action.action}_{detail}"] += 1
        
        return dict(movement_data)
    
    def analyze_combat_patterns(self) -> Dict[str, Any]:
        """Analyze bot combat behavior."""
        combat_actions = ['nade', 'equ', 'fire', 'aim', 'reload', 'switch_weapon']
        
        combat_data = {
            'total_combat_actions': 0,
            'combat_breakdown': defaultdict(int),
            'weapon_usage': defaultdict(int),
            'grenade_usage': defaultdict(int),
            'bot_combat_stats': defaultdict(lambda: defaultdict(int))
        }
        
        for action in self.actions:
            if action.action in combat_actions:
                combat_data['total_combat_actions'] += 1
                combat_data['combat_breakdown'][action.action] += 1
                combat_data['bot_combat_stats'][action.bot_name][action.action] += 1
                
                if action.action == 'nade':
                    weapon = action.details[0] if action.details else 'unknown'
                    combat_data['grenade_usage'][weapon] += 1
                elif action.action == 'equ':
                    weapon = action.details[0] if action.details else 'unknown'
                    combat_data['weapon_usage'][weapon] += 1
        
        return dict(combat_data)
    
    def analyze_decision_making(self) -> Dict[str, Any]:
        """Analyze bot decision-making patterns."""
        decision_actions = ['killcam', 'revenge', 'camp', 'patrol', 'search']
        
        decision_data = {
            'total_decisions': 0,
            'decision_breakdown': defaultdict(int),
            'killcam_analysis': defaultdict(int),
            'revenge_patterns': defaultdict(int),
            'bot_decision_stats': defaultdict(lambda: defaultdict(int))
        }
        
        for action in self.actions:
            if action.action in decision_actions:
                decision_data['total_decisions'] += 1
                decision_data['decision_breakdown'][action.action] += 1
                decision_data['bot_decision_stats'][action.bot_name][action.action] += 1
                
                if action.action == 'killcam':
                    decision_data['killcam_analysis'][action.bot_name] += 1
                elif action.action == 'revenge':
                    detail = action.details[0] if action.details else 'unknown'
                    decision_data['revenge_patterns'][detail] += 1
        
        return dict(decision_data)
    
    def identify_problematic_bots(self) -> Dict[str, Any]:
        """Identify bots with problematic behavior patterns."""
        bot_problems = defaultdict(lambda: {
            'stuck_count': 0,
            'killcam_count': 0,
            'total_actions': 0,
            'action_diversity': set(),
            'issues': []
        })
        
        for action in self.actions:
            bot = action.bot_name
            bot_problems[bot]['total_actions'] += 1
            bot_problems[bot]['action_diversity'].add(action.action)
            
            if action.action == 'stuck':
                bot_problems[bot]['stuck_count'] += 1
            elif action.action == 'killcam':
                bot_problems[bot]['killcam_count'] += 1
        
        # Analyze problems
        problematic_bots = {}
        for bot, stats in bot_problems.items():
            issues = []
            
            # Check for excessive getting stuck
            if stats['stuck_count'] > 5:
                issues.append(f"Gets stuck frequently ({stats['stuck_count']} times)")
            
            # Check for excessive killcam time
            if stats['killcam_count'] > 10:
                issues.append(f"Spends too much time in killcam ({stats['killcam_count']} times)")
            
            # Check for low action diversity
            if len(stats['action_diversity']) < 5:
                issues.append(f"Low action diversity ({len(stats['action_diversity'])} unique actions)")
            
            # Check for very low activity
            if stats['total_actions'] < 10:
                issues.append(f"Very low activity ({stats['total_actions']} total actions)")
            
            if issues:
                problematic_bots[bot] = {
                    'issues': issues,
                    'stats': dict(stats)
                }
        
        return problematic_bots
    
    def generate_recommendations(self) -> List[str]:
        """Generate recommendations for improving bot behavior."""
        stats = self.get_basic_stats()
        movement = self.analyze_movement_patterns()
        combat = self.analyze_combat_patterns()
        decisions = self.analyze_decision_making()
        problems = self.identify_problematic_bots()
        
        recommendations = []
        
        # Movement recommendations
        if movement['stuck_analysis']:
            stuck_bots = len(movement['stuck_analysis'])
            if stuck_bots > len(self.bots) * 0.3:  # More than 30% of bots get stuck
                recommendations.append("PATHFINDING: Many bots are getting stuck. Consider improving waypoint navigation and collision detection.")
        
        # Combat recommendations
        if combat['total_combat_actions'] < len(self.actions) * 0.2:  # Less than 20% combat actions
            recommendations.append("COMBAT: Bots are not engaging in combat enough. Consider adjusting combat aggression settings.")
        
        # Decision-making recommendations
        if decisions['killcam_analysis']:
            avg_killcam = sum(decisions['killcam_analysis'].values()) / len(decisions['killcam_analysis'])
            if avg_killcam > 5:
                recommendations.append("RESPAWN: Bots are spending too much time in killcam. Consider adjusting respawn times or killcam duration.")
        
        # Problematic bot recommendations
        if problems:
            recommendations.append(f"INDIVIDUAL BOTS: {len(problems)} bots have behavioral issues. Review their individual settings and waypoint paths.")
        
        # General recommendations
        if len(stats['action_types']) < 10:
            recommendations.append("BEHAVIOR DIVERSITY: Bots are performing a limited variety of actions. Consider adding more behavioral states.")
        
        return recommendations
    
    def export_analysis(self, output_file: str = None):
        """Export complete analysis to JSON file."""
        analysis = {
            'summary': self.get_basic_stats(),
            'movement_analysis': self.analyze_movement_patterns(),
            'combat_analysis': self.analyze_combat_patterns(),
            'decision_analysis': self.analyze_decision_making(),
            'problematic_bots': self.identify_problematic_bots(),
            'recommendations': self.generate_recommendations(),
            'raw_actions': [
                {
                    'bot': action.bot_name,
                    'action': action.action,
                    'details': action.details
                }
                for action in self.actions
            ]
        }
        
        if output_file:
            with open(output_file, 'w') as f:
                json.dump(analysis, f, indent=2)
            print(f"Analysis exported to {output_file}")
        
        return analysis

def main():
    parser = argparse.ArgumentParser(description='Analyze Bot Warfare action logs')
    parser.add_argument('input', help='Input log file or use "-" for stdin')
    parser.add_argument('--output', '-o', help='Output JSON file for analysis')
    parser.add_argument('--summary', '-s', action='store_true', help='Show summary only')
    parser.add_argument('--problems', '-p', action='store_true', help='Show problematic bots only')
    parser.add_argument('--recommendations', '-r', action='store_true', help='Show recommendations only')
    
    args = parser.parse_args()
    
    # Read input
    if args.input == '-':
        log_content = sys.stdin.read()
    else:
        with open(args.input, 'r') as f:
            log_content = f.read()
    
    # Analyze
    analyzer = BotAnalyzer()
    analyzer.load_logs(log_content)
    
    if not analyzer.actions:
        print("No bot actions found in the log file.")
        return
    
    # Generate analysis
    analysis = analyzer.export_analysis(args.output)
    
    # Display results based on flags
    if args.summary:
        print("\n=== BOT ACTION SUMMARY ===")
        stats = analysis['summary']
        print(f"Total Actions: {stats['total_actions']}")
        print(f"Unique Bots: {stats['unique_bots']}")
        print(f"Action Types: {stats['unique_action_types']}")
        print(f"\nMost Common Actions:")
        for action, count in list(stats['action_frequency'].items())[:10]:
            print(f"  {action}: {count}")
    
    elif args.problems:
        print("\n=== PROBLEMATIC BOTS ===")
        for bot, data in analysis['problematic_bots'].items():
            print(f"\n{bot}:")
            for issue in data['issues']:
                print(f"  - {issue}")
    
    elif args.recommendations:
        print("\n=== RECOMMENDATIONS ===")
        for i, rec in enumerate(analysis['recommendations'], 1):
            print(f"{i}. {rec}")
    
    else:
        # Full analysis
        print("\n=== BOT WARFARE ANALYSIS REPORT ===")
        
        # Summary
        stats = analysis['summary']
        print(f"\n📊 SUMMARY:")
        print(f"   Total Actions: {stats['total_actions']}")
        print(f"   Unique Bots: {stats['unique_bots']}")
        print(f"   Action Types: {stats['unique_action_types']}")
        
        # Movement Analysis
        movement = analysis['movement_analysis']
        print(f"\n🚶 MOVEMENT ANALYSIS:")
        print(f"   Total Movement Actions: {movement['total_movement_actions']}")
        print(f"   Stuck Incidents: {sum(movement['stuck_analysis'].values())}")
        print(f"   Follow Actions: {movement['movement_breakdown']['follow'] + movement['movement_breakdown']['follow_threat']}")
        
        # Combat Analysis
        combat = analysis['combat_analysis']
        print(f"\n🔫 COMBAT ANALYSIS:")
        print(f"   Total Combat Actions: {combat['total_combat_actions']}")
        print(f"   Grenade Usage: {sum(combat['grenade_usage'].values())}")
        print(f"   Weapon Switches: {combat['combat_breakdown']['equ']}")
        
        # Problematic Bots
        problems = analysis['problematic_bots']
        if problems:
            print(f"\n⚠️  PROBLEMATIC BOTS ({len(problems)}):")
            for bot, data in problems.items():
                print(f"   {bot}: {', '.join(data['issues'])}")
        
        # Recommendations
        recommendations = analysis['recommendations']
        if recommendations:
            print(f"\n💡 RECOMMENDATIONS:")
            for i, rec in enumerate(recommendations, 1):
                print(f"   {i}. {rec}")
        
        if args.output:
            print(f"\n📄 Full analysis exported to: {args.output}")

if __name__ == "__main__":
    main()
