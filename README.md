# SmartGroupFilter

A helper for the Group Finder in World of Warcraft: Forever. It docks a panel beside Blizzard's
own Looking For Group window, shortens the player list to the single players you need, and
builds your five-player group with one click.

**Status: in development** - version 0.1.0, not released yet.

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
  healer, three damage dealers. Each place takes the highest class in its row, then the highest
  level, then the longest wait; players without a role only fill what is left. Only free places
  are filled. Invited players keep their place for two minutes, and while they are in the
  group; whoever declines, lets the invite run out or is already in a group is not asked again.
  Not listed yet, the button reads **List Self** and opens Blizzard's listing page, where you
  choose the dungeon, play style and role. When the list is older than 30 seconds it reads
  **Refresh List** first and clicks Blizzard's own refresh arrow. The chat names every invite; the button's tooltip says why it is
  greyed out.

## Installation

Not published yet. Once it is, it will be on CurseForge and Wago, and WowUp will find it.

## Chat commands

| Command | What it does |
|---|---|
| `/sgf` or `/sgf help` | Lists the chat commands |
| `/sgf test` | Shows whom Build Group would invite and why, and why every other single player is left out - sends nothing |

## Languages

The addon speaks your client's language: English, German, French, Spanish (Spain and Mexico),
Italian, Brazilian Portuguese, Russian, Korean and Chinese (simplified and traditional).

## Privacy and security

- No addon messages and no chat messages to other players. All it sends are group invites and
  the Group Finder's own search, each from your click.
- No dynamic code.
- Saved settings are validated at login (types and ranges), so damaged files cannot break the
  addon.
- No personal data is stored: only your choices. The names of invited players are kept in memory
  until you log out or reload.

## Data protection

This is not legal advice; it says how bug reports are handled.

- **Who is responsible** - ZulshiBLN, the author of SmartGroupFilter, Switzerland. Contact
  through GitHub: an issue, or - for anything that should not be public - a private
  vulnerability report on this repository (*Security > Report a vulnerability*).
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

## License

[MIT](LICENSE), by ZulshiBLN.
