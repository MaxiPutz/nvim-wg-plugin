-------------------------------------------------------------
-- MODULE TABLE
------------------------------------------------------------
local M = {}

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function file_exists(path)
	local stat = vim.loop.fs_stat(path)
	return stat ~= nil
end

local function read_file(path)
	local f, err = io.open(path, "r")
	if not f then
		return nil, err
	end
	local content = f:read("*a")
	f:close()
	return content
end

local function write_file(path, content, mode)
	mode = mode or "w"
	local f, err = io.open(path, mode)
	if not f then
		return nil, err
	end
	f:write(content)
	f:close()
	return true
end

local function trim(s)
	return (s:gsub("%s+$", ""))
end

local function get_next_client_name()
	local scandir = vim.loop.fs_scandir(".")
	local max_n = 0

	if not scandir then
		return "client1", 1
	end

	while true do
		local name, t = vim.loop.fs_scandir_next(scandir)
		if not name then
			break
		end
		if t == "directory" then
			local n = name:match("^client(%d+)$")
			if n then
				n = tonumber(n)
				if n > max_n then
					max_n = n
				end
			end
		end
	end

	local next_n = max_n + 1
	return ("client" .. next_n), next_n
end

local function detect_ip_base_and_max(wg_conf)
	local base, first_octet = wg_conf:match("Address%s*=%s*(%d+%.%d+%.%d+%.)(%d+)%s*/%d+")
	local max_octet = tonumber(first_octet or "1") or 1

	if base then
		local pattern = "AllowedIPs%s*=%s*" .. base:gsub("%.", "%%.") .. "(%d+)%s*/32"
		for oct in wg_conf:gmatch(pattern) do
			local n = tonumber(oct)
			if n and n > max_octet then
				max_octet = n
			end
		end
		return base, max_octet
	end

	base, first_octet = wg_conf:match("AllowedIPs%s*=%s*(%d+%.%d+%.%d+%.)(%d+)%s*/32")
	max_octet = tonumber(first_octet or "1") or 1

	if base then
		local pattern = "AllowedIPs%s*=%s*" .. base:gsub("%.", "%%.") .. "(%d+)%s*/32"
		for oct in wg_conf:gmatch(pattern) do
			local n = tonumber(oct)
			if n and n > max_octet then
				max_octet = n
			end
		end
		return base, max_octet
	end

	return nil, nil
end

local function generate_keypair()
	local priv = vim.fn.systemlist("wg genkey")[1]
	if not priv or priv == "" then
		return nil, nil, "wg genkey failed"
	end
	priv = trim(priv)

	local cmd = 'echo "' .. priv .. '" | wg pubkey'
	local pub = vim.fn.systemlist(cmd)[1]
	if not pub or pub == "" then
		return nil, nil, "wg pubkey failed"
	end
	pub = trim(pub)

	return priv, pub, nil
end

------------------------------------------------------------
-- CLIPBOARD HANDLING
------------------------------------------------------------
local use_osc52 = false

local function copy_to_clipboard(text)
	if use_osc52 then
		require("osc52").copy(text)
		vim.notify("Client config copied via OSC52 clipboard", vim.log.levels.INFO)
	else
		vim.fn.setreg("+", text)
		vim.notify("Client config copied to + register", vim.log.levels.INFO)
	end
end

------------------------------------------------------------
-- SERVER INITIALIZATION
------------------------------------------------------------
function M.init_server()
	if file_exists("wg0.conf") then
		vim.notify("wg0.conf already exists — aborting", vim.log.levels.ERROR)
		return
	end

	-- Generate server keys
	local priv, pub, err = generate_keypair()
	if err then
		vim.notify("Failed to generate server key: " .. err, vim.log.levels.ERROR)
		return
	end

	write_file("privatekey", priv .. "\n")
	write_file("publickey", pub .. "\n")

	local server_conf = string.format(
		[[
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = %s

# Forward von wg0 -> eth0 erlauben + Antworten zurück + NAT
PostUp   = iptables -A FORWARD -i %%i -o eth0 -j ACCEPT; iptables -A FORWARD -i eth0 -o %%i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %%i -o eth0 -j ACCEPT; iptables -D FORWARD -i eth0 -o %%i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
]],
		priv
	)

	write_file("wg0.conf", server_conf, "w")

	vim.notify("WireGuard server initialized successfully!", vim.log.levels.INFO)
end

------------------------------------------------------------
-- ADD PEER
------------------------------------------------------------
function M.add_peer()
	local cwd = vim.loop.cwd()
	vim.notify("nvim-add-peer: working directory: " .. cwd, vim.log.levels.INFO)

	if not file_exists("wg0.conf") then
		vim.notify("wg0.conf not found — run :WGInitServer first", vim.log.levels.ERROR)
		return
	end

	if not file_exists("publickey") then
		vim.notify("./publickey (server public key) not found", vim.log.levels.ERROR)
		return
	end

	local server_pub = trim(read_file("publickey"))
	local wg_conf = read_file("wg0.conf")

	local base_ip, max_octet = detect_ip_base_and_max(wg_conf)
	if not base_ip then
		vim.notify("Cannot detect base IP from wg0.conf", vim.log.levels.ERROR)
		return
	end

	local new_octet = max_octet + 1
	local client_name = get_next_client_name()
	local client_dir = client_name

	vim.fn.mkdir(client_dir, "p")

	local priv, pub, err = generate_keypair()
	if err then
		vim.notify("Failed to generate peer key: " .. err, vim.log.levels.ERROR)
		return
	end

	write_file(client_dir .. "/privatekey", priv .. "\n")
	write_file(client_dir .. "/publickey", pub .. "\n")

	local client_ip = base_ip .. tostring(new_octet)

	local peer_block = string.format(
		[[
[Peer]
# %s
PublicKey = %s
AllowedIPs = %s/32

]],
		client_name,
		pub,
		client_ip
	)

	write_file("wg0.conf", peer_block, "a")

	local client_conf = string.format(
		[[
[Interface]
PrivateKey = %s
Address = %s/32
DNS = 1.1.1.1

[Peer]
PublicKey = %s
Endpoint = your.server:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25

]],
		priv,
		client_ip,
		server_pub
	)

	write_file(client_dir .. "/wg0.conf", client_conf, "w")

	copy_to_clipboard(client_conf)

	vim.notify(string.format("Peer %s created with IP %s", client_name, client_ip), vim.log.levels.INFO)
end

------------------------------------------------------------
-- SETUP
------------------------------------------------------------
function M.setup(opts)
	opts = opts or {}
	use_osc52 = opts.osc52 or false

	-- Custom commands
	vim.api.nvim_create_user_command("WGAddPeer", function()
		M.add_peer()
	end, {})

	vim.api.nvim_create_user_command("WGInitServer", function()
		M.init_server()
	end, {})

	vim.notify("nvim-add-peer loaded (OSC52 = " .. tostring(use_osc52) .. ")", vim.log.levels.INFO)
end

return M
