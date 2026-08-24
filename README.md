# PhD Funding Command Center

A personal, honest, self-verifying dashboard for a computational-biology PhD
application cycle (entry Oct 2027): funding triage, odds, deadlines, writing
studios and interview preparation — built around one real CV.

**Live:** https://gabriele-bambini.github.io/phd-funding-dashboard/
**Funding hub:** https://gabriele-bambini.github.io/phd-funding-dashboard/funding.html

## What is inside

| Page | Purpose |
|---|---|
| `index.html` | Main dashboard: chances, targets, professors (ranked), projects, plan, graph, estimates. Single-line body; data in embedded JSON blocks (`drillData`, `graphData`). Installable PWA shell. |
| `funding.html` | The operational hub — 16 sections: realistic triage → raise-your-odds → research proposals (PDF) → deadline radar → readiness score → pipeline → outreach board → odds → money → documents → must-apply/external/all funds → playbooks → decision matrix → writing studio → SoP lab → variant tracker → interview drill → proposal forge → intel → verify queue. |
| `deadlines.ics` | Import once into any calendar: 10 key deadlines with 7-day + 1-day alarms. |
| `proposals/*.pdf` | Three complete research proposals (p53 sheaf-GNN, mosquito TE landscape, immuno-uncertainty graphs) with an automated **chain of verification**: every cited source probed at build time (✓ HTTP 200 / ○ unverified). |
| `tools/build_funding_page.ps1` | The full build script — regenerates everything from the data in `index.html`. |

## Honest-data conventions

- Odds (`chance.p/b/m`) are **personal estimates** calibrated on one CV — not official rates.
- Link badges: ✓ = probed HTTP 200 this build; ○ = unverified/blocked — check before applying.
- Tier-C US routes stay listed for auto-box scholarships but their supervisors are excluded from the contact flow by design.

## Rebuild

```powershell
pwsh -NoProfile -File tools/build_funding_page.ps1
```

- Requires PowerShell 7+ (UTF-8 with BOM matters — the script re-applies it).
- Probes ~30 official URLs + every proposal reference; results cached in
  `$env:TEMP\phdfund_probe_cache.json` (24 h) and `phdfund_refs_cache.json`.
- Generates PDFs via headless Chrome when present; falls back to HTML-only.
- On CI (Linux) it runs unchanged: repo path falls back to the script location.

## Self-verification

`.github/workflows/monthly-refresh.yml` rebuilds the site on the 1st of each
month with fresh probes and commits changes automatically.

## Local-state keys (all `phdbot_*` in localStorage)

`phdbot_verify_v1` · `phdbot_pipe_v1` · `phdbot_score_v1` ·
`phdbot_matrix_v1` · `phdbot_outreach_v1` · `phdbot_sop_v1` ·
`phdbot_drill_v1` · `phdbot_forge_v1` · `phdbot_review_v1` ·
`phdbot_variants_v1`

Use the **Backup progress** button on the funding page to export all of them
as JSON; **Restore** reloads them on any device.
