# Changelog

## [1.0.1](https://github.com/jmetzz/zweig/compare/v1.0.0...v1.0.1) (2026-11-03)


### Bug Fixes

* **ci:** let the release workflow comment on issues and PRs ([2a05495](https://github.com/jmetzz/zweig/commit/2a05495b248b16c56e0d565758e834ccc894d816))

# 1.0.0 (2026-11-03)


### Bug Fixes

* address re-review nitpicks for the control root ([fa782a0](https://github.com/jmetzz/zweig/commit/fa782a01de737415997e0cbd810cd003a91ee148))
* address review of location-agnostic bulk commands ([1e45605](https://github.com/jmetzz/zweig/commit/1e45605fc3e3f2fa850cbee9797a85a7a040656d)), closes [#15](https://github.com/jmetzz/zweig/issues/15)
* address review of location-agnostic remove merged/select/migrate/sync ([292e1f0](https://github.com/jmetzz/zweig/commit/292e1f027553646396161dc4a7bc301ce9edb922))
* address review of location-agnostic remove/finalize/rebuild ([3f76085](https://github.com/jmetzz/zweig/commit/3f7608520471282a4dec0f8d9273c60f18b2b2f2))
* address review of readable list and status output ([1ef46ff](https://github.com/jmetzz/zweig/commit/1ef46ff2ae9a1eaf168398290710c8439a8878ee))
* address review of the worktree resolver ([a7822d6](https://github.com/jmetzz/zweig/commit/a7822d6974ec316b2fd806067ceae40708a6b568))
* address team review of declined-prompt exit codes ([7f251e8](https://github.com/jmetzz/zweig/commit/7f251e82dc3a8df01ab99553bebbcee4273868fa))
* address team review of the control root resolution ([9fcf2f8](https://github.com/jmetzz/zweig/commit/9fcf2f8d62c028f319b7f1ddfdc77a030b0bef1c))
* address team review of the default-branch guard ([6d8d02d](https://github.com/jmetzz/zweig/commit/6d8d02db017bef3e8adcee1718698c039eea05d7))
* address team review of the test runner ([352a49a](https://github.com/jmetzz/zweig/commit/352a49ae56f6362a68dbc03d0b574bb90f071c9d))
* **ci:** run the release workflow on Node 22 ([2801e5f](https://github.com/jmetzz/zweig/commit/2801e5fb0ae773ae85bf34cc13f484023a75a82a))
* exit non-zero when a confirmation prompt is declined ([11fe57b](https://github.com/jmetzz/zweig/commit/11fe57b2127acf643cc5efc8c411badc8a2b90f6))
* finalize fails when it can't delete the branch ([1b3a9bd](https://github.com/jmetzz/zweig/commit/1b3a9bd9a230a240c99dc19857c652a65d647ca6)), closes [#46](https://github.com/jmetzz/zweig/issues/46)
* finalize fetches origin only when it deletes a branch ([c6b945f](https://github.com/jmetzz/zweig/commit/c6b945f41bfdf83ea6aa1f7a62881334aa318d1b)), closes [#39](https://github.com/jmetzz/zweig/issues/39)
* flatten slash-containing branch names in zg migrate ([d70002b](https://github.com/jmetzz/zweig/commit/d70002b921b7bb5d8a6c531f7d4f609eab46aa09))
* guard the default branch in remove and never delete it in finalize ([340a8db](https://github.com/jmetzz/zweig/commit/340a8db41600c11691ab28c1812b550539177eb4)), closes [#19](https://github.com/jmetzz/zweig/issues/19)
* harden from-pr reuse and error reporting ([16456e7](https://github.com/jmetzz/zweig/commit/16456e77475b6f3dc71fa6906cae85ff9e8d1a7b))
* harden prune trees argument handling and reporting ([a1777fa](https://github.com/jmetzz/zweig/commit/a1777fa9f4bc92a27c0c59bdc5a9cd29e85f7228))
* harden the shim's directory handoff ([e6288c6](https://github.com/jmetzz/zweig/commit/e6288c684d985acffb173c0f1800aa2c2153c06e))
* keep remove merged from discarding submodule work ([1b880ef](https://github.com/jmetzz/zweig/commit/1b880ef2f5a3390a686572334b0498a497b706a7))
* let make test find bats without basher ([a41ae94](https://github.com/jmetzz/zweig/commit/a41ae94dd627a7833d465bc7c386bb3e9d6e4444))
* make finalize messages accurate for unborn branches ([c9df3c1](https://github.com/jmetzz/zweig/commit/c9df3c1b5064a47dd9cae5e00d24e25979ee5aa9))
* make remove merged, select, migrate and sync current location-agnostic ([e930139](https://github.com/jmetzz/zweig/commit/e930139db44d6cc1da6cdeddaabafa4481928f23)), closes [#15](https://github.com/jmetzz/zweig/issues/15)
* make zg create -s target resolution zsh-safe ([43193af](https://github.com/jmetzz/zweig/commit/43193afe9dbe4cb6f84787d91f4416458597f185))
* move the shell for zg root, main, select and create from-pr ([addb770](https://github.com/jmetzz/zweig/commit/addb770821dcf647d9bf9279f6bd7b56e8e3903d)), closes [#14](https://github.com/jmetzz/zweig/issues/14)
* name the default branch when finalize refuses a directory holding it ([9a8ecff](https://github.com/jmetzz/zweig/commit/9a8ecffecb756b759ca79addd49b6d62c07eb5ec))
* pin @semantic-release/git to existing ^11.0.1 ([5e1502a](https://github.com/jmetzz/zweig/commit/5e1502ae67a9e63e2fef8d9529d011f6a7458a1e))
* prevent zg remove merged from aborting silently under set -e ([767faab](https://github.com/jmetzz/zweig/commit/767faab3d171f5de9b19311351ce6c8cf1a750b7))
* prune trees only removes worktrees whose origin upstream is gone ([6380daa](https://github.com/jmetzz/zweig/commit/6380daaafee800c6b3e67138c09e60eaed4f2556)), closes [#22](https://github.com/jmetzz/zweig/issues/22)
* resolve the control root for submodules and separate git dirs ([142e8f8](https://github.com/jmetzz/zweig/commit/142e8f8cc9d6f585ef2f59bdedf92a2c0343379c))
* resolve the control root when .git is a symlink or GIT_DIR is set ([a78be90](https://github.com/jmetzz/zweig/commit/a78be900643b0f78aa1594ba4b257a6c79e43cf8))
* resolve zg root to the control repo instead of the current worktree ([dfd4ce5](https://github.com/jmetzz/zweig/commit/dfd4ce520049098689092103f2fc131695bb2f86))
* resolve ZWEIG_ROOT through symlinks to prevent install-time fork bomb ([05ca0af](https://github.com/jmetzz/zweig/commit/05ca0af288e7098dcac696ba0753f9a94b04d507))
* skip worktrees whose submodules git can't read in remove merged ([6f03e12](https://github.com/jmetzz/zweig/commit/6f03e12e117a57789aafee642b210df1d2de422e))
* stop creating the worktree dir on every zg invocation ([f8c1333](https://github.com/jmetzz/zweig/commit/f8c1333d6e4be84a2d72889fd04b995309ada02e)), closes [#11](https://github.com/jmetzz/zweig/issues/11)


### Features

* add cd/switch shell shim ([6c1432f](https://github.com/jmetzz/zweig/commit/6c1432ff352abd7209c0eb75f24c5af81f8ee39a))
* add install.sh --local mode to install from a local clone ([2d5af79](https://github.com/jmetzz/zweig/commit/2d5af79f572365d2a6b4a9083227a54dc06e6f34))
* add installer script ([563b485](https://github.com/jmetzz/zweig/commit/563b485a183f86924cdab144eac33778509e8d6b))
* add maintenance commands (sync, prune, protect, migrate) ([0e1def1](https://github.com/jmetzz/zweig/commit/0e1def1a1863b0abdbc5d168a9ce769182fb1d35))
* add optional gh/fzf extensions ([1f32670](https://github.com/jmetzz/zweig/commit/1f32670ea066cc6ef91287013c2844f55d9b3296))
* add zg create -s to create and switch into a worktree in one step ([9562c72](https://github.com/jmetzz/zweig/commit/9562c72f49b372ea32e326b7f5c8d5a81d7bb43d))
* add zweig CLI core, helpers, and dispatcher ([3630b36](https://github.com/jmetzz/zweig/commit/3630b36f58081a6d72f63e88698cdb4680a48f2c))
* default worktrees to a repo-local .worktrees directory ([b64a930](https://github.com/jmetzz/zweig/commit/b64a9306d35a47e312bf2fc46ee7a71103911365))
* name from-pr worktrees as pr-<N>-<branch> ([0a3cca0](https://github.com/jmetzz/zweig/commit/0a3cca00ccef797a0f2729d347f425bcfd33ee49)), closes [#13](https://github.com/jmetzz/zweig/issues/13)
* readable zg list and status output ([c0ec342](https://github.com/jmetzz/zweig/commit/c0ec3423539ae97a00ab4c00fc2d5a28f4df7528)), closes [#12](https://github.com/jmetzz/zweig/issues/12)
* resolve remove/protect/finalize/rebuild targets anywhere on disk ([7748e5b](https://github.com/jmetzz/zweig/commit/7748e5b8bb9e09d176332fb578bf70a969a94917)), closes [#4](https://github.com/jmetzz/zweig/issues/4)
* seed new worktrees with local env files and AI harness context dirs ([07cdb99](https://github.com/jmetzz/zweig/commit/07cdb994aea5af48c681ea4ec7581ac00637ae3d))
* sweep every worktree in status, prune trees and sync all ([bb89355](https://github.com/jmetzz/zweig/commit/bb89355cce390b0a007ed4410a7b3fd2b6b86ff3)), closes [#5](https://github.com/jmetzz/zweig/issues/5)
