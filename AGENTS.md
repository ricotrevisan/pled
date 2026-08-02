# Pled Development Guide for AI Agents

This document provides a comprehensive guide for AI agents working on the Pled codebase.

## 1. Project Overview

Pled is a command-line interface (CLI) tool built with Elixir to streamline the development of plugins for [Bubble.io](https://bubble.io). It allows developers to pull a plugin's structure from Bubble, edit the code locally in their preferred environment, and then push the changes back to Bubble. This workflow improves upon Bubble's native online plugin editor by enabling version control, local testing, and the use of familiar development tools.

The tool is designed to be used on a per-plugin basis, with environment variables configured for each plugin's directory.

## 2. Key Technologies

*   **Elixir:** The core language for the CLI tool.
*   **Mix:** Elixir's build tool, used for managing dependencies, compiling, and running tasks.
*   **ExUnit:** Elixir's testing framework.
*   **Req:** An HTTP client for making requests to the Bubble.io API.
*   **Burrito:** A tool for packaging the Elixir application into a single, distributable executable.
*   **FileSystem:** A library for watching file system events, used in the `watch` command.
*   **Jason:** A JSON library for Elixir.

## 3. Architecture

Pled is a standard Elixir OTP application.

*   **Main Entry Point:** The `Pled` module (`lib/pled.ex`) is the main entry point for the CLI. It parses command-line arguments and delegates tasks to the appropriate command modules.
*   **Command Modules:** Each CLI command (e.g., `pull`, `push`, `watch`) has its own module located in the `lib/pled/commands/` directory.
*   **Bubble API Interaction:** All communication with the Bubble.io API is handled by the `Pled.BubbleApi` module (`lib/pled/bubble_api.ex`), which uses the `Req` library.
*   **Core Workflow:**
    1.  **`pull`:** The `Pled.Commands.Pull` command uses `Pled.BubbleApi` to fetch the plugin data from Bubble. The `Pled.Commands.Decoder` module then converts the JSON response into a human-readable local file structure.
    2.  **`push`:** The `Pled.Commands.Encoder` module takes the local files and reconstructs the Bubble.io JSON format. The `Pled.Commands.Push` command then uses `Pled.BubbleApi` to save the plugin data back to Bubble.

## 4. Development Conventions

### 4.1. Testing

*   **CRITICAL:** When implementing new features, you **MUST** always create comprehensive, meaningful tests.
*   Tests are located in the `test/` directory.
*   Run all tests (excluding integration tests) with `mix test`.
*   Integration tests are tagged with `:integration` and are excluded by default. To run them, use `mix test --include integration`.
*   Follow existing test patterns and ensure new functionality is thoroughly tested before considering it complete.

### 4.2. Code Style

*   The project uses the default Elixir formatter.
*   Run `mix format` to format the code before committing.
*   Run `mix format --check-formatted` to verify that the code is correctly formatted.

### 4.3. Environment Variables

The following environment variables are required for interacting with the Bubble.io API:

*   `BUBBLE_COOKIE`: Your Bubble.io authentication cookie.
*   `PLUGIN_ID`: The ID of the plugin you are working on.

It is recommended to use a tool like `direnv` to manage these variables on a per-directory basis. An example `.envrc` file can be created using the `pled init` command.

## 5. Building and Running

### 5.1. Dependencies

*   Elixir >= 1.20 (with Erlang/OTP 29; pinned in `.tool-versions`)
*   mix (Elixir's build tool)
*   Zig (pinned in `.tool-versions`; required by Burrito when running `mix release`)

### 5.2. Installation

1.  Clone the repository.
2.  Install dependencies: `mix deps.get`
3.  Build the project: `mix compile`

### 5.3. Running the CLI

*   **With mix:** `mix run pled -- <command>` (e.g., `mix run pled -- --help`)
*   **Release Executable:**
    1.  Build a release executable: `mix release`
    2.  Run the executable: `./_build/dev/rel/pled/bin/pled <command>`

## 6. Available Commands

*   `pull`: Fetches the plugin data from Bubble.io and decodes it into local files. Refuses when local changes are unpushed unless `--wipe`; removes entities deleted or renamed in Bubble.
*   `push`: Encodes local files and pushes the changes to Bubble.io. Refuses when the remote moved since the last pull unless `--force`.
*   `encode`: Encodes the plugin files into `dist/plugin.json`.
*   `upload <file_path>`: Uploads a specific JSON file to Bubble.io.
*   `watch`: Keeps `src/` and Bubble in sync through the three-way sync engine: pushes local edits when the remote is clean, pulls remote changes when nothing local is unpushed, and pauses with a conflict banner when both sides moved. `--interval` sets the remote poll period in seconds (default 15).
*   `init`: Initializes a new plugin directory with a recommended structure and configuration files.
*   `help`: Displays the help message.
*   `check_remote`: Reports the three-way sync state (baseline, local, remote) without changing anything; agrees with `status`.
*   `compile`: Compiles the Elixir code.

## 7. File Structure

*   `lib/`: The main source code for the application.
*   `test/`: Contains all the tests.
*   `config/`: Application configuration files.
*   `priv/`: Private data, such as example files for tests.
*   `dist/`: The output directory for the `encode` command.
*   `burrito_out/`: The output directory for the release executables created by Burrito.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues on `ricotrevisan/pled`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical labels, spelled as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
