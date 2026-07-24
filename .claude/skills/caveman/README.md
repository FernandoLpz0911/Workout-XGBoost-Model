# Caveman Mode Overview

The caveman system is a token-compression technique that reformats Claude's responses into minimal syntax while preserving technical accuracy. According to the documentation, it "Drops articles, filler, pleasantries, and hedging. Keeps every technical detail, code block, error string, and symbol exact."

## Key Features

The system offers six intensity levels ranging from `lite` (maintaining full sentences) to `wenyan-ultra` (extreme classical Chinese compression). The default `full` mode uses "fragments OK, short synonyms" to achieve approximately 65-75% token reduction.

An important safeguard exists: "caveman drops to normal prose for security warnings, irreversible-action confirmations, multi-step sequences where fragment ambiguity risks misread."

## Invocation

Users activate it via `/caveman` commands with optional intensity modifiers, or disable it with `stop caveman`.

The example demonstrates the effect—a response about React re-rendering gets compressed from standard explanation style to fragments like "New object ref each render" and symbols like "→" for causality in ultra mode.
