# 📚 Knowledge Management System — Fase 2 (Post 21 Settembre)

**Questo documento descrive come configurare Obsidian + automazione per creare una memoria centralizzata di tutti i progetti, funzioni e decisioni architetturali.**

---

## 🎯 Visione

Una **knowledge base centralizzata** che:
- ✅ Vive sul server (accessibile da ovunque via Tailscale)
- ✅ Memorizza funzioni, patterns, logiche di tutti i progetti
- ✅ Auto-aggiorna quando crei/modifichi progetti
- ✅ Accessibile via web browser (Obsidian Remote)
- ✅ Base per future automazioni e AI training

---

## 📦 Fase 2 Architecture

```
Home Server
├── Claude Code CLI (SSH via Tailscale)
├── Obsidian Server
│   ├── Vault: ~/obsidian/knowledge-base
│   ├── Obsidian Remote (web access)
│   └── Sync su GitHub (backup)
├── Project Analyzer (Python script)
│   ├── Scansiona repo GitHub
│   ├── Estrae funzioni/patterns
│   ├── Genera note Obsidian
│   └── Cron job (daily auto-run)
└── Tailscale (connessione privata)
    └── Accesso web a Obsidian Remote
```

---

## ⚙️ Step 1: Installa Obsidian sul Server

### 1.1 Scarica Obsidian AppImage

```bash
ssh homeserver@100.64.x.x
cd ~
mkdir -p obsidian
cd obsidian

# Scarica AppImage (headless server version)
wget https://github.com/obsidianmd/obsidian-releases/releases/download/latest/Obsidian-latest.AppImage
chmod +x Obsidian-latest.AppImage

# Oppure usa Obsidian CLI (più leggero per server)
npm install -g obsidian-cli
```

### 1.2 Crea Vault

```bash
cd ~/obsidian
mkdir knowledge-base
cd knowledge-base

# Inizializza come vault Obsidian
# (crea .obsidian folder automaticamente)
```

### 1.3 Setup Obsidian Remote (Web Access)

**Metodo A: Obsidian Remote (ufficiale, richiede account Obsidian)**

1. Accedi a https://obsidian.md/account
2. Abilita "Obsidian Sync"
3. Collega il vault sul server
4. Accedi da web: https://obsidian.md/account/login

**Metodo B: Alternative Open-Source (no account)**

- **Vimwiki + Nginx**: Serve il vault via HTTP
- **Mkdocs**: Documenti come static site
- **Zk-Notebook**: Zettelkasten web UI

---

## 📁 Step 2: Struttura Vault

Crea questa struttura in `~/obsidian/knowledge-base/`:

```
knowledge-base/
├── projects/
│   ├── notify-bot/
│   │   ├── overview.md
│   │   ├── functions.md
│   │   ├── architecture.md
│   │   └── decisions.md
│   └── [altri progetti]
├── patterns/
│   ├── rate-limiting.md
│   ├── state-management.md
│   ├── auth-flow.md
│   └── [altri patterns]
├── functions/
│   ├── telegram_notifier.py.md
│   ├── mcp-server-setup.md
│   └── [altre funzioni]
├── decisions/
│   ├── docker-vs-systemd.md
│   ├── tailscale-for-vpn.md
│   └── [altre decisioni ADR]
├── memory/
│   ├── learned-lessons.md
│   ├── common-mistakes.md
│   └── optimization-tips.md
└── dashboard.md (index principale)
```

### 2.1 File Template

**projects/[nome]/overview.md:**
```markdown
# [Progetto Name]

## Descrizione
[What is this project about]

## Repository
[GitHub link]

## Key Functions
- `function_name()` — what it does
- `another_func()` — what it does

## Architecture Decisions
[[decision-name]]

## Patterns Used
[[pattern-name]]

## Status
- Created: YYYY-MM-DD
- Last Updated: YYYY-MM-DD
- Status: Active/Archived

## Related Projects
[[other-project]]
```

**patterns/[pattern-name].md:**
```markdown
# [Pattern Name]

## Description
[What is this pattern]

## When to Use
[When should this be applied]

## Implementation
[Code example or description]

## Projects Using This
- [[project-name]]

## Lessons Learned
[What we learned from using this]
```

---

## 🤖 Step 3: Project Analyzer Script

### 3.1 Crea script Python

File: `~/obsidian/project-analyzer.py`

```python
#!/usr/bin/env python3
"""
Auto-analyze GitHub repos and generate Obsidian notes
"""

import os
import json
import subprocess
from pathlib import Path
from datetime import datetime
import re

VAULT_PATH = Path.home() / "obsidian" / "knowledge-base"
GITHUB_USERNAME = "MATEJ081"  # Sostituisci con tuo username

def clone_or_update_repo(repo_name):
    """Clone/update repo locally"""
    repo_path = Path("/tmp") / repo_name
    repo_url = f"https://github.com/{GITHUB_USERNAME}/{repo_name}.git"
    
    if repo_path.exists():
        os.system(f"cd {repo_path} && git pull")
    else:
        os.system(f"git clone {repo_url} {repo_path}")
    
    return repo_path

def extract_functions(repo_path):
    """Extract function definitions from Python files"""
    functions = []
    
    for py_file in repo_path.glob("**/*.py"):
        with open(py_file) as f:
            content = f.read()
            # Regex per def nome_funzione
            matches = re.finditer(r'def\s+(\w+)\s*\([^)]*\):', content)
            for match in matches:
                functions.append({
                    "name": match.group(1),
                    "file": str(py_file.relative_to(repo_path)),
                    "type": "function"
                })
    
    return functions

def extract_patterns(repo_path):
    """Identify common patterns in codebase"""
    patterns = []
    
    # Scansiona per patterns comuni
    for py_file in repo_path.glob("**/*.py"):
        with open(py_file) as f:
            content = f.read()
            
            if "rate_limit" in content or "RateLimit" in content:
                patterns.append("rate-limiting")
            if "authentication" in content or "auth" in content:
                patterns.append("authentication")
            if "logging" in content:
                patterns.append("logging")
            if "async" in content:
                patterns.append("async-patterns")
    
    return list(set(patterns))

def generate_project_note(repo_name, repo_path):
    """Generate Obsidian note for project"""
    
    functions = extract_functions(repo_path)
    patterns = extract_patterns(repo_path)
    
    # Read README
    readme_content = ""
    readme_file = repo_path / "README.md"
    if readme_file.exists():
        readme_content = readme_file.read_text()[:500]  # First 500 chars
    
    # Create note content
    note_content = f"""# {repo_name}

## Description
[Auto-generated from GitHub repo]

{readme_content}

## Functions Found
"""
    
    for func in functions:
        note_content += f"- `{func['name']}()` — from {func['file']}\n"
    
    note_content += f"""
## Patterns Detected
"""
    for pattern in patterns:
        note_content += f"- [[{pattern}]]\n"
    
    note_content += f"""
## Metadata
- Repository: https://github.com/{GITHUB_USERNAME}/{repo_name}
- Last Analyzed: {datetime.now().isoformat()}
- Functions Count: {len(functions)}
- Patterns: {len(patterns)}
"""
    
    # Write to vault
    project_dir = VAULT_PATH / "projects" / repo_name
    project_dir.mkdir(parents=True, exist_ok=True)
    
    note_path = project_dir / "overview.md"
    note_path.write_text(note_content)
    
    print(f"✅ Generated note: {note_path}")

def main():
    """Main analyzer loop"""
    
    # List your repos (sostituisci con i tuoi)
    repos = ["notify-bot"]  # Aggiungi altri progetti
    
    for repo in repos:
        print(f"\n📦 Analyzing {repo}...")
        repo_path = clone_or_update_repo(repo)
        generate_project_note(repo, repo_path)
    
    print("\n✅ Analysis complete!")

if __name__ == "__main__":
    main()
```

### 3.2 Rendi eseguibile e testa

```bash
chmod +x ~/obsidian/project-analyzer.py

# Test manuale
python3 ~/obsidian/project-analyzer.py
```

### 3.3 Cron job (auto-run giornaliero)

```bash
# Edit crontab
crontab -e

# Aggiungi questa riga (esegui ogni giorno a mezzanotte)
0 0 * * * python3 /home/homeserver/obsidian/project-analyzer.py >> /home/homeserver/obsidian/analyzer.log 2>&1
```

---

## 🌐 Step 4: Accedi via Browser

### 4.1 Obsidian Sync (ufficiale)

Se usi Obsidian Sync:
1. Accedi a https://obsidian.md
2. Apri il vault dal browser
3. Accedi via Tailscale IP se preferisci locale

### 4.2 Alternativa: Serve Vault via HTTP

```bash
# Installa Python http.server
cd ~/obsidian/knowledge-base

# Serve semplice (non per produzione!)
python3 -m http.server 8080

# Accedi: http://100.64.x.x:8080 (da Tailscale)
```

---

## 📊 Step 5: Integra con Claude Code

Quando usi Claude Code sul server, la memoria:
- ✅ Vive in `~/.claude/projects/-home-claude/memory/`
- ✅ Sincronizza manualmente a Obsidian con script
- ✅ Oppure auto-sync via symlink

**Setup symlink (per auto-sync):**

```bash
cd ~/obsidian/knowledge-base/memory
ln -s ~/.claude/projects/-home-claude/memory/* .

# Ora tutti i .md della memoria di Claude Code appaiono in Obsidian
```

---

## 🔄 Workflow Giornaliero

1. **Lavora su progetto** con Claude Code (via SSH)
   ```bash
   ssh homeserver@100.64.x.x
   claude code [project]
   ```

2. **Salva lezioni apprese** in memo personale
   ```bash
   # In Claude Code session
   # Memory auto-saves in ~/.claude/projects/.../memory/
   ```

3. **Ogni notte**, cron job:
   - Scansiona i tuoi repo GitHub
   - Estrae funzioni/patterns nuovi
   - Genera/aggiorna note Obsidian

4. **Accedi alla memoria** via browser
   ```
   https://obsidian-remote.100.64.x.x:8080
   # (via Tailscale)
   ```

---

## 📝 Obsidian Tips

### Linking Notes
```markdown
[[project-name]] — backlink a progetto
[[pattern-rate-limiting]] — backlink a pattern
[[function-name]] — backlink a funzione
```

### Graph View
Obsidian mostra automaticamente i collegamenti tra note (funzioni → progetti → patterns).

### Search
Usa il search per trovare rapidamente concetti:
- `tag:#pattern` — tutte le note con tag pattern
- `function:` — tutte le funzioni
- `backlinks of [[project]]` — cosa dipende da questo progetto

### Sync to GitHub
Aggiungi repo sync (opzionale):
```bash
cd ~/obsidian/knowledge-base
git init
git remote add origin https://github.com/MATEJ081/knowledge-base.git
git add .
git commit -m "Initial knowledge base"
git push -u origin main

# Auto-commit ogni giorno
# Cron: daily git commit + push
```

---

## 🚀 Timeline

- **21 Settembre**: Server + Claude Code live
- **22-28 Settembre**: Test Claude Code workflow via SSH
- **Settimana 2**: Installa Obsidian
- **Settimana 3**: Setup analyzer script
- **Settimana 4**: Full automation live

---

## 📚 Prossimi Step

Una volta live:
1. Aggiungi tutti i tuoi progetti al vault
2. Manual tagging/categorizzazione
3. Estendi analyzer per pattern detection più sofisticati
4. Crea view personali (dashboard note)
5. Backup automatico su GitHub

---

**Questo sistema diventerà la tua "memoria esterna" — sempre accessibile, sempre aggiornata!** 🧠✨
