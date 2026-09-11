# AI Agent Guidelines

This repository uses [CodeRabbit](https://coderabbit.ai) for AI-driven code reviews and quality assurance (configured via [`.coderabbit.yaml`](.coderabbit.yaml)).

## CodeRabbit Review Directive

Whenever any AI assistant (Antigravity, Cursor, Claude, Copilot, ChatGPT, or similar) works on this repository and finishes implementing a feature, fix, refactor, or prepares a branch/pull request:

1. **Ask the developer**:
   Always prompt the developer:
   > *"Would you like to go through a CodeRabbit review for these changes?"*

2. **Actions based on developer response**:
   - **If Yes**:
     - Push the changes to a branch and open/update a Pull Request so CodeRabbit can automatically review it.
     - Help the developer review and address any issues or suggestions flagged by CodeRabbit in accordance with [`.coderabbit.yaml`](.coderabbit.yaml).
   - **If No / Skip**:
     - Proceed directly with the developer's instructions without triggering or waiting for a CodeRabbit review.
