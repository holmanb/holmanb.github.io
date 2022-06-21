---
title: "Quickstart: Neovim Configuration for cloud-init"
---


Manually writing yaml cloud-configs is error prone and debugging can be
painful. Neovim can help us write configs faster and with more
confidence with editor integration.

This post will help you get up and running with cloud-init editor integration
for Neovim.

Here's an example completion list copied from my editor:
```vim
1 #cloud-config
2 users:
3   - name: holmanb
4     |
~       uid~                 Property
~       sudo                 Property
~       gecos                Property
~       shell                Property
~       groups               Property
~       passwd               Property
~       system~              Property
~       homedir~             Property
~       inactive             Property
~       snapuser             Property
~       expiredate~          Property
~       lock_passwd~         Property
~       no_log_init~         Property
~       selinux_user         Property
~       no_user_group~       Property
~       hashed_passwd        Property
~       create_groups~       Property
~       primary_group~       Property
~       ssh_import_id~       Property
~       no_create_home~      Property
~       plain_text_passwd    Property
~       ssh_redirect_user~   Property
~       ssh_authorized_keys~ Property
```


# Background

Since neovim has native LSP support, it can use many of the same language
servers available in VS Code (and any other language server that implements the
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/))
with just a little configuration.


Cloud-init uses a jsonschema for validating user configs. This can be manually
invoked via `cloud-init schema -c userdata.yml` starting with release 22.2 (May 2022).
The same schema will be used for editor hints.

We will also install and configure
[nvim-cmp](https://github.com/hrsh7th/nvim-cmp), a completion engine for
neovim, and [yamlls](https://github.com/redhat-developer/yaml-language-server)
language server, which is described as a "Language Server for YAML Files".

If you would rather test this functionality without modifying your configs,
you're in luck! Skip ahead to the
[quicktest]({{< ref "setup-neovim-cloud-init-completion.md#quicktest" >}})
section.


# Dependencies:

```
- neovim (version 0.6 or higher)
- npm
- curl
```

# Configurations

The configs are in separate files so that you can easily integrate them into
your existing config. After this section is complete, the directory
structure under `~/.config/nvim/` should look something like this:
```
.
├── init.vim
└── lua
    ├── lsp-config.lua
    └── nvim-cmp.lua
```

The init.vim installs plugins and sources configs for the LSP server and
completion plugin.

`/root/.config/nvim/init.vim`
```vim
" Install plugins
" ===============
call plug#begin()

" For language servers
Plug 'neovim/nvim-lspconfig'

" For nvim-cmp
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-nvim-lsp'

call plug#end()

" source lsp and cmp plugin configs
lua require'lsp-config'
lua require'nvim-cmp'
```

Note the keybinds for the completion engine.
`/root/.config/nvim/lua/nvim-cmp.lua`
```lua
-- Setup nvim-cmp.
local cmp = require'cmp'
cmp.setup({
mapping = {
['<C-n>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
['<C-p>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
['<Down>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
['<Up>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
['<C-d>'] = cmp.mapping.scroll_docs(-4),
['<C-f>'] = cmp.mapping.scroll_docs(4),
['<C-Space>'] = cmp.mapping.complete(),
['<C-e>'] = cmp.mapping.close(),
['<CR>'] = cmp.mapping.confirm({
  behavior = cmp.ConfirmBehavior.Replace,
  select = true,
  })
},
sources = {
  { name = 'nvim_lsp' },
}
})
```

The schema referenced is the latest version in the main branch. To
reference a specific release version (schemas change over time), one can
find the url location of the file in the release tag file tree and
update this value accordingly. These will soon be published on the schema store
for easier configuration.
`/root/.config/nvim/lua/lsp-config.lua`
```lua
-- yamlls config
require'lspconfig'.yamlls.setup{
  on_attach=on_attach,
  capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities()),
  settings = {
    yaml = {
      schemas = {
        ["https://raw.githubusercontent.com/canonical/cloud-init/main/cloudinit/config/schemas/versions.schema.cloud-config.json"]= "user-data.yml",
      }
    }
  }
}
```

# Install Language Server and Plugins
```bash
# install yamlls
npm i -g yaml-language-server

# install vim plugin manager
sh -c 'curl -fLo /root/.local/share/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# install yaml plugins
nvim +PlugInstall
```

At this point, opening a file named `user-data.yml` with neovim should start
the yamlls server and source the schema for yaml hints.

To view all available keys, use `<ctrl-space>` (in insert mode).

If `nvim` shows an error or doesn't behave as expected, I suggest executing
`:checkhealth` to check for errors, and `:help lsp` for more information.


# Quicktest

This [cloud config](https://gist.githubusercontent.com/holmanb/75e0974c759dd6180cdf74da6fd01551/raw/c70ffba3e454957754923eaf8060ef4b3feaaa27/user-data-schema-neovim.yml)
will configure neovim in an lxc container. This requires LXD.

To use this config, execute the following:

```bash
# Launch the image with the cloud-config
lxc launch images:ubuntu/kinetic/cloud neovim \
	-c cloud-init.user-data="$(curl https://gist.githubusercontent.com/holmanb/75e0974c759dd6180cdf74da6fd01551/raw/aed0f4f3c38a56d06309878b61e91d1a9dca0894/user-data-schema-neovim.yml)"

# This will take a couple of minutes - coffee break!
lxc exec neovim -- sh -c "cd /root && cloud-init status --wait && nvim user-data.yml"
```

Start typing and you should see the completions!

To view all available keys, use `<ctrl-space>` (in insert mode).

Stay curious!


# Credit

This post is heavily based on a post by Waylon Walker on
[neovim/yamlls configuration](https://waylonwalker.com/setup-yamlls/).
