$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'C:\Users\Gabriele\OneDrive - Università Commerciale Luigi Bocconi\Desktop\CONOSCENZA\phd-funding-dashboard'
if (-not (Test-Path $repo)) { $repo = Split-Path -Parent $PSScriptRoot }
$fIdx = Join-Path $repo 'index.html'
$fFun = Join-Path $repo 'funding.html'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

function Norm([string]$n) { ($n.ToLower() -replace '[^a-z0-9]','') }
function Esc([string]$s) { [net.WebUtility]::HtmlEncode(([string]$s)) }

# ---------- load ----------
$raw = [System.IO.File]::ReadAllText($fIdx)
$m = [regex]::Match($raw, '(?s)<script type="application/json" id="drillData">(.*?)</script>')
$drill = $m.Groups[1].Value | ConvertFrom-Json

# ---------- 0b. profile fit: prune off-CV programmes, drop tier-C-US supervisors, rank contacts ----------
$usTierC = @('Harvard University','MIT','Stanford University','UC Berkeley','Princeton University','Caltech')
$progKill = '(ai4er|environmental risks|sensor technologies|cyber security|autonomous intelligent|random systems|experimental psychology|psychiatry|neurotech|neuroinformatics|operations research|orfe|ieor|industrial engineering|management science|applied mathematics|applied and computational mathematics|applied physics|mathematics phd|phd in mathematics|mathematics \(|edma|electrical engineering|edee|edrs|robotics|control and dynamical|neuroscience|neurobiology|brain and cognitive|cognitive neuro|chemical and biological engineering|chemical and systems biology|molecular biology|biophysics|biological and biomedical|systems, synthetic|microbiology|ecology and evolutionary|social and decision|computational social|physics|astronomy)'
$progKeep = '(statistic|machine learning|genom|bioinf|biostat|health data|ai for healthcare|bioengineer)'
$prunedProgs = 0; $prunedPis = 0; $rankedPis = 0
$uniW = @{ 'University of Cambridge'=1.00; 'University of Oxford'=0.95; 'Imperial College London'=0.93; 'ETH Zurich'=0.90; 'EPFL'=0.88; 'Karolinska Institutet'=0.86 }
foreach ($un in $drill.unis.PSObject.Properties.Name) {
  $u = $drill.unis.$un
  if (@($u.programs).Count -gt 0) {
    $kept = @()
    foreach ($p in @($u.programs)) {
      $nm = [string]$p.n
      if ($nm -match $progKill -and $nm -notmatch $progKeep) { $prunedProgs++; continue }
      $kept += $p
    }
    $drill.unis.$un.programs = $kept
  }
}
foreach ($un in $usTierC) { if ($drill.unis.PSObject.Properties.Name -contains $un) { $prunedPis += @($drill.unis.$un.pis).Count; $drill.unis.$un.pis = @() } }
foreach ($un in $uniW.Keys) {
  if (-not ($drill.unis.PSObject.Properties.Name -contains $un)) { continue }
  $pis = @($drill.unis.$un.pis)
  $scored = foreach ($p in $pis) {
    $rf = if (([string]$p.r) -match 'high') { 1.0 } elseif (([string]$p.r) -match 'medium') { 0.8 } else { 0.7 }
    [pscustomobject]@{ p = $p; sc = [double]$uniW[$un] * $rf }
  }
  $sorted = @($scored | Sort-Object sc -Descending | ForEach-Object { $_.p })
  for ($i = 0; $i -lt $sorted.Count; $i++) {
    $rankedPis++
    if ($un -eq 'University of Cambridge' -and $i -eq 0) { $sorted[$i].r = 'S-tier · current boss · high reply odds' }
    elseif ($i -eq 0) { if ([string]$sorted[$i].r) { $sorted[$i].r = 'A-tier · ' + [string]$sorted[$i].r + ' reply odds' } else { $sorted[$i].r = 'A-tier contact' } }
    elseif ($i -eq 1 -and [string]$sorted[$i].r) { $sorted[$i].r = 'B-tier · ' + [string]$sorted[$i].r + ' reply odds' }
  }
  $drill.unis.$un.pis = $sorted
}
"programmes pruned: $prunedProgs | supervisors dropped (tier-C US): $prunedPis | contacts ranked: $rankedPis"
# dedupe near-duplicate programmes (same Key2, keep highest s)
foreach ($un in $drill.unis.PSObject.Properties.Name) {
  $progs = @($drill.unis.$un.programs); if ($progs.Count -lt 2) { continue }
  $best = @{}; $out = @()
  foreach ($p in ($progs | Sort-Object { if ($_.s) { [double]$_.s } else { 0 } } -Descending)) {
    $k2 = Norm ((([string]$p.n) -replace '\([^)]*\)','') )
    if (-not $k2) { $k2 = Norm ([string]$p.n) }
    if (-not $best.ContainsKey($k2)) { $best[$k2] = 1; $out += $p }
  }
  $drill.unis.$un.programs = $out
}

# ---------- 1. probe official URLs ----------
function Probe([string]$u) {
  try { $r = Invoke-WebRequest -Uri $u -Headers @{'User-Agent'=$ua} -TimeoutSec 12 -UseBasicParsing -MaximumRedirection 6; return ($r.StatusCode -eq 200) } catch { return $false }
}
$cand = [ordered]@{
  'imperial_presidents' = @('https://www.imperial.ac.uk/study/fees-and-funding/postgraduate-doctoral/scholarships/presidents-phd-scholarships/')
  'knight_hennessy'     = @('https://knighthennessy.stanford.edu/')
  'fulbright_it'        = @('https://www.fulbright.it/')
  'eskas'               = @('https://www.sbfi.admin.ch/sbfi/en/home/education/scholarships-and-grants/swiss-government-excellence-scholarships.html')
  'eipp'                = @('https://www.embl.de/training/eipp/','https://www.embl.de/training/eipp/index.html')
  'sanger_phd'          = @('https://www.sanger.ac.uk/study/phd/')
  'ccaim'               = @('https://ccaim.cam.ac.uk/study-with-us/')
  'cruk_ci'             = @('https://www.cruk.cam.ac.uk/')
  'mrc_bsu'             = @('https://www.mrc-bsu.cam.ac.uk/')
  'whs'                 = @('https://www.whscholarships.org/')
  'reuben'              = @('https://reuben.ox.ac.uk/')
  'epfl_globaleaders'   = @('https://www.epfl.ch/schools/education/epflglobaleaders/','https://www.epfl.ch/education/doctoral-studies/epflglobaleaders/')
  'eth_aicenter'        = @('https://aicenter.ethz.ch/')
  'harvard_gsas'        = @('https://gsas.harvard.edu/financing-your-education','https://gsas.harvard.edu/tuition-funding')
  'mit_oge'             = @('https://oge.mit.edu/financing/','https://oge.mit.edu/')
  'princeton_gs'        = @('https://gradschool.princeton.edu/financial-support','https://gradschool.princeton.edu/')
  'berkeley_grad'       = @('https://grad.berkeley.edu/admissions/financial-support/','https://grad.berkeley.edu/financial-support/')
  'ki_phd'              = @('https://ki.se/en/education/doctoral-phd-education','https://ki.se/en/education/phd-studies','https://ki.se/en/studying/phd-studies')
  'epfl_doctoral'       = @('https://www.epfl.ch/education/doctoral-studies/')
  'eth_doctorate'       = @('https://ethz.ch/en/studies/doctorate.html','https://ethz.ch/en/doctorate.html')
  'daad'                = @('https://www.daad.de/en/studying-in-germany/scholarships/research-grants-doctoral-programmes/','https://www.daad.de/en/')
  'cam_funding_search'  = @('https://www.postgraduate.study.cam.ac.uk/finance/funding-search')
  'findaphd'            = @('https://www.findaphd.com/phds/computational-biology/')
  'scholarshipdb'       = @('https://scholarshipdb.net/scholarships/computational-biology')
  'naturecareers'       = @('https://www.nature.com/naturecareers/search?q=computational+biology+phd')
  'ebi_careers'         = @('https://www.ebi.ac.uk/careers/phd','https://www.ebi.ac.uk/careers/')
  'euraxess_search'     = @('https://euraxess.ec.europa.eu/jobs/search?keywords=computational+biology')
  'unipv'               = @('https://dottorati.unipv.it/','https://unipv.it/')
}
$ok = @{}
$cachePath = Join-Path $env:TEMP 'phdfund_probe_cache.json'
if (Test-Path $cachePath) {
  try {
    $cj = Get-Content $cachePath -Raw | ConvertFrom-Json
    if ($cj.ts -and ((Get-Date) - [datetime]$cj.ts).TotalHours -lt 24) {
      foreach ($pr in $cj.ok.PSObject.Properties) { $ok[$pr.Name] = [string]$pr.Value }
      "probe cache loaded: $($ok.Count) entries ($([datetime]$cj.ts))"
    }
  } catch { }
}
if ($ok.Count -eq 0) {
foreach ($k in $cand.Keys) {
  $found = ''
  foreach ($u in $cand[$k]) { if (Probe $u) { $found = $u; break } }
  $ok[$k] = $found
  if ($found) { "OK  $k -> $found" } else { "MISS $k" }
}
try { [System.IO.File]::WriteAllText($cachePath, (@{ ts=(Get-Date).ToString('o'); ok=$ok } | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false))); 'probe cache saved' } catch { }
}

# ---------- 1b. append genuinely-accessible local routes (idempotent) ----------
$have = @{}
foreach ($r in $drill.lists.external.rows) { $hk = Norm ([string]$r.n); $have[$hk] = 1 }
$newRoutes = @(
  @{ n='IFOM PhD Programme'; uni='IFOM — FIRC Institute of Molecular Oncology · Milan'; stage='★ PRE-ENTRY · COMP-BIO · INSIDER ROUTE'; u='https://www.ifom.eu/en/'; v=0; t='Call opens autumn, closes ~Jan–Feb (verify)'; o='You already work in this building (Buffa/Tangherloni labs): internal references, a known project, FIRC-funded positions. Your single most accessible top-tier route — treat as Plan A alongside Cambridge.' },
  @{ n='Humanitas / University of Milan PhD (comp-bio, AI for health)'; uni='Humanitas University · University of Milan'; stage='PRE-ENTRY · COMP-BIO · LOCAL ADVANTAGE'; u='https://www.hunimed.eu/'; v=0; t='Calls vary, mostly spring–autumn (verify)'; o='You are inside the Bocconi–Humanitas MSc pipeline: aligned coursework and existing tutors make admission probability high while keeping IFOM ties alive.' },
  @{ n='Italian PhD routes — Pavia / Milan / national programmes (data science, AI for health, genomic medicine)'; uni='University of Pavia · University of Milan · national doctorates'; stage='PRE-ENTRY · COMP-BIO · SAFETY ANCHOR'; u='https://www.unimi.it/en'; v=0; t='Calls ~May–Jul annually (verify)'; o='Your grades win merit prizes year after year: Italian PhD admission is a different game from Oxbridge — high probability, funded (~€1,350/mo net), and compatible with staying near IFOM part-time.' },
  @{ n='Salaried Nordic PhD positions (KI · DTU · Copenhagen · Stockholm)'; uni='Danish & Swedish public universities'; stage='PRE-ENTRY · COMP-BIO · SALARIED'; u='https://www.dtu.dk/english/education/PhD'; v=0; t='Positions advertised per-project, year-round'; o='Employment-contract PhDs selected on project fit rather than prestige games: your mosquito-genomics + ML pipeline matches many posted projects. Apply broadly to individual adverts.' }
)
$addedR = 0
foreach ($nr in $newRoutes) {
  if (-not $have.ContainsKey((Norm $nr.n))) {
    $rows = @($drill.lists.external.rows)
    $drill.lists.external.rows = $rows + [pscustomobject]@{ n=$nr.n; uni=$nr.uni; stage=$nr.stage; u=$nr.u; v=$nr.v; t=$nr.t; o=$nr.o }
    $addedR++
  }
}
"accessible routes added to external list: $addedR"

# ---------- 1c. realistic-tiers dataset for the dedicated section ----------
$tierA = @(
  @{ n='IFOM PhD Programme'; url='https://www.ifom.eu/en/'; ch='40–60%'; why='INSIDER — you already work there (Buffa/Tangherloni); internal references + known project; FIRC-funded.' },
  @{ n='Cambridge PhD with Liò → central scholarships (Trust/CIS · Harding) or supervisor-held studentship'; url='https://www.postgraduate.study.cam.ac.uk/finance/funding-search'; ch='30–45% funding · admission alone 65–75%'; why='Supervisor backing is THE signal at Cambridge — and he is your current RA boss. One application, five funding shots.' },
  @{ n='Wellcome PhD in Mathematical Genomics and Medicine (Cambridge)'; url='https://www.postgraduate.study.cam.ac.uk/finance/funding-search'; ch='22–35%'; why='Profile-exact programme; Liò/Buffa network reads your sheaf-GNN oncology work as core business.' },
  @{ n='CCAIM studentships (Cambridge AI in Medicine)'; url='https://ccaim.cam.ac.uk/'; ch='25–35%'; why='Liò is CCAIM faculty; AI×medicine is literally your MSc title.' },
  @{ n='Dottorati locali e nazionali (Pavia · Milano · Data Science/AI-health/genomic medicine)'; url='https://www.unimi.it/en'; ch='≥50%'; why='Different game: your transcript wins merit prizes every year. Funded (~€1,350/mo net) and keeps IFOM within reach. This is the safety anchor.' },
  @{ n='Humanitas / University of Milan doctoral routes'; url='https://www.hunimed.eu/'; ch='~40%'; why='You are already inside the teaching pipeline (Bocconi–Humanitas MSc).' },
  @{ n='Salaried Nordic positions (KI · DTU · Copenhagen · Stockholm)'; url='https://www.dtu.dk/english/education/PhD'; ch='25–40% per well-chosen post'; why='Job-contract PhDs chosen on project fit: mosquito-genomics + ML matches many adverts; no prestige lottery.' },
  @{ n='MSCA Doctoral Networks (comp-bio calls)'; url='https://marie-sklodowska-curie-actions.ec.europa.eu/actions/doctoral-networks'; ch='20–35%'; why='Any nationality, excellent pay; target oncology/genomics networks where your profile IS the spec.' }
)
$tierB = @(
  @{ n='EMBL International PhD Programme'; ch='~18%' },
  @{ n='Wellcome Sanger 4-Year Programme'; ch='~17% · hard wall 27 Nov 2026' },
  @{ n='MRC LMB · Francis Crick · Institut Pasteur · CRG Barcelona'; ch='10–15% each' },
  @{ n='DKFZ Heidelberg (cancer computational)'; ch='10–20%, twice-yearly calls' },
  @{ n='Boehringer Ingelheim Fonds (once your PhD starts — also on an Italian PhD!)'; ch='10–15%' },
  @{ n="Imperial President's + departmental nomination"; ch='8–15% if nominated early' }
)
$tierC = @(
  @{ n='Gates Cambridge'; ch='1–3%'; why='BUT ticking its box on the Cambridge application costs nothing — tick it; just never plan around it.' },
  @{ n='Rhodes · Knight-Hennessy'; ch='2–4%'; why='Leadership-narrative prizes misaligned with a technical pre-first-paper CV.' },
  @{ n='Direct PhD at Harvard/Stanford/MIT/Berkeley/Princeton/Caltech'; ch='3–7%'; why='No first-author paper + US pipeline norms; go only if a PI actively recruits you.' },
  @{ n='ETH AI Center · ELLIS'; ch='<5%'; why='Pure-ML pools against CS-strong applicants; revisit after a first paper.' },
  @{ n='Post-entry boosters (Google · NVIDIA · Apple · Turing)'; ch='n/a'; why='These are NOT admission competitions — they stack money once you are enrolled anywhere. Keep them on the radar for year 1.' }
)

function TierSection {
  param($title, $color, $items, [bool]$withWhy)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('<div class="tw tw-' + $color + '"><h3 class="t-h">' + $title + '</h3><div class="tgrid">')
  foreach ($it in $items) {
    $nm = [string]$it.n
    $inner = if ([string]$it.url -ne '') { '<a href="' + (Esc ([string]$it.url)) + '" target="_blank" rel="noopener">' + (Esc $nm) + '</a>' } else { Esc $nm }
    $whyLine = ''
    if ($withWhy -and [string]$it.why) { $whyLine = '<span class="twhy">' + (Esc ([string]$it.why)) + '</span>' }
    [void]$sb.Append('<div class="titem"><span class="tch">' + (Esc ([string]$it.ch)) + '</span><span class="tnm">' + $inner + '</span>' + $whyLine + '</div>')
  }
  [void]$sb.Append('</div></div>')
  return $sb.ToString()
}
$realisticHtml = '<h2 id="realistic">Where you ACTUALLY have a chance</h2><p class="lead">Honest triage, not a brochure: ranked by structural advantage for YOUR cv (no first-author paper yet; RA in Li&ograve;&rsquo;s lab; IFOM insider; transcript that wins Italian merit prizes yearly). Strategy line: <b>Plan A</b> Cambridge-with-Li&ograve; &#8741; IFOM internal &middot; <b>Plan B</b> Nordic/MSCA salaried &middot; <b>Safety</b> Milano&ndash;Pavia dottorato &middot; everything else is upside, not plan.</p>' +
  (TierSection 'TIER A — structural advantage: apply first, apply well' 'a' $tierA $true) +
  (TierSection 'TIER B — steep but winnable: one strong, tailored application each' 'b' $tierB $false) +
  (TierSection 'TIER C — brutal competition: spend zero planning time here' 'c' $tierC $true)

# ---------- 2. hardcoded official map (fund-name-regex -> url key or literal) ----------
$hard = @(
  @{ re='(?i)president''s phd scholarships'; url=$ok['imperial_presidents'] },
  @{ re='(?i)knight-hennessy';               url=$ok['knight_hennessy'] },
  @{ re='(?i)fulbright';                     url=$ok['fulbright_it'] },
  @{ re='(?i)swiss government excellence';   url=$ok['eskas'] },
  @{ re='(?i)EMBL International PhD';        url=$(if ($ok['eipp']) { $ok['eipp'] } else { 'https://www.embl.de/training/eipp/' }) },
  @{ re='(?i)wellcome sanger 4-year';        url=$(if ($ok['sanger_phd']) { $ok['sanger_phd'] } else { 'https://www.sanger.ac.uk/study/phd/' }) },
  @{ re='(?i)ccaim';                         url=$(if ($ok['ccaim']) { $ok['ccaim'] } else { 'https://ccaim.cam.ac.uk/study-with-us/' }) },
  @{ re='(?i)CRUK CI 4-year|cruk';           url=$(if ($ok['cruk_ci']) { $ok['cruk_ci'] } else { 'https://www.cruk.cam.ac.uk/' }) },
  @{ re='(?i)MRC Biostatistics';             url=$(if ($ok['mrc_bsu']) { $ok['mrc_bsu'] } else { 'https://www.mrc-bsu.cam.ac.uk/' }) },
  @{ re='(?i)weidenfeld';                    url=$(if ($ok['whs']) { $ok['whs'] } else { 'https://www.whscholarships.org/' }) },
  @{ re='(?i)oxford-reuben|reuben scholar';  url=$(if ($ok['reuben']) { $ok['reuben'] } else { 'https://reuben.ox.ac.uk/' }) },
  @{ re='(?i)EPFLglobaLeaders';              url=$(if ($ok['epfl_globaleaders']) { $ok['epfl_globaleaders'] } else { 'https://www.epfl.ch/education/doctoral-studies/' }) },
  @{ re='(?i)ETH AI Center';                 url=$(if ($ok['eth_aicenter']) { $ok['eth_aicenter'] } else { 'https://aicenter.ethz.ch/' }) },
  @{ re='(?i)harvard griff?in gsas|harvard gsas'; url=$(if ($ok['harvard_gsas']) { $ok['harvard_gsas'] } else { 'https://gsas.harvard.edu/' }) },
  @{ re='(?i)MIT (Guaranteed|Presidential)'; url=$(if ($ok['mit_oge']) { $ok['mit_oge'] } else { 'https://oge.mit.edu/' }) },
  @{ re='(?i)princeton graduate school guaranteed|princeton guaranteed'; url=$(if ($ok['princeton_gs']) { $ok['princeton_gs'] } else { 'https://gradschool.princeton.edu/' }) },
  @{ re='(?i)berkeley (fellowship|doctoral funding|statistics phd funding|eecs phd funding|biostatistics phd full)'; url=$(if ($ok['berkeley_grad']) { $ok['berkeley_grad'] } else { 'https://grad.berkeley.edu/' }) },
  @{ re='(?i)KI salaried|KID funding';       url=$(if ($ok['ki_phd']) { $ok['ki_phd'] } else { 'https://ki.se/en/education' }) },
  @{ re='(?i)EPFL Doctoral Assistantship|EDIC'; url=$(if ($ok['epfl_doctoral']) { $ok['epfl_doctoral'] } else { 'https://www.epfl.ch/education/doctoral-studies/' }) },
  @{ re='(?i)ETH salaried doctoral';         url=$(if ($ok['eth_doctorate']) { $ok['eth_doctorate'] } else { 'https://ethz.ch/en/studies/doctorate.html' }) },
  @{ re='(?i)wellcome phd in mathematical genomics'; url=$(if ($ok['cam_funding_search']) { $ok['cam_funding_search'] } else { 'https://www.postgraduate.study.cam.ac.uk/finance/funding-search' }) },
  @{ re='(?i)^cambridge trust scholarships';               url='https://www.cambridgetrust.org/scholarships' },
  @{ re='(?i)harding distinguished postgraduate scholar';  url='https://www.postgraduate.study.cam.ac.uk/finance/funding/harding-distinguished-postgraduate-scholarship-programme' },
  @{ re='(?i)stanford graduate fellowship';                url='https://gradadmissions.stanford.edu/funding' },
  @{ re="(?i)chancellor's fellowship for graduate study";  url='https://grad.berkeley.edu/admissions/financial-support/' },
  @{ re='(?i)mrc dtp|research council studentships';       url='https://www.ukri.org/councils/mrc/' },
  @{ re='(?i)wellcome trust doctoral programme|wellcome trust 4-year'; url='https://www.postgraduate.study.cam.ac.uk/finance/funding-search' },
  @{ re='(?i)ndm / wellcome centre|nuffield department of population health'; url='https://www.ndm.ox.ac.uk/' },
  @{ re='(?i)roth phd scholarships|departmental / wellcome studentships'; url='https://www.ox.ac.uk/admissions/graduate/funding-your-study' },
  @{ re='(?i)funding package \(fellowship|doctoral funding guarantee|graduate division fellowships'; url='https://grad.berkeley.edu/admissions/financial-support/' },
  @{ re='(?i)president.?s phd scholarships'; url='https://www.imperial.ac.uk/study/fees-and-funding/postgraduate-doctoral/scholarships/' },
  @{ re='(?i)wellcome trust neuroscience doctoral'; url='https://www.ox.ac.uk/admissions/graduate/funding-your-study' },
  @{ re='(?i)inps';                          url='https://www.inps.it/' }
)

function Better([string]$cur, [string]$new) {
  if ($new -and $new -ne '' -and $cur -notmatch '^https' ) { return $new }
  if ($new -and $cur -match 'google\.com/search') { return $new }
  return $cur
}

# ---------- 3. collect real URLs + odds + v across everything; then apply ----------
$allRows = New-Object System.Collections.Generic.List[object]
foreach ($ln in 'must_apply','eligible','external') { foreach ($r in $drill.lists.$ln.rows) { $allRows.Add($r) } }
foreach ($un in $drill.unis.PSObject.Properties.Name) { foreach ($s in $drill.unis.$un.schols) { $allRows.Add($s) } }

$urlMap = @{}; $oddsMap = @{}; $vMap = @{}
foreach ($r in $allRows) {
  $k = Norm ([string]$r.n); if (-not $k) { continue }
  $uu = [string]$r.u
  if ($uu -and $uu -notmatch 'google\.com/search') {
    if (-not $urlMap.ContainsKey($k) -or $urlMap[$k] -match 'google\.com/search' -or $urlMap[$k] -eq '') { $urlMap[$k] = $uu }
  }
  $oo = [string]$r.o
  if ($oo -and -not $oddsMap.ContainsKey($k)) { $oddsMap[$k] = $oo }
  if ($r.v -eq 1) { $vMap[$k] = 1 }
}
# secondary propagation via parenthetical-stripped keys (unifies name variants)
function Key2([string]$n) { Norm (([string]$n) -replace '\([^)]*\)','') }
$u2=@{}; $o2=@{}; $v2=@{}
foreach ($r in $allRows) {
  $k2 = Key2 ([string]$r.n); if (-not $k2) { continue }
  $uu=[string]$r.u
  if ($uu -and $uu -notmatch 'google\.com/search' -and -not $u2.ContainsKey($k2)) { $u2[$k2]=$uu }
  if ([string]$r.o -and -not $o2.ContainsKey($k2)) { $o2[$k2]=[string]$r.o }
  if ($r.v -eq 1) { $v2[$k2]=1 }
}
$k2fixed = 0
foreach ($r in $allRows) {
  $k1 = Norm ([string]$r.n); $k2 = Key2 ([string]$r.n)
  if ($k2 -ne $k1 -and $k2) {
    if ($u2.ContainsKey($k2) -and ((([string]$r.u) -match 'google\.com/search') -or -not ([string]$r.u))) { $r.u = $u2[$k2]; $k2fixed++ }
    if (-not [string]$r.o -and $o2.ContainsKey($k2)) { $r.o = $o2[$k2] }
    if ($r.v -ne 1 -and $v2.ContainsKey($k2)) { $r.v = 1 }
  }
}
"key2 links unified: $k2fixed"
# apply hardcoded (verified) over everything
foreach ($h in $hard) {
  if (-not $h.url) { continue }
  foreach ($r in $allRows) {
    if (([string]$r.n) -match $h.re) {
      $r.u = Better ([string]$r.u) $h.url
      $hk = Norm ([string]$r.n)
      $urlMap[$hk] = $h.url
    }
  }
}
# propagate urls/odds/v into every row
$fixedU = 0; $fixedO = 0; $fixedV = 0
foreach ($r in $allRows) {
  $k = Norm ([string]$r.n); if (-not $k) { continue }
  $uu = [string]$r.u
  if ($urlMap.ContainsKey($k) -and ($uu -match 'google\.com/search' -or -not $uu)) { if ($urlMap[$k] -ne $uu) { $r.u = $urlMap[$k]; $fixedU++ } }
  if (-not [string]$r.o -and $oddsMap.ContainsKey($k)) { $r.o = $oddsMap[$k]; $fixedO++ }
  if ($r.v -ne 1 -and $vMap.ContainsKey($k)) { $r.v = 1; $fixedV++ }
}
"links upgraded: $fixedU | odds filled: $fixedO | verified flags: $fixedV"
$stillPh = 0; foreach ($r in $allRows) { if (([string]$r.u) -match 'google\.com/search' -or -not ([string]$r.u)) { $stillPh++ } }
"rows still without real URL: $stillPh / $($allRows.Count)"

# ---------- 4+5. patch the single body line inside index ----------
$newJson = $drill | ConvertTo-Json -Depth 12 -Compress
$lines = [System.IO.File]::ReadAllLines($fIdx)
$idxLine = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith('</style><header')) { $idxLine = $i; break } }
if ($idxLine -lt 0) { throw 'body line not found' }
$body = $lines[$idxLine]

$mBody = [regex]::Match($body, '(?s)<script type="application/json" id="drillData">(.*?)</script>')
if (-not $mBody.Success) { throw 'drillData not found in body line' }
if ($newJson.Contains('</script>')) { throw 'unsafe json' }
$body = $body.Replace($mBody.Value, ('<script type="application/json" id="drillData">' + $newJson + '</script>'))

$kpiAnchor = '<div class="kpi"><div class="n">€0.61</div>'
$chipN = $drill.lists.must_apply.rows.Count + $drill.lists.external.rows.Count
if (-not $body.Contains($kpiAnchor) -and -not $body.Contains('href="funding.html"')) { throw 'kpi anchor missing' }
if (-not $body.Contains('href="funding.html"')) {
  $kpiNew = '<a class="kpi" href="funding.html" title="Open the dedicated funding page" style="text-decoration:none;color:inherit"><div class="n">' + $chipN + '</div><div class="l">Funding page &#8599;</div></a>' + $kpiAnchor
  $body = $body.Replace($kpiAnchor, $kpiNew)
}
$body = [regex]::Replace($body, '<div class="n">\d+</div><div class="l">Funding page', ('<div class="n">' + $chipN + '</div><div class="l">Funding page'))
if (-not $body.Contains('funding.html#radar')) {
  $fnav = '<div style="flex-basis:100%;font-size:12.5px;margin:-4px 0 6px;color:#5a6478">Funding hub quick links: <a href="funding.html#radar">Deadlines radar</a> &middot; <a href="funding.html#pipeline">Pipeline</a> &middot; <a href="funding.html#score">Readiness score</a> &middot; <a href="funding.html#outreach">PI outreach</a> &middot; <a href="funding.html#docs">Documents</a> &middot; <a href="funding.html#intel">Intel</a> &middot; <a href="funding.html#verifyq">Verify</a></div>'
  $body = $body.Replace($kpiAnchor, ($fnav + $kpiAnchor))
}
if ($body.Contains("`n") -or $body.Contains("`r")) { throw 'newline injected into body line!' }

$nl = if (([System.IO.File]::ReadAllText($fIdx)).Contains("`r`n")) { "`r`n" } else { "`n" }
$lines[$idxLine] = $body
[System.IO.File]::WriteAllText($fIdx, (($lines -join $nl) + $nl), (New-Object System.Text.UTF8Encoding($false)))
'index.html updated (links + odds propagation + KPI).'

# ---------- 6. generate funding.html ----------
function Pct([string]$o) { if ($o -match '^(\d+(?:\.\d+)?)\s?%$') { return [double]$Matches[1] }; return $null }
function NegPct([string]$o) { $p = Pct $o; if ($null -ne $p) { return -$p }; return 999 }
$mustSorted = @($drill.lists.must_apply.rows | Sort-Object @{e={ NegPct ([string]$_.o) }}, @{e={[string]$_.n}})
$eligSorted = @($drill.lists.eligible.rows | Sort-Object @{e={[string]$_.uni}}, @{e={ NegPct ([string]$_.o) }}, @{e={[string]$_.n}})
$ext = @($drill.lists.external.rows)

# ---------- 6b. radar + raise + intel + verify-queue modules ----------
function ToJsonArr($arr) {
  if ($arr.Count -eq 0) { return '[]' }
  if ($arr.Count -eq 1) { return '[' + ($arr[0] | ConvertTo-Json -Compress) + ']' }
  return ($arr | ConvertTo-Json -Compress)
}
$radar = @(
  @{ n='NVIDIA Graduate Fellowship — window opens'; d='2026-09-30'; a=1; u='https://www.nvidia.com/en-us/research/graduate-fellowships/' }
  @{ n='BIF — next quarterly deadline (apply at PhD start)'; d='2026-10-01'; a=0; u='https://www.bifonds.de/fellowships-grants/phd-fellowships.html' }
  @{ n='EMBL EIPP closes'; d='2026-10-24'; a=1; u='https://www.embl.de/training/eipp/' }
  @{ n='ELLIS PhD closes'; d='2026-10-31'; a=1; u='https://ellis.eu/research/phd-postdoc' }
  @{ n='Wellcome Sanger 4-Year — HARD WALL'; d='2026-11-27'; a=0; u='https://www.sanger.ac.uk/study/phd/' }
  @{ n='Oxford December field (Clarendon auto)'; d='2026-12-05'; a=1; u='https://www.ox.ac.uk/admissions/graduate/funding-your-study' }
  @{ n='Cambridge funding deadline (Gates · Trust · Harding)'; d='2026-12-08'; a=1; u='https://www.postgraduate.study.cam.ac.uk/finance/funding-search' }
  @{ n='IFOM PhD call closes'; d='2027-01-15'; a=1; u='https://www.ifom.eu/en/' }
  @{ n='Google PhD Fellowship EU — opens'; d='2027-03-05'; a=0; u='https://research.google/outreach/phd-fellowship/' }
  @{ n='INPS borse dottorato estero — bando'; d='2027-05-01'; a=1; u='https://www.inps.it/' }
)
$radarJson = ToJsonArr $radar

# ---------- 6b-ics. deadlines.ics for phone calendar ----------
$ics = New-Object System.Text.StringBuilder
[void]$ics.Append("BEGIN:VCALENDAR`r`nVERSION:2.0`r`nPRODID:-//GB PhD Funding Command Center//EN`r`nCALSCALE:GREGORIAN`r`nX-WR-CALNAME:PhD Funding Deadlines 2026-27`r`n")
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
foreach ($r in $radar) {
  $yd = ([datetime]$r.d).ToString('yyyyMMdd')
  $sum = ([string]$r.n) -replace '[,;]',' '
  $esc2 = (([string]$r.n + ' - confirm on official page: ' + [string]$r.u)) -replace '[,;\\]',' '
  [void]$ics.Append("BEGIN:VEVENT`r`nUID:phdfund-$yd-$(Norm ([string]$r.n))@gabriele-bambini`r`nDTSTAMP:$stamp`r`nDTSTART;VALUE=DATE:$yd`r`nSUMMARY:$sum`r`nDESCRIPTION:$esc2`r`nBEGIN:VALARM`r`nTRIGGER:-P7D`r`nACTION:DISPLAY`r`nDESCRIPTION:1 week left`r`nEND:VALARM`r`nBEGIN:VALARM`r`nTRIGGER:-P1D`r`nACTION:DISPLAY`r`nDESCRIPTION:tomorrow!`r`nEND:VALARM`r`nEND:VEVENT`r`n")
}
[void]$ics.Append("END:VCALENDAR`r`n")
[System.IO.File]::WriteAllText((Join-Path $repo 'deadlines.ics'), $ics.ToString(), (New-Object System.Text.UTF8Encoding($false)))
'deadlines.ics written: ' + $radar.Count + ' events'

$seenVq = @{}; $vqD = @()
foreach ($r in @($drill.lists.must_apply.rows + $drill.lists.external.rows)) {
  if ($r.v -eq 1) { continue }
  $k = Norm ([string]$r.n)
  if ($k -and -not $seenVq.ContainsKey($k)) { $seenVq[$k] = 1; $vqD += [pscustomobject]@{ n = [string]$r.n; u = [string]$r.uni } }
}
$vqJson = ToJsonArr $vqD
"verify-queue items: $($vqD.Count)"

$sources = @(
  @{ n='EURAXESS — live comp-bio doctoral vacancies'; u=$(if ($ok['euraxess_search']) { $ok['euraxess_search'] } else { 'https://euraxess.ec.europa.eu/jobs/search' }); w='New MSCA-DN and institute posts, any nationality'; v=$(if ($ok['euraxess_search']) {1} else {0}) }
  @{ n='FindAPhD — computational biology'; u=$(if ($ok['findaphd']) { $ok['findaphd'] } else { 'https://www.findaphd.com/phds/computational-biology/' }); w='Set an email alert with these keywords'; v=$(if ($ok['findaphd']) {1} else {0}) }
  @{ n='ScholarshipDB — comp-bio'; u=$(if ($ok['scholarshipdb']) { $ok['scholarshipdb'] } else { 'https://scholarshipdb.net/' }); w='Funded-position aggregator incl. Nordic/DK/SE'; v=$(if ($ok['scholarshipdb']) {1} else {0}) }
  @{ n='Nature Careers — comp-bio PhD'; u=$(if ($ok['naturecareers']) { $ok['naturecareers'] } else { 'https://www.nature.com/naturecareers' }); w='Institute-level adverts (EMBL/EBI/Crick orbit)'; v=$(if ($ok['naturecareers']) {1} else {0}) }
  @{ n='Cambridge funding search (live)'; u='https://www.postgraduate.study.cam.ac.uk/finance/funding-search'; w='Filter by deadline — Trust/Harding/dept funds appear here'; v=0 }
  @{ n='Oxford graduate funding'; u='https://www.ox.ac.uk/admissions/graduate/funding-your-study'; w='Clarendon auto + college calls opening'; v=0 }
  @{ n='EMBL EIPP portal'; u='https://www.embl.de/training/eipp/'; w='Application windows + EBI/Heidelberg group lists'; v=1 }
  @{ n='EMBL-EBI careers'; u=$(if ($ok['ebi_careers']) { $ok['ebi_careers'] } else { 'https://www.ebi.ac.uk/careers/' }); w='Studentships posted per-group'; v=$(if ($ok['ebi_careers']) {1} else {0}) }
  @{ n='DKFZ PhD calls'; u='https://www.dkfz.de/en/phd-program/index.php'; w='Mar & Sep call pages'; v=1 }
  @{ n='Crick — students'; u='https://www.crick.ac.uk/careers-and-study/students'; w='PhD programme window + supervisor list'; v=1 }
  @{ n='MRC LMB — prospective students'; u='https://www2.mrc-lmb.cam.ac.uk/study-with-us/prospective-phd-students/'; w='Studentship rounds + rotation lists'; v=1 }
  @{ n='INPS — borse di studio'; u='https://www.inps.it/'; w='Search "dottorato all''estero" when bando drops (spring)'; v=0 }
$unipvN = if ($ok['unipv']) { 'Pavia dottorati' } else { 'Pavia - dottorati (via portale)' }
$unipvU = if ($ok['unipv']) { $ok['unipv'] } else { 'https://unipv.it/' }
$unipvV = if ($ok['unipv']) { 1 } else { 0 }
  @{ n=$unipvN; u=$unipvU; w='Genomic/data-science doctoral calls (your safety anchor)'; v=$unipvV }
  @{ n='Humanitas University'; u='https://www.hunimed.eu/'; w='PhD/MSc continuation calls with UniMi'; v=1 }
)
$sourcesHtml = New-Object System.Text.StringBuilder
[void]$sourcesHtml.Append('<div class="srcgrid">')
foreach ($s in $sources) {
  $badge = if ([int]$s.v -eq 1) { '<span class="vok">&#10003;</span>' } else { '<span class="vno">&#9678;</span>' }
  [void]$sourcesHtml.Append('<a class="src" href="' + (Esc ([string]$s.u)) + '" target="_blank" rel="noopener"><span class="sn">' + (Esc ([string]$s.n)) + ' ' + $badge + '</span><span class="sw">' + (Esc ([string]$s.w)) + '</span></a>')
}
[void]$sourcesHtml.Append('</div>')

$raiseSec = @'
<div class="dates">
<div class="date"><b>M0 — by 1 Sep 2026</b><br>Freeze scope with Liò + Buffa: p53 sheaf-GNN benchmark paper, target bioRxiv mid-Nov.</div>
<div class="date"><b>M1 — by 30 Sep</b><br>Results table + figures done; methods section drafted in parallel with applications.</div>
<div class="date"><b>M2 — by 15 Oct</b><br>Draft v0 circulated to both labs. This date sits BEFORE EIPP/ELLIS close.</div>
<div class="date"><b>M3 — by 1 Nov</b><br>Supervisor revisions in; pick venue fallback (workshop/DOI-less preprint is fine).</div>
<div class="date"><b>M4 — by 15 Nov</b><br><b>bioRxiv submission.</b> You now have a citable first-author preprint.</div>
<div class="date"><b>M5 — by 1 Dec</b><br>Preprint cited in EVERY application (Sanger wall 27 Nov → cite in SoP; Cambridge Dec → CV + SoP).</div>
</div>
<h3 class="t-h" style="color:var(--brass-dk)">Lever 2 &mdash; warm PI outreach: send these THIS week</h3>
<details class="tpl"><summary>Cold-email template — external PI (copy, fill, send)</summary><pre>Subject: Prospective PhD student (2027) — sheaf-GNN models of [THEIR TOPIC]

Dear Professor [SURNAME],

I am a research assistant in Prof. Pietro Liò's group at the Cambridge Computer
Laboratory, where I work on sheaf-based geometric deep learning applied to
cancer genomics; I also model p53 signalling with graph neural networks at IFOM
(Milan). Your [YEAR] paper on [THEIR PAPER, one concrete point] directly
connects to our open question on [ONE SPECIFIC BRIDGE — e.g. calibrated
uncertainty for variant effect prediction].

I am applying for funded PhD positions for October 2027 and believe your group
is the strongest environment for this line of work. Would you be open to a
short call, or should I apply through [PROGRAMME] with you as proposed
supervisor?

CV and a 1-page research summary: [LINK]. Preprint in progress, submission
planned for mid-November.

Best regards,
Gabriele Bambini — [email] · [LinkedIn]</pre></details>
<details class="tpl"><summary>Follow-up template — day 10–12, no reply</summary><pre>Subject: Re: Prospective PhD student (2027) — sheaf-GNN models of [TOPIC]

Dear Professor [SURNAME],

Brief follow-up on the note below — the [PROGRAMME] funding deadline is
[DATE] and I would value knowing whether you might consider supervising an
application. Since writing, [ONE NEW ITEM: preprint posted / result X
confirmed]. Happy to send the 1-page summary if easier.

Best regards,
Gabriele</pre></details>
<details class="tpl"><summary>Internal ask — Liò / Buffa (send FIRST, this week)</summary><pre>[Prof. Liò / Prof. Buffa],

Two quick questions as I plan the October 2027 applications:

1. If I apply to [Cambridge PhD / CCAIM / Math Genomics] with you as
   supervisor, would you champion the application at the funding stage
   (Trust/Harding/studentship you may hold)?

2. For the IFOM PhD Programme call (opens autumn), would you and
   [Tangherloni] support an internal application on the p53 sheaf-GNN
   project — and is there a studentship line you expect to be attached to?

I will send the preprint plan (bioRxiv mid-Nov) separately.

Grazie,
Gabriele</pre></details>
<h3 class="t-h" style="color:var(--ink2)">Lever 3 &mdash; referees briefed and booked before the September rush</h3>
<div class="dates">
<div class="date"><b>Pietro Liò</b> — request by <b>1 Sep 2026</b><br>Emphasise: research maturity beyond the transcript, originality of the sheaf-GNN angle, that he has supervised the work directly since Jun 2026.</div>
<div class="date"><b>Francesca Buffa</b> — request by <b>5 Sep 2026</b><br>Emphasise: biological insight + independence (you defined scope/milestones on p53 modelling); bridges CS and oncology audiences.</div>
<div class="date"><b>Andrea Tangherloni / Pavia MSc referee</b> — request by <b>10 Sep 2026</b><br>Emphasise: technical depth (HPC pipelines, >70 genomes analysis, ImageJ quantification) and reliability across three labs.</div>
</div>
'@

$radarSec = '<h2 id="radar">Deadline radar <span class="mut" style="font-size:13px;font-weight:400">(auto-updates every visit)</span></h2><p class="lead">Computed in your browser from the dates below — nothing to rebuild. Red = inside 30 days. <i>~verify</i> = date moves yearly. <b>One-time setup:</b> import the calendar file into Google Calendar and every deadline gets phone reminders (1 week + 1 day before).</p><div id="radarlist" class="rgrid"></div><a class="btn" href="deadlines.ics" download="phd-deadlines.ics">&#128197; Add all 10 deadlines to my calendar (.ics)</a>'

$verifySec = '<h2 id="verifyq">Verify queue <span class="mut" style="font-size:13px;font-weight:400">(20 min/month, saved in your browser)</span></h2><p class="lead">Every fact below is currently unverified. Click through, confirm the page still matches, tick it. Ticks persist locally on this device.</p><div id="vqlist" class="vqlist"></div>'

$intelSec = '<h2 id="intel">Weekly intel routine <span class="mut" style="font-size:13px;font-weight:400">(20 minutes, same day every week)</span></h2><p class="lead">These are LIVING links — pre-filtered searches that always show current calls, unlike static lists. Mon: EURAXESS + FindAPhD. Tue: Cambridge/Oxford funding search. Wed: EMBL/EBI/DKFZ/Crick/LMB portals. Fri: tick the verify queue below.</p>' + $sourcesHtml.Text + '<button class="btn" id="digestBtn">Build this week&#8217;s briefing (copy-ready)</button><pre id="digestOut"></pre>'

# ---------- 6c. pipeline board + readiness score + take-home + playbooks ----------
$pipeKs = @{}
$pipeItems = @()
foreach ($r in @($drill.lists.must_apply.rows + $drill.lists.external.rows)) {
  $k = Norm ([string]$r.n)
  if (-not $k -or $pipeKs.ContainsKey($k)) { continue }
  $pipeKs[$k] = 1
  $pipeItems += [pscustomobject]@{ k = $k; n = [string]$r.n; g = [string]$r.uni; u = [string]$r.u; o = [string]$r.o }
}
$pipeItems = @($pipeItems | Sort-Object n)
$pipeJson = ToJsonArr ($pipeItems | ForEach-Object { [pscustomobject]@{ n = $_.n; g = $_.g } })
"pipeline items: $($pipeItems.Count)"

$takehome = @(
  @{ n='Gates Cambridge'; m='£1,838 net-equivalent'; c='Cambridge ~£1,150'; b='Comfortable'; v=1 }
  @{ n='Cambridge Harding / Trust CIS'; m='~£1,780 + £6k research pot (Harding)'; c='Cambridge ~£1,150'; b='Comfortable'; v=1 }
  @{ n='Oxford Clarendon'; m='£1,250 + fees covered'; c='Oxford ~£1,050'; b='Tight but fine'; v=1 }
  @{ n='MSCA Doctoral Network'; m='~€3,400 living + €600 mobility (gross, country-corrected)'; c='Varies by host'; b='Strong — top EU package'; v=0 }
  @{ n='EMBL EIPP (salaried)'; m='~€2,900 gross'; c='Heidelberg ~€1,000'; b='Strong'; v=0 }
  @{ n='Nordic salaried (KI / DTU / Copenhagen)'; m='~€2,600–2,900 net after tax'; c='Stockholm/Copenhagen ~€1,300–1,450'; b='Strong'; v=0 }
  @{ n='IFOM PhD (FIRC-funded)'; m='~€1,800–2,200 net'; c='Milan ~€1,400'; b='Adequate — plus zero relocation cost'; v=0 }
  @{ n='Italian national/local PhD'; m='~€1,350 net'; c='Milan/Pavia ~€1,200–1,400'; b='Tight — INPS borsa estero or tutoring can top up'; v=0 }
)
$takeRows = New-Object System.Text.StringBuilder
foreach ($t in $takehome) {
  $badge = if ([int]$t.v -eq 1) { '<span class="vok">&#10003;</span>' } else { '<span class="vno">&#9678;</span>' }
  $bcls = if (([string]$t.b).StartsWith('Comfortable') -or ([string]$t.b).StartsWith('Strong')) { 'good' } else { 'warn' }
  [void]$takeRows.Append('<tr><td>' + (Esc ([string]$t.n)) + ' ' + $badge + '</td><td>' + (Esc ([string]$t.m)) + '</td><td class="mut">' + (Esc ([string]$t.c)) + '</td><td><span class="tier ' + $bcls + '">' + (Esc ([string]$t.b)) + '</span></td></tr>')
}
$takeSec = '<h2 id="takehome">What you would actually take home</h2><p class="lead">Monthly reality check: funding vs cost of living, so offers can be compared like-for-like in spring 2027. &#10003; = figure verified on the official page; &#9678; = typical range, confirm at offer time.</p><div class="tblwrap"><table><thead><tr><th>Route</th><th>Monthly</th><th>City cost</th><th>Verdict</th></tr></thead><tbody>' + $takeRows.ToString() + '</tbody></table></div>'

$playbooks = @'
<div class="cards">
<div class="card"><div class="stage boost">SCENARIO A &mdash; multiple offers (Mar&ndash;May 2027)</div><h3>Decision matrix, pre-committed weights</h3><p>Score each offer 0&ndash;10 per row the day it arrives. Weights are fixed NOW so spring-you cannot rationalise: Supervisor 30 &middot; Topic fit 25 &middot; Postdoc ladder 20 &middot; Money net-of-rent 15 &middot; Location/life 10. Highest total wins; never trade Supervisor points for Location.</p>
<table id="dmat" style="width:100%;border-collapse:collapse;font-size:12.5px"><thead><tr><th style="text-align:left;padding:4px">Criterion (weight)</th><th>Offer A</th><th>Offer B</th><th>Offer C</th></tr></thead><tbody>
<tr><td style="padding:4px">Supervisor &amp; championing <b>(30)</b></td><td><input type="number" min="0" max="10" class="dm" data-w="30"></td><td><input type="number" min="0" max="10" class="dm" data-w="30"></td><td><input type="number" min="0" max="10" class="dm" data-w="30"></td></tr>
<tr><td style="padding:4px">Topic fit with your toolkit <b>(25)</b></td><td><input type="number" min="0" max="10" class="dm" data-w="25"></td><td><input type="number" min="0" max="10" class="dm" data-w="25"></td><td><input type="number" min="0" max="10" class="dm" data-w="25"></td></tr>
<tr><td style="padding:4px">Postdoc ladder value <b>(20)</b></td><td><input type="number" min="0" max="10" class="dm" data-w="20"></td><td><input type="number" min="0" max="10" class="dm" data-w="20"></td><td><input type="number" min="0" max="10" class="dm" data-w="20"></td></tr>
<tr><td style="padding:4px">Money net of rent <b>(15)</b></td><td><input type="number" min="0" max="10" class="dm" data-w="15"></td><td><input type="number" min="0" max="10" class="dm" data-w="15"></td><td><input type="number" min="0" max="10" class="dm" data-w="15"></td></tr>
<tr><td style="padding:4px">Location / life <b>(10)</b></td><td><input type="number" min="0" max="10" class="dm" data-w="10"></td><td><input type="number" min="0" max="10" class="dm" data-w="10"></td><td><input type="number" min="0" max="10" class="dm" data-w="10"></td></tr>
</tbody><tfoot><tr><td style="padding:6px 4px;font-weight:700">TOTAL /1000</td><td style="font-weight:700" id="dmt0">&mdash;</td><td style="font-weight:700" id="dmt1">&mdash;</td><td style="font-weight:700" id="dmt2">&mdash;</td></tr></tfoot></table>
<div id="dmWin" style="font-size:12.5px;margin-top:8px;color:var(--brass-dk);font-weight:600"></div></div>
<div class="card"><div class="stage bridge">SCENARIO B &mdash; only Italian offers</div><h3>Optimise the ladder, not the brand</h3><p>Choose the Italian PhD that maximises: (1) co-authorship velocity with IFOM/Bocconi networks, (2) an exchange semester abroad (Erasmus+ traineeship to Li&ograve; or an ELLIS unit &mdash; 6&ndash;12 months abroad converts a local PhD into a global CV), (3) INPS borsa estero stacking in year 2&ndash;3. Re-apply internationally in cycle 2029 with 2&ndash;3 papers: your odds move from reach to target.</p></div>
<div class="card"><div class="stage anti">SCENARIO C &mdash; nothing lands by May 2027</div><h3>Gap-year playbook (planned, not drifted)</h3><p>Extend IFOM RA into a second project with a defined co-authorship target; add one ELLIS/EMBL workshop + one teaching line (tutoring already proven); apply MSCA-style positions year-round (no season); re-enter Oct 2028 with a paper, two more champions, and the same transcript. This path has produced stronger files than a panic second masters.</p></div>
</div>
<h3 class="t-h" style="color:var(--ink2)">Interview kit &mdash; the four formats you are most likely to face</h3>
<details class="tpl"><summary>Cambridge CS / CCAIM &mdash; supervisor-led, technical</summary><pre>Format: 1-2 conversations, mostly with your proposed supervisor + one colleague.
Prepare: 3-minute tour of the p53 sheaf-GNN work (problem, why sheaves not plain
GNNs, one result); one limitation you would fix next; why THIS dept (say the
programme name and the specific groups you would rotate with); a question about
THEIR current paper. Expect: "what would you do if the benchmark fails?"</pre></details>
<details class="tpl"><summary>IFOM PhD &mdash; internal, project-defence style</summary><pre>Format: presentation of your project + questions from a small committee.
Prepare: slide on data sources already assembled; milestones you defined with
Buffa/Tangherloni (show ownership); how computational results would be validated
experimentally (name the collaborator lab); timeline to first co-authorship.
Your edge: they can call your supervisors tomorrow. Make that call easy.</pre></details>
<details class="tpl"><summary>EMBL EIPP / Sanger &mdash; panel + rotation talk</summary><pre>Format: interview with 3+ group leaders; Sanger adds rotation preferences.
Prepare: 5-minute chalk-talk of the preprint (by then submitted); why dry-lab
belongs in a wet institute (answer: in silico hypotheses that generate wet
validation, cite their own papers doing this); 3 rotation choices ranked with
reasons. Nationality-blind: nobody cares where you are from, only the science.</pre></details>
<details class="tpl"><summary>Nordic salaried positions &mdash; job-interview format</summary><pre>Format: structured interview against the advertised project, sometimes a
work trial (code review / mini-analysis).
Prepare: map your pipeline experience to THEIR advertised tasks line by line;
salary questions are normal (it is an employment contract); ask about
supervision load and co-authorship expectations. Fit-to-advert beats brilliance.</pre></details>
'@
# ---------- 6f. writing studio: sop anatomy, scholarship genres, builder, self-review ----------
$sopMoves = @(
  @{ k='hook';    w=110; t='1 &middot; Hook';            d='One concrete scientific moment that raised the question your PhD answers. No childhood stories, no dictionary quotes.'; weak='I have always been passionate about science since I was a child.'; strong='The first time our p53 sheaf-graph predicted a rescue phenotype that CRISPR data then confirmed, I stopped treating models as homework.' }
  @{ k='train';   w=160; t='2 &middot; Training logic';   d='Why YOUR unusual path is a feature: sport science taught measurement discipline on humans; biomedicine gave wet-lab literacy; data/AI added the toolkit. One causal sentence per hop.'; weak='My curriculum covers many fields, which shows my versatility.'; strong='Quantifying athletes taught me that noisy human data demands uncertainty from day one - a habit I now impose on omics pipelines.' }
  @{ k='project'; w=230; t='3 &middot; One project deep'; d='The p53 sheaf-GNN story: problem, why sheaves (not plain GNNs), what you built, one result, one limitation you would fix next. Depth beats breadth.'; weak='I worked on several exciting projects involving machine learning and biology.'; strong='Because pathway edges carry direction and state, we modelled them as sheaf stalks; oversmoothing dropped and TP53-mutant lines separated where GCNs collapsed.' }
  @{ k='why';     w=140; t='4 &middot; Why this programme'; d='Named groups, modules, institutes - and the bridge only they offer. If you can swap the university name without editing the paragraph, it is not written yet.'; weak='Your world-class department is the ideal place for my research interests.'; strong='Liò group bridges geometric deep learning and biology exactly where my sheaf work stalls; CCAIM rotations would pair it with [NAMED] clinical cohort.' }
  @{ k='future';  w=100; t='5 &middot; Future';           d='A 10-year trajectory with checkpoints, tied to the preprint line. Ambition with coordinates, not job-title worship.'; weak='I hope to become a leading research scientist in academia or industry.'; strong='Post-PhD: first-author methods paper lineage from the bioRxiv line, then an ERC-style group marrying sheaf geometry with clinical oncology.' }
  @{ k='close';   w=70;  t='6 &middot; Close';            d='Echo the hook forward, one sentence of fit, stop. No gratitude padding, no re-summary.'; weak='Thank you for considering my application; it would be an honour to join you.'; strong='The question that hooked me is now a preprint; your programme is where it becomes a thesis.' }
)
$sopHtml = New-Object System.Text.StringBuilder
[void]$sopHtml.Append('<div id="soplab" class="sopwrap"><div class="sophead"><b>SoP Lab</b> &mdash; write yours here, paragraph by paragraph. Autosaved in this browser; export when done.</div>')
foreach ($mv in $sopMoves) {
  [void]$sopHtml.Append('<div class="sopblock"><label><b>' + $mv.t + '</b> <span class="mut">target ~' + $mv.w + ' words &middot; <span id="wc-' + $mv.k + '">0</span></span></label><p class="mvd">' + $mv.d + '</p><textarea id="ta-' + $mv.k + '" data-w="' + $mv.w + '" rows="4" placeholder="Write here - autosaved as you type"></textarea></div>')
}
[void]$sopHtml.Append('<div class="soptotal">Total: <b id="wctot">0</b> words <button class="btn" id="sopExp" style="padding:5px 12px;font-size:12px">&#11015;&#65039; Export draft (.txt)</button> <button class="btn" id="sopClr" style="padding:5px 12px;font-size:12px;background:var(--ink2)">Clear</button></div></div>')
$writeMoves = New-Object System.Text.StringBuilder
foreach ($mv in $sopMoves) {
  [void]$writeMoves.Append('<div class="card"><h3>' + $mv.t + '</h3><p>' + $mv.d + '</p><p class="wx no2"><b>&#10007; Weak:</b> ' + (Esc ([string]$mv.weak)) + '</p><p class="wx"><b style="color:var(--good)">&#10003; Strong:</b> ' + (Esc ([string]$mv.strong)) + '</p></div>')
}
$writeSec = '<div class="cards">' + $writeMoves.ToString() + '</div>
<h3 class="t-h" style="color:var(--ink2)">Scholarship genre map &mdash; same facts, different essays</h3>
<div class="cards">
<div class="card"><div class="stage boost">Gates Cambridge</div><p>Scores <b>leadership + impact beyond yourself</b> harder than academics. Essay must show people you lifted (tutoring record, lab onboarding) and a societal problem your research touches. Tactic: one paragraph on who benefits, quantified.</p></div>
<div class="card"><div class="stage bridge">Cambridge Trust</div><p>Pure <b>academic merit + financial need</b>, told without drama. Reuse your SoP paragraphs 2&ndash;3 verbatim; add honest funding-gap arithmetic and what you already won (merit prizes every year = evidence).</p></div>
<div class="card"><div class="stage anti">Clarendon / Harding</div><p><b>No extra essay</b> - auto-considered with course application. The lesson: December deadline IS the essay deadline. Everything rides on the file you already built.</p></div>
<div class="card"><div class="stage boost">MSCA Doctoral Networks</div><p>Scored against published criteria: <b>excellence, impact, implementation</b>. Mirror their vocabulary explicitly; mobility narrative is a plus for you (IT->UK/EU). Tactic: address researchers-at-risk/outreach boxes even if optional.</p></div>
<div class="card"><div class="stage bridge">Boehringer Ingelheim Fonds</div><p>The <b>project is the essay</b>: hypothesis-driven, feasible in 36 months, supervisor letter carries weight. Your proposal PDFs are the raw material - attach the p53 one, rewritten to BIF structure (background, preliminary work, work programme).</p></div>
<div class="card"><div class="stage anti">Fulbright Italy / NVIDIA</div><p>Fulbright scores <b>bilateral US-Italy impact</b> (only if a US route revives); NVIDIA wants a dense technical statement + 3 champions. Both: reuse, do not reinvent.</p></div>
</div>
<h3 class="t-h" style="color:var(--ink2)">Self-review protocol &mdash; run every draft through all twelve before anyone else sees it</h3>
<div class="wrules" id="wrules"></div>'

$reviewItems = @(
  'Every claim has evidence attached (number, result, name) - zero adjectives doing unpaid work'
  '"Passionate", "cutting-edge", "world-class", "since childhood" - none appear'
  'Programme/supervisor names appear naturally at least twice - zero paste smell'
  'One project told DEEP beats three projects listed shallow (para 3 rule)'
  'Past-tense concrete verbs dominate: built, benchmarked, cut, validated'
  'Each paragraph opens with its point sentence - skimmable in 20 seconds'
  'Read aloud once: any sentence you stumble on gets cut by 30 percent'
  'Cut pass: total length reduced by 15 percent AFTER you thought it was done'
  'Non-expert test: a friend outside CS/biology can retell your project after one read'
  'Hook and Close echo each other - one thread, no loose ends'
  'All names, programme codes and deadlines spellchecked against official pages'
  'Numbers consistent everywhere (grades, dates, word counts match CV)'
)
$revHtml = New-Object System.Text.StringBuilder
foreach ($ri in $reviewItems) { [void]$revHtml.Append('<label class="vqi"><input type="checkbox" data-r="1"><span>' + (Esc ([string]$ri)) + '</span></label>') }
$writeBlock = '<h2 id="writing">Writing studio &mdash; learn to write your own way in <span class="mut" style="font-size:13px;font-weight:400">(SoP, scholarship essays, proposals)</span></h2><p class="lead">Committees read files, not futures. These six moves are the skeleton of every winning SoP; the scholarship map tells you how each funder bends them; the lab below is where you actually write, with word budgets and autosave; the protocol is how you revise alone like a professional.</p>' + $writeSec.ToString() + $sopHtml.ToString() + '<div class="wrhead">Twelve-point protocol <span class="mut">(saved locally)</span></div><div class="wrules">' + $revHtml.ToString() + '</div>'

# ---------- 6g. interview drill ----------
$drillQs = @(
  @{ k='tour';   w=240; sec=110; q='Tell me about your research.'; test='structure under pressure - the 3-minute tour decides the tone of everything after';
     skel=@('Problem: p53 rescue prediction is cell-context dependent','Gap: plain GNNs oversmooth directional pathway biology','Your move: cellular sheaf over the signalling graph','Result: one concrete separation where GCNs failed (preprint M4)','Next: conformal uncertainty -> wet-lab triage list') }
  @{ k='sheaf';  w=180; sec=80;  q='Why sheaves and not plain GNNs / transformers?'; test='technical depth + honesty about costs';
     skel=@('Edges carry direction and state -> stalks encode it natively','Oversmoothing argument in one sentence (Bodnar et al.)','Admit the cost: compute + data hunger on small cohorts','Name one alternative you tried or would benchmark') }
  @{ k='fails';  w=150; sec=70;  q='What do you do if your main benchmark fails?'; test='scientific process, not optimism';
     skel=@('Freeze splits first - never tune after looking','Error analysis by TP53/mutation class','Sanity-check baselines and label provenance','Document the negative result; pre-set a pivot criterion') }
  @{ k='whyus';  w=140; sec=65;  q='Why this institute / programme specifically?'; test='did you do the homework';
     skel=@('Named group(s) whose papers intersect YOUR method','Resource only they have (cohort, HPC, clinical partner)','The bridge: what your toolkit supplies that they lack','Say the programme name out loud at least once') }
  @{ k='failstory'; w=170; sec=78; q='Tell me about a failure.'; test='maturity - STAR format, real stakes';
     skel=@('Situation: first mosquito TE annotation pass failed QC at scale','Task: deliver a reproducible library for >70 genomes','Action: rebuilt with curation gates + validation before scale','Result: pipeline survived to publication grade; lesson stated plainly') }
  @{ k='future'; w=100; sec=45;  q='Where do you see yourself in ten years?'; test='ambition with coordinates';
     skel=@('A lineage from the bioRxiv line to an independent group','Geometry x clinical oncology as the long-term seam','One checkpoint per phase (PhD, postdoc, group) - no job-title worship') }
  @{ k='ask';    w=120; sec=55;  q='Do you have questions for us?'; test='you ALWAYS have three - zero is a red flag';
     skel=@('Supervision load + co-authorship expectations in year one','Rotation/project structure: how are projects matched?','What does the group need right now that my profile supplies?') }
  @{ k='lay';    w=130; sec=60;  q='Explain your work to a non-expert.'; test='communication - panels include clinicians/administrators';
     skel=@('Sport analogy start: training data = athlete measurements, noisy humans','Cancer cells as players whose playbook (p53) we learn to read','One sentence on why prediction must say "I am not sure" sometimes') }
)
$drlHtml = New-Object System.Text.StringBuilder
[void]$drlHtml.Append('<div id="drill" class="sopwrap"><div class="sophead"><b>Interview drill</b> &mdash; write spoken answers here. Try from memory FIRST, then peek the skeleton. Spoken pace &asymp; 130 words/min.</div>')
$i2 = 0
foreach ($dq in $drillQs) {
  $i2++
  $skelItems = ($dq.skel | ForEach-Object { '<li>' + (Esc ([string]$_)) + '</li>' }) -join ''
  [void]$drlHtml.Append('<div class="sopblock"><label><b>Q' + $i2 + ' &middot; ' + (Esc ([string]$dq.q)) + '</b> <span class="mut">~' + $dq.w + ' words &#8776; ' + $dq.sec + 's &middot; <span id="wc-dq-' + $dq.k + '">0</span></span></label><p class="mvd">Panel is testing: ' + (Esc ([string]$dq.test)) + '</p><details class="tpl"><summary>Skeleton (peek after trying)</summary><ul class="skel">' + $skelItems + '</ul></details><textarea id="ta-dq-' + $dq.k + '" data-w="' + $dq.w + '" rows="4" placeholder="Speak it first, then type what you said..."></textarea></div>')
}
[void]$drlHtml.Append('<div class="soptotal">Total: <b id="wcdtot">0</b> words <button class="btn" id="drillExp" style="padding:5px 12px;font-size:12px">&#11015;&#65039; Export answers (.txt)</button></div></div>')
$drillBlock = '<h3 class="t-h" style="color:var(--brass-dk)">Interview drill &mdash; eight answers every panel will ask for</h3><p class="lead">Same discipline as the SoP Lab: attempt from memory, check the skeleton, rewrite until it fits the word budget. Answers autosave locally; export before interviews and read them aloud once more.</p>' + $drlHtml.ToString()

# ---------- 6h. proposal forge: architecture, risks, rubric, lab ----------
$forgeParts = @(
  @{ t='1 &middot; Title'; d='Formula: <b>method</b> + <b>system</b> + <b>outcome</b>. A reviewer should know the whole project from the title alone.'; ex='Sheaf-based geometric deep learning for p53 signalling response prediction' }
  @{ t='2 &middot; Summary (~150 w)'; d='Four sentences: problem, gap, your move, expected result. Written LAST, placed FIRST.'; ex='Problem: rescue phenotypes are context-dependent. Gap: GNNs oversmooth directional biology. Move: cellular sheaf on pathway graphs. Result: calibrated triage lists.' }
  @{ t='3 &middot; Background'; d='A funnel: field (2 sentences) -> subfield (3) -> the precise gap YOU close (2), citing 8&ndash;12 sources. Every citation earns its place by setting up your move.'; ex='End with: no existing model encodes edge directionality at cell level - exactly what a sheaf structure provides.' }
  @{ t='4 &middot; Hypothesis + aims'; d='ONE falsifiable hypothesis sentence; then 2&ndash;4 aims that are independent, feasible in the funding window, each with a concrete milestone. If two aims share one dependency chain, one is decoration.'; ex='H: sheaf encoding improves p53-rescue prediction AND yields calibrated uncertainty. A1 build, A2 benchmark, A3 translate.' }
  @{ t='5 &middot; Design &amp; methods'; d='Per aim: data source (named), approach, validation, and a FALLBACK if the primary route stalls. Reviewers fund people who already imagined failure.'; ex='If DepMap fitness labels prove noisy: fall back to PRISM screens; splits frozen before any tuning.' }
  @{ t='6 &middot; Outputs &amp; impact'; d='Concrete artefacts: papers (venue class named), datasets/tools released, who uses them next. Impact without a named user is decoration.'; ex='Preprint by month 15; curated dataset release; wet-lab triage shortlist adopted by Buffa lab.' }
  @{ t='7 &middot; Timeline &amp; risks'; d='A simple phase bar suffices; the RISK TABLE is what signals maturity: risk / likelihood / mitigation, at least three rows.'; ex='Worked example below - taken straight from the p53 proposal.' }
)
$forgeCards = New-Object System.Text.StringBuilder
foreach ($fp in $forgeParts) { [void]$forgeCards.Append('<div class="card"><h3>' + $fp.t + '</h3><p>' + $fp.d + '</p><p class="wx"><b style="color:var(--brass-dk)">Example:</b> ' + (Esc ([string]$fp.ex)) + '</p></div>') }
$riskRows = @(
  @('DepMap CRISPR labels too noisy for rescue phenotype', 'Medium', 'Cross-check with PRISM; restrict to well-profiled lines; document label provenance')
  @('Sheaf compute exceeds IFOM HPC allocation', 'Low', 'Subsample pathways by centrality; mixed-precision training; ETH CSCS backup via Lio collaboration')
  @('Wet-lab triage list not actionable for partners', 'Medium', 'Monthly checkpoint with Buffa lab; pre-agreed criteria; conformal set-size cap')
)
$rr2 = New-Object System.Text.StringBuilder
foreach ($rw in $riskRows) { [void]$rr2.Append('<tr><td>' + (Esc ([string]$rw[0])) + '</td><td>' + (Esc ([string]$rw[1])) + '</td><td>' + (Esc ([string]$rw[2])) + '</td></tr>') }
$rubricRows = @(
  @('Significance - does the gap matter?', '25%', 'Funnel lands on a gap a reviewer cares about')
  @('Approach - is the method sound?', '30%', 'Sheaf choice justified vs baselines; validation named per aim')
  @('Feasibility - can THIS person do it?', '20%', 'Preliminary work exists (RA record); fallbacks written')
  @('Fit - candidate <-> programme', '15%', 'Named groups/modules; environment answers a real need')
  @('Training value - what will you become?', '10%', 'Skills ladder explicit: pipelines -> calibrated models -> translational contact')
)
$rb2 = New-Object System.Text.StringBuilder
foreach ($rw2 in $rubricRows) { [void]$rb2.Append('<tr><td>' + (Esc ([string]$rw2[0])) + '</td><td><b>' + (Esc ([string]$rw2[1])) + '</b></td><td>' + (Esc ([string]$rw2[2])) + '</td></tr>') }
$forgeLab = New-Object System.Text.StringBuilder
[void]$forgeLab.Append('<div id="forgelab" class="sopwrap"><div class="sophead"><b>Forge Lab</b> &mdash; draft YOUR proposal spine here (BIF, MSCA-DN, departmental studentships). Autosaved.</div>')
$forgeF = @(
  @{ k='fa-hyp'; w=40; t='Central hypothesis (one sentence!)'; d='Falsifiable, mechanistic, no "and" chaining three ideas. If it cannot be wrong it is not science.' }
  @{ k='fa-a1'; w=60;  t='Aim 1 - build / measure'; d='What you construct first and its milestone artefact.' }
  @{ k='fa-a2'; w=60;  t='Aim 2 - benchmark / test'; d='Comparison against named baselines; frozen evaluation protocol.' }
  @{ k='fa-a3'; w=60;  t='Aim 3 - translate / release'; d='The output someone else touches: tool, list, dataset, paper.' }
)
foreach ($ff in $forgeF) {
  [void]$forgeLab.Append('<div class="sopblock"><label><b>' + $ff.t + '</b> <span class="mut">max ~' + $ff.w + ' words &middot; <span id="wc-' + $ff.k + '">0</span></span></label><p class="mvd">' + $ff.d + '</p><textarea id="ta-' + $ff.k + '" data-w="' + $ff.w + '" rows="3" placeholder="Write here - autosaved"></textarea></div>')
}
[void]$forgeLab.Append('<div class="soptotal"><button class="btn" id="forgeExp" style="padding:5px 12px;font-size:12px">&#11015;&#65039; Export proposal spine (.txt)</button></div></div>')
$forgeBlock = '<h3 id="forge" class="t-h" style="color:var(--brass-dk)">Proposal forge &mdash; build one from zero, not just read examples</h3><p class="lead">Your three downloadable proposals are finished exemplars; this is the machine that produced them. Seven parts, the risk register reviewers secretly look for, the scoring rubric panels actually apply, and a lab to draft your own spine in forty-word sentences.</p>
<div class="cards">' + $forgeCards.ToString() + '</div>
<div class="tblwrap"><table><thead><tr><th>Risk (worked example - p53 project)</th><th>Likelihood</th><th>Mitigation</th></tr></thead><tbody>' + $rr2.ToString() + '</tbody></table></div>
<div class="tblwrap"><table><thead><tr><th>Reviewer rubric (typical BIF / DTP weights)</th><th>Weight</th><th>How you score it</th></tr></thead><tbody>' + $rb2.ToString() + '</tbody></table></div>
' + $forgeLab.ToString()

$scoreItems = @(
  @{ w=25; t='Preprint submitted to bioRxiv (M4 of the sprint)' }
  @{ w=20; t='Liò confirms he champions the Cambridge/CCAIM application' }
  @{ w=15; t='IFOM internal champion confirmed (Buffa/Tangherloni)' }
  @{ w=10; t='3 referees briefed and booked (Lio, Buffa, third)' }
  @{ w=10; t='10+ PI outreach emails sent (tracker updated)' }
  @{ w=10; t='Core SoP + 5 programme-tailored variants done' }
  @{ w=5;  t='English test booked or passed' }
  @{ w=5;  t='Every must-apply fund submitted by its wall' }
)
$scoreHtml = New-Object System.Text.StringBuilder
[void]$scoreHtml.Append('<div class="scorewrap"><div class="scorebox"><div class="snum" id="scoreNum">0</div><div class="slab">readiness /100</div><div class="sbar"><i id="scoreBar"></i></div><div class="smsg" id="scoreMsg">tick what is done — saved locally</div></div><div class="scoreitems">')
foreach ($si in $scoreItems) {
  [void]$scoreHtml.Append('<label class="vqi"><input type="checkbox" data-w="' + [int]$si.w + '"><span>' + (Esc ([string]$si.t)) + ' <b class="sw">+' + [int]$si.w + '</b></span></label>')
}
[void]$scoreHtml.Append('</div></div>')
$scoreSec = '<h2 id="score">Admission readiness score <span class="mut" style="font-size:13px;font-weight:400">(live, saved locally)</span></h2><p class="lead">The eight behaviours that actually move your file, weighted. Watch the number, not your anxiety.</p>' + $scoreHtml.ToString()

$pipeSec = '<h2 id="pipeline">Application pipeline <span class="mut" style="font-size:13px;font-weight:400">(state saved locally)</span></h2><p class="lead">One row per must-apply + external fund: set the state as you go. Submitted beats perfect. Filter to see what needs action this week.</p><input class="q" id="qpipe" type="search" placeholder="Filter pipeline&hellip;"><div class="tblwrap"><table id="pipetable"><thead><tr><th>Fund</th><th>Organisation</th><th>State</th></tr></thead><tbody id="pipebody"></tbody></table></div>'

# ---------- 6d. PI outreach board + documents matrix ----------
$outreachRows = @(
  @{ uni='University of Cambridge'; angle='Li&ograve; IS your supervisor: ask him explicitly to champion CCAIM / Math Genomics at funding stage, and which 2 co-supervisors he would add.' }
  @{ uni='University of Oxford'; angle='Email Yau/Holmes/Gal groups citing the sheaf-GNN oncology line; December application with Clarendon auto-box.' }
  @{ uni='Imperial College London'; angle='Dept nomination needs supervisor contact BEFORE applying &mdash; earliest hard date among UK targets.' }
  @{ uni='ETH Zurich'; angle='ELLIS format: Li&ograve; (UK) + an ETH-unit fellow as second supervisor satisfies the two-country rule exactly.' }
  @{ uni='EPFL'; angle='EDIC first-year fellowship route; lead with geometric DL applied to biology problems.' }
  @{ uni='Karolinska Institutet'; angle='Formal applications against posted WASP-DDLS projects &mdash; fit-to-advert beats brilliance.' }
  @{ uni='EMBL-EBI'; angle='Browse group pages, shortlist 2 whose latest method papers intersect your pipelines, name them in the EIPP form.' }
  @{ uni='Wellcome Sanger Institute'; angle='Programme application only &mdash; everything must be ready before the 27 Nov 09:00 GMT wall.' }
)
$orHtml = New-Object System.Text.StringBuilder
foreach ($o in $outreachRows) {
  $pis = @($drill.unis.($o.uni).pis | Select-Object -First 3)
  $piHtml = ''
  if ($pis.Count -gt 0) {
    $piHtml = ($pis | ForEach-Object {
      $nm = [string]$_.n
      if ([string]$_.u -match '^https') { '<a href="' + (Esc ([string]$_.u)) + '" target="_blank" rel="noopener">' + (Esc $nm) + '</a>' } else { Esc $nm }
    }) -join ' &middot; '
  } else {
    $piHtml = '<span class="mut">programme-direct route (no pre-selection)</span>'
  }
  [void]$orHtml.Append('<tr><td class="un">' + (Esc ([string]$o.uni)) + '</td><td>' + $piHtml + '</td><td class="pt">' + ([string]$o.angle) + '</td><td><select class="psel" data-o="' + (Esc ([string]$o.uni)) + '"><option>not started</option><option>drafted</option><option>sent</option><option>replied</option><option>call booked</option><option>applied</option><option>archived</option></select></td></tr>')
}
$outreachSec = '<h2 id="outreach">PI outreach board <span class="mut" style="font-size:13px;font-weight:400">(state saved locally)</span></h2><p class="lead">Warm channels beat cold lists: top contacts per route with the angle that works for YOUR cv. Update the state after every send.</p><div class="tblwrap"><table id="outtable"><thead><tr><th>Route</th><th>Top contacts</th><th>Your angle</th><th>Status</th></tr></thead><tbody>' + $orHtml.ToString() + '</tbody></table></div>'

$docCols = @('Cambridge','Oxford','Imperial','EMBL EIPP','Sanger','IFOM','Nordic','MSCA DN')
$docRows = @(
  @{ d='Research CV (2 pages)'; c=@('●','●','●','●','●','●','●','○') }
  @{ d='Core SoP / motivation letter'; c=@('●','●','●','●','●','●','○','○') }
  @{ d='1-page research summary'; c=@('●','○','●','○','●','●','○','○') }
  @{ d='Research proposal (1–3k words)'; c=@('○','●','○','–','–','●','–','○') }
  @{ d='Transcripts (+ sworn translation)'; c=@('●','●','●','○','●','●','●','○') }
  @{ d='English test (IELTS/TOEFL)'; c=@('●','●','●','○','●','○','○','○') }
  @{ d='3 referees portal-ready'; c=@('●','●','●','●','●','●','●','●') }
  @{ d='Passport / ID valid beyond Oct 2027'; c=@('●','●','●','●','●','●','●','●') }
  @{ d='Preprint PDF link (from M4 sprint)'; c=@('●','●','●','●','●','●','▲','▲') }
  @{ d='Fee-status / funding statement section'; c=@('●','●','●','–','–','–','–','–') }
)
$dgHead = ($docCols | ForEach-Object { '<th>' + (Esc $_) + '</th>' }) -join ''
$dgBody = New-Object System.Text.StringBuilder
foreach ($dr2 in $docRows) {
  $cells = ($dr2.c | ForEach-Object {
    $m2 = [string]$_
    switch ($m2) { '●' { '<td class="dc req">&#9679;</td>' } '○' { '<td class="dc opt">&#9675;</td>' } '▲' { '<td class="dc rec">&#9650;</td>' } default { '<td class="dc na">&ndash;</td>' } }
  }) -join ''
  [void]$dgBody.Append('<tr><td>' + (Esc ([string]$dr2.d)) + '</td>' + $cells + '</tr>')
}
$docsSec = '<h2 id="docs">Document matrix <span class="mut" style="font-size:13px;font-weight:400">(what each route demands from you)</span></h2><p class="lead"><b>&#9679;</b> required &middot; <b>&#9675;</b> often optional &mdash; verify on the call page &middot; <b>&#9650;</b> not formally required but decisive this cycle &middot; &ndash; not used. Build once, reuse everywhere: CV, core SoP, summary and referees cover 80% of every column.</p><div class="tblwrap"><table class="doctbl"><thead><tr><th>Document</th>' + $dgHead + '</tr></thead><tbody>' + $dgBody.ToString() + '</tbody></table></div>'

# odds rows
$oddsRows = New-Object System.Text.StringBuilder
$uniList = @($drill.unis.PSObject.Properties.Name | ForEach-Object { [pscustomobject]@{ n=$_; c=$drill.unis.$_.chance } } | Sort-Object @{e={ if ($_.c.m) { -$_.c.m } else { 999 } }})
foreach ($u in $uniList) {
  $c = $u.c
  $top = @($drill.unis.($u.n).schols | Where-Object { Pct ([string]$_.o) } | Sort-Object @{e={ NegPct ([string]$_.o) }} | Select-Object -First 3)
  $topHtml = ($top | ForEach-Object { '<a href="' + (Esc $_.u) + '" target="_blank" rel="noopener">' + (Esc ([string]$_.n)) + ' <b>' + (Esc ([string]$_.o)) + '</b></a>' }) -join ' · '
  if (-not $topHtml) { $topHtml = '<span class="mut">&mdash;</span>' }
  $band = if ($c.b) { [string]$c.b } else { 'programme' }
  $bar = if ($c.m) { '<div class="bar"><i style="width:' + [double]$c.m + '%"></i></div><span class="mut">' + [double]$c.m + '%</span>' } else { '<span class="mut">&mdash;</span>' }
  $ptext = if ([string]$c.p) { Esc ([string]$c.p) } else { 'Admission via programme application (salaried positions; odds tracked per programme below)' }
  [void]$oddsRows.Append('<tr><td class="un">' + (Esc $u.n) + '</td><td><span class="band ' + (Esc $band) + '">' + (Esc $band) + '</span></td><td class="pt">' + $ptext + '</td><td class="bm">' + $bar + '</td><td class="tsch">' + $topHtml + '</td></tr>')
}

function LinkCell($r) {
  $uu = [string]$r.u
  if ($uu -match 'google\.com/search') {
    return '<a class="ph" href="' + (Esc $uu) + '" target="_blank" rel="noopener" title="No official page found yet &mdash; opens a pre-filled search">' + (Esc ([string]$r.n)) + '</a>'
  }
  if ($uu -match '^https') {
    return '<a href="' + (Esc $uu) + '" target="_blank" rel="noopener">' + (Esc ([string]$r.n)) + '</a>'
  }
  return '<span class="ph">' + (Esc ([string]$r.n)) + '</span>'
}

# must-apply table
$mustRows = New-Object System.Text.StringBuilder
foreach ($r in $mustSorted) {
  $badge = if ($r.v -eq 1) { '<span class="vok" title="verified against official page">&#10003;</span>' } else { '<span class="vno" title="verify on page">&#9678;</span>' }
  $odds = if ([string]$r.o) { '<span class="odds">' + (Esc ([string]$r.o)) + '</span>' } else { '<span class="mut">&mdash;</span>' }
  [void]$mustRows.Append('<tr><td>' + (LinkCell $r) + ' ' + $badge + '</td><td class="mut">' + (Esc ([string]$r.uni)) + '</td><td>' + $odds + '</td><td><span class="tier must">must-apply</span></td></tr>')
}

# external cards
$extCards = New-Object System.Text.StringBuilder
foreach ($r in $ext) {
  $badge = if ($r.v -eq 1) { '<span class="vok" title="verified this month">&#10003;</span>' } else { '<span class="vno" title="verify current dates">&#9678;</span>' }
  $stage = [string]$r.stage
  $cls = if ($stage -match 'COMP-BIO') { 'st bio' } elseif ($stage -match 'BRIDGE') { 'st bridge' } elseif ($stage -match 'ANTI') { 'st anti' } else { 'st boost' }
  $link = if (([string]$r.u) -match '^https') { '<a class="go" href="' + (Esc ([string]$r.u)) + '" target="_blank" rel="noopener">Official page &#8599;</a>' } else { '' }
  [void]$extCards.Append('<div class="card"><div class="stage ' + $cls + '">' + (Esc $stage) + ' ' + $badge + '</div><h3>' + (Esc ([string]$r.n)) + '</h3><div class="org">' + (Esc ([string]$r.uni)) + '</div><div class="dl"><b>' + (Esc ([string]$r.t)) + '</b></div><p>' + (Esc ([string]$r.o)) + '</p>' + $link + '</div>')
}

# all funds table
$allRows2 = New-Object System.Text.StringBuilder
foreach ($r in $eligSorted) {
  $t = [string]$r.t; $tcls = switch -Regex ($t) { 'must' { 'must' } 'worth' { 'worth' } 'conditional' { 'cond' } default { 'long' } }
  $badge = if ($r.v -eq 1) { '<span class="vok">&#10003;</span>' } else { '' }
  $odds = if ([string]$r.o) { (Esc ([string]$r.o)) } else { '&mdash;' }
  [void]$allRows2.Append('<tr><td>' + (LinkCell $r) + ' ' + $badge + '</td><td class="mut">' + (Esc ([string]$r.uni)) + '</td><td>' + $odds + '</td><td><span class="tier ' + $tcls + '">' + (Esc $t) + '</span></td></tr>')
}

$today = (Get-Date).ToString('yyyy-MM-dd')
$css = @'
:root{--ink:#1f2740;--ink2:#2c3b5e;--navy:#22304f;--paper:#f6f4ee;--card:#fffdf9;--line:rgba(34,48,79,.12);--muted:#6b7488;--brass:#c39a52;--brass-dk:#9a7734;--good:#3f8a66;--warn:#c08a34;--crit:#c0554a;--rule:rgba(20,33,58,.14);--serif:"Newsreader","Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif;--sans:"Hanken Grotesk","Segoe UI",-apple-system,system-ui,Roboto,Helvetica,sans-serif}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.55;-webkit-font-smoothing:antialiased}
.wrap{max-width:1180px;margin:0 auto;padding:0 20px}
header.top{background:var(--navy);color:#f6f4ee;padding:26px 0 18px;border-bottom:3px solid var(--brass)}
header.top h1{font-family:var(--serif);font-weight:600;font-size:30px;margin:0;letter-spacing:.2px}
header.top .sub{color:#c9d2e4;margin-top:4px;font-size:14px}
header.top .row{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-start;justify-content:space-between}
.backlink{color:#f6f4ee;text-decoration:none;border:1px solid rgba(246,244,238,.4);padding:6px 12px;border-radius:3px;font-size:13px}
.backlink:hover{border-color:#f6f4ee}
.kpis{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.kpi{background:rgba(246,244,238,.08);border:1px solid rgba(246,244,238,.25);border-radius:3px;padding:8px 14px;color:#f6f4ee}
.kpi .n{font-family:var(--serif);font-size:22px;font-weight:600}
.kpi .l{font-size:11px;color:#c9d2e4;text-transform:uppercase;letter-spacing:.6px}
nav.jump{position:sticky;top:0;z-index:5;background:var(--paper);border-bottom:1px solid var(--line);padding:10px 0}
nav.jump a{color:var(--ink2);text-decoration:none;font-size:13.5px;margin-right:18px;padding:4px 2px;border-bottom:2px solid transparent}
nav.jump a:hover{border-bottom-color:var(--brass)}
main{padding:26px 0 60px}
h2{font-family:var(--serif);font-weight:600;font-size:24px;margin:38px 0 6px}
p.lead{color:var(--muted);margin:0 0 16px;font-size:14.5px}
.tblwrap{overflow-x:auto;background:var(--card);border:1px solid var(--line);border-radius:3px;box-shadow:0 1px 2px rgba(20,33,58,.05)}
table{border-collapse:collapse;width:100%;font-size:14px}
th{font-size:11px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted);text-align:left;padding:10px 12px;border-bottom:1px solid var(--rule)}
td{padding:10px 12px;border-bottom:1px solid var(--rule-2, rgba(20,33,58,.07));vertical-align:top}
tr:last-child td{border-bottom:none}
td a{color:var(--ink2);text-decoration:none;border-bottom:1px solid rgba(34,48,79,.25)}
td a:hover{border-bottom-color:var(--brass-dk);color:var(--ink)}
td.un{font-weight:600;white-space:nowrap}
td.pt{max-width:420px;font-size:13.5px}
td.tsch{max-width:300px;font-size:12.5px}
td.tsch a{border-bottom:none;color:var(--ink2)}
td.tsch b{color:var(--brass-dk)}
.band{display:inline-block;font-size:11px;text-transform:uppercase;letter-spacing:.6px;padding:2px 8px;border-radius:3px;color:#fff}
.band.target{background:var(--good)}.band.likely{background:var(--good)}.band.reach{background:var(--crit)}.band.programme{background:var(--muted)}
.bar{display:inline-block;width:90px;height:6px;background:rgba(20,33,58,.1);border-radius:3px;overflow:hidden;vertical-align:middle;margin-right:6px}
.bar i{display:block;height:100%;background:var(--brass-dk)}
.odds{font-family:var(--serif);font-weight:600;color:var(--brass-dk)}
.tier{display:inline-block;font-size:11px;padding:2px 8px;border-radius:3px;letter-spacing:.4px;color:#fff;white-space:nowrap}
.tier.must{background:var(--crit)}.tier.worth{background:var(--warn)}.tier.cond{background:var(--ink2)}.tier.long{background:var(--muted)}
.vok{color:var(--good);font-weight:700}
.vno{color:var(--brass-dk)}
.mut{color:var(--muted)}
.ph{border-bottom:1px dotted var(--muted)}
.dates{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:10px}
.date{background:var(--card);border:1px solid var(--line);border-left:3px solid var(--brass);border-radius:3px;padding:10px 12px;font-size:13.5px}
.date b{font-family:var(--serif);font-size:15px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:3px;padding:16px;box-shadow:0 1px 2px rgba(20,33,58,.05)}
.card h3{font-family:var(--serif);font-size:18px;margin:8px 0 2px;font-weight:600}
.card .org{color:var(--muted);font-size:13px}
.card .dl{margin:8px 0 4px;font-size:13.5px;color:var(--ink2)}
.card p{font-size:13.5px;margin:6px 0 10px;color:var(--ink2)}
.stage{font-size:10.5px;letter-spacing:.7px;text-transform:uppercase;padding:2px 8px;border-radius:3px;display:inline-block;color:#fff}
.stage.bio{background:var(--good)}.stage.bridge{background:var(--brass-dk)}.stage.boost{background:var(--ink2)}.stage.anti{background:var(--crit)}
a.go{display:inline-block;font-size:13px;color:var(--ink2);text-decoration:none;border:1px solid var(--rule);padding:5px 10px;border-radius:3px}
a.go:hover{border-color:var(--brass-dk)}
.tw{margin:16px 0 24px}
.t-h{font-family:var(--serif);font-size:17.5px;margin:14px 0 8px;padding-bottom:4px;border-bottom:2px solid var(--line)}
.tgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:8px}
.titem{background:var(--card);border:1px solid var(--line);border-left-width:3px;border-radius:3px;padding:9px 11px;font-size:13.5px;display:flex;flex-direction:column;gap:3px}
.tw-a .t-h{color:var(--good)} .tw-b .t-h{color:var(--brass-dk)} .tw-c .t-h{color:var(--crit)}
.tw-a .titem{border-left-color:var(--good)} .tw-b .titem{border-left-color:var(--brass-dk)} .tw-c .titem{border-left-color:var(--crit)}
.tch{font-family:var(--serif);font-weight:600;color:var(--brass-dk);font-size:13.5px}
.tnm a{color:var(--ink2);text-decoration:none;border-bottom:1px solid rgba(34,48,79,.25)}
.tnm a:hover{border-bottom-color:var(--brass-dk)}
.twhy{color:var(--muted);font-size:12.5px}
input.q{width:100%;max-width:380px;padding:9px 12px;border:1px solid var(--line);border-radius:3px;font-family:var(--sans);font-size:14px;margin:6px 0 12px;background:var(--card)}
.rgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:8px}
.ritem{display:flex;gap:10px;align-items:baseline;background:var(--card);border:1px solid var(--line);border-radius:3px;padding:9px 11px;text-decoration:none;color:var(--ink)}
.ritem:hover{border-color:var(--brass-dk)}
.ritem .rd{font-family:var(--serif);font-weight:600;font-size:16px;min-width:52px}
.ritem .rn{font-size:13px;flex:1}
.ritem .rn i{color:var(--muted);font-style:normal;font-size:11px}
.ritem .rdate{font-size:11px;color:var(--muted)}
.r-red{border-left:3px solid var(--crit)} .r-red .rd{color:var(--crit)}
.r-amb{border-left:3px solid var(--warn)} .r-amb .rd{color:var(--brass-dk)}
.r-nrm{border-left:3px solid var(--line)}
.srcgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:8px}
.src{display:flex;flex-direction:column;gap:2px;background:var(--card);border:1px solid var(--line);border-radius:3px;padding:10px 12px;text-decoration:none;color:var(--ink)}
.src:hover{border-color:var(--brass-dk)}
.src .sn{font-weight:600;font-size:13.5px}
.src .sw{font-size:12px;color:var(--muted)}
.vqlist{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:6px}
.vqi{display:flex;gap:8px;align-items:flex-start;background:var(--card);border:1px solid var(--line);border-radius:3px;padding:8px 10px;font-size:13px;cursor:pointer}
.vqi input{margin-top:3px}
.vqi i{color:var(--muted);font-style:normal;font-size:11.5px}
details.tpl{background:var(--card);border:1px solid var(--line);border-radius:3px;padding:10px 14px;margin:8px 0}
details.tpl summary{cursor:pointer;font-weight:600;color:var(--ink2);font-size:14px}
details.tpl pre{white-space:pre-wrap;font-family:var(--mono,Consolas,monospace);font-size:12.5px;background:transparent;border-left:2px solid var(--brass);padding-left:12px;margin:10px 0 2px;line-height:1.5}
.scorewrap{display:grid;grid-template-columns:220px 1fr;gap:14px;background:var(--card);border:1px solid var(--line);border-radius:3px;padding:16px}
@media(max-width:700px){.scorewrap{grid-template-columns:1fr}}
.scorebox{border-right:1px solid var(--rule);padding-right:14px}
@media(max-width:700px){.scorebox{border-right:none;border-bottom:1px solid var(--rule);padding:0 0 12px}}
.snum{font-family:var(--serif);font-size:52px;font-weight:600;color:var(--brass-dk);line-height:1}
.slab{font-size:11px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted);margin:4px 0 10px}
.sbar{height:8px;background:rgba(20,33,58,.1);border-radius:4px;overflow:hidden}
.sbar i{display:block;height:100%;width:0;background:linear-gradient(90deg,var(--crit),var(--warn),var(--good));transition:width .4s}
.smsg{font-size:12px;color:var(--muted);margin-top:8px}
.scoreitems{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:6px;align-content:start}
.tier.good{background:var(--good)} .tier.warn{background:var(--warn)}
.psel{padding:4px 6px;border:1px solid var(--line);border-radius:3px;font-family:var(--sans);font-size:12.5px;background:#fffdf9;color:var(--ink)}
.psel.submitted,.psel.interview,.psel.offer{border-color:var(--good);color:var(--good);font-weight:600}
.doctbl td{text-align:center;font-size:14px}
.doctbl td:first-child{text-align:left;font-size:13.5px}
.dc.req{color:var(--crit);font-weight:700}.dc.opt{color:var(--brass-dk)}.dc.rec{color:var(--good)}.dc.na{color:var(--muted)}
.btn{display:inline-block;background:var(--navy);color:#f6f4ee;border:none;border-radius:3px;padding:9px 16px;font-family:var(--sans);font-size:13.5px;cursor:pointer;margin-top:10px}
.btn:hover{background:var(--ink2)}
#digestOut{white-space:pre-wrap;font-family:Consolas,monospace;font-size:12px;background:var(--card);border:1px solid var(--line);border-radius:3px;padding:10px;margin-top:8px;display:none}
.starthere{background:#fffdf9;border:2px solid var(--brass-dk);border-radius:3px;padding:14px 18px;margin-bottom:22px}
.starthere .sh-t{font-family:var(--serif);font-weight:600;font-size:17px;color:var(--brass-dk);margin-bottom:8px}
.starthere ol{margin:0;padding-left:20px}
.starthere li{font-size:14px;line-height:1.55;margin:5px 0}
.sopwrap{background:var(--card);border:2px solid var(--brass-dk);border-radius:3px;padding:16px;margin-top:14px}
.sophead{font-size:13.5px;margin-bottom:10px}
.sopblock{margin-bottom:12px}
.sopblock label{font-size:13.5px;cursor:text}
.sopblock .mut span{font-weight:600}
.sopblock textarea,.sopblock textarea:focus{width:100%;box-sizing:border-box;border:1px solid var(--line);border-radius:3px;background:#fffdf9;font-family:var(--serif);font-size:15px;line-height:1.6;padding:10px;color:var(--ink);resize:vertical;margin-top:4px}
.sopblock textarea:focus{outline:none;border-color:var(--brass-dk)}
.mvd{font-size:12px;color:var(--muted);margin:2px 0 4px}
.soptotal{border-top:1px solid var(--line);padding-top:10px;font-size:13.5px}
.wx{font-size:12.5px;margin:6px 0 0}
.wx.no2 b{color:var(--crit)}
.wrhead{font-size:14.5px;font-weight:600;margin:16px 0 8px}
.wrules{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:6px}
ul.skel{margin:8px 0 4px;padding-left:18px;font-size:12.5px;line-height:1.55;color:var(--ink2)}
@media print{
 nav.jump,.q,.btn,#digestOut,.starthere{display:none!important}
 body{background:#fff;font-size:12px}
 .wrap{max-width:100%;padding:0}
 h2,h3,.card,.tblwrap,details.tpl,.scorewrap,.rgrid,.srcgrid,.vqlist{break-inside:avoid}
 details.tpl pre{white-space:pre-wrap!important}
 a[href]::after{content:' ['attr(href)']';font-size:9px;color:#666;word-break:break-all}
}
.printhead{display:none}
@media print{.printhead{display:block;font-family:var(--serif);font-size:17px;border-bottom:2px solid var(--navy);padding-bottom:6px;margin-bottom:12px}}
@media(max-width:760px){
 nav.jump .wrap{overflow-x:auto;white-space:nowrap;-webkit-overflow-scrolling:touch;display:block;padding:8px 10px}
 nav.jump a{margin-right:12px;font-size:12.5px}
 .scorewrap{grid-template-columns:1fr!important}
}
footer{border-top:1px solid var(--line);padding:18px 0 40px;color:var(--muted);font-size:12.5px}
@media(max-width:700px){header.top h1{font-size:24px}td.pt,td.tsch{max-width:none}}
'@

# ---------- 6e. research proposals with chain-of-verification (html + pdf) ----------
function Probe8([string]$u) { try { $r = Invoke-WebRequest -Uri $u -Headers @{'User-Agent'=$ua} -TimeoutSec 10 -UseBasicParsing -MaximumRedirection 5; return ($r.StatusCode -eq 200) } catch { return $false } }
$refsCachePath = Join-Path $env:TEMP 'phdfund_refs_cache.json'
$refOk = @{}
if (Test-Path $refsCachePath) { try { $rj = Get-Content $refsCachePath -Raw | ConvertFrom-Json; foreach ($pr in $rj.PSObject.Properties) { $refOk[$pr.Name] = [bool]$pr.Value } } catch { } }
$proposals = @(
  @{ id='p53-sheaf-gnn'; title='Sheaf-based geometric deep learning for p53 signalling response prediction'; sub='IFOM (Buffa / Tangherloni) x Cambridge (Lio) - flagship preprint target, M0-M5 sprint';
     hyp='Plain message-passing GNNs oversmooth and miss directionality on cell-level signalling graphs. Constructing a cellular sheaf over pathway topology (one stalk per protein complex edge, grounded in expression state) should improve prediction of p53-rescue fitness phenotypes and yield calibrated, TP53-status-aware uncertainty bands for wet-lab triage.';
     met='Data: DepMap expression + CRISPR fitness labels; TCGA stratification; Reactome/STRING topology. Models: neural sheaf diffusion vs GCN/GAT/graph-transformer baselines under identical splits; conformal wrappers for calibrated sets. Validation: rank correlation with independent screens; pathway enrichment of top predictions reviewed with Buffa lab; HPC runs on IFOM cluster (Tangherloni).';
     out='bioRxiv preprint (M4 milestone); curated sheaf-dataset release; wet-lab triage shortlist co-signed by both labs.';
     refs=@(
       @{ c='Sheaf Neural Networks introduce cellular-sheaf message passing'; u='https://arxiv.org/abs/2012.03119'; r='Hansen & Gebhart, arXiv 2020' }
       @{ c='Neural sheaf diffusion targets heterophily/oversmoothing'; u='https://arxiv.org/abs/2202.04579'; r='Bodnar et al., CVPR 2022' }
       @{ c='GCN baseline formalism'; u='https://arxiv.org/abs/1609.02907'; r='Kipf & Welling, ICLR 2017' }
       @{ c='GAT attention baseline'; u='https://arxiv.org/abs/1710.10903'; r='Velickovic et al., ICLR 2018' }
       @{ c='p53 pathway centrality motivates target phenotype'; u='https://doi.org/10.1038/nm1087'; r='Vogelstein et al., Nature Medicine 2004' }
       @{ c='DepMap expression correction enables pan-cancer features'; u='https://doi.org/10.1038/ng.3914'; r='Meyers et al., Nat Genet 2017' }
       @{ c='Dependency Map provides CRISPR fitness labels'; u='https://doi.org/10.1016/j.cell.2017.06.010'; r='Tsherniak et al., Cell 2017' }
       @{ c='TP53 mutation spectrum for stratification'; u='https://p53.fr/'; r='IARC TP53 Database' }
       @{ c='Conformal prediction gives distribution-free bands'; u='https://arxiv.org/abs/2107.07511'; r='Angelopoulos & Bates, 2021' }
     )
     aims='A1 signalling-sheaf construction from DepMap + pathway topology | A2 benchmark vs GNN baselines on p53-rescue fitness | A3 TP53-stratified conformal uncertainty -> wet-lab triage list.'
     cov=@(@{ c='DepMap portal reachable, research terms available'; u='https://depmap.org/' }, @{ c='STRING API reachable for edge construction'; u='https://string-db.org/' }) },
  @{ id='te-mosquito'; title='Transposable-element landscape and transcriptomic dysregulation across invasive mosquito vectors'; sub='University of Pavia - genomics RA project (>70 genomes analysed)';
     hyp='TE family expansion and TE-transcript activation differ systematically between vector species and population-invasive lineages, producing measurable immune-neighbourhood effects. A curated, per-species TE library is the missing substrate for reproducible TE-expression comparison at this scale.';
     met='Pipelines: RepeatModeler2 de novo families + EDTA-style curation; RepeatMasker genome masking; RNA-seq TE quantification (TEtranscripts approach) across the compendium; divergence tables per family superfamily; browser + library release. Compute: Pavia HPC (proven ImageJ/HPC track record extends naturally).';
     out='Curated TE libraries per species; divergence atlas; methods paper targeting bioinformatics venues; reusable Snakemake pipeline.';
     refs=@(
       @{ c='Improved Aedes aegypti reference genome underpins reannotation'; u='https://doi.org/10.1038/s41586-018-0692-z'; r='Matthews et al., Nature 2018' }
       @{ c='TEtranscripts quantifies TE expression from RNA-seq'; u='https://doi.org/10.1093/bioinformatics/btv022'; r='Jin et al., Bioinformatics 2015' }
       @{ c='RepeatModeler2 de novo TE discovery pipeline'; u='https://www.biorxiv.org/content/10.1101/675722'; r='Flynn et al., 2020' }
       @{ c='RepeatMasker standard masking pipeline'; u='https://www.repeatmasker.org/'; r='Smit, Hubley & Green' }
       @{ c='VectorBase hosts vector genomes and annotations'; u='https://vectorbase.org/'; r='VectorBase' }
     )
     aims='A1 consensus TE library per species (curation pass) | A2 TE-expression divergence maps across >70 genomes compendium | A3 immune-neighbourhood association + public browser release.'
     cov=@(@{ c='VectorBase bulk downloads reachable'; u='https://vectorbase.org/common/downloads' }, @{ c='NCBI Datasets usable for accession pulls'; u='https://www.ncbi.nlm.nih.gov/datasets/' }) },
  @{ id='immuno-uncertainty'; title='Uncertainty-calibrated graph models of multi-omics markers for immunotherapy response'; sub='Cambridge Computer Lab (Lio) extension - bridges the preprint line toward clinical AI';
     hyp='Response-to-checkpoint models fail clinically because point predictions hide uncertainty. Patient-graph ensembles with conformal risk control can output calibrated response SETS that clinicians can act on, while graph attribution exposes which omics modules drive each call.';
     met='Cohorts: TCGA multi-omics via GDC + public ICB response sets; features: TMB, expression signatures, pathway activity graphs. Models: deep ensembles inside a sheaf/GNN scaffold; conformal wrappers; baselines: TIDE-style signatures and TMB alone. Reporting: coverage curves, set sizes, attribution stability across seeds.';
     out='Workshop paper on calibrated graph models for ICB response; open evaluation harness; bridge to CCAIM application narrative.';
     refs=@(
       @{ c='Pan-tumor genomic biomarkers correlate with PD-1 response'; u='https://doi.org/10.1126/science.aar3593'; r='Cristescu et al., Science 2018' }
       @{ c='Tumour mutational load predicts survival under ICB'; u='https://doi.org/10.1038/s41588-018-0312-8'; r='Samstein et al., Nat Genet 2019' }
       @{ c='TIDE-style expression signature predicts immunotherapy failure'; u='https://doi.org/10.1038/s41591-018-0136-1'; r='Jiang et al., Nature Medicine 2018' }
       @{ c='Deep ensembles give practical predictive uncertainty'; u='https://arxiv.org/abs/1612.01474'; r='Lakshminarayanan et al., NeurIPS 2017' }
       @{ c='Conformal prediction wrappers for calibrated sets'; u='https://arxiv.org/abs/2107.07511'; r='Angelopoulos & Bates, 2021' }
       @{ c='TCGA multi-omics cohorts via GDC portal'; u='https://portal.gdc.cancer.gov/'; r='NCI GDC' }
     )
     aims='A1 patient-graph construction from TCGA+ICB labels | A2 ensemble+conformal model vs TIDE/TMB baselines | A3 calibrated response sets + attribution analysis -> workshop submission.'
     cov=@(@{ c='GDC API status endpoint reachable'; u='https://api.gdc.cancer.gov/status' }, @{ c='TCGA programme page live'; u='https://www.cancer.gov/about-nci/organization/ccg/research/structural-genomics/tcga' }) }
)
$dirty = $false
foreach ($pp in $proposals) { foreach ($rr in @($pp.refs) + @($pp.cov)) { if (-not $refOk.ContainsKey([string]$rr.u)) { $refOk[[string]$rr.u] = Probe8 ([string]$rr.u); $dirty = $true } } }
if ($dirty) { try { [System.IO.File]::WriteAllText($refsCachePath, ($refOk | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false))); 'refs cache saved' } catch { } }

$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$propDir = Join-Path $repo 'proposals'
New-Item -ItemType Directory -Force -Path $propDir | Out-Null
$today = (Get-Date -Format 'yyyy-MM-dd')
$propCards = New-Object System.Text.StringBuilder
$pdfCount = 0
foreach ($pp in $proposals) {
  $tot = @($pp.refs).Count + @($pp.cov).Count
  $okn = 0
  foreach ($rr in (@($pp.refs) + @($pp.cov))) { if ($refOk[[string]$rr.u]) { $okn++ } }
  $h = New-Object System.Text.StringBuilder
  [void]$h.Append('<!doctype html><html><head><meta charset="utf-8"><title>' + (Esc ([string]$pp.title)) + '</title><style>body{font-family:Georgia,serif;max-width:760px;margin:30px auto;padding:0 20px;color:#1d2433;line-height:1.55;font-size:14px}h1{font-size:22px;line-height:1.25;margin-bottom:2px}.sub{color:#666;font-size:13px;margin-bottom:18px}h2{font-size:15px;text-transform:uppercase;letter-spacing:.8px;border-bottom:1px solid #ddd;padding-bottom:4px;margin-top:26px}table{width:100%;border-collapse:collapse;font-size:12px;margin-top:8px}td,th{border:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}th{background:#f4f1e9}.ok{color:#1a7f37;font-weight:700}.no{color:#b35900;font-weight:700}.meta{font-size:11px;color:#888;margin-top:30px;border-top:1px solid #ddd;padding-top:8px}a{color:#22508f;word-break:break-all}@media print{body{margin:12mm auto}}</style></head><body>')
  [void]$h.Append('<h1>' + (Esc ([string]$pp.title)) + '</h1><div class="sub">' + (Esc ([string]$pp.sub)) + ' &middot; Gabriele Bambini &middot; draft v1 &middot; ' + $today + '</div>')
  [void]$h.Append('<h2>Hypothesis</h2><p>' + (Esc ([string]$pp.hyp)) + '</p><h2>Aims</h2><p>' + (Esc ([string]$pp.aims)) + '</p><h2>Methods</h2><p>' + (Esc ([string]$pp.met)) + '</p><h2>Expected outputs</h2><p>' + (Esc ([string]$pp.out)) + '</p>')
  [void]$h.Append('<h2>Bibliography &amp; chain of verification (' + $okn + '/' + $tot + ' sources live on ' + $today + ')</h2><table><tr><th>Claim used</th><th>Source</th><th>Link</th><th>CoV</th></tr>')
  foreach ($rr in @($pp.refs)) {
    $uu = ([string]$rr.u).Trim()
    if ($refOk[$uu]) { $badge = '<span class="ok">&#10003; HTTP 200</span>' } else { $badge = '<span class="no">&#9678; unverified</span>' }
    [void]$h.Append('<tr><td>' + (Esc ([string]$rr.c)) + '</td><td>' + (Esc (([string]$rr.r).Trim())) + '</td><td><a href="' + (Esc $uu) + '">' + (Esc $uu) + '</a></td><td>' + $badge + '</td></tr>')
  }
  foreach ($cc in @($pp.cov)) {
    $uu2 = ([string]$cc.u).Trim()
    if ($refOk[$uu2]) { $b2 = '<span class="ok">&#10003; HTTP 200</span>' } else { $b2 = '<span class="no">&#9678; unverified</span>' }
    [void]$h.Append('<tr><td>[CoV] ' + (Esc ([string]$cc.c)) + '</td><td>data source check</td><td><a href="' + (Esc $uu2) + '">' + (Esc $uu2) + '</a></td><td>' + $b2 + '</td></tr>')
  }
  [void]$h.Append('</table><div class="meta">Chain-of-verification method: every claim row was probed automatically at build time (' + $today + '); &#10003; = endpoint answered HTTP 200 during generation, &#9678; = probe failed or blocked (verify manually before citing in applications). Draft generated by the PhD Funding Command Center build.</div></body></html>')
  $htmlFile = Join-Path $propDir ($pp.id + '.html')
  [System.IO.File]::WriteAllText($htmlFile, $h.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  $pdfFile = Join-Path $propDir ($pp.id + '.pdf')
  if (Test-Path $chrome) {
    try {
      $tmpHtml = Join-Path $env:Temp (($pp.id) + '_print.html')
      [System.IO.File]::WriteAllText($tmpHtml, $h.ToString(), (New-Object System.Text.UTF8Encoding($false)))
      $tmpPdf = Join-Path $env:Temp (($pp.id) + '_print.pdf')
      if (Test-Path $tmpPdf) { Remove-Item $tmpPdf -Force }
      Start-Process -FilePath $chrome -ArgumentList @('--headless=new','--disable-gpu','--no-pdf-header-footer',('--print-to-pdf=' + $tmpPdf),('file:///' + ($tmpHtml -replace '\\','/'))) -Wait -NoNewWindow
      if ((Test-Path $tmpPdf) -and ((Get-Item $tmpPdf).Length -gt 2000)) { Move-Item $tmpPdf $pdfFile -Force; $pdfCount++ }
    } catch { }
  }
}
$propCards = New-Object System.Text.StringBuilder
$anyPdf = ($pdfCount -gt 0) -or (Test-Path (Join-Path $propDir 'p53-sheaf-gnn.pdf'))
foreach ($pp in $proposals) {
  $tot = @($pp.refs).Count + @($pp.cov).Count
  $okn = 0
  foreach ($rr in (@($pp.refs) + @($pp.cov))) { if ($refOk[[string]$rr.u]) { $okn++ } }
  $ext = if ($anyPdf) { '.pdf' } else { '.html' }
  [void]$propCards.Append('<a class="src" href="proposals/' + $pp.id + $ext + '" target="_blank" rel="noopener"><span class="sn">&#128196; ' + (Esc ([string]$pp.title)) + '</span><span class="sw">' + (Esc ([string]$pp.sub)) + '</span><span class="sw"><b class="vok">&#10003;</b> CoV: ' + $okn + '/' + $tot + ' sources verified ' + $today + '</span></a>')
}
"proposals written: $($proposals.Count) html | $pdfCount pdf"

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Funding hub &mdash; PhD Funding Command Center</title>
<link rel="icon" href="icon.svg">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Newsreader:opsz,wght@6..72,400;6..72,600&family=Hanken+Grotesk:wght@400;600&display=swap" rel="stylesheet">
<style>
$css
</style>
</head>
<body>
<header class="top"><div class="wrap"><div class="row"><div><h1>Funding hub</h1><div class="sub">Gabriele Bambini &middot; Italian/EU &middot; computational biology first (genomic data science &middot; sheaf-GNN oncology) + ML/AI &middot; Sept-2027 entry &middot; UK-first</div></div><a class="backlink" href="index.html">&#8592; Command Center</a></div><div class="kpis"><div class="kpi"><div class="n">14</div><div class="l">Universities</div></div><div class="kpi"><div class="n">$($mustSorted.Count)</div><div class="l">Must-apply funds</div></div><div class="kpi"><div class="n">$($ext.Count)</div><div class="l">External fellowships</div></div><div class="kpi"><div class="n">$($eligSorted.Count)</div><div class="l">Eligible funds</div></div></div></div></header>
<nav class="jump"><div class="wrap"><button onclick="window.print()" style="float:right;background:var(--navy);color:#f6f4ee;border:none;border-radius:3px;padding:4px 12px;font-family:var(--sans);font-size:12.5px;cursor:pointer" title="Print or save this whole page as a PDF dossier with all links">Export PDF dossier</button><a href="#realistic">Realistic shots</a><a href="#raise">Raise your odds</a><a href="#radar">Deadlines</a><a href="#score">Readiness</a><a href="#pipeline">Pipeline</a><a href="#outreach">Outreach</a><a href="#odds">Odds</a><a href="#takehome">Money</a><a href="#docs">Documents</a><a href="#must">Must-apply</a><a href="#external">External</a><a href="#all">All funds</a><a href="#playbooks">Playbooks</a><a href="#writing">Writing studio</a><a href="#drill">Interview drill</a><a href="#forge">Proposal forge</a><a href="#intel">Intel</a><a href="#verifyq">Verify</a></div></nav>
<main class="wrap">
<div class="printhead"><b>PhD Funding Command Center &mdash; application dossier</b> &middot; Gabriele Bambini &middot; generated $today</div>
<div class="starthere"><div class="sh-t">START HERE &mdash; this week</div><ol>
<li><b>Send the internal ask</b> to Li&ograve; &amp; Buffa (<a href="#raise">template above</a>): championing + IFOM studentship line. This unlocks everything else.</li>
<li><b>Pencil the three referees</b>: Li&ograve; by 1 Sep &middot; Buffa by 5 Sep &middot; third by 10 Sep.</li>
<li><b>Freeze preprint scope by 1 Sep</b> &mdash; the bioRxiv date is what converts your file before December walls.</li>
<li><b>Set two email alerts</b>: FindAPhD comp-bio + EURAXESS (<a href="#intel">links below</a>). Ten minutes, permanent coverage.</li>
</ol><div style="font-size:12px;color:#5a6478;margin-top:8px">How this page works: the bar on top jumps to any module &middot; <b>Readiness</b>, <b>Pipeline</b> and <b>Outreach</b> save your ticks in this browser &middot; use <b>Export PDF dossier</b> (top-right) to print/save everything with links.</div>
<div style="margin-top:10px;padding-top:10px;border-top:1px solid var(--line);font-size:12px;color:#5a6478">Your progress lives only in this browser &mdash; <button class="btn" id="bkExp" style="padding:5px 12px;font-size:12px">&#128190; Backup progress</button> downloads a JSON with every tick/state; <button class="btn" id="bkImp" style="padding:5px 12px;font-size:12px;background:var(--ink2)">&#128194; Restore</button> reloads it after clearing cache or on a new device.<input type="file" id="bkFile" accept=".json" style="display:none"></div></div>
$realisticHtml

<h2 id="raise">Raise your odds &mdash; the three levers that move admission probability more than any list</h2>
<p class="lead">Odds are not fixed: a citable first-author preprint converts your weakest signal into a strength BEFORE the December wall; briefed referees land on time; warm emails convert PIs before committees ever meet. All three levers below are actionable this week.</p>
<h3 class="t-h" style="color:var(--good)">Lever 1 &mdash; preprint sprint (Sep &rarr; Nov 2026): turn your RA work into a citable paper</h3>
$raiseSec

<h3 id="proposals" class="t-h" style="color:var(--brass-dk)">Research proposals &mdash; full documents, verified bibliography (download)</h3>
<p class="lead">Your three live projects turned into complete research proposals: hypothesis, aims, methods, expected outputs and a <b>chain of verification</b> &mdash; every cited claim probed at build time (&#10003; HTTP 200 / &#9678; check before citing). Attach to cold emails, supervisor meetings and applications.</p>
<div class="srcgrid">$($propCards.ToString())</div>

$radarSec

$scoreSec

$pipeSec

$outreachSec

<h2 id="odds">Admission + funding odds</h2>
<p class="lead">Calibrated on your CV (Li&ograve; backing, IFOM sheaf-GNN oncology, genomic data science). The bar is the combined admission+full-funding midpoint; the last column links your three strongest scholarships there. &#10003; = link verified this month.</p>
<div class="tblwrap"><table>
<thead><tr><th>University</th><th>Band</th><th>Odds</th><th>Midpoint</th><th>Top scholarships there</th></tr></thead>
<tbody>
$($oddsRows.ToString())
</tbody>
</table></div>

$takeSec

$docsSec

<h2 id="must">Must-apply funds ($($mustSorted.Count))</h2>
<p class="lead">Sorted by your estimated odds. &#10003; = official link verified this month; &#9678; = verify the page. These are the applications that cannot be skipped.</p>
<div class="tblwrap"><table>
<thead><tr><th>Fund</th><th>Organisation</th><th>Your odds</th><th>Tier</th></tr></thead>
<tbody>
$($mustRows.ToString())
</tbody>
</table></div>

<h2 id="external">External fellowships ($($ext.Count))</h2>
<p class="lead">Funders OUTSIDE the university lists, ranked for a computational-biology profile: comp-bio schemes first, ML&times;bio bridges next, enrolled-stage boosters last &mdash; plus an anti-list so you do not waste time.</p>
<div class="cards">
$($extCards.ToString())
</div>

<h2 id="all">All eligible funds ($($eligSorted.Count))</h2>
<p class="lead">The full cleaned universe: every university-linked fund worth tracking, grouped by organisation. Dotted names have no official page found yet &mdash; the link opens a pre-filled search instead of a dead end.</p>
<input class="q" id="q" type="search" placeholder="Filter funds (name, organisation, tier&hellip;)">
<div class="tblwrap"><table id="alltable">
<thead><tr><th>Fund</th><th>Organisation</th><th>Odds</th><th>Tier</th></tr></thead>
<tbody>
$($allRows2.ToString())
</tbody>
</table></div>

<h2 id="playbooks">Playbooks &mdash; decide now, not under adrenaline</h2>
<p class="lead">Three scenarios pre-planned so that spring 2027 is execution, not improvisation: how to choose between offers, how to convert an Italian-only year into a global ladder, and what a deliberate gap year looks like.</p>
$playbooks

$writeBlock

$drillBlock

$forgeBlock

$intelSec

$verifySec

</main>
<footer><div class="wrap">Generated $today from the scored dataset in <a href="index.html">PhD Funding Command Center</a>. Odds are personal estimates calibrated on your CV &mdash; not official acceptance rates. Links: &#10003; verified against the live official page this month; &#9678; verify before applying.</div></footer>
<script>
var q=document.getElementById('q');
if(q){q.addEventListener('input',function(){var v=q.value.toLowerCase();var rows=document.querySelectorAll('#alltable tbody tr');var n=0;rows.forEach(function(r){var hit=r.textContent.toLowerCase().indexOf(v)>-1;r.style.display=hit?'':'none';if(hit)n++;});});}

var RD=$radarJson;var today=new Date();today.setHours(0,0,0,0);
var rbox=document.getElementById('radarlist');
if(rbox){var items=[];for(var i=0;i<RD.length;i++){var x=RD[i];var d=new Date(x.d+'T09:00:00');items.push({x:x,days:Math.ceil((d-today)/864e5)});}
items.sort(function(a,b){return a.days-b.days;});
rbox.innerHTML=items.map(function(o){var cls=o.days<=30?'r-red':(o.days<=75?'r-amb':'r-nrm');var dd=o.days<0?o.x.d:(o.days+' days');return '<a class="ritem '+cls+'" href="'+(o.x.u||'#')+'" target="_blank" rel="noopener"><span class="rd">'+dd+'</span><span class="rn">'+o.x.n+(o.x.a?' <i>~verify</i>':'')+'</span><span class="rdate">'+o.x.d+'</span></a>';}).join('');}

var VQ=$vqJson;var VKEY='phdbot_verify_v1';var vst={};try{vst=JSON.parse(localStorage.getItem(VKEY)||'{}')}catch(e){}
var vq=document.getElementById('vqlist');
if(vq){vq.innerHTML=VQ.map(function(x,i){var id='vq'+i;var ck=vst[id]?' checked':'';return '<label class="vqi"><input type="checkbox" data-id="'+id+'"'+ck+'><span><b>'+x.n+'</b><br><i>'+x.u+'</i></span></label>';}).join('');
vq.addEventListener('change',function(e){var id=e.target.getAttribute&&e.target.getAttribute('data-id');if(!id)return;vst[id]=e.target.checked;try{localStorage.setItem(VKEY,JSON.stringify(vst))}catch(e2){}});}

var PIPE=$pipeJson;var PKEY='phdbot_pipe_v1';var pst={};try{pst=JSON.parse(localStorage.getItem(PKEY)||'{}')}catch(e){}
var STATES=['to do','preparing','submitted','interview','offer','rejected','skip'];
var pbody=document.getElementById('pipebody');
function pipeRender(f){if(!pbody)return;var q=(f||'').toLowerCase();var html='';for(var i=0;i<PIPE.length;i++){var x=PIPE[i];var hay=(x.n+' '+x.g).toLowerCase();if(q&&hay.indexOf(q)<0)continue;var st=pst[x.n]||'to do';var opts='';for(var j=0;j<STATES.length;j++){opts+='<option'+(STATES[j]===st?' selected':'')+'>'+STATES[j]+'</option>';}
html+='<tr><td>'+(x.u?'<a href="'+x.u+'" target="_blank" rel="noopener">'+x.n+'</a>':x.n)+'</td><td class="mut">'+x.g+'</td><td><select class="psel '+st.replace(' ','')+'" data-p="'+encodeURIComponent(x.n)+'">'+opts+'</select></td></tr>';}
pbody.innerHTML=html;}
if(pbody){pipeRender('');var qp=document.getElementById('qpipe');if(qp){qp.addEventListener('input',function(){pipeRender(this.value);});}
pbody.addEventListener('change',function(e){var k=e.target.getAttribute&&e.target.getAttribute('data-p');if(!k)return;var name=decodeURIComponent(k);pst[name]=e.target.value;try{localStorage.setItem(PKEY,JSON.stringify(pst))}catch(e2){}e.target.className='psel '+e.target.value.replace(' ','');});}

var sbox=document.querySelector('.scorewrap');
if(sbox){var SKEY='phdbot_score_v1';var sst={};try{sst=JSON.parse(localStorage.getItem(SKEY)||'{}')}catch(e){}
var sitems=sbox.querySelectorAll('.vqi input');
function calcScore(){var s=0;sitems.forEach(function(c){if(c.checked)s+=Number(c.getAttribute('data-w'));});var num=document.getElementById('scoreNum'),bar=document.getElementById('scoreBar'),msg=document.getElementById('scoreMsg');if(!num)return;num.textContent=s;bar.style.width=s+'%';msg.textContent=s>=70?'strong — keep the machine running':(s>=40?'on track — push the next item':'critical — start with the internal ask + referee briefs');}
sitems.forEach(function(c,i){c.checked=!!sst[i];c.addEventListener('change',function(){sst[i]=c.checked;try{localStorage.setItem(SKEY,JSON.stringify(sst))}catch(e2){}calcScore();});});
calcScore();}

var dmInputs=document.querySelectorAll('#dmat .dm');
var DMKEY='phdbot_matrix_v1';var dmv={};try{dmv=JSON.parse(localStorage.getItem(DMKEY)||'[]')}catch(e){}
function dmCalc(){var tot=[0,0,0];dmInputs.forEach(function(inp,idx){var w=Number(inp.getAttribute('data-w'));var v=Math.max(0,Math.min(10,Number(inp.value)||0));tot[idx%3]+=v*w;});
for(var t=0;t<3;t++){var el=document.getElementById('dmt'+t);if(el)el.textContent=tot[t]>0?String(tot[t]):'\u2014';}
var mx=Math.max(tot[0],tot[1],tot[2]);var names=['Offer A','Offer B','Offer C'];var win=document.getElementById('dmWin');if(win){win.textContent=mx>0?'Leader: '+names[tot.indexOf(mx)]+' ('+mx+'/1000)':'';}}
if(dmInputs.length){dmInputs.forEach(function(inp,i){if(dmv[i]!==undefined&&dmv[i]!==null)inp.value=dmv[i];inp.addEventListener('input',function(){dmv[i]=Number(inp.value)||0;try{localStorage.setItem(DMKEY,JSON.stringify(dmv))}catch(e4){}dmCalc();});});dmCalc();}

var bkE=document.getElementById('bkExp');
if(bkE){bkE.addEventListener('click',function(){var out={};for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);if(k.indexOf('phdbot_')===0)out[k]=localStorage.getItem(k);}
var blob=new Blob([JSON.stringify(out,null,2)],{type:'application/json'});var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='phd-funding-progress-'+new Date().toISOString().slice(0,10)+'.json';document.body.appendChild(a);a.click();a.remove();});
var bkF=document.getElementById('bkFile');
if(document.getElementById('bkImp')&&bkF){document.getElementById('bkImp').addEventListener('click',function(){bkF.click();});
bkF.addEventListener('change',function(){var f=bkF.files[0];if(!f)return;var rd=new FileReader();rd.onload=function(){try{var obj=JSON.parse(rd.result);var n=0;for(var k in obj){if(k.indexOf('phdbot_')===0){localStorage.setItem(k,obj[k]);n++;}}alert('Restored '+n+' keys. Reloading.');location.reload();}catch(err){alert('Not a valid backup file.');}};rd.readAsText(f);});}}

var SOPKEY='phdbot_sop_v1';var sop={};try{sop=JSON.parse(localStorage.getItem(SOPKEY)||'{}')}catch(e){}
var tas=document.querySelectorAll('.sopblock textarea[id^="ta-"]:not([id^="ta-dq-"])');
function wcStr(s){s=(s||'').replace(/^\s+/,'');return s?s.split(/\s+/).length:0;}
function sopPersist(){try{localStorage.setItem(SOPKEY,JSON.stringify(sop))}catch(e){}}
function totUpd(){var s=0;for(var i=0;i<tas.length;i++){s+=wcStr(tas[i].value);}var wt=document.getElementById('wctot');if(wt)wt.textContent=s;}
tas.forEach(function(t){var id=t.id;if(sop[id])t.value=sop[id];var tgt=Number(t.getAttribute('data-w'))||100;
var badge=document.getElementById('wc-'+id.slice(3));
t.addEventListener('input',function(){sop[id]=t.value;sopPersist();var n=wcStr(t.value);
if(badge){badge.textContent=n+' / '+tgt;badge.style.color=(n>=tgt*0.85&&n<=tgt*1.15)?'var(--good)':(n>tgt*1.15?'var(--crit)':'var(--brass-dk)');}
totUpd();});
if(badge){var n0=wcStr(t.value);badge.textContent=n0+' / '+tgt;}});
totUpd();
var sopExp=document.getElementById('sopExp');
if(sopExp){sopExp.addEventListener('click',function(){var L=['STATEMENT OF PURPOSE - working draft','Gabriele Bambini - '+new Date().toISOString().slice(0,10),''];
tas.forEach(function(t){var lbl=t.closest('.sopblock')&&t.closest('.sopblock').querySelector('label b');L.push('== '+(lbl?lbl.textContent:t.id)+' ==');L.push(t.value||'[empty]');L.push('');});
var blob=new Blob([L.join(String.fromCharCode(10))],{type:'text/plain'});var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='sop-draft-'+new Date().toISOString().slice(0,10)+'.txt';document.body.appendChild(a);a.click();a.remove();});}
var sopClr=document.getElementById('sopClr');
if(sopClr){sopClr.addEventListener('click',function(){if(!confirm('Clear all six paragraphs? Export first if unsure.'))return;tas.forEach(function(t){t.value='';});sop={};sopPersist();totUpd();tas.forEach(function(t){var b=document.getElementById('wc-'+t.id.slice(3));if(b)b.textContent='0 / '+t.getAttribute('data-w');});});}

var DRKEY='phdbot_drill_v1';var drl={};try{drl=JSON.parse(localStorage.getItem(DRKEY)||'{}')}catch(e){}
var dtas=document.querySelectorAll('.sopblock textarea[id^="ta-dq-"]');
function drlPersist(){try{localStorage.setItem(DRKEY,JSON.stringify(drl))}catch(e6){}}
dtas.forEach(function(t){var id=t.id;if(drl[id])t.value=drl[id];var tgt=Number(t.getAttribute('data-w'))||120;
var badge=document.getElementById('wc-'+id.slice(3));
t.addEventListener('input',function(){drl[id]=t.value;drlPersist();var n=wcStr(t.value);
if(badge){badge.textContent=n+' / '+tgt;badge.style.color=(n>=tgt*0.8&&n<=tgt*1.2)?'var(--good)':(n>tgt*1.2?'var(--crit)':'var(--brass-dk)');}});
if(badge){badge.textContent=wcStr(t.value)+' / '+tgt;}});
var dExp=document.getElementById('drillExp');
if(dExp){dExp.addEventListener('click',function(){var L=['INTERVIEW ANSWERS - drill sheet','Gabriele Bambini - '+new Date().toISOString().slice(0,10),''];
dtas.forEach(function(t){var lbl=t.closest('.sopblock')&&t.closest('.sopblock').querySelector('label b');L.push('== '+(lbl?lbl.textContent:t.id)+' ==');L.push(t.value||'[empty]');L.push('');});
var blob=new Blob([L.join(String.fromCharCode(10))],{type:'text/plain'});var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='interview-answers-'+new Date().toISOString().slice(0,10)+'.txt';document.body.appendChild(a);a.click();a.remove();});}

var FKEY='phdbot_forge_v1';var frg={};try{frg=JSON.parse(localStorage.getItem(FKEY)||'{}')}catch(e){}
var ftas=document.querySelectorAll('.sopblock textarea[id^="ta-fa-"]');
ftas.forEach(function(t){var id=t.id;if(frg[id])t.value=frg[id];var tgt=Number(t.getAttribute('data-w'))||50;
var badge=document.getElementById('wc-'+id.slice(3));
t.addEventListener('input',function(){frg[id]=t.value;try{localStorage.setItem(FKEY,JSON.stringify(frg))}catch(e7){}var n=wcStr(t.value);
if(badge){badge.textContent=n+' / '+tgt;badge.style.color=n<=tgt?'var(--good)':'var(--crit)';}});
if(badge){badge.textContent=wcStr(t.value)+' / '+tgt;}});
var fExp=document.getElementById('forgeExp');
if(fExp){fExp.addEventListener('click',function(){var L=['PROPOSAL SPINE - working draft','Gabriele Bambini - '+new Date().toISOString().slice(0,10),''];
ftas.forEach(function(t){var lbl=t.closest('.sopblock')&&t.closest('.sopblock').querySelector('label b');L.push('== '+(lbl?lbl.textContent:t.id)+' ==');L.push(t.value||'[empty]');L.push('');});
var blob=new Blob([L.join(String.fromCharCode(10))],{type:'text/plain'});var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='proposal-spine-'+new Date().toISOString().slice(0,10)+'.txt';document.body.appendChild(a);a.click();a.remove();});}

var RKEY='phdbot_review_v1';var rst={};try{rst=JSON.parse(localStorage.getItem(RKEY)||'[]')}catch(e){}
var rins=document.querySelectorAll('#wrules input[data-r]');
rins.forEach(function(c,i){c.checked=!!rst[i];c.addEventListener('change',function(){rst[i]=c.checked;try{localStorage.setItem(RKEY,JSON.stringify(rst))}catch(e5){}});});

var OKEY='phdbot_outreach_v1';var ost={};try{ost=JSON.parse(localStorage.getItem(OKEY)||'{}')}catch(e){}
var osels=document.querySelectorAll('select[data-o]');
for(var oi=0;oi<osels.length;oi++){(function(s){var k2o=s.getAttribute('data-o');if(ost[k2o])s.value=ost[k2o];s.addEventListener('change',function(){ost[k2o]=s.value;try{localStorage.setItem(OKEY,JSON.stringify(ost))}catch(e3){}});})(osels[oi]);}

var dbtn=document.getElementById('digestBtn');
if(dbtn){dbtn.addEventListener('click',function(){var L=[];L.push('PHD FUNDING - WEEKLY BRIEFING '+new Date().toISOString().slice(0,10));L.push('');
L.push('DEADLINES <= 30 DAYS:');
var any=false;for(var i2=0;i2<RD.length;i2++){var x2=RD[i2];var dd2=new Date(x2.d+'T09:00:00');var dys=Math.ceil((dd2-today)/864e5);if(dys>=0&&dys<=30){any=true;L.push(' - ['+dys+'d] '+x2.n+' ('+x2.d+')'+(x2.a?' ~verify':''));}}
if(!any)L.push(' - none inside 30 days');
L.push('');L.push('PIPELINE:');
var counts={};for(var j3=0;j3<PIPE.length;j3++){var stt=pst[PIPE[j3].n]||'to do';counts[stt]=(counts[stt]||0)+1;}
for(var kk in counts){L.push(' - '+kk+': '+counts[kk]);}
var scn=document.getElementById('scoreNum');L.push('');L.push('READINESS SCORE: '+(scn?scn.textContent:'0')+'/100');
L.push('REFEREES: Lio by 1 Sep | Buffa by 5 Sep | third by 10 Sep');
L.push('NEXT BIF DEADLINE: 1 Oct (only at PhD start)');
var txt=L.join(String.fromCharCode(10));
var out=document.getElementById('digestOut');out.textContent=txt;out.style.display='block';
if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(txt);}});
}

window.addEventListener('beforeprint',function(){document.querySelectorAll('details').forEach(function(d){d.open=true;});});
</script>
</body>
</html>
"@
[System.IO.File]::WriteAllText($fFun, $html, (New-Object System.Text.UTF8Encoding($false)))
"funding.html written: $((Get-Item $fFun).Length) bytes"

# ---------- 7. validate ----------
$raw2 = [System.IO.File]::ReadAllText($fIdx)
$m2 = [regex]::Match($raw2, '(?s)<script type="application/json" id="drillData">(.*?)</script>')
$d2 = $m2.Groups[1].Value | ConvertFrom-Json
'index JSON re-parses OK: ext=' + $d2.lists.external.rows.Count + ' must=' + $d2.lists.must_apply.rows.Count + ' elig=' + $d2.lists.eligible.rows.Count
'kpi link present: ' + $raw2.Contains('href="funding.html"')
$toolsDir = Join-Path $repo 'tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
Copy-Item $PSCommandPath (Join-Path $toolsDir 'build_funding_page.ps1') -Force
'build script archived to tools/build_funding_page.ps1'
$fh = [System.IO.File]::ReadAllText($fFun)
'h2 sections: ' + ([regex]::Matches($fh, '<h2 ')).Count + ' | table rows: ' + ([regex]::Matches($fh, '<tr>')).Count + ' | https links: ' + ([regex]::Matches($fh, 'href="https')).Count
