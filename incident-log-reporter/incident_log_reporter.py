# incident_log_reporter.py
# Reads a ticket CSV and generates a formatted shift report
# Usage: python incident_log_reporter.py tickets.csv

import csv
import sys
import os
from datetime import datetime

# ── Default CSV file if none provided ──────────────────────────────────────
DEFAULT_FILE = "tickets.csv"

def load_tickets(filepath):
    """Read tickets from CSV file and return as list of dicts."""
    tickets = []
    with open(filepath, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            tickets.append(row)
    return tickets

def generate_report(tickets, source_file):
    """Build the shift report string from ticket data."""
    now = datetime.now().strftime("%d %B %Y %H:%M")
    total = len(tickets)

    # Count by priority
    p1 = [t for t in tickets if t.get('priority','').upper() == 'P1']
    p2 = [t for t in tickets if t.get('priority','').upper() == 'P2']
    p3 = [t for t in tickets if t.get('priority','').upper() == 'P3']

    # Count by status
    resolved   = [t for t in tickets if t.get('status','').lower() == 'resolved']
    open_t     = [t for t in tickets if t.get('status','').lower() == 'open']
    in_prog    = [t for t in tickets if t.get('status','').lower() == 'in progress']

    # Count by category
    categories = {}
    for t in tickets:
        cat = t.get('category', 'Uncategorised').strip()
        categories[cat] = categories.get(cat, 0) + 1

    # ── Build report ───────────────────────────────────────────────────────
    lines: list[str] = []
    lines.append("=" * 55)
    lines.append("       HELPDESK.LAB — SHIFT REPORT")
    lines.append(f"       Generated: {now}")
    lines.append(f"       Source:    {os.path.basename(source_file)}")
    lines.append("=" * 55)

    lines.append("\n── TICKET SUMMARY ──────────────────────────────────")
    lines.append(f"  Total tickets:    {total}")
    lines.append(f"  Resolved:         {len(resolved)}")
    lines.append(f"  In Progress:      {len(in_prog)}")
    lines.append(f"  Open:             {len(open_t)}")

    lines.append("\n── PRIORITY BREAKDOWN ──────────────────────────────")
    lines.append(f"  P1 (Critical):    {len(p1)}")
    lines.append(f"  P2 (High):        {len(p2)}")
    lines.append(f"  P3 (Standard):    {len(p3)}")

    lines.append("\n── CATEGORY BREAKDOWN ──────────────────────────────")
    for cat, count in sorted(categories.items()):
        lines.append(f"  {cat:<25} {count}")

    lines.append("\n── TICKET DETAIL ───────────────────────────────────")
    lines.append(f"  {'ID':<8} {'Priority':<10} {'Status':<12} {'Category':<20} Title")
    lines.append(f"  {'-'*7} {'-'*9} {'-'*11} {'-'*19} {'-'*20}")
    for t in tickets:
        tid      = t.get('ticket_id','?')[:7]
        priority = t.get('priority','?')[:9]
        status   = t.get('status','?')[:11]
        category = t.get('category','?')[:19]
        title    = t.get('title','?')[:40]
        lines.append(f"  {tid:<8} {priority:<10} {status:<12} {category:<20} {title}")

    lines.append("\n" + "=" * 55)
    lines.append("  End of report")
    lines.append("=" * 55)

    return "\n".join(lines)

def main():
    # Use argument or default file
    filepath = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FILE

    if not os.path.exists(filepath):
        print(f"ERROR: Cannot find ticket file: {filepath}")
        print("Usage: python incident_log_reporter.py tickets.csv")
        sys.exit(1)

    tickets = load_tickets(filepath)
    report  = generate_report(tickets, filepath)

    # Print to screen
    print(report)

    # Save to file
    timestamp   = datetime.now().strftime("%Y-%m-%d_%H%M")
    output_file = f"shift_report_{timestamp}.txt"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(report)

    print(f"\n  Report saved to: {output_file}")

if __name__ == "__main__":
    main()
