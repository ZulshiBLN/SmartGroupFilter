# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

### Added

- A panel docked beside the Group Finder's player list, opened and closed with it; a fourth side
  tab with the SmartGroupFilter logo, on the player list, shows and hides it.
- The filter: the player list shows only the single players within the level range and fitting
  your priority rows; groups and your own listing stay, delisted entries are hidden. Players
  whose class and level arrive after the search are filtered as soon as they do.
- The level range as two fields and a slider, starting at the dungeon you are listed for.
- One priority row of class icons per role - drag to reorder, right-click to exclude - and the
  options "Allow double classes" and "Allow same armor class" (off: classes of your armor get a
  faint cross and leave the list). Saved per character.
- Reset Filter shows Blizzard's full list until your next change or login; the bottom right
  corner counts the players shown, and each row's header the players shown who signed up for
  its role - "Tank (3 listed)".
- Build Group: one click invites the players your group lacks around your own role - one tank,
  one healer, three damage dealers - only from players listed for your dungeon, filling the most
  tank and healer places, then the most players; among equal fills by your rows, highest level
  first, then the longest wait; players without a role last, only for free places.
  Invited players keep their place for two minutes and while they are in the group; a decline,
  a run-out invite or "already in a group" frees the place, and that player is not asked again.
  A list older than 30 seconds is refreshed first with the same button. The chat names each
  invite; the tooltip says why the button is greyed out.
- Listed for several dungeons, Build Group builds for the one where it finds the most tanks and
  healers, then the most players, and names it in the chat; the group keeps it while it has members or pending invites.
- A player listed for several roles or none gets an English whisper with the invite, "Tank for
  Shadowfang Keep?"; one listed for one role but several dungeons gets "You want to join for
  Shadowfang Keep?".
- Not listed yet? The same button reads List Self and lights up Blizzard's eye tab, where you
  choose the dungeon, play style and role; once Blizzard has listed you it reads Build Group.
- A minimap button with the logo: left-click opens or closes the Group Finder, as Blizzard's
  button and key do; right-click opens SmartGroupFilter's settings; drag it around the minimap.
  `/sgf minimap` hides and shows it. An entry in the AddOn menu opens the settings too.
- A gear in the panel switches to the settings and back: the language - Automatic follows the
  client, or choose one of eleven, every text switches at once - the minimap button, and the
  window background: a slider from invisible to solid for the panel and the bug report.
- A bug report: `/sgf bug` or the button in the settings opens a window where you describe the
  bug; it shows a code to copy into a GitHub issue. It holds SmartGroupFilter's state and its
  errors, never another player's name.
- The addon loads in every client language and answers `/sgf` with its chat commands; its icon
  in the AddOn list is the SmartGroupFilter logo.
