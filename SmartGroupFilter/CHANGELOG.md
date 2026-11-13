# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-13

### Added

- A panel docked beside the Group Finder's player list, opened and closed with it; a fourth side
  tab with the SmartGroupFilter logo, on the player list, shows and hides it.
- The filter: the panel counts the single players within the level range and fitting your
  priority rows; groups and your own listing are not counted, delisted players never fit.
  Blizzard's player list stays as Blizzard shows it. Players whose class and level arrive after
  the search are counted as soon as they do. Inside an instance, where the game hides the search
  results from addons, the counts stay as they were.
- The level range as two fields and a slider, starting at the dungeon you are listed for.
- One priority row of class icons per role - drag to reorder, right-click to exclude - and the
  options "Allow double classes" and "Allow same armor class" (off: classes of your armor get a
  faint cross and do not fit). Saved per character.
- Reset Filter clears the exclusions, allows the same armor class again and sets the level range
  back to your dungeon's; the panel's bottom line counts the players who fit - "No player of 12
  fits your filter" when none does - and each row's header those who signed up for its role -
  "Tank (3 listed)". Hovering a role's header lists them, "[24] | Name" in class colour.
- Build Group: one click invites the players your group lacks around your own role - one tank,
  one healer, three damage dealers - only from players listed for your dungeon, filling the most
  tank and healer places, then the most players; among equal fills by your rows, highest level
  first, then the longest wait; players without a role last, only for free places.
  Invited players keep their place for two minutes and while they are in the group; a decline,
  a run-out invite or "already in a group" frees the place, and that player is not asked again.
  A list older than 30 seconds is refreshed first with the same button. The chat names each
  invite; the tooltip says why the button is greyed out.
- Listed for several dungeons, Build Group builds for the one where it finds the most tanks and
  healers, then the most players, and names it in the chat; the group keeps it while it has
  members or pending invites.
- Already in a group before the first Build Group, the button reads Check Roles and runs
  Blizzard's role check; once every member chose, it reads Build Group and their roles count.
  A member who only confirms their role counts with it 15 seconds after the click.
  Asked once, until you are alone again - declines and run-out invites never bring it back.
  A member who joins later without your Build Group invite counts with the role chosen on
  joining.
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
