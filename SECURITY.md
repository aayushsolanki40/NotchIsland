# Security Policy

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please **don't** open a public issue for security problems. Instead, report them privately via
[GitHub's private vulnerability reporting](https://github.com/aayushsolanki40/NotchIsland/security/advisories/new)
or email **aayushsolanki40@gmail.com**.

Include a description, steps to reproduce and the impact. You'll get a reply within a week, and
credit in the release notes once a fix ships (unless you'd rather stay anonymous).

## Scope

NotchIsland runs unsandboxed, sends Apple Events to Music and Spotify, listens for Bluetooth
connections and runs `system_profiler`. Issues where these could be abused — for example,
injecting AppleScript through track metadata — are in scope.
