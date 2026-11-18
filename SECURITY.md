# Security policy

## Reporting a vulnerability

Report privately through GitHub, not in a public issue:

**[Open a private security advisory](https://github.com/nnemirovsky/cc-agterm-remote/security/advisories/new)**

The report is visible only to the maintainer ([@nnemirovsky](https://github.com/nnemirovsky)) until an advisory is published, so nothing sensitive is exposed while a fix is prepared. Expect an acknowledgement within a week.

If the form is unavailable, open a normal issue that says only "I would like a private channel for a security report", with no details, and a private advisory will be opened for you.

Never attach real credentials, tokens, personal data or private files to a report. Describe the shape of the problem instead.

## Supported versions

Only the latest release gets security fixes.

## Scope

cc-agterm-remote connects your Mac and your servers over ssh, serves the Mac clipboard and link opening to the servers through a forwarded socket, edits a few of your dotfiles, and ships the `rename-session` plugin. A vulnerability here would be, for example:

- Another user on the Mac or on a server reaching the clipboard and link sockets.
- `cc-remote-clipboard` or `cc-remote-open` opening anything other than an http(s) URL, or running any other command on the Mac.
- A session name, directory, branch, pane title or server reply reaching a shell on the Mac or the server as code. Remote commands quote every argument they pass, and a gap in that is a bug.
- `install.sh` changing a file of yours outside its `cc-agterm-remote` markers.
- The `rename-session` tool doing anything other than queueing `/rename` with a one-line name.

Out of scope: what anyone who can already act as your user on a server can do while the bridge is connected (read the Mac clipboard image, set its text and open http(s) links). That is the feature, and the README's Security section describes it. Also out of scope: how you expose ssh, and bugs in Claude Code, agterm or OpenSSH.
