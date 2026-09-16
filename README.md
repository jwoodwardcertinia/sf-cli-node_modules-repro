# Metadata under `node_modules` is skipped from deploys without warning

Minimal reproduction for the behavior introduced by
[forcedotcom/source-tracking#847](https://github.com/forcedotcom/source-tracking/pull/847).

## What changed

That PR added a filter to `localShadowRepo.ts`:

```js
// no node_modules (e.g. uiBundle packages inside force-app)
!f.split(path.sep).includes('node_modules')
```

Any file whose path contains a `node_modules` segment is excluded from local
source tracking. The commit message gives the motivation as
*"ignore node_modules because ui-bundle/webapp/react stuff"* — i.e. avoiding
the cost of tracking JS dependency trees.

The side effect is that it is no longer possible to distribute Apex (or any
other metadata) as an npm package and deploy it, which is a legitimate and
previously working pattern.

## Why this is hard to notice

The deploy does not fail. It exits with a status of Succeeded, and the
component list it prints contains only the class from `force-app`. The class
under `node_modules` is not listed as failed, or skipped, or ignored — it is
simply not there.

So the deploy is not silent, but the *omission* is: nothing reports that a
registered `packageDirectory` contributed zero components, and nothing
distinguishes "deployed everything you asked for" from "deployed less than
you asked for, successfully". You have to already know how many components
you expected in order to spot that one is missing.

In practice that means the problem surfaces much later, as a compile error in
unrelated code that references the type that never arrived.

## The repository

Two Apex classes, identical except for where they live:

| Class             | Location                                                       | Reaches the org? |
|-------------------|----------------------------------------------------------------|------------------|
| `FromForceApp`    | `force-app/`                                                   | yes — control    |
| `FromNodeModules` | shipped in an npm package, so `node_modules/demo-apex-pkg/...` | no.              |

Both directories are registered as `packageDirectories` in
`sfdx-project.json`, so both are equally in scope as far as the project
config is concerned.

`demo-apex-pkg` is a deliberately inert fixture: no lifecycle scripts, no
dependencies, nothing but the Apex and a `package.json`. Its source is in
`fixture-src/` and the packed tarball is committed to `vendor/`.

## Reproduce

```bash
npm install
sf org create scratch -f config/project-scratch-def.json -a nodemodulesdemo -d
sf project deploy start -o nodemodulesdemo
```

The deploy succeeds, and reports deploying one of the two classes:

```text
Status: Succeeded
 Deploy ID: 0Afcb00000Bk7szCAB
 Elapsed Time: 1.53s

Deployed Source
┌─────────┬──────────────┬───────────┬──────────────────────────────────────────────────────────┐
│ State   │ Name         │ Type      │ Path                                                     │
├─────────┼──────────────┼───────────┼──────────────────────────────────────────────────────────┤
│ Created │ FromForceApp │ ApexClass │ force-app/main/default/classes/FromForceApp.cls          │
│ Created │ FromForceApp │ ApexClass │ force-app/main/default/classes/FromForceApp.cls-meta.xml │
└─────────┴──────────────┴───────────┴──────────────────────────────────────────────────────────┘
```

`FromNodeModules` does not appear in that table at all — not as failed, not
as skipped, not as ignored. The second registered `packageDirectory`
contributed nothing, and the command exited Succeeded without remarking on
it.

Confirming against the org — Setup → Apex Classes, or:

```bash
sf data query -o nodemodulesdemo --use-tooling-api \
  -q "SELECT Name FROM ApexClass WHERE Name IN ('FromForceApp','FromNodeModules')"
```

```text
┌──────────────┐
│ NAME         │
├──────────────┤
│ FromForceApp │
└──────────────┘

Total number of records retrieved: 1.
```

`FromNodeModules` never reached the org. The same result from Apex:

```bash
sf apex run -o nodemodulesdemo -f scripts/apex/check-classes.apex
```

```text
USER_DEBUG|FromForceApp => present
USER_DEBUG|FromNodeModules => MISSING
```

And the realistic failure mode — unrelated code that references the type
that never arrived:

```bash
sf apex run -o nodemodulesdemo -f scripts/apex/use-from-node-modules.apex
```

```text
Error (executeCompileFailure): Compilation failed at Line 10 column 14 with the error:

Variable does not exist: FromNodeModules
```

This is where the problem actually shows up in practice, typically a long way
from the deploy that caused it.

## Things deliberately avoided

So that the result cannot be attributed to the repo's own configuration:

- **`.forceignore` does not ignore `node_modules/`.** The default sfdx
  template does ignore it; that line has been removed and the reason
  documented in the file. Only `node_modules/demo-apex-pkg/sfdx-source/demo`
  is a registered `packageDirectory`, so nothing else under `node_modules`
  is scanned.
- **The fixture installs as a real directory, not a symlink.** It is
  installed from a committed tarball (`file:vendor/demo-apex-pkg-1.0.0.tgz`)
  rather than a directory path, because `npm install ./some-dir` creates a
  symlink in `node_modules` and symlink handling is a separate confounding
  issue. Verify with `find node_modules -maxdepth 2 -type l`.
- **The fixture package runs no install scripts**, so nothing it does can be
  blamed for the result.

## The symlink workaround no longer works either

The obvious workaround is to symlink the metadata to a path outside
`node_modules`, so the `path.sep` check never sees a `node_modules` segment.
That worked until it was broken by a second, unrelated change — this time not
in the Salesforce CLI at all, but in an unpinned transitive dependency.

`source-tracking` depends on isomorphic-git through a caret range:

```json
"isomorphic-git": "^1.34.2"
```

so new minor versions are picked up without any change on the Salesforce side.
isomorphic-git 1.38.10 added a single line to its working-directory walker, in
`src/models/GitWalkerFs.js`:

```js
async readdir(entry) {
  if ((await entry.type()) !== 'tree') return null   // added in 1.38.10
  const filepath = entry._fullpath
  ...
```

A symlinked directory types as a symlink rather than a `tree`, so the walker
no longer descends into it.

| Reference | Detail |
| --- | --- |
| Issue | [isomorphic-git#1215](https://github.com/isomorphic-git/isomorphic-git/issues/1215) — `statusMatrix()` does not work correctly when there is a symlink that targets an ignored directory |
| PR | [isomorphic-git#2382](https://github.com/isomorphic-git/isomorphic-git/pull/2382) |
| Commit | [`90ea101`](https://github.com/isomorphic-git/isomorphic-git/commit/90ea101d329daa84b99cc0140a6275896ebbaf68) — *fix(statusMatrix): do not traverse symlinks in GitWalkerFs* |
| First released in | 1.38.10 |

Bisected: 1.38.9 works, 1.38.10 / 1.39.x / 1.40.0 / 1.41.7 all fail.

This change brings isomorphic-git closer to native git, which records a
symlink as a blob rather than descending into it.

It is mentioned here only to explain why symlinking out of `node_modules` is
not available as a workaround for the issue above. Whether source tracking
should follow symlinked package directories is a separate question, and not
one this report is trying to settle.

The practical position today is that neither route works: metadata under
`node_modules` is excluded from tracking, and moving it out of the way with a
symlink is no longer effective either.

## Ask

Please make metadata under `node_modules` deployable again when it has been
explicitly declared.

The narrowest fix we can see is to scope the #847 exclusion to paths that
were not deliberately registered: skip `node_modules` when the segment
appears *below* a declared `packageDirectory` — the ui-bundle/React case that
motivated the change — but not when it appears *within* the declared path
itself, as it does here. That preserves the performance benefit in full,
needs no new configuration, and requires no action from existing users.

A configuration flag would also solve it, but less well: because nothing
warns that components were skipped, an opt-in setting only helps people who
have already worked out what is wrong. Everyone else stays broken without
ever learning why.

Failing that, even a warning when a registered `packageDirectory` contributes
zero components would have turned this from a multi-day investigation into an
obvious one.

We are happy with any resolution that restores the capability.

## Rebuilding the fixture

```bash
npm run repack-fixture
```
