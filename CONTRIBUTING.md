# Contributing

## Development Workflow

1. Create a feature branch from `main`
2. Make changes following the project conventions
3. Run `make fmt lint` before committing
4. Create a PR - Terraform plan will run automatically
5. Get review from required CODEOWNERS
6. Merge to main - auto-deploys to dev

## Terraform Changes

- Always run `make plan` locally before pushing
- Use modules for reusable components
- Add variables with descriptions and validation
- Update environment tfvars for all three environments

## Python Changes

- Follow PEP 8 style (enforced by ruff)
- Add type hints to all functions
- Use rich for console output
- Handle AWS API errors gracefully

## Commit Messages

Follow conventional commits:
- `feat(scope):` for new features
- `fix(scope):` for bug fixes
- `chore:` for maintenance
- `docs:` for documentation
- `security:` for security improvements
