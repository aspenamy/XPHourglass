# Hourglass

Hourglass puts your leveling stats on the Blizzard XP (experience) bar in
WoW Forever, so your time to level, XP per hour and rested XP are there at a
glance. Hover over the bar for the rest, including kills to level, quests
ready to turn in and how long your last level took.

The default bar keeps its look and its Edit Mode position, and your
reputation bar stays right where it was, since Hourglass only adds text and
a little shading on top of it.

## On the bar

- By default the left end shows how far through the level you are and your
  rested XP (`45.2% · 30% rested`), and the right end shows your XP per hour,
  time to level and kills to level (`12.3k xp/hr · 38m to level · ~14 kills`).
- Any of these can go on the left end, the right end or in the center, or be
  hidden and kept to the tooltip.
- XP from quests you've finished but haven't turned in yet is shaded gold on
  the bar. You can pick a different color for it in the settings.
- Blizzard's own XP numbers still show in the middle when you hover over the
  bar, and anything you've put in the center will adjust.

## In the tooltip

Time to level, XP per hour (recent and for the session), XP left in the
level, rested XP, kills to level, quests ready to turn in, time on this
level, how long your last level took and your session so far.

## How it works

- XP per hour is based on your last 15 minutes of play. You can change it to
  5, 30 or 60 minutes, or the whole session.
- The clock pauses while you're AFK.
- Kills to level is based on your last 10 kills and includes rested XP.
- Your session carries over a `/reload` or a relog within 10 minutes.
- When you level up, a chat message tells you how long the level took.
- If you install Hourglass partway through a level, that level's time shows
  with a `+`.

## Settings

Options > AddOns > Hourglass, or `/xph config`. You can choose where each
stat goes, the font, size, outline and position of the text, and the quest
shading color, and turn off anything you don't use.

To move the text, move the XP bar in Edit Mode.

## Commands

- `/xph` shows your stats in chat
- `/xph config` opens the settings
- `/xph reset` starts a new session
- `/hourglass` works the same as `/xph`
