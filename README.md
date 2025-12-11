# nvim-wg-plugin

A lightweight Neovim plugin to manage **WireGuard servers directly inside Neovim**.
Initialize a server, generate keys, create peers, update `wg0.conf`, and automatically copy client configurations to your clipboard — all without leaving your editor.

Perfect for sysadmins working over SSH, developers building VPN setups, or anyone maintaining WireGuard nodes.

---

## ✨ Features

### 🔞 Server Initialization — `:WGInitServer`

Automatically creates a fully working WireGuard server config in the current directory:

- `privatekey` – server private key  
- `publickey`  – server public key  
- `wg0.conf`   – default WireGuard configuration with:

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <privatekey>

# Forward von wg0 -> eth0 erlauben + Antworten zurück + NAT
PostUp   = iptables -A FORWARD -i %i -o eth0 -j ACCEPT; iptables -A FORWARD -i eth0 -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -o eth0 -j ACCEPT; iptables -D FORWARD -i eth0 -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

### 🧩 Add New Peer — `:WGAddPeer`

For each new peer, the plugin:

- Detects the next free client name (`client1`, `client2`, …)
- Detects the next available IP inside the WireGuard subnet (e.g. `10.0.0.2/32`, `10.0.0.3/32`, …)
- Creates a directory:

```text
clientN/
  privatekey
  publickey
  wg0.conf
```

- Appends a new `[Peer]` block to the server `wg0.conf`
- Copies the generated client config to your clipboard:
  - via **OSC52** (terminal clipboard) if enabled
  - otherwise into the `+` register (system clipboard)

### 🖥 Clipboard support

- **OSC52** (terminal clipboard, ideal for SSH sessions)  
- **`+` register** (default system clipboard)

### 📏 Auto-incrementing peers

- Automatically finds the highest used peer IP and increments it.
- Automatically finds the highest `clientN` directory and increments it.

### 🧰 Minimal dependencies

- Requires WireGuard tools: `wg`, `wg pubkey`
- `ojroques/nvim-osc52` is optional (for OSC52 clipboard support)

---

## 📦 Installation (lazy.nvim)

```lua
{
  "MaxiPutz/nvim-wg-plugin",
  dependencies = {
    "ojroques/nvim-osc52", -- optional, only needed if you want OSC52 clipboard
  },
  config = function()
    require("nvim-wg-plugin").setup({
      -- If true: copy configs via OSC52 (for SSH/terminal)
      -- If false or omitted: copy configs to the + register
      osc52 = false,
    })
  end,
}
```

---

## 🚀 Usage

### 1. Initialize a WireGuard server

In the directory where you want your WireGuard config (e.g. `/etc/wireguard`):

```vim
:WGInitServer
```

This creates:

```text
privatekey
publickey
wg0.conf
```

`wg0.conf` will have a default `[Interface]` config with:

- Address: `10.0.0.1/24`
- ListenPort: `51820`
- NAT + forwarding rules via iptables

> **Note:** You may need to adjust `eth0` to match your real network interface (e.g. `ens3`, `enp1s0`, …).

---

### 2. Add a new peer

From the same directory (where `wg0.conf` lives):

```vim
:WGAddPeer
```

This will:

1. Scan existing peers / IPs in `wg0.conf`
2. Determine the next free IP in the subnet (e.g. `10.0.0.2/32`, `10.0.0.3/32`, …)
3. Create a new folder:

```text
client1/
client2/
client3/
...
```

4. Inside the new folder, it creates:

```text
privatekey
publickey
wg0.conf
```

5. Append a new `[Peer]` block to the server `wg0.conf`
6. Copy the generated client configuration to your clipboard

You can then paste the client config directly into the WireGuard mobile or desktop app.

---

## 🗂 Directory Structure

After initializing and adding some peers, your directory might look like this:

```text
.
├── privatekey
├── publickey
├── wg0.conf
├── client1
│   ├── privatekey
│   ├── publickey
│   └── wg0.conf
├── client2
│   ├── privatekey
│   ├── publickey
│   └── wg0.conf
└── ...
```

The plugin always operates based on the **current working directory**.
Check with:

```vim
:pwd
```

---

## ⚙️ Configuration Options

`setup()` accepts a single (optional) table:

```lua
require("nvim-wg-plugin").setup({
  osc52 = false, -- default: use + register
})
```

### Available options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| osc52  | bool | false   | If `true`, use OSC52 clipboard. Otherwise use the `+` register. |

Behavior matrix:

| Call                                | `use_osc52` |
|-------------------------------------|-------------|
| `setup()`                           | `false`     |
| `setup({})`                         | `false`     |
| `setup({ osc52 = false })`          | `false`     |
| `setup({ osc52 = true })`           | `true`      |

---

## 📄 Example Client Configuration

A typical generated client configuration looks like this:

```ini
[Interface]
PrivateKey = <client private key>
Address    = 10.0.0.X/32
DNS        = 1.1.1.1

[Peer]
PublicKey  = <server public key>
Endpoint   = your.server:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

You can paste this directly into the WireGuard app on your phone or laptop.

---

## 💡 Tips

### Show current working directory

```vim
:pwd
```

### Reload plugin (lazy.nvim)

```vim
:Lazy reload nvim-wg-plugin
```

### Show messages / errors

```vim
:messages
```

---

## 🗇️ Roadmap / Ideas

Planned or possible future features:

- [ ] `:WGDeletePeer` — safely remove a peer and clean `wg0.conf`
- [ ] QR code output (for mobile import) using `qrencode`
- [ ] Automatic `wg syncconf` execution after changes
- [ ] Customizable server endpoint (prompt or config option)
- [ ] Support for custom IP ranges and subnets
- [ ] Telescope integration or a small UI for managing peers

---

## 🤝 Contributing

Contributions, ideas, issues, and PRs are very welcome!
If you have improvements for UX, safety, or additional features, feel free to open an issue or a pull request.

---

## ⭐ Support

If this plugin helps you manage WireGuard more efficiently, please consider giving it a ⭐ on GitHub:

👉 https://github.com/MaxiPutz/nvim-wg-plugin
