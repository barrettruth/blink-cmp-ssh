rockspec_format = '3.0'
package = 'blink-cmp-ssh'
version = 'scm-1'

source = {
  url = 'git+https://github.com/barrettruth/blink-cmp-ssh.git',
}

description = {
  summary = 'SSH configuration completion source for blink.cmp',
  homepage = 'https://github.com/barrettruth/blink-cmp-ssh',
  license = 'MIT',
}

dependencies = {
  'lua >= 5.1',
}

test_dependencies = {
  'nlua',
  'busted >= 2.1.1',
}

test = {
  type = 'busted',
}

build = {
  type = 'builtin',
}
