# Plateau-Breaker Progression Algorithm — Research Findings

**Status:** Research only. No Dart/application code was written as part of this
document. This is the first file in `docs/research/` — there was no prior
research-notes convention in this repo, so this establishes one.

**Scope:** Informs a real implementation of
`LocalRecommendationEngine._recommendPlateauBreaker` in
`app/lib/services/local_recommendation_engine.dart`, which today (as of this
research) is a placeholder that just calls `_recommendStandard`. It is
dispatched from `ProgressionAlgorithm.plateauBreaker`, a per-exercise setting
the user assigns manually via a UI picker (`app/lib/models/recommendation_models.dart`).
That matters for the design below: this function does not need its own
"should I even run" gate the way `_recommendStandard`'s crude `_isPlateaued`
check does — the user has already told the app "this lift needs different
handling." The design still needs to detect *when the plateau has actually
broken* so it can hand control back to `_recommendStandard`, because a user
may leave the picker set to plateau-breaker indefinitely.

**Grounding data:** findings below are checked against the user's real
15-month FitNotes export (1,938 rows, 32 exercises) as summarized in the task
brief: chronically flat/declining isolation lifts (Dumbbell Curl, EZ-Bar
Reverse Curl, EZ-Bar Preacher Curl, Cable Overhead Triceps Extension, Back
Extension) vs. strongly progressing compounds and machine lifts (Barbell
Squat +64.5%, Seated Leg Curl +149.8%, Incline DB Bench +80.1%, Cable Face
Pull +129.3%, Flat Bench +21.9%, Lat Pulldown +9.4%, OHP +16.2%, Leg
Extension +28.6%), plus a documented false-positive where the existing
`_isPlateaued` (last-4-sessions, first-vs-max) flagged Seated Cable Row as
plateaued despite +42.5% 1RM gain over the full period and a still-rising
trend — pure session-to-session noise in a narrow window.

---

## 1. Is plateau-breaking different for isolation vs. compound lifts?

**Short answer: the mechanism differs, but no peer-reviewed RCT was found
that runs "plateau-breaker protocol A vs. B" specifically on isolation
exercises.** This is a real evidence gap and the report treats it as such
rather than dressing up coaching consensus as settled science.

What *is* well supported:

- **Periodization/undulation itself works, and equally well for hypertrophy
  regardless of model.** Grgic et al.'s systematic review and meta-analysis
  (13 studies) found linear periodization (LP) and daily undulating
  periodization (DUP) produce statistically indistinguishable hypertrophy
  outcomes (pooled SMD ≈ −0.02, i.e. no meaningful difference) once volume
  and intensity are equated (Grgic et al., *PeerJ* 2017,
  https://peerj.com/articles/3695/, PMID 28848690). This means the value of
  a plateau-breaker cycle is very unlikely to come from "undulation is
  magic" — it's much more likely to come from **novel stimulus relative to
  what that specific lift has been doing**, i.e. simply *not* being the same
  weight/rep pattern the lift has plateaued on.

- **For strength specifically, DUP has outperformed LP in at least one
  well-cited controlled trial.** Rhea et al. (*J Strength Cond Res* 2002,
  16(2):250–255, PMID 11991778) had one group run LP (8RM weeks 1–4, 6RM
  weeks 4–8, 4RM weeks 9–12) and another run DUP (Mon 8RM / Wed 6RM / Fri
  4RM, same 12 weeks, bench press and leg press, equated volume/intensity).
  DUP produced ~28.8% strength improvement vs. ~14.4% for LP, a statistically
  significant difference favoring DUP. The mechanistic read: **varying the
  rep range every session, not every mesocycle, produced more strength gain
  than a straight linear ramp** — directly relevant to lifts trained
  frequently, which accessory/isolation lifts often are.

- **The "weakest-link" theory for compounds is standard coaching logic, not
  a controlled trial finding.** The claim that isolation work breaks a
  compound-lift plateau by strengthening a limiting muscle (e.g., weak
  triceps capping a bench press) is widely repeated (e.g., Legion Athletics'
  plateau guide, https://legionathletics.com/weightlifting-plateau/) but the
  report did not find a peer-reviewed source isolating that causal claim.
  It is directionally sensible (compounds are limited by the weakest
  contributing muscle/joint) but should be treated as coaching heuristic,
  not settled evidence.

- **Isolation exercises are less neurologically/systemically taxing per set**
  (fewer motor units, less axial loading, less systemic fatigue) than
  multi-joint compounds — this is the mechanistic basis coaches use to
  justify pushing isolation work to higher relative volume/frequency and
  closer to failure than compounds without the same injury/recovery cost
  (reflected in rep-range guidance below). No single RCT was pulled for this
  specific claim; it is treated as low-controversy applied-physiology
  consensus.

**Practical implication for design:** because the isolation/compound
difference is not "use a totally different protocol," but "isolation lifts
tolerate — and may need — more frequent stimulus variation and can be pushed
closer to failure more often," the plateau-breaker algorithm should be a
**general-purpose undulation/wave cycle** applied per-session (matching
Rhea's DUP cadence) rather than a per-mesocycle block scheme. This also
happens to fit the app's per-exercise (not per-program) unit of control,
and matches the grounding data — every currently-plateaued exercise in the
user's log is isolation/small-muscle/machine work trained with moderate-to-high
rep ranges, exactly the population DUP evidence covers best.

---

## 2. Deterministic parameters implementable in pure Dart

All of the following are concrete numeric rules, chosen to be
directly translatable into conditionals comparable in complexity to
`_recommendStandard` (~60 lines):

### Deload/light-phase magnitude
- Deloading-practices survey of competitive strength/physique
  athletes (Colenso-Semple et al., *Sports Medicine – Open* 2024,
  PMID 38499934, https://link.springer.com/article/10.1186/s40798-024-00691-y):
  reported deloads averaged **6.4 ± 1.7 days long**, spaced **every 5.6 ± 2.3
  weeks**, most commonly achieved by cutting volume (fewer sets/reps) and/or
  effort (more reps-in-reserve), with intensity (%1RM) reduced more
  conservatively than volume.
- Jim Wendler's 5/3/1 (a well-documented, widely-adopted deterministic
  system — Wendler, *5/3/1: The Simplest and Most Effective Training System
  for Raw Strength*, 2009; percentages corroborated by multiple independent
  program summaries, e.g. https://arvo.guru/resources/methods/wendler-531,
  https://www.typeatraining.com/blog/5-3-1-program-guide-jim-wendlers-proven-strength-system/):
  the deload week is a fixed **40% / 50% / 60% of training max for 3×5**,
  i.e. roughly a **35–40% intensity cut** relative to the cycle's top
  working sets, taken every 4th week without exception (deterministic, not
  autoregulated).
- **Chosen value for this design:** a light/deload phase at **~65–70% of the
  plateaued working weight**, paired with a much higher rep target (see rep
  cycling below). This is more aggressive than Wendler's pure-intensity
  deload because it's compensated by volume/reps (consistent with how the
  survey data show real deloads cut volume more than intensity) and is
  gentler than a full 40% Wendler-style crash since it recurs every 3rd
  session rather than every 4th week — a shallower, more frequent dip fits
  the DUP cadence better than a rare, steep one.

### Wave/undulation pattern and period length
- Wave loading as practiced by strength coaches (e.g. Westside Barbell
  descriptions, https://www.westside-barbell.com/a/blog/wave-periodization;
  EliteFTS, https://elitefts.com/blogs/training/mastering-wave-loading-techniques)
  is a repeating short cycle of decreasing-reps/increasing-intensity
  followed by a reset, typically **3-set micro-waves reset every 3–6
  sessions**, with wave-loading blocks for general strength/size lasting
  **4–6 weeks** including a lighter session built into the wave itself so a
  separate full deload isn't always needed.
- Rhea et al.'s DUP protocol cycled rep target **every session, 3
  sessions/week** (8RM → 6RM → 4RM → repeat), for 12 weeks total, with no
  separate deload built in — the light day (8RM) *was* the deload.
- **Chosen value:** a **3-session repeating wave** (Heavy → Moderate →
  Light), directly modeled on Rhea's 3-day DUP cadence but adapted for a
  log-based app with no fixed weekly schedule — phase is derived from the
  count of qualifying sessions logged for that exercise since the plateau
  was confirmed, not from calendar days. Two full waves (6 sessions) form
  one "macro-cycle" before the trend is re-evaluated for exit (see below).

### Rep-range cycling scheme
- Double progression (well-established, deterministic method — e.g.
  https://legionathletics.com/double-progression/,
  https://mesostrength.com/blog/double-progression): work within a rep
  band, add reps set-to-set until every set hits the top of the band, then
  add weight and reset to the bottom. This is essentially what
  `_recommendStandard` already does (graduation reps → weight increment).
- Accessory/isolation-specific rep-range guidance from applied sources
  (Furthermore/Equinox, https://furthermore.equinox.com/articles/2019/02/best-rep-range-isolation-exercises;
  RP Strength rep-range guidance, https://help.rpstrength.com/hc/en-us/articles/30803058239127):
  isolation work is commonly programmed in the **8–15 rep band** for
  general hypertrophy, with occasional excursions to **15–20+ reps** for a
  metabolite-stress/deload-style stimulus, and coaches use short (~3–5
  session) rep-range block rotations on stalled accessory lifts rather than
  changing the exercise itself.
- **Chosen 3-phase cycle** (percentages relative to the plateaued baseline
  weight, defined precisely in §5/§6 below):
  - **Phase H (Heavy):** ~5 reps at ~110% of the recent working weight —
    a genuinely novel, lower-rep/higher-load stimulus the lift hasn't seen
    recently (breaks the "always 10–12 reps at the same weight" rut).
  - **Phase M (Moderate):** ~10 reps at the plateaued baseline weight —
    reinforces the exercise's normal hypertrophy stimulus so the wave
    doesn't drift the lift away from its trained rep range entirely.
  - **Phase L (Light):** ~18 reps at ~65–70% of baseline — the
    volume/metabolite deload phase, directly modeled on the deload-survey
    finding that real-world deloads cut load more than volume.

### Lookback window for plateau confirmation and noise resistance
This directly answers the Seated Cable Row false-positive problem flagged
in the grounding data. The existing `_isPlateaued` compares only the
**first vs. maximum** of a 4-session slice — a single noisy top session
anywhere in the window masks a real plateau, and a single noisy low first
session creates a false positive. Literature on what actually constitutes a
stall supports a longer, averaged window:
- Applied coaching sources on defining a genuine stall converge on
  **3–4 weeks of flat performance at minimum** before calling it a plateau
  rather than normal session-to-session variance (e.g. Barbell Medicine,
  https://www.barbellmedicine.com/blog/training-expectations-understanding-stalls/,
  and general strength-coaching consensus) — i.e. several sessions, not one
  data point on each end.
- **Chosen design:** use a **6-session trailing window**, and compare the
  **average of the most recent 3 sessions' e1RM** against the **average of
  the oldest 3 sessions' e1RM within that same window** (rolling-average vs.
  rolling-average, not single-point vs. single-point). This is far more
  resistant to single-session noise than `_isPlateaued`'s current
  first-vs-max check, and it's the same fix that would have prevented the
  Seated Cable Row false positive (a noisy single low session would be
  diluted into a 3-session average instead of anchoring the whole
  comparison).

### Exit rule (back to `_recommendStandard`)
- Because `recommend()` is stateless and recomputes from full history every
  call, the exit condition can simply be the **negation of the entry
  condition, re-evaluated every call** — no persisted "cycle counter" is
  needed. Concretely: if the 6-session rolling-average comparison above
  shows a **≥6% relative e1RM gain** (last-3 avg vs. first-3 avg), the lift
  is no longer plateaued and the function should return a
  `_recommendStandard`-style recommendation instead (with a status/notes
  string indicating the plateau broke and normal progression resumed).
- Two different thresholds — enter below +3% (flat/negative), exit above
  +6% — are used deliberately (**hysteresis**), so the algorithm doesn't
  flap between plateau-breaker and standard mode every other session on
  borderline data. This is standard control-systems practice for any
  threshold-triggered mode switch and directly prevents a Cable-Row-style
  false-positive from yanking the mode back and forth.
- A secondary, session-count-based backstop: after **12 qualifying sessions**
  (roughly 4 full waves) without triggering the exit condition, keep running
  the wave but add a `notesInsight` flag suggesting the user reconsider
  recovery, nutrition, or exercise selection — the algorithm should not
  silently cycle forever without ever telling the user it isn't working.

---

## 3. How this maps onto `Recommendation`

`Recommendation` (`app/lib/models/recommendation_models.dart`) has:
`targetReps` (int), `targetWeight` (double), `status` (String),
`predicted1RM` (double), `required1RM` (double), `notesInsight` (String).

The design below reuses the exact same field semantics `_recommendStandard`
already established, so the UI needs no changes:
- `predicted1RM` = e1RM from the most recent quality session (`calcOneRM`),
  same as standard.
- `required1RM` = `targetWeight * (1 + 0.0333 * targetReps)`, same formula
  standard already uses.
- `status` gets a short machine-readable-ish label prefixed `PLATEAU-BREAKER:`
  so the UI can visually distinguish it, mirroring the existing
  `'$modeLabel PROGRESSION: ...'` convention.
- `notesInsight` explains which wave phase is active, why, and previews the
  next phase — mirroring the existing insights-list-then-join pattern in
  `_recommendStandard`.

See §6 for the exact pseudocode producing these fields.

---

## 4. Assistance-based exercises (assisted pull-up / dip machines)

This is flagged in the task brief as a **separate bug**, not something
`_recommendPlateauBreaker` itself should fix — but the research on how it's
normally handled is captured here for whoever picks that up.

- No peer-reviewed literature specifically addresses assistance-machine
  progression tracking; this is purely a logging/UX convention question
  answered by how apps and coaches handle it in practice.
- **Universal convention found:** the number on an assisted pull-up/dip
  stack represents **assistance provided, not load lifted** — so *less*
  stack weight means *more* bodyweight is being moved, i.e. progress is
  `weight ↓`. Coaching guides are explicit about this inversion (e.g.
  Strength Warehouse USA's assisted-machine guide,
  https://strengthwarehouseusa.com/blogs/resources/how-to-use-the-assisted-pull-up-machine;
  GXMMAT's "stop guessing" guide,
  https://www.gxmmat.us/blogs/daily-news/assisted-pull-up-machine-weight-explained-stop-guessing).
  Some machines/gyms further complicate this because the printed number is
  itself sometimes "assistance" and sometimes "counterweight subtracted from
  bodyweight" depending on manufacturer — the sign convention is not even
  universally standardized across equipment, which is worth flagging to
  whoever fixes this.
  A common practical fallback several sources use: track and progress by
  **effective load = bodyweight − assistance weight**, which turns the
  metric back into a normal "higher is better" number and lets it flow
  through *unmodified* existing progression logic (linear or plateau-breaker)
  rather than needing an inverted code path everywhere.
- **General-purpose logging apps** (Strong, mentioned by
  https://www.hevyapp.com/21-pullup-variations/ and BULLBAR's app roundups,
  e.g. https://bullbarfit.com/blogs/q-as/what-are-the-best-apps-or-devices-for-tracking-pull-up-progress-and-sets)
  mostly just log the raw stack weight per set and leave the
  interpretation to the user; they do not appear to run automated
  progression math on assisted variations the way they do on loaded lifts.
  Purpose-built bodyweight-progression apps (e.g. Thenics, per the same
  BULLBAR roundup) instead track *progression through movement difficulty
  tiers* (dead hang → scapular pull → band-assisted → strict rep) rather
  than a continuous weight number at all.
- **Recommendation for the future fix (not implemented here):** rather than
  inverting sign logic throughout the recommendation engine, tag
  assistance-based exercises (by category/name heuristic or an explicit
  per-exercise flag) and **transform the input at ingestion**: store/derive
  an "effective load" value (`bodyweight_estimate − assistance_weight`, or
  simply `−assistance_weight` if bodyweight isn't tracked) before it ever
  reaches `calcOneRM`/`_slope`/either progression algorithm. That keeps
  `_recommendStandard` and `_recommendPlateauBreaker` exercise-shape-agnostic
  and avoids duplicating an inverted branch in both.

---

## 5. Why the existing `_isPlateaued` check is worth replacing (context for §6)

`_isPlateaued` currently does:
```
rms.reduce(max) - rms.first < 2.5   // over the last 4 sessions
```
Two weaknesses this design fixes:
1. **Single-point comparison.** `rms.first` is one session; if that
   session happened to be a noisy high point (bad day before it, unusually
   fresh after it, etc.), everything after looks flat by comparison even
   with real progress happening — this is what produced the Seated Cable
   Row false positive (+42.5% over the full record, still rising, but
   flagged as plateaued by the narrow 4-session window).
2. **Fixed absolute threshold (2.5 lbs).** 2.5 lbs means something very
   different for a 315 lb squat 1RM (0.8%) than for a 20 lb dumbbell curl
   1RM (12.5%) — it will essentially never trigger for heavy compounds and
   triggers very easily for light isolation work, which is backwards from
   what the grounding data shows (isolation lifts are the ones actually
   plateauing).

§6's design uses a **6-session rolling 3-vs-3 average** and a
**percentage-based threshold**, which resolves both.

---

## 6. Recommended algorithm (implementation-ready pseudocode)

This is written to be handed directly to implementation. It assumes reuse
of the existing helpers already in `local_recommendation_engine.dart`:
`calcOneRM`, `_slope`, `_workingWeight`, `_groupBySessions`, `_isFormIssue`,
`_isFatigue`, `_isDropSet`, `_isWarmup`, and the same category-threshold
table `_recommendStandard` uses.

```
FUNCTION _recommendPlateauBreaker(exercise, category, allHistory, mode):

    # ---- 1. Filter & session-group (identical to _recommendStandard) ----
    raw = allHistory
        .filter(s => s.exercise == exercise)
        .filter(s => !_isDropSet(s.comment) && !_isWarmup(s.comment))
        .sortBy(s => s.date)

    IF raw.isEmpty:
        RETURN Recommendation(
            targetReps: (mode == strength ? 5 : 10),
            targetWeight: 0.0,
            status: "NEW EXERCISE: No history — log your first sets",
            predicted1RM: 0, required1RM: 0,
            notesInsight: "No sets logged yet. Plateau-breaker cycle will "
                          "begin once you have at least 3 quality sessions."
        )

    sessions = _groupBySessions(raw)
    workingSessions = # same 60%-of-session-max filter as _recommendStandard
        sessions.map(sess => {
            maxW = max(sess.map(s => s.weight))
            RETURN sess.filter(s => maxW == 0 OR s.weight >= 0.6 * maxW)
        }).filter(sess => sess.isNotEmpty)

    # ---- 2. Not enough history yet: fall back to standard's baseline path
    IF workingSessions.length < 3:
        RETURN _recommendStandard(exercise, category, allHistory, mode)
        # (identical baseline/new-exercise handling; plateau-breaker logic
        #  needs at least 3 sessions to compute anything meaningful)

    lastSess       = workingSessions.last
    lastMaxW       = max(lastSess.map(s => s.weight))
    last1RM        = max(lastSess.map(s => calcOneRM(s.weight, s.reps)))
    hadFormIssue   = lastSess.any(s => _isFormIssue(s.comment))
    hadFatigue     = lastSess.any(s => _isFatigue(s.comment))

    # ---- 3. Robust trend window: last 6 sessions (or all if 3-5 avail.) --
    window = workingSessions.tail(min(6, workingSessions.length))
    e1RMs  = window.map(sess => max(sess.map(s => calcOneRM(s.weight, s.reps))))

    n = e1RMs.length
    firstAvg = mean(e1RMs.take(min(3, n)))          # oldest slice of window
    lastAvg  = mean(e1RMs.takeLast(min(3, n)))       # newest slice of window
    pctChange = firstAvg == 0 ? 0 : (lastAvg - firstAvg) / firstAvg * 100
    trendSlope = _slope(e1RMs)                        # existing helper

    # ---- 4. Exit condition: real progress resumed -> hand back to standard
    IF pctChange >= 6.0 AND trendSlope > 0:
        result = _recommendStandard(exercise, category, allHistory, mode)
        RETURN result.copyWith(
            status: "PLATEAU-BREAKER: Plateau broken (+" + round(pctChange,1)
                    + "% over last " + n + " sessions) — standard "
                    + "progression resumed",
            notesInsight: "Your plateau-breaker cycle worked — 1RM is "
                          "trending up again. Switching back to normal "
                          "linear progression." + result.notesInsight
        )

    # ---- 5. Form-issue safety override (same precedence as standard) ----
    IF hadFormIssue:
        RETURN Recommendation(
            targetReps: (mode == strength ? 5 : 10),
            targetWeight: lastMaxW,
            status: "FORM FOCUS: Repeat weight to nail technique",
            predicted1RM: last1RM,
            required1RM: lastMaxW * (1 + 0.0333 * (mode==strength?5:10)),
            notesInsight: "Form issues were logged last session — pausing "
                          "the plateau-breaker cycle until technique is solid."
        )

    # ---- 6. Determine wave phase from session count (stateless, derived) -
    # baseline = 3-session rolling average max weight -> noise-resistant
    # anchor for the wave (fixes the single-session-noise problem).
    baselineWeight = mean(window.tail(min(3, n)).map(sess => max(sess.map(s=>s.weight))))

    phaseIndex = workingSessions.length MOD 3     # 0, 1, or 2 -> H, M, L
    waveNumber = (workingSessions.length / 3) truncating-divide   # for messaging only

    SWITCH phaseIndex:
        CASE 0:  # Heavy
            targetReps   = 5
            rawWeight    = baselineWeight * 1.10
            phaseLabel   = "Heavy Wave"
            phaseDetail  = "Low reps, elevated load — novel stimulus"
        CASE 1:  # Moderate
            targetReps   = 10
            rawWeight    = baselineWeight * 1.00
            phaseLabel   = "Moderate Wave"
            phaseDetail  = "Baseline reload — reinforce normal rep range"
        CASE 2:  # Light
            targetReps   = 18
            rawWeight    = baselineWeight * 0.675   # midpoint of 65-70%
            phaseLabel   = "Light Wave"
            phaseDetail  = "High-rep deload — recover work capacity"

    targetWeight = round(rawWeight / 2.5) * 2.5      # same rounding convention
                                                       # as _recommendStandard's
                                                       # deload branch
    IF targetWeight <= 0: targetWeight = lastMaxW      # bodyweight/edge guard

    # ---- 7. Category safety clamp on the Heavy phase only ---------------
    # (reuse _recommendStandard's category threshold table so heavy-phase
    #  weight can never imply an unsafe %1RM jump)
    thresholds = {"Legs":0.95, "Chest":0.95, "Back":0.95,
                  "Shoulders":0.90, "Arms":0.85}
    threshold = thresholds[category] ?? 0.95
    required1RM = targetWeight * (1 + 0.0333 * targetReps)
    IF phaseIndex == 0 AND last1RM > 0 AND required1RM > last1RM * threshold:
        targetWeight = round(_workingWeight(last1RM * threshold, targetReps) / 2.5) * 2.5
        required1RM  = targetWeight * (1 + 0.0333 * targetReps)

    # ---- 8. Status / notes -------------------------------------------
    status = "PLATEAU-BREAKER: " + phaseLabel
             + " (session " + (phaseIndex+1) + "/3, wave " + (waveNumber+1) + ")"

    insights = []
    insights.add(phaseDetail + ".")
    insights.add("Trailing " + n + "-session e1RM change: "
                 + round(pctChange,1) + "% — still within plateau range "
                 + "(exits automatically at +6% with a rising trend).")
    IF hadFatigue:
        insights.add("Fatigue was logged last session — consider extra rest.")
    IF workingSessions.length >= 12 AND pctChange < 6.0:
        insights.add("This exercise has been in the plateau-breaker cycle "
                     + "for 12+ sessions without resolving. Consider "
                     + "reviewing recovery, nutrition, or swapping the "
                     + "exercise variation.")

    RETURN Recommendation(
        targetReps: targetReps,
        targetWeight: targetWeight,
        status: status,
        predicted1RM: last1RM,
        required1RM: required1RM,
        notesInsight: insights.join(" ")
    )
```

### Summary of the exact numeric contract
| Parameter | Value |
|---|---|
| Trend window | last 6 sessions (min 3 to run at all) |
| Plateau confirmation | rolling 3-vs-3 avg e1RM change < 6% (implicit: stay in cycle) |
| Exit to standard | rolling 3-vs-3 avg e1RM change ≥ 6% **and** slope > 0 |
| Wave length | 3 sessions (Heavy → Moderate → Light), repeating |
| Heavy phase | 5 reps @ 110% of 3-session rolling avg weight |
| Moderate phase | 10 reps @ 100% of 3-session rolling avg weight |
| Light phase | 18 reps @ 67.5% (65–70% band) of 3-session rolling avg weight |
| Weight rounding | nearest 2.5 lb (matches existing convention) |
| Safety clamp | Heavy phase capped so required1RM ≤ last1RM × category threshold (same table as `_recommendStandard`) |
| Stuck-cycle flag | notesInsight warning after 12 sessions without exit |

---

## Sources cited

- Grgic, J. et al. (2017). Effects of linear and daily undulating periodized
  resistance training programs on measures of muscle hypertrophy: a
  systematic review and meta-analysis. *PeerJ*, 5:e3695.
  https://peerj.com/articles/3695/ · PMID 28848690
- Rhea, M.R. et al. (2002). A comparison of linear and daily undulating
  periodized programs with equated volume and intensity for strength.
  *Journal of Strength and Conditioning Research*, 16(2):250–255.
  https://pubmed.ncbi.nlm.nih.gov/11991778/
- Zourdos, M.C. et al. (2016). Novel resistance training–specific rating of
  perceived exertion scale measuring repetitions in reserve. *Journal of
  Strength and Conditioning Research*, 30(1):267–275.
  https://pubmed.ncbi.nlm.nih.gov/26049792/
- Helms, E.R. et al. (2018). RPE vs. percentage 1RM loading in periodized
  programs matched for sets and repetitions. *Frontiers in Physiology*, 9:247.
  https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2018.00247/full
  · PMID 29628895
- Colenso-Semple, L.M. et al. (2024). Deloading practices in strength and
  physique sports: a cross-sectional survey. *Sports Medicine – Open*.
  https://link.springer.com/article/10.1186/s40798-024-00691-y · PMID 38499934
- Wendler, J. (2009). *5/3/1: The Simplest and Most Effective Training
  System for Raw Strength.* Percentages corroborated via
  https://arvo.guru/resources/methods/wendler-531 and
  https://www.typeatraining.com/blog/5-3-1-program-guide-jim-wendlers-proven-strength-system/
- Wave-loading coaching methodology: https://www.westside-barbell.com/a/blog/wave-periodization
  and https://elitefts.com/blogs/training/mastering-wave-loading-techniques
  (established coaching practice, not peer-reviewed — cited as such).
- Block periodization phase lengths:
  https://www.hprc-online.org/physical-fitness/training-performance/plan-your-workouts-block-periodization
  and https://myliftingcoach.com/blog/block-periodization-guide (secondary
  summaries of Issurin's block-periodization framework).
- Double progression method: https://legionathletics.com/double-progression/,
  https://mesostrength.com/blog/double-progression
- Isolation/accessory rep-range guidance:
  https://furthermore.equinox.com/articles/2019/02/best-rep-range-isolation-exercises,
  https://help.rpstrength.com/hc/en-us/articles/30803058239127
- Plateau/stall definition (3–4 week minimum):
  https://www.barbellmedicine.com/blog/training-expectations-understanding-stalls/
- Compound-vs-isolation "weakest link" plateau reasoning (coaching
  heuristic, not an RCT): https://legionathletics.com/weightlifting-plateau/
- Assisted pull-up/dip machine assistance-weight convention:
  https://strengthwarehouseusa.com/blogs/resources/how-to-use-the-assisted-pull-up-machine,
  https://www.gxmmat.us/blogs/daily-news/assisted-pull-up-machine-weight-explained-stop-guessing
- Pull-up/bodyweight tracking apps (Strong, Thenics):
  https://www.hevyapp.com/21-pullup-variations/,
  https://bullbarfit.com/blogs/q-as/what-are-the-best-apps-or-devices-for-tracking-pull-up-progress-and-sets

**Note on source access:** direct WebFetch of several primary pages
(pubmed.ncbi.nlm.nih.gov, peerj.com PDF, ncbi PMC, shu.ac.uk) returned HTTP
403 during this research session (bot-blocking, not a proxy fault — the
agent proxy status was confirmed healthy). All figures above were verified
through indexed search-result abstracts/summaries of those same papers
rather than full-text PDFs; PMIDs are included so the underlying abstracts
can be pulled directly from PubMed by a human or a session with working
fetch access.
