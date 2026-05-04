# blink-cmp-ssh

SSH configuration completion source for
[blink.cmp](https://github.com/saghen/blink.cmp).

> [!NOTE]
> Due to GitHub's historic unreliability, development, issues, and pull requests
> have moved to
> [Forgejo](https://git.barrettruth.com/barrettruth/blink-cmp-ssh).

![blink-cmp-ssh preview](https://github.com/user-attachments/assets/75927ef9-4af8-481a-bd17-01713de48280)

## Features

- Completes `ssh_config` keywords with man page documentation
- Provides enum values for keywords with known option sets (ciphers, MACs, key
  exchange algorithms, etc.)
- Keyword and enum data fetched asynchronously at runtime via `man ssh_config`
  and `ssh -Q`

## Requirements

- Neovim 0.10.0+
- [blink.cmp](https://github.com/saghen/blink.cmp)
- `ssh` and `man` executables

## Installation

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  'https://git.barrettruth.com/barrettruth/blink-cmp-ssh',
})
```

Or via [luarocks](https://luarocks.org/modules/barrettruth/blink-cmp-ssh):

```
luarocks install blink-cmp-ssh
```

Configure `blink.cmp`:

```lua
require('blink.cmp').setup({
  sources = {
    default = { 'ssh' },
    providers = {
      ssh = {
        name = 'SSH',
        module = 'blink-cmp-ssh',
      },
    },
  },
})
```
