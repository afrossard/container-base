# Context

Glossary for this repo, which publishes shared container base images consumed by other repos' devcontainers and production Containerfiles.

## Language

**Language variant**:
Which language toolchain a published image carries: `base` for none, or a specific language such as `python`. Each language variant is added independently and does not require the others to exist.

**Build variant**:
Whether a published image carries the interactive shell and dotfiles bootstrap layer (zsh, `chsh`, Homebrew, chezmoi, fpath completions): `dev` carries it, `prod` does not.
_Avoid_: devcontainer image, runtime image — both conflate build variant with a specific consumer, but a `dev` image can be consumed by something other than a devcontainer, and a `prod` image is not always literally a production deployment.

**Image tag**:
`{language variant}-{build variant}`, for example `python-dev` or `base-prod`. Every language variant publishes both build variants.
