# SmartGroupFilter

A helper for the Group Finder in World of Warcraft: Forever. It docks a panel beside Blizzard's
own Looking For Group window, shortens the player list to the single players you need, and
builds your five-player group with one click.

**Status: released** - version 1.0.0, for WoW Forever.

## How it works

- **The panel** sits right of the Group Finder's side tabs and opens with the player list. A
  fourth side tab with the logo shows and hides it; while it is hidden the list is Blizzard's.
- **Level range** - two fields and a slider; it starts at the dungeon you are listed for
  (Shadowfang Keep: 20-30) and keeps a range you set until you list for another dungeon.
- **Priorities** - one row of class icons per role: tank, healer, damage. Drag an icon to reorder
  the row; right-click it to exclude the class from that role. Beside each header: how many of
  the players shown signed up for that role - "Tank (3 listed)".
- **Options** - *Allow double classes* (off: one player per class in the group, you included;
  on: two). *Allow same armor class* (on; off leaves out players who wear your armor - by class
  and level, as hunters, shamans, warriors and paladins change armor at 40).
- **The filter** keeps the single players who fit: within the level range, signed up for a role
  whose row holds their class, or signed up without a role for any role their class can fill.
  Groups and your own listing stay; delisted entries go. **Reset Filter** shows Blizzard's full
  list until your next change or login. The bottom right corner counts the players shown.
- **Build Group** invites the players your group lacks around your own role: one tank, one
  healer, three damage dealers, only from players listed for your dungeon. It fills the free
  places so that the most tanks and healers come, then the most players - a paladin listed as
  tank and healer heals when a warrior can only tank. Among equal fills each place takes the
  highest class in its row, then the highest level, then the longest wait. Players without a
  role only fill what is left.
  - **Several dungeons:** listed for more than one, it builds for the one where it finds the
    most tanks and healers - they are rare - then the most players, and names it in the chat.
    The group keeps that dungeon while it has members or pending invites.
  - **Ambiguous sign-ups:** a player listed for several roles or none gets an English whisper
    with the invite ("Tank for Shadowfang Keep?"); one listed for one role but several dungeons
    gets "You want to join for Shadowfang Keep?".
  - **A group of friends first:** already in a group before your first Build Group, the button
    reads **Check Roles** and runs Blizzard's role check; once every member chose a role it
    reads Build Group, and their roles count. Whoever just confirms his role counts with it 15
    seconds after the click. Asked once - until you are alone again.
  - **Held places:** invited players keep their place for two minutes, and while they are in the
    group; whoever declines, lets the invite run out or is already in a group is not asked again.
  - **The button:** not listed yet, it reads **List Self** and lights up Blizzard's eye tab,
    where you list yourself with dungeon, play style and role. When the list is older than 30
    seconds it reads **Refresh List** first and clicks Blizzard's own refresh arrow. The chat
    names every invite; the tooltip says why the button is greyed out.
- **Minimap button** - left-click opens or closes the Group Finder as Blizzard's button and key
  do; right-click opens the settings; drag it around the minimap. The AddOn menu entry opens the
  settings too.
- **Settings** - the gear left of Reset Filter switches the panel to the language, the minimap
  button, the window background - a slider from invisible to solid for the panel and the bug
  report - and the bug report, and back.

## Installation

Install it with WowUp, which finds SmartGroupFilter on its own, or download it from
[CurseForge](https://www.curseforge.com/wow/addons/smartgroupfilter) or
[Wago](https://addons.wago.io/addons/smartgroupfilter) and unpack it into
`Interface\AddOns` of your WoW Forever folder.

## Chat commands

| Command | What it does |
|---|---|
| `/sgf` or `/sgf help` | Lists the chat commands |
| `/sgf minimap` | Hides or shows the minimap button |
| `/sgf bug` | Opens the bug report: describe the bug, copy the code into a GitHub issue |

## Languages

The addon speaks your client's language: English, German, French, Spanish (Spain and Mexico),
Italian, Brazilian Portuguese, Russian, Korean and Chinese (simplified and traditional). The
gear in the panel lets you choose another one.

## Privacy and security

- No addon messages. All it sends are group invites, the Group Finder's own search and one
  English whisper with an invite when a player's sign-up is ambiguous ("Tank for Shadowfang
  Keep?") - each from your click.
- No dynamic code.
- Saved settings are validated at login (types and ranges), so damaged files cannot break the
  addon.
- No personal data is stored: only your choices. The names of invited players and the names the
  Group Finder showed are kept in memory until you log out or reload - the bug report needs them
  to remove them.

## Data protection

This is not legal advice; it says how bug reports are handled.

- **Who is responsible** - ZulshiBLN, the author of SmartGroupFilter, Switzerland. Contact
  through GitHub: an issue, or - for anything that should not be public - a private
  vulnerability report on this repository (*Security > Report a vulnerability*).
- **What it holds** - the addon's and the client's version and language, your class and level
  band, SmartGroupFilter's settings, your listing's activity IDs, the list's counts, the Build
  Group button's state, invited players as role, class and level, how many members chose a role, SmartGroupFilter's errors and
  last actions, and what you type. It removes your character, realm and guild, your group and
  every name the Group Finder showed since your last login or reload; names it never saw can
  remain, so write none. "Show content" shows the text before you copy it.
- **Why** - you choose to send a report; it is used only to fix the bug you report (legitimate
  interest, GDPR Art. 6(1)(f); Swiss FADP). Nothing leaves the game unless you copy and post it.
- **Who receives it** - GitHub, Inc. (USA) hosts the issue. It is public, and people who watch
  the repository get a copy by e-mail. GitHub is responsible for what it hosts under its own
  [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement);
  for transfers to the USA it relies on the EU-U.S. and Swiss-U.S. Data Privacy Framework.
- **How long** - once the bug is fixed, the author removes report codes, with their edit
  history, from the issue; on request earlier, or the whole issue. Copies outside GitHub -
  e-mail notifications, web archives - cannot be recalled.
- **Your rights** - access, correction, deletion, restriction, portability and objection, through
  the contact above. You may also complain to the Swiss FDPIC or to the data protection
  authority of your EU country.
- **Under 16** - ask a parent before you post a report.

## Development

A checkout of this repository has one more chat command, `/sgf test`: it shows whom Build
Group would invite and why, the target dungeon and each whisper, and why every other single
player is left out - sending nothing. It lives in `DevTest.lua`, which the release package
leaves out (`#@do-not-package@` in the TOC, `ignore` in `.pkgmeta`). Specs: `busted`, `luacheck .`.

## License

[MIT](LICENSE), by ZulshiBLN.
