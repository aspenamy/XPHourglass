# Hourglass

A lightweight leveling addon for World of Warcraft: Forever. It writes your
time to level, XP per hour and rested XP onto Blizzard's own XP bar, and
puts the rest in the bar's tooltip. There's no extra window to place and
nothing replaces or hides the default bar, so it keeps its look, its Edit
Mode position and the reputation bar next to it.

## What it shows

On the bar, at the left end: how far through the level you are and your
rested XP, like `45.2%  ·  30% rested`. At the right end: your XP per hour,
time to level and kills to level, like `12.3k xp/hr  ·  38m to level  ·  ~14 kills`.
Blizzard's own XP numbers still show in the middle when you hover.

Hovering the bar adds:

- Time to level, and XP per hour from recent play and for the whole session
- XP left in the level
- Rested XP, as XP and as a share of the level
- About how many kills are left, from your last 10 kills
- Quests in your log that are ready to turn in, and how much XP they're worth
- Time on this level, and how long the last level took
- The session so far: time played, XP and levels gained

The part of the bar your finished quests will fill is shaded gold, so you
can see how far a trip back to town will take you.

## How the numbers work

- **XP per hour follows what you're doing now.** It's worked out from the
  last 15 minutes of play by default (5, 30 or 60 minutes, or the whole
  session, in the settings).
- **The clock stops while you're AFK**, so a break doesn't pull your pace
  down. Time on the level stops too. You can turn this off.
- **No wild numbers right after logging in.** For the first 3 minutes the
  rate counts as at least 3 minutes of play, so one quest turn-in doesn't
  show as a million XP an hour.
- **Kills to level counts rested XP.** While you're rested, kills are worth
  double until the rested XP runs out, and the estimate allows for that.
- **A /reload doesn't lose your session.** Neither does logging back in
  within 10 minutes.
- **Level times are per character** and only count time you were logged in.
  If you install Hourglass partway through a level, that level's time is
  shown with a `+`, since the time before it was installed isn't known.
- **A chat line on level up** says how long the level took.

## Settings

Options > AddOns > Hourglass, or `/xph config`.

- **Where each stat goes.** Percent, rested XP, XP per hour, time to level
  and kills to level can each go on the left end of the bar, the center, the
  right end, or be hidden and kept to the tooltip. Center text makes way for
  Blizzard's own XP numbers while you hover the bar.
- **Text.** Font, size and outline, plus how far in from the ends of the bar
  the text sits and a pixel-by-pixel nudge up or down. The font list includes
  fonts shared by other addons through LibSharedMedia, if you have any.
- **Quest shading color.** A color picker, with an opacity slider for how
  much of the bar shows through, and a reset back to gold.
- **The rest.** Quest shading on or off, the tooltip lines, how much recent play XP per
  hour is worked out from, the AFK pause and the level-up line.

The text stays on Blizzard's XP bar, so to move the whole thing, move the
bar in Edit Mode and the text goes with it.

## Commands

- `/xph` shows your stats in chat
- `/xph config` opens the settings
- `/xph reset` starts the session over
- `/hourglass` works the same as `/xph`

## Works with

Blizzard's XP bar, wherever Edit Mode puts it. If another addon replaces the
XP bar, Hourglass says so in chat once and `/xph` still shows your stats.
