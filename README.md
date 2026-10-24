# Skill clever-tools

Un skill pour agents de code (Claude Code, Codex et tout outil compatible avec le format [Agent Skills](https://agentskills.io)) qui déploie, configure et diagnostique une application sur Clever Cloud avec la CLI `clever`.

Il apprend à l'agent ce qu'il ne devine pas seul :

- les commandes qui bloquent un agent (`clever login`, `clever logs` sans `--until`, `addon create` sans `--yes`) ;
- le contrat d'exécution Clever (`0.0.0.0:8080`, variables `*_ADDON_*`, dépôt git = ce qui est commité) ;
- la lecture des logs d'un déploiement en échec : « not listening on 8080 » est un symptôme, la cause est la ligne au-dessus.

## Installation

Prérequis : [clever-tools](https://www.clever.cloud/developers/doc/cli/) installé et `clever login` déjà fait.

```bash
git clone <ce-dépôt> && cd clever-tools-skill
bash install.sh
```

Le script copie `skills/clever-tools/` dans :

| Agent | Dossier |
|---|---|
| Claude Code | `~/.claude/skills/clever-tools/` |
| Codex (et agents compatibles) | `~/.agents/skills/clever-tools/` |

Pour un seul projet, copier plutôt le dossier dans `.claude/skills/` ou `.agents/skills/` à la racine du dépôt.

## Essai

Dans un dépôt d'application :

> Déploie cette app sur Clever Cloud dans mon organisation, région Paris, puis montre-moi les logs.

## Contenu

```
skills/clever-tools/SKILL.md   # le skill (un seul fichier)
install.sh                     # installation Claude Code + Codex
```
