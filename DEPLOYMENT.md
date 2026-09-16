# 🚀 Deployment Guide — Home Server Setup (21 Settembre 2026)

**Questo documento contiene tutti i step per configurare il notify-bot MCP server su DreamQuest Mini PC.**

---

## 📋 Prerequisiti

- ✅ DreamQuest Mini PC (Intel N95, 32GB RAM, 1TB storage)
- ✅ USB bootabile con Ubuntu 24.04 LTS
- ✅ Connessione internet stabile
- ✅ Telegram bot token (da @BotFather)
- ✅ Telegram chat ID
- ✅ Tailscale account + auth key
- ✅ GitHub token (per clone privato, se serve)

---

## 🔧 Fase 1: Installazione Ubuntu 24.04 LTS

### 1.1 Prepara USB Bootabile

**Su Mac/Linux:**
```bash
# Scarica ISO
wget https://releases.ubuntu.com/jammy/ubuntu-24.04-server-amd64.iso

# Crea USB (sostituisci /dev/diskX con il tuo device)
sudo diskutil unmountDisk /dev/diskX
sudo dd if=ubuntu-24.04-server-amd64.iso of=/dev/rdiskX bs=4m
sudo diskutil eject /dev/diskX
```

**Oppure usa Balena Etcher** (GUI, più facile):
- Scarica: https://www.balena.io/etcher/
- Seleziona ISO + USB
- Flash

### 1.2 Installa Ubuntu sul Mini PC

1. **Inserisci USB nel Mini PC**
2. **Accendi e avvia da USB** (premi Del/F2 durante boot per BIOS)
3. **Segui installer Ubuntu:**
   - Keyboard: Italian (o tua lingua)
   - Network: Ethernet (consigliato) o WiFi
   - Storage: Use entire disk (1TB)
   - Username: `homeserver`
   - Password: **FORTE** (ricordatela!)
   - SSH server: ✅ **Installa**
   - Automatic updates: ✅ Abilita

4. **Riavvia** quando finito

---

## 🌐 Fase 2: Primo Accesso e Setup Base

### 2.1 Trova IP del server

Sulla rete LAN, cerca l'IP (es. con `nmap` o router):
```bash
nmap -sn 192.168.1.0/24 | grep "DreamQuest\|homeserver"
```

O guarda il router DHCP per trovare l'IP assegnato.

### 2.2 SSH e Update del Sistema

```bash
# SSH dal tuo computer
ssh homeserver@192.168.1.XXX  # Sostituisci XXX con IP reale
# Password: quella che hai impostato

# Update sistema
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget nano htop

# Genera SSH key (per GitHub)
ssh-keygen -t ed25519 -f ~/.ssh/id_homeserver -C "homeserver@dreamquest"
cat ~/.ssh/id_homeserver.pub  # Copia e aggiungi su GitHub
```

### 2.3 Configura Firewall (opzionale ma consigliato)

```bash
sudo ufw enable
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 5000/tcp # MCP Server
sudo ufw status
```

---

## 📦 Fase 3: Deploy notify-bot

### 3.1 Clone Repository

```bash
cd ~
git clone https://github.com/MATEJ081/notify-bot.git
cd notify-bot
```

### 3.2 Configura .env

```bash
cp .env.example .env
nano .env  # Edita con i tuoi valori
```

**Edita questi campi:**
```env
BOT_TOKEN=your_telegram_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
DRY_RUN=true          # Cambia a false quando sei pronto per invii reali
RATE_LIMIT_PER_MINUTE=5
DEDUP_WINDOW_SECONDS=300
MCP_AUTH_TOKEN=your_secret_token_here  # Genera una password forte!
MCP_HOST=127.0.0.1    # Cambia a 0.0.0.0 se vuoi accesso locale
MCP_PORT=5000
```

**Come trovare Telegram Chat ID:**
1. Manda messaggio a [@userinfobot](https://t.me/userinfobot) su Telegram
2. Ti mostra il tuo chat ID

**MCP_AUTH_TOKEN (genera password forte):**
```bash
openssl rand -base64 32  # Copia questo
```

### 3.3 Run Deploy Script

```bash
# Test offline (opzionale)
bash test_offline.sh

# Deploy con systemd
sudo bash deploy.sh --systemd

# O con Tailscale (fase dopo)
sudo bash deploy.sh --tailscale
```

### 3.4 Verifica che il Service è Running

```bash
sudo systemctl status notify-bot.service
sudo journalctl -u notify-bot -f  # Vedi i log in tempo reale
```

Dovresti vedere:
```
[INFO] event=startup outcome=ok host=127.0.0.1 port=5000 dry_run=true
```

---

## 🌐 Fase 4: Tailscale Setup

### 4.1 Installa Tailscale sul server

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 4.2 Accedi a Tailscale

```bash
sudo tailscale login
# Oppure usa auth key per non-interactive:
sudo tailscale up --authkey=tskey-auth-XXXXXXX
```

Ottieni auth key da: https://login.tailscale.com/admin/settings/keys

### 4.3 Trova IP Tailscale

```bash
tailscale ip -4
# Output: 100.64.x.x
```

**Annota questo IP** — lo usi in Claude Code!

### 4.4 Installa Tailscale anche sul tuo computer

https://tailscale.com/download

---

## 💻 Fase 5: Configura Claude Code per MCP Server

### 5.1 Copia le credenziali dal server

```bash
# Sul server homeserver
echo $MCP_AUTH_TOKEN  # Mostra il token
tailscale ip -4      # Mostra IP Tailscale
```

Annota:
- **Tailscale IP**: `100.64.x.x`
- **MCP_AUTH_TOKEN**: (dal .env)

### 5.2 Configura Claude Code

Su **tuo computer** (dove usi Claude Code), crea o modifica:

**`~/.claude/settings.json`:**
```json
{
  "mcpServers": {
    "notify-bot": {
      "command": "curl",
      "args": [
        "-X", "POST",
        "http://100.64.x.x:5000/tools/send_telegram_message",
        "-H", "Authorization: Bearer YOUR_MCP_AUTH_TOKEN",
        "-H", "Content-Type: application/json",
        "-d", "@-"
      ],
      "env": {
        "MCP_SERVER_URL": "http://100.64.x.x:5000",
        "MCP_AUTH_TOKEN": "YOUR_MCP_AUTH_TOKEN"
      }
    }
  }
}
```

**Sostituisci:**
- `100.64.x.x` con il tuo IP Tailscale
- `YOUR_MCP_AUTH_TOKEN` con il token dal .env

### 5.3 Test di connessione

```bash
# Dal tuo computer, verifica che Tailscale è connesso
tailscale status

# Test curl al server
curl -X GET http://100.64.x.x:5000/health \
  -H "Authorization: Bearer YOUR_MCP_AUTH_TOKEN"

# Dovrebbe ritornare: {"status": "ok"}
```

---

## ✅ Test Finali

### 6.1 Test DRY-RUN (simulato)

```bash
# Dalla riga di comando sul server
python3 notify.py "Test message da dry-run"
# Output: [DRY RUN] Messaggio non inviato realmente...

# Oppure via MCP (da Claude Code)
# Dovresti vedere il tool disponibile
```

### 6.2 Abilita LIVE SEND (se tutto OK)

```bash
# Sul server, edita .env
nano .env
# Cambia: DRY_RUN=false

# Riavvia il service
sudo systemctl restart notify-bot.service
```

### 6.3 Test LIVE

```bash
# Manda un messaggio Telegram vero
python3 notify.py "Primo messaggio LIVE dal home server!"

# Dovresti ricevere il messaggio su Telegram
```

---

## 📊 Monitoring & Logs

### 7.1 Vedi log del service

```bash
# Ultimi 50 log
sudo journalctl -u notify-bot -n 50

# Segui i log in tempo reale
sudo journalctl -u notify-bot -f

# Per data specifica
sudo journalctl -u notify-bot --since "2 hours ago"
```

### 7.2 Vedi uptime e stats

```bash
# Status del service
sudo systemctl status notify-bot.service

# Vedi chi è loggato al dashboard
cat ~/.notifybot_audit_logs  # Se esiste
```

### 7.3 Se il service crashes

```bash
# Riavvia
sudo systemctl restart notify-bot.service

# O abilita auto-restart se non è già abilitato
sudo systemctl enable notify-bot.service
```

---

## 🔐 Security Checklist

- [ ] `.env` con permessi 600 (`sudo chmod 600 ~/.notifybot/.env`)
- [ ] SSH key su GitHub (non password)
- [ ] MCP_AUTH_TOKEN: password forte (32+ caratteri)
- [ ] DRY_RUN=true finché non sei sicuro
- [ ] Firewall abilitato (ufw)
- [ ] Tailscale authenticated e IP privato
- [ ] No tokens in git commit
- [ ] Rate limit configurato
- [ ] Audit log checking regolarmente

---

## 🆘 Troubleshooting

### "Connection refused" quando accedo al MCP server

```bash
# Verifica che il service sia running
sudo systemctl status notify-bot.service

# Verifica porta 5000 è in ascolto
sudo netstat -tlnp | grep 5000

# Verifica firewall
sudo ufw status
```

### "Permission denied" con sudo bash deploy.sh

```bash
# Dai permessi al file
chmod +x deploy.sh

# Oppure lancia come root
sudo -i
bash /home/homeserver/notify-bot/deploy.sh --tailscale
```

### Tailscale non si connette

```bash
# Ri-autentica
sudo tailscale logout
sudo tailscale up

# Verifica firewall (potrebbe bloccare WireGuard)
sudo ufw allow 41641/udp
```

### MCP server não vê il token

```bash
# Verifica che il token sia nel .env
grep MCP_AUTH_TOKEN ~/.notifybot/.env

# Verifica che il service sia ripartito dopo la modifica
sudo systemctl restart notify-bot.service
sudo journalctl -u notify-bot -n 5  # Vedi ultimi 5 log
```

---

## 📞 Supporto

- **Docs**: Vedi README.md e MCP_SETUP.md in repo
- **GitHub**: https://github.com/MATEJ081/notify-bot
- **Logs**: `sudo journalctl -u notify-bot -f`
- **Health check**: `curl http://localhost:5000/health`

---

## 🎯 Prossimi Step

Una volta tutto funzionante:

1. **Aggiungi monitoring** (cron job per health check)
2. **Backup config** (salva .env in luogo sicuro)
3. **Setup multi-user** (se Lucrezia vuole accesso SSH)
4. **CI/CD** (auto-update dal repo GitHub)
5. **Altri servizi** (Discord, Slack, etc. su MCP server)

---

**Good luck! 🚀 Contatta se hai domande durante il deploy!**
