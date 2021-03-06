Patchwork-VC
============

So, at work we use subversion for everything.  And it works well for us.  However, I've been using git at home, and at work it often becomes a hassle to keep around diff files if I'm working on a few things at once, or something is on hold and I don't want to commit yet, or even just in case there's a messy conflict coming on `$ svn up` due to a co-worker changing the same area of the code.

I didn't particularly care for the descriptions of using `git-svn` as a bridge (it sounded kind of complicated and prone to breakage), so I decided to try something weird:  Plop a git repo right on top of my subversion checkout.

And as of this writing, over the past two weeks, it's been working pretty well.  The hacked-together bash functions in the initial commit are what came of continually running the same commands over and over.  Several parts still have to be done manually, such as setting up the checkout (due to `.gitignore` being custom every time), and there are limitations as to what I can do.  But as long as I keep the mindset that this is a _subversion staging area_, not a _real_ repository, it works out.

Feel free to ignore the `Notes` file.  Those are my thoughts and plans for the future.  Not all of them will happen.

Limitations
-----------

This makes extensive use of `rebase` and assumes specific branch structures:

```
* 004037f (feature_1) Commit 6
* 6b60b1f Commit 5
| * 58ec685 (feature_2) Commit 7
|/  
| * b9dee7d (bugfix_1) Commit 8
|/  
* aa57597 (HEAD, master) Commit 4
* 3d1ae22 Commit 3
* 9e014f6 (subversion) Commit 2
* bcdcec4 Commit 1
```

* `subversion` is assumed to always be a clean checkout of the svn repository.  At any time a `$ git checkout subversion` should result in `$ svn diff` showing zero changes.
* `master` contains changes such as local settings or tweaks that you need for your checkout to work, but that should not be commited to svn.  I've also put some customized maintenance scripts in there, that aren't useful to anyone else.
* Your work will branch off of `master`.  There are 3 such branches above.
* When pushing one of your branches to svn, they are rebased from `master` to `subversion`, so that `$ svn diff` will only show that branch's changes, but nothing from `master`.  The `subversion` branch is then updated, and all the other branches are rebased back on top of it.

This extensive use of `rebase` means that you cannot safely have any remotes to push or pull from.  History rewriting makes it a massive headache.

Additionally, try to avoid branching or merging your git branches, and keep the history linear off of `master`.  _Sometimes_ the automatic rebasing back onto `master` works right, but sometimes it blows up or conflicts (and once it flattened my branch+merge into a linear set of commits).  I would love to get this working correctly and consistently, but so far no luck...

Initializing a checkout
-----------------------

This must be done manually for the moment:

```bash
svn co http://example.com/repo/
cd repo/
git init .
echo '.svn/' > .gitignore     # Absolutely **required** or else you'll corrupt your svn checkout
echo '*.pyc' >> .gitignore    # And anything else that shouldn't be included in git or svn
git add .
git commit -m'Initial subversion state'
git branch subversion

touch settings_local.py
git add settings_local.py
git commit -m'My version-controlled settings, not to be added to subversion'
```

Commands
--------

Basics:

| Command         | Description |
| -------         | ----------- |
| sync            | Ensure `subversion` is an ancestor of `master`, and that `master` is an ancestor of your branches.  Only necessary to call manually when committing to `master` or resolving conflicts |
| pull            | Update the `subversion` branch from svn |
| push            | Rebase the current branch onto subversion and commit it.  Will use `$EDITOR` to ask for an svn commit message (or `vim` if not set) |
| log             | View local changes.  Basically a wrapper around different calls to `git log` that I used often |
| squash_svn      | The svn repository we pushed to is the canonical history, so squash the long tail in git down to one commit |

Additional arguments:

| Arg             | Description |
| ---             | ----------- |
| --username foo  | For interacting with the remote repository, svn username "foo" |
| --password foo  | For interacting with the remote repository, svn password "foo" |
| log --branches  | Show all branches instead of just the current one |
| log --all       | In addition to all branches, include history of `master` and `subversion` |

Semi-Internals:

`pull` and `push`, being wrappers around svn calls, have been split to make it easier to use if the git repository was not initted at the top of the svn checkout, or some other unusual setup is used.  `--prepare` does everything up until the interaction with svn, while `--complete` does everything afterwards.  `push` additionally has an `--abort` in case you decide not to do a commit to svn.

None of these are normally necessary.  Basically:

`pw pull` is identical to:

```bash
pw pull --prepare
svn up
pw pull --complete
```

`pw push` is similar to:

```bash
pw push --prepare
# Generate commit message.  If non-blank:
   svn commit
   pw push --complete
# If commit was blank or svn commit fails:
   pw push --abort
```

Sample Workflow
---------------

Assuming you've just finished initializing, this is an example of how to use the commands above.

Let's start working on Feature Foo and make a few commits...

```bash
git checkout -b feature_foo master
echo 1 > foo_1
echo 2 > foo_2
git add foo_1 foo_2
git commit -m'First foo commit'
echo 3 >> foo_1
echo 4 >> foo_2
git commit -a -m'Second foo commit'
```

Your git repo should now look something like this if you run `$ pw log --all`:

```
* 9cdfb6d (HEAD, feature_foo) Second foo commit
* fcc46a9 First foo commit
* 41f603d (master) My version-controlled settings, not to be added to subversion
* 217e485 (subversion) Initial subversion state
```

So the branch is ready to commit to svn - run a `$ pw push` and you'll get an editor to write your svn commit message.  Like svn or git, it will contain a summary of your changes - but much more detailed.  A list of files and their current svn status (Modified/Added/Deleted), all the git commit messages you made, then the entire diff.  Save your commit message and you'll get a confirmation, and after the push your git repository will look like this:

```
* 33c24cf (HEAD, master, feature_foo) My version-controlled settings, not to be added to subversion
* 53891d0 (subversion) Second foo commit
* f615480 First foo commit
* 217e485 Initial subversion state
```

It's now safe to `$ git checkout master && git branch -d feature_foo`, since it's been pushed to svn.

On the other hand, if when reviewing your commits you decide against the commit, you can either save an empty commit message (and the push is automatically aborted) or say "no" when asked to confirm the commit.  If the svn commit itself fails, the same happens.

Eventually, the `subversion` branch will end up with a long tail that you probably don't particularly care about, since the canonical history is stored in svn.  That's why `$ pw squash_svn` exists.  It will make `subversion` have one single root commit.  For example, running it on the above results in something like this:

```
* 15ca7e1 (HEAD, master, feature_foo) My version-controlled settings, not to be added to subversion
* 94ffe4c (subversion) r196: 2014-05-24/0:17:29
```

Conflicts
---------

These are expected, and have happened a few times to me already.  Basically, during the `$ pw sync` (or `pull`, which calls `sync`) is when a conflict might happen.

Right now, it'll fail at a particular point and then have a string of errors due to git refusing to rebase when already in the middle of a rebase that has a conflict.  Resolution is simple:

`$ git status` will show you what the current conflict is.  Resolve it as you would normally, and as git instructs, use `$ git rebase --continue` or `$ git rebase --skip`

When that rebase completes, run `$ pw sync` again.  If it completes successfully, you're done.  If it does not, resolve and try again until it does.
