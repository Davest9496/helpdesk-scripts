# Incident Log Reporter — Python

Parses a helpdesk incident CSV export and generates a structured plain-text summary report. Built for end-of-shift handovers, weekly team reviews, and management updates — without needing Excel or a BI tool.

## What It Produces

- Total incidents, resolved vs. open, and resolution rate
- Average, fastest, and slowest resolution times
- Breakdown by category, priority, and assignee
- Daily volume chart (text-based)
- Open incident list with priority flags — so nothing gets missed at handover

## Usage

```bash
# Run with your own CSV
python incident_log_reporter.py --input incidents.csv

# Save the report to a file
python incident_log_reporter.py --input incidents.csv --output report.txt

# Try it immediately with built-in sample data
python incident_log_reporter.py --demo
```

## Expected CSV Format

| Column | Description |
|---|---|
| `incident_id` | Unique ticket reference |
| `date` | Date in YYYY-MM-DD format |
| `category` | e.g. Network, Hardware, Software, Access Control |
| `priority` | High / Medium / Low |
| `status` | Resolved / Open |
| `assigned_to` | Technician name |
| `resolution_time_mins` | Minutes to resolve (0 if still open) |
| `description` | Brief description of the issue |

Column names are case-insensitive. Export directly from ServiceNow, Jira, or any ticketing system that supports CSV.

## Example Output

```
════════════════════════════════════════════════════════════
  HELPDESK INCIDENT REPORT
  Source    : incidents.csv
  Generated : 2026-02-28 09:15
════════════════════════════════════════════════════════════

OVERVIEW
────────────────────────────────────────────────────────────
  Total incidents    : 15
  Resolved           : 13  (87%)
  Open               : 2
  High-priority      : 5  (5 resolved)

RESOLUTION TIME (resolved tickets)
────────────────────────────────────────────────────────────
  Average  : 40 mins
  Fastest  : 10 mins
  Slowest  : 120 mins

INCIDENTS BY CATEGORY
────────────────────────────────────────────────────────────
  Network              5  █████
  Hardware             5  █████
  Access Control       3  ███
  Software             2  ██

OPEN INCIDENTS (action required)
────────────────────────────────────────────────────────────
  [Low   ] INC006  |  Hardware  |  Sarah
           Monitor flickering intermittently
  [Low   ] INC011  |  Software  |  Sarah
           Printer driver needs updating
```

## Requirements

Python 3.7+ — no external libraries needed. Uses only the standard library.

```bash
python --version  # confirm 3.7+
python incident_log_reporter.py --demo
```

## Why This Exists

Generating a shift or weekly summary from a ticket export is a repetitive manual task in most support teams. This script turns a CSV into a ready-to-paste report in seconds — consistent format every time, no manual counting.
