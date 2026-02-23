# blink-cmp-ssh

SSH configuration completion source for
[blink.cmp](https://github.com/saghen/blink.cmp).

<img width="1920" height="1200" alt="image" src="https://github.com/user-attachments/assets/75927ef9-4af8-481a-bd17-01713de48280" />

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

Install via [luarocks](https://luarocks.org/modules/barrettruth/blink-cmp-ssh):

```
luarocks install blink-cmp-ssh
```

Or with lazy.nvim:

```lua
{
  'saghen/blink.cmp',
  dependencies = {
    'barrettruth/blink-cmp-ssh',
  },
  opts = {
    sources = {
      default = { 'ssh' },
      providers = {
        ssh = {
          name = 'SSH',
          module = 'blink-cmp-ssh',
        },
      },
    },
  },
}
```
