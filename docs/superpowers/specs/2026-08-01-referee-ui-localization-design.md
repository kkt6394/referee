# Referee UI and Localization Design

## Goal

Make the referee app pleasant and fast for real 11-a-side match use. The
iPhone is used before and after the match; the Apple Watch is the primary
match-time input surface. Korean is the default language, with English as a
user-selectable alternative.

## Product split

### iPhone: before and after the match

- Use a bright, calm card-based interface.
- Pre-match flow: match creation → teams/rosters → venue and pitch → crew and
  checklist → readiness gate → send package to Watch.
- Post-match flow: timeline review → complete missing incident details →
  resolve blocking issues → referee declaration → sign and export.
- The match control screen remains available as a fallback, but is not the
  primary interaction path during live play.
- Team names, selected kit colors, readiness status, and sync status are
  visible without opening secondary screens.

### Apple Watch: during the match

- Use a dark, high-contrast interface optimized for sunlight and one-handed
  operation.
- Home screen shows period, large running clock, score, team-colored labels,
  local-save/queue status, and the four fastest actions: goal, foul, yellow
  card, and red card.
- Goal and card actions return to the match home after saving. Red card keeps
  the existing long-press confirmation.
- Every action provides visible local-save feedback and haptic feedback where
  supported. No live action depends on the iPhone connection.
- Secondary details remain on iPhone; Watch captures only the minimum event
  data needed at the moment of play.

## Localization

- Replace user-facing hard-coded English strings with localization keys.
- Korean (`ko`) is the default locale; English (`en`) is complete and remains
  selectable from an in-app language setting.
- Persist the selected language locally and apply it consistently to iPhone,
  Watch, validation messages, sync status, and export labels.
- Keep event type identifiers, database values, accessibility identifiers, and
  protocol field names language-neutral.
- Use short Korean labels on Watch; use descriptive Korean copy on iPhone.

## Visual system

- Shared semantic colors: background, surface, primary text, secondary text,
  success, warning, blocking, and team kit colors.
- iPhone uses grouped cards, generous spacing, clear section headings, and
  one primary action per screen.
- Watch uses large typography, minimum 44pt touch targets, strong contrast,
  and no dense forms.
- Team kit color is an accent only; text must remain readable in both light and
  dark appearances.
- Dynamic Type and VoiceOver labels are required for all primary actions.

## Implementation boundaries

- Add a shared localization layer without changing ledger schemas or event
  payload vocabulary.
- Extract reusable iPhone and Watch style tokens into small SwiftUI helpers.
- Refactor only the screens touched by this design; do not redesign report
  generation or the append-only ledger.
- Preserve current offline queue, package transfer, readiness blocking, and
  sign-off behavior.

## Verification

- Unit tests verify locale-independent persistence and localized display text
  at the view-model boundary.
- iPhone UI tests cover Korean default, English switch, pre-match readiness,
  and post-match review entry.
- Watch UI tests cover Korean/English labels, score visibility, team colors,
  local queue feedback, and long-press red card behavior.
- Run `swift test`, full iPhone UI tests, and full Watch UI tests before each
  integration commit.
- Confirm the redesigned iPhone app fills the simulator screen and manually
  inspect both locales on simulator screenshots.
