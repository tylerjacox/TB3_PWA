# TB3 PWA Project Memory

## Project Structure
- **App root:** `/Users/tylerjacox/TB3_PWA/app/`
- **Framework:** Preact 10.x + Preact Signals + Vite + VitePWA
- **Build:** `npm run build` (tsc + vite build), output in `dist/`
- **Deploy:** `AWS_PROFILE=tb3-deployer bash deploy.sh` from repo root
- **URL:** https://d1c704j6qnvml9.cloudfront.net

## Key Architecture Decisions
- IndexedDB (via idb-keyval) is primary store, localStorage only for auth tokens
- Profile lifts are DERIVED from maxTestHistory (no dual-write)
- ActiveSession is self-contained snapshot (doesn't reference computedSchedule during workout)
- Hash-based routing for iOS standalone mode compatibility
- Cognito SDK lazy-loaded on first auth interaction (~28KB gzipped)
- ComputedSchedule has sourceHash for staleness detection

## Templates (7 total)
- **Operator:** 3/wk, fixed lifts, set range
- **Zulu:** 4/wk A/B split, Cluster One/Two percentages, user-selectable lifts
- **Fighter:** 2/wk, user-selectable 2-3 lifts, set range
- **Gladiator:** 3/wk, ALL cluster lifts every session, fixed sets, Week 6 descending [3,2,1,3,2]
- **Mass Protocol:** 3/wk, ALL cluster lifts every session, no rest minimums
- **Mass Strength:** 3wk cycle, 4 tracked sessions/wk, sessions 2/4 untracked, DL day
- **Grey Man:** 12wk, 3/wk, ALL cluster lifts every session

## Bundle Size
- App shell: ~28KB gzipped (JS) + ~4KB gzipped (CSS) = ~32KB total
- Cognito SDK: ~31KB gzipped (lazy-loaded)
- Total with Cognito: ~63KB gzipped — slightly over 50KB target for app shell alone

## Files Created (v1.0 build)
- 34 new files + 6 modified existing files = 40 total source files
- See `app/src/` for full structure
