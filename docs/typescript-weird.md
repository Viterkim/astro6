# TypeScript formatting setup (thanks gippity)

## Normal setup

- TypeScript language server:
  - autocomplete
  - type checking
  - navigation
  - rename/imports

- ESLint:
  - lint rules
  - project-specific code rules
  - fixable errors

- Prettier:
  - whitespace
  - quotes
  - wrapping
  - commas/brackets

- Usually:
  - Prettier formats
  - ESLint fixes lint issues
  - only one formatter owns save-time formatting

## Weird shitty setup here (why the setup is stupid but needed)

- Most ESLint rules live in a shared package under `node_modules`.
- The local `.eslintrc` mostly extends that hidden config.
- Prettier is integrated through ESLint.
- The project expects `eslint --fix`.
- Standalone Prettier should not run on TS/JS files.
- Editors can easily run:
  - TypeScript formatting
  - Prettier formatting
  - ESLint fixes
- That means two or three tools can fight over the same file on save.

## Correct editor setup

- Use TypeScript language server for code intelligence.
- Disable TypeScript LSP formatting.
- Enable ESLint diagnostics.
- Run ESLint fixes on save.
- Use the project-local ESLint.
- Disable standalone Prettier for TS/JS.

So flow is: save -> eslint --fix -> write file
