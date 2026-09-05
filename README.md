# wow

World of Warcraft addons and scripts, consolidated from three repositories.

| Folder | Was | What |
|---|---|---|
| `toolkit` | `vanilla-addon` | Modular WoW 1.12 addon: combat tracking, time-to-death warnings, auction economics, Aux offline search |
| `fishing` | `fishing-WoW` | Fishing bot in Python with screen detection |
| `autobeggar` | `autobeggar` | Chat auto-response addon (Lua) |

History from each source is preserved via `git subtree`. Pre-merge commits are
not reachable through `git log -- <folder>`; walk the merge's second parent:

```sh
sha=$(git log --full-history --format=%H -- toolkit | tail -1)
git log $sha^2
```
