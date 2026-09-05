# games

Game-related tools and scripts.

| Folder | Was | What |
|---|---|---|
| `fishing` | `fishing-WoW` | WoW fishing bot in Python with screen detection |
| `autobeggar` | `autobeggar` | WoW chat auto-response addon (Lua) |
| `cs2-round-notify` | `cs2-mtch-ntfy` | CS2 Game State Integration notifier for round events (C) |

The Vanilla Toolkit addon lives in its own repo, `vanilla-addon`, because WoW
loads it straight from a folder in `Interface/AddOns/` and it needs to stay
clone-shaped. It was briefly `toolkit/` here.

History from each source is preserved via `git subtree`; pre-merge commits are
reachable via the merge commit's second parent:

```sh
sha=$(git log --full-history --format=%H -- fishing | tail -1)
git log $sha^2
```
