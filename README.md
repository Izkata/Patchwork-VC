Patchwork-VC
============

So, at work we use subversion for everything.  And it works well for us.  However, I've been using git at home, and at work it often becomes a hassle to keep around diff files if I'm working on a few things at once, or something is on hold and I don't want to commit yet, or even just in case there's a conflict when I `$ svn up`.

So I decided to try something weird:  Plop a git repo right on top of my subversion checkout.

And as of this writing, over the past two weeks, it's been working pretty well.  The hacked-together bash functions (and a dispatch function) are essentially what I've been using, although up until now they hadn't been version-controlled.  Several parts still have to be done manually, such as setting up the checkout (due to `.gitignore` being custom every time), and there are limitations as to what I can do.  But as long as I keep the mindset that this is a _subversion staging area_, not a _real_ repository, it works out.

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
* When pushing one of your branches to svn, they are rebased from `master` to `subversion`, so that `$ svn diff` will only show that branch's changes.  The `subversion` branch is then updated, and all the other branches are rebased back on top of it.

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

Source the file (`$ source patchwork_vc.sh`) to use these.

| Command         | Description |
| -------         | ----------- |
| pw sync         | Rebase master onto subversion, then all branches onto master, ensuring the latest svn code is in use everywhere.  Only needs to be called manually when making commits to `master` |
| pw pre_pull     | Notes your current svn revision and branch |
| pw pull         | Wrapper for `$ pw pre_pull; svn up; pw post_pull` |
| pw post_pull    | Commits the local changes to `subversion`, the commit message being an `$ svn log` command you can copy/paste to see what the changes were.  Calls `$ pw sync` when complete |
| pw push         | Rebase changes in the current branch onto `subversion`, add files that were added to `git` and remove files removed from `git`.  Do an `$ svn commit` after this |
| pw post_push    | After your `$ svn commit`, do this to update your `subversion` branch.  Calls `$ pw sync` when complete |
| pw abort_push   | If you've called `$ pw push`, then look at the svn diff and decided against it, restore your checkout to how it was before `$ pw push` |
| pw squash_svn   | Sqaush the `subversion` branch down to 1 root commit.  Calls `$ pw sync` when complete |
| pw branches     | One-line tree view of `$ git log` for all your branches with `master` at the root |
| pw log          | One-line tree view of `$ git log` for only the current branch with `master` at the root |
| pw treelog      | One-line tree view of `$ git log` for everything, including commits to the `subversion` branch.  The log you see above under the "Limitations" section is a sample of this |

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

Your git repo should now look something like this if you run `$ pw treelog`:

```
* 9cdfb6d (HEAD, feature_foo) Second foo commit
* fcc46a9 First foo commit
* 41f603d (master) My version-controlled settings, not to be added to subversion
* 217e485 (subversion) Initial subversion state
```

So the branch is ready to commit - run a `$ pw push` and this is your new tree:

```
* 53891d0 (HEAD, feature_foo) Second foo commit
* f615480 First foo commit
| * 41f603d (master) My version-controlled settings, not to be added to subversion
|/  
* 217e485 (subversion) Initial subversion state
```

It's now safe to `$ svn commit`, since any local changes on `master` are no longer included.  So you do so, and when done, be sure to run `$ pw post_push`.  It updates your `subversion` branch and resyncs everything, resulting in this history:

```
* 33c24cf (HEAD, master, feature_foo) My version-controlled settings, not to be added to subversion
* 53891d0 (subversion) Second foo commit
* f615480 First foo commit
* 217e485 Initial subversion state
```

It's now safe to `$ git checkout master && git branch -d feature_foo`, since it's been pushed to svn.

On the chance that your `$ svn commit` failed due to a conflict, `$ pw abort_push` would've moved those two commits back to `master`, giving you a clean slate for `$ pw pull`.  Afterwards, you can do another `$ pw push`.

Eventually, the `subversion` branch will end up with a long tail that you probably don't particularly care about, since the canonical history is stored in svn.  That's why `$ pw squash_svn` exists.  It will make `subversion` have one single root commit.  For example, running it on the above results in something like this:

```
* 15ca7e1 (HEAD, master, feature_foo) My version-controlled settings, not to be added to subversion
* 94ffe4c (subversion) r196: 2014-05-24/0:17:29
```

