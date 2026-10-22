# Process identity and app attribution

A process is `(pid, start_time)` because PIDs are reused. Its app is the app of its responsible process, found with the private `responsibility_get_pid_responsible_for_pid` (looked up with `dlsym`), so helpers group under the app that launched them. Terminal apps (default list: Terminal, iTerm, Ghostty, rootshell; editable) are excluded, otherwise every shell command would group under the terminal; then, or when the private call fails, the outermost `.app` bundle on the path is used. The private API is a known risk (user call, 2026-10-22). Spec §5.
