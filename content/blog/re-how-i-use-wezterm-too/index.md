---
title: "re: how i use wezterm"
---

While configuring Wezterm, I stumbled across Matthew O'Phinney's blog
post about Wezterm.

This post is based on his, so if you haven't read it yet
[go read his first](https://mwop.net/blog/2024-07-04-how-i-use-wezterm.html).

# How I Chose Wezterm

I used to use exclusively tiling window managers (i3-> sway -> DWM*). For
practical reasons I have used custom keybindings for tiling windows and
swapping workspaces on Gnome. What started as constant tmux use turned
occasional and was eventually superseded by vim's (later neovim) split windows.

Gnome-terminal was less than satisfactory but hadn't bothered with custom
terminals** until recently.

I use Wayland and enjoy writing core code in modern type-safe languages. My
neovim configuration enjoys the flexibility of Lua. Wezterm stood
out when compared to the other modern terminal emulator options.

# How Matthew uses Wezterm

His post was a fantastic introduction. It adds nice functional additions on top
of the default configuration. Sessions were the original reason that I took
interest in his post. The ability to switch between and resize neovim windows
and Wezterm panes using the same keybindings was interesting. I had never used
the tmux plugin that he mentioned, but I saw the benefit in that and was
intrigued.

# Another look at the integration plugin

After experimenting with the configuration that he shared, I took another look
at the neovim integration plugin. Depending on it made me uncomfortable for a
number of reasons:

1. last update was 3 years ago
2. low user activity (3 forks / 41 stars including mine)
3. depends on deprecated behavior

None of the above is a dealbreaker for short-term use, but my experience with
neovim is that the community is large and moves fast; lots of little projects
get left behind as APIs change and larger projects gain community traction. The
extra source dependency wasn't appealing either.

Upon inspecting the code, I realized that the entire utility is 32 lines of go:
a single RPC call.

# A small change in the tooling

I set out to remove the dependency on the deprecated environment variable and
Go.

## Deprecated $NVIM_LISTEN_ADDRESS

The plugin uses the pane ID to tell neovim where to open the RPC socket for the
server to listen on. This is what it used `$NVIM_LISTEN_ADDRESS` is used for.

This environment variable [is
deprecated](https://neovim.io/doc/user/deprecated.html#_environment-variables)
because it overloaded for too many things which causes problems in various
ways. The location of the socket file can be set using `--listen`, so a simple
shell alias allows us to tell neovim where to set the unix socket. Wezterm
communicates the pane ID to the current shell via the `$WEZTERM_PANE`
environment variable. If this environment variable exists, we can tell neovim
to use it with the following in `.bashrc`.

```
## wezterm <-> neovim integration
#
# this sets the pane to a known filepath when neovim is invoked in a wezterm pane
# see ~/.weztermrc for where this gets used
#
# note: NVIM_RUNTIME_DIR is deprecated, and NVIM does not set socket location, per the docs
# --listen is the preferred way to set the primary socket
if [ -n "$WEZTERM_PANE" ]; then
    alias nvim='nvim --listen $XDG_RUNTIME_DIR/wezterm/pane-${WEZTERM_PANE}.sock'
fi wezterm <-> neovim integration
#
# this sets the pane to a known filepath when neovim is invoked in a wezterm pane
# see ~/.weztermrc for where this gets used
#
# note: NVIM_RUNTIME_DIR is deprecated, and NVIM does not set socket location, per the docs
# --listen is the preferred way to set the primary socket
if [ -n "$WEZTERM_PANE" ]; then
    alias nvim='nvim --listen $XDG_RUNTIME_DIR/wezterm/pane-${WEZTERM_PANE}.sock'
fi
```

## Golang dependency

Wezterm is configured in lua. Neovim is configured in lua. Go as a language
doesn't add a benefit - and thankfully isn't required.

Neovim supports using the `nvim` command itself
[for RPC calls](https://neovim.io/doc/user/remote.html) with running neovim
sessions.

The following command in a key press event handler is sufficient to indicate
whether the key press should be redirected to neovim or kept within Wezterm:

```bash
nvim --headless --server <socket file> --remote-expr 'winnr() == winnr("<direction>")'
```

The `winnr() == winnr("<>")` piece above just checks to see if there is another
neovim window in the direction of the key press. If they are the same number,
then the key press is directed to Wezterm, otherwise sit is sent to neovim.

```lua
-- Wezterm <-> nvim pane integration
--
-- Before switching or resizing a wezterm pane, check first whether
-- switching or resizing a neovim window would be preferred.
--
-- This requires the neovim socket to be discoverable by wezterm at a known
-- location. NVIM_RUNTIME_DIR is the deprecated way to do that, '--listen' is
-- preferred. Therefore, set the following in your shell configuration
--
-- if [ -n "$WEZTERM_PANE" ]; then
--     alias nvim="nvim --listen $XDG_RUNTIME_DIR/wezterm/pane-${WEZTERM_PANE}.sock"
-- fi
--
-- This uses neovim as an RPC client to discover the position of the current window.
--
local commands_for_nvim = function(pane, direction)
	-- if nvim is installed locally rather than system-wide, set this variable to
    -- the correct path, otherwise Wezterm won't be able to find it and the nvim
    -- command will exit with error code 127.
	local nvim_path = "nvim"
	local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
	if not runtime_dir then
		-- no XDG_RUNTIME_DIR, no neovim pane integration
		-- it is probably possible to support no XDG_RUNTIME_DIR -> why bother?
		wezterm.log_warn("Environment variable XDG_RUNTIME_DIR not set, neovim integration not supported.")
		return false
	end

	-- no socket exists, no neovim running in this pane
	-- this assumes neovim was started with
	local socket_dir = tostring(runtime_dir) .. "/wezterm/"
	local socket = socket_dir .. "pane-" .. tostring(pane:pane_id()) .. ".sock"

	-- standard library doesn't give you tools to check if a path exists
	for _, file_name in ipairs(wezterm.read_dir(socket_dir)) do
		if file_name == socket then
			local cmd = nvim_path
				.. " --headless --server "
				.. socket
				.. " --remote-expr 'winnr() == winnr(\""
				.. direction
				.. '")'
				.. "'"
			local handle = io.popen(cmd)
			if not handle then
				wezterm.log_error("Failed to send RPC to neovim server: " .. cmd)
				return false
			end
			local result = handle:read("*a")
			-- this is weird but not well documented and it works?
			local rc = { handle:close() }
			local exit_code = rc[3]
			if exit_code ~= 0 then
				wezterm.log_error("Failed to run RPC command: " .. cmd .. " - ")
				wezterm.log_error(rc)
			end

			-- a debug log level would be nice, but since info events are
			-- logged, leave this commented out unless debugging
			-- wezterm.log_info(cmd .. " result: " .. tostring(result))
			if "0" == result then
				return true
			else
				return false
			end
		end
	end

	return false
end
```

That did most of the heavy lifting - now we just need to update the
`move_around()` and `vim_resize()` function from Matthew's post:

```lua
-- move: integrate Wezterm and neovim keybindings
local move_around = function(window, pane, direction_wez, direction_nvim)
	if commands_for_nvim(pane, direction_nvim) then
		window:perform_action(act({ SendString = "\x17" .. direction_nvim }), pane)
	else
		window:perform_action(act({ ActivatePaneDirection = direction_wez }), pane)
	end
end

-- resize: integrate Wezterm and neovim keybindings
local vim_resize = function(window, pane, direction_wez, direction_nvim)
	if commands_for_nvim(pane, direction_nvim) then
		window:perform_action(act({ SendString = "\x1b" .. direction_nvim }), pane)
	else
		window:perform_action(act({ AdjustPaneSize = { direction_wez, 2 } }), pane)
	end
end
```

There you have it. No extra dependencies or deprecated environment variables!

Thanks, Matthew!

# Notes

* a workflow based around the concept that single window could live on multiple
  workspace was powerful for me

** okay fine, I used to use terminator and `urxvt`, probably some others too

