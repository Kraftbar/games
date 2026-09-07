# personalFinanceHelper
<br/>

### Install from the games repository

Clone `games` outside the WoW installation, then link this addon folder into
`Interface/AddOns`. WoW needs `autobeggar.toc` directly inside the addon folder.

```sh
mkdir -p ~/github
git clone https://github.com/Kraftbar/games.git ~/github/games
ln -s ~/github/games/autobeggar ~/Games/WOW-Classic/Interface/AddOns/autobeggar
```

If `~/github/games` already exists, skip the clone. Adjust the WoW path for your
installation. If `AddOns/autobeggar` already exists, preserve any local edits
before replacing it with the link.

Update with `git -C ~/github/games pull --ff-only`. For installations where
symlinks are unavailable, copy `games/autobeggar` into `Interface/AddOns` and
repeat the copy after updating the repository.


### todo
- [ ] Respond to chat
- [ ] Hide HS when clicked


### ideas
> not loaded when not female  
> 2D array with string for agressiveness  


### ide
>**[ZeroBraneStudio](https://github.com/pkulchenko/ZeroBraneStudio)**    
