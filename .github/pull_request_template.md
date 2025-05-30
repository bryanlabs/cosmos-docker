## Description

Brief description of what this PR does.

## Type of Change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Configuration improvement
- [ ] Security enhancement

## Changes Made

- [ ] Modified Docker Compose configuration
- [ ] Updated environment files
- [ ] Changed Makefile targets
- [ ] Updated documentation
- [ ] Added/modified scripts
- [ ] Updated CI/CD workflows

## Testing

- [ ] Ran `./validate.sh` successfully
- [ ] Tested Docker Compose configuration with `docker compose config`
- [ ] Tested Makefile targets with `make --dry-run`
- [ ] Verified environment file syntax
- [ ] Tested with both minimal (`.env.example`) and complete (specific chain `.env`) configurations
- [ ] Manual testing performed (describe below)

### Manual Testing Details

Describe any manual testing you performed:

```
# Commands run and results
make start
# Service started successfully

docker compose logs
# No error messages in logs
```

## Backwards Compatibility

- [ ] This change is backwards compatible
- [ ] This change requires migration steps (documented below)
- [ ] This change breaks existing configurations (justify below)

### Migration Steps (if applicable)

If this change requires users to update their configuration:

1. Step 1
2. Step 2
3. etc.

## Documentation

- [ ] Updated README.md
- [ ] Updated CONTRIBUTING.md
- [ ] Updated DEVELOPMENT.md
- [ ] Added/updated comments in configuration files
- [ ] No documentation changes needed

## Security Considerations

- [ ] No security implications
- [ ] Reviewed for security issues
- [ ] Updated security documentation
- [ ] Added security-related configuration options

## Checklist

- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my own changes
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings or errors
- [ ] All automated tests pass
- [ ] The validation script (`./validate.sh`) passes

## Additional Notes

Any additional information that reviewers should know about this PR.
