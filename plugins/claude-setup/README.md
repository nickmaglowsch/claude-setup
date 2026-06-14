# Claude Setup Plugin

Claude Code plugin package for the software delivery workflows in this repo.

The plugin installs the same core skills and agents as the shell installer, but plugin skills are namespaced:

```bash
/claude-setup:build
/claude-setup:debug-workflow
/claude-setup:refactor
/claude-setup:qa
/claude-setup:craft-pr
/claude-setup:grill-me
/claude-setup:grill-with-docs
```

## Install

Add this repo as a self-hosted marketplace:

```bash
claude plugin marketplace add nickmaglowsch/claude-setup
claude plugin install claude-setup@claude-setup
```

For local testing from a clone:

```bash
claude plugin marketplace add ./ --scope local
claude plugin install claude-setup@claude-setup
```

## Update

Update the marketplace, then update the plugin:

```bash
claude plugin marketplace update claude-setup
claude plugin update claude-setup@claude-setup
```

If you are testing a local clone, regenerate the packaged files first:

```bash
scripts/build-claude-plugin.sh
claude plugin validate .
claude plugin validate ./plugins/claude-setup --strict
```

## Uninstall

```bash
claude plugin uninstall claude-setup@claude-setup
claude plugin marketplace remove claude-setup --scope local
```

Omit `--scope local` if you added the marketplace at user scope.

## Plugin vs Shell Installer

Use the plugin when you want versioned, shareable, namespaced workflows without running the shell installer. The plugin packages Claude Code skills and agents, plus the cross-model review helpers and a single `SessionStart` hook (`hooks/hooks.json`) that bootstraps the Codex CLI for the optional Cross-Model Review feature.

Use `setup.sh` when you want the canonical unnamespaced commands such as `/build`, plus installer-managed extras like the Token Reducer Pack, RTK setup, status line wiring, token-reducer nudge hook, cron auto-update, devcontainer support, or `run-claude.sh`.

Installing this plugin does not modify `~/.claude/settings.json`, install RTK, create cron jobs, install the devcontainer, or add `run-claude.sh`. It does add one hook: a `SessionStart` self-heal (`hooks/hooks.json`) that runs `scripts/ensure-codex.sh` to bootstrap the Codex CLI (a fast no-op once Codex is present; run `codex login` once to authenticate).

## Release Checklist

1. Bump `plugins/claude-setup/.claude-plugin/plugin.json` version.
2. Run `scripts/build-claude-plugin.sh`.
3. Run `claude plugin validate .`.
4. Run `claude plugin validate ./plugins/claude-setup --strict`.
5. Tag the release if desired.
