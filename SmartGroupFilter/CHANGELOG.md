# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

### Added

- The addon loads in every client language and answers `/sgf` with its chat commands.
- The Group Finder's player list shows only the single players within the level range of the
  dungeon you are listed for (or chose in the list); groups and your own listing stay, delisted
  entries are hidden.
- A panel docked beside the player list steers the filter: the count of players shown (bottom right),
  Reset Filter for Blizzard's own list, the level range as two fields and a slider, one
  priority row of class icons per role - drag to reorder, right-click to exclude - and the
  options "Allow double classes" and "Allow same armor class" (off: classes of your armor get a
  faint cross and leave the list). Saved per character.
- A fourth side tab with the SmartGroupFilter logo, on every page of the window, opens the Group
  Browser with the panel there, and shows or hides the panel on it; while it is hidden
  the list is Blizzard's own.
- Players whose class and level the game hands over only after the search are filtered as soon
  as they arrive.
- Build Group in the panel: one click invites the players your group lacks - one tank, one
  healer, three damage dealers around your own role - by your priority rows, highest level
  first, then the longest wait, players without a role last. Invited players keep their place
  for two minutes, and for as long as they are in the group; someone who declines an invite or
  lets it run out is not asked again. The chat names each invite; the button's tooltip says why it is
  greyed out.
- `/sgf test` shows in the chat whom Build Group would invite and why, and why every other
  single player is left out - without sending a single invite.
- Build Group works in two steps when the list is older than 30 seconds: the first click
  refreshes it, the next invites from the fresh results. A player who is already in another
  group counts like a decline.
