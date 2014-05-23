
# This is an experiment:  Can my combined svn+git be formalized into a "simple" set of commands?

# ==================== Utils

util_current_branch() {
   echo "$(git branch | grep '\*' | awk '{ print $2 }')"
}
# local BRANCH=$(current_branch)

util_var_save() {
   local FILE=$1
   local NAME=$2
   local VAL=$3

   local CUR_DIR=$(pwd)
   while ! [ -e '.git' ] && ! [ '/' == "$(pwd)" ];do cd ..;done

   # Hmm.. Place elsewhere, too?  Make its own util?
   if [ '/' == "$(pwd)" ];then
      echo "Error:  Must be within patchwork (or at least git)"
      cd "$CUR_DIR"
      return 1
   fi

   echo "$NAME='$VAL'" >> "$FILE"
   cd "$CUR_DIR"
}
util_var_load() {
   local FILE=$1
   local NAME=$2

   local CUR_DIR=$(pwd)
   while ! [ -e '.git' ] && ! [ '/' == "$(pwd)" ];do cd ..;done

   source "$FILE"
   echo "${!NAME}"
   cd "$CUR_DIR"
}
util_var_clear() {
   local FILE=$1

   local CUR_DIR=$(pwd)
   while ! [ -e '.git' ] && ! [ '/' == "$(pwd)" ];do cd ..;done

   cat "$FILE"
   rm "$FILE"
   cd "$CUR_DIR"
}
# util_var_save .pw_pushing CUR_BRANCH "IE7_Fixes"
# local CUR_BRANCH=$(util_var_load .pw_pushing CUR_BRANCH)
# util_var_clear .pw_pushing


# ==================== Currently in-use:

patchwork_branches() {
   git log --graph --decorate --oneline --color --all master~1..
}
patchwork_log() {
   git log --graph --decorate --oneline --color master~1..
}
patchwork_treelog() {
   git log --graph --decorate --oneline --color --all
}

# This is better with metadata:
#   Directories:
#      subversion
#         master
#            B1
#               B1_2
#            B2
#
#   foo() {
#      local PARENT=$1
#      local CUR=
#      for CUR in *; do
#         if [ '*' == "$CUR" ];then break; fi
#
#         echo git checkout $CUR
#         echo git branch OLD_$CUR
#         echo git rebase --onto $PARENT OLD_$PARENT $CUR
#         pushd $CUR > /dev/null
#         foo $CUR
#         popd > /dev/null
#         echo git branch -D OLD_$CUR
#      done
#   }
#
#   cd subversion
#   git branch OLD_subversion
#   // svn up -> svn commit -> etc
#   foo subversion
#   git branch -D OLD_subversion
#   ->
#   git checkout master
#   git branch OLD_master
#   git rebase --onto subversion OLD_subversion master
#   git checkout B1
#   git branch OLD_B1
#   git rebase --onto master OLD_master B1
#   git checkout B1_2
#   git branch OLD_B1_2
#   git rebase --onto B1 OLD_B1 B1_2
#   git branch -D OLD_B1_2
#   git branch -D OLD_B1
#   git checkout B2
#   git branch OLD_B2
#   git rebase --onto master OLD_master B2
#   git branch -D OLD_B2
#   git branch -D OLD_master

patchwork_sync() {
   local CUR_BRANCH=$(util_current_branch)

   git checkout master
   git rebase subversion

   echo "!!!!! This isn't correct - sub-branches should not be blindly rebased onto master!"
   echo "--> Also have to die immediately on conflicts and handle a rebase"
   for BRANCH in $(git branch | egrep -v " (master|subversion)$"); do
      git checkout $BRANCH
      git rebase master
   done

   git checkout $CUR_BRANCH
}

patchwork_squash_svn() {
   # Minor issue:  If I was the last to commit, and haven't "svn up"d to update the index,
   #               then SVN_REV and SVN_DATE do not include my own changes
   local CUR_BRANCH=$(git branch | grep '\*' | awk '{ print $2 }')

   local BASE=$(git log | grep '^commit' | tail -1 | awk '{ print $2 }')
   local SVN_REV=$(svn log -l 1 --username svn --password '' --no-auth-cache | egrep -o '^r[0-9]+' | head -1)
   local SVN_DATE=$(svn info | egrep '^(Last Changed Date)' | awk '{ print $4,"/",$5 }')

   git checkout subversion
   git branch OLD_subversion
   git reset --soft $BASE
   git commit --amend -m"$SVN_REV: $SVN_DATE"

   git checkout master
   git branch OLD_master
   git rebase --onto subversion OLD_subversion master

   git branch -D OLD_subversion

   echo "!!!!! This isn't correct - sub-branches should not be rebased onto master!"
   echo "--> Also, sync can be changed to this OLD_* format and just called from here"
   for BRANCH in $(git branch | egrep -v " (master|subversion|OLD_.*)$"); do
      git checkout $BRANCH
      git rebase --onto master OLD_master $BRANCH
   done

   git branch -D OLD_master
   git checkout $CUR_BRANCH
}

patchwork_pre_pull() {
   local CUR_BRANCH=$(util_current_branch)
   local START_REV=$(svn log -l 1 --username svn --password '' --no-auth-cache | egrep -o '^r[0-9]+' | head -1 | sed -e 's/r//')

   util_var_save .pw_pulling CUR_BRANCH "$CUR_BRANCH"
   util_var_save .pw_pulling START_REV "$START_REV"
   git checkout subversion
}
patchwork_pull() {
   patchwork_pre_pull
   svn up --username svn --password '' --no-auth-cache
   patchwork_post_pull
}
patchwork_post_pull() {
   CUR_BRANCH=$(util_var_load .pw_pulling CUR_BRANCH)
   START_REV=$(util_var_load .pw_pulling START_REV)
   util_var_clear .pw_pulling

   local END_REV=$(svn log -l 1 --username svn --password '' --no-auth-cache | egrep -o '^r[0-9]+' | head -1 | sed -e 's/r//')

   # This is done because we want to both exclude START_REV (it was already pulled), and
   # list the specific revisions for us that apply:

   local LOGS=$(svn log -r$((START_REV + 1)):$END_REV --username svn --password '' --no-auth-cache)
   local REVS=$(echo "$LOGS" | egrep -o '^r[0-9]+' | sed -e 's/r//')

   local START=$(echo "$REVS" | head -1)
   local END=$(echo "$REVS" | tail -1)

   # For the new untracked files, have to add them all..
   local FILES=$(svn --username svn --password '' --no-auth-cache diff --summarize -r$((START - 1)):$END)
   echo "$FILES" | grep '^ *M' | awk '{ print $(NF) }' | xargs git add  2> /dev/null
   echo "$FILES" | grep '^ *A' | awk '{ print $(NF) }' | xargs git add  2> /dev/null
   echo "$FILES" | grep '^ *D' | awk '{ print $(NF) }' | xargs git rm   2> /dev/null

   git commit -a -m"svn log -r$END:$START" # This order is the same as "-l 4"

   git checkout $CUR_BRANCH
   patchwork_sync # Also uses a CUR_BRANCH that was overwriting this one.  Hmm...
}

patchwork_push() {
   local CUR_BRANCH=$(util_current_branch)
   util_var_save .pw_pushing CUR_BRANCH "$CUR_BRANCH"

   git rebase --onto subversion master $CUR_BRANCH

   # Up until here is confirmed to work fine
   # And apparently if I abort, post_commit moved it back onto master?  Scary, not sure why that worked..  It shouldn't have!

   local FILES=$(git diff --name-status --relative subversion..HEAD)
   if echo "$FILES" | grep '^ *A' > /dev/null; then
      echo "$FILES" | grep '^ *A' | awk '{ print $(NF) }' | xargs svn add
   fi
   if echo "$FILES" | grep '^ *D' > /dev/null; then
      echo "$FILES" | grep '^ *D' | awk '{ print $(NF) }' | xargs svn rm
   fi

   #svn commit
   #patchwork_post_commit
   return 0
}
patchwork_abort_push() {
   CUR_BRANCH=$(util_var_load .pw_pushing CUR_BRANCH)
   util_var_clear .pw_pushing

   git rebase --onto master subversion $CUR_BRANCH
   git checkout $CUR_BRANCH
}
patchwork_post_push() {
   CUR_BRANCH=$(util_var_load .pw_pushing CUR_BRANCH)
   util_var_clear .pw_pushing

   git checkout subversion
   git merge $CUR_BRANCH # Fast-forward
   git checkout $CUR_BRANCH
   patchwork_sync
}

patchwork_patch() {
   echo "Not Implemented"
   # Basic idea - if I have a couple-line change, the whole branch/commit/push is a lot.
   # So:

   # $ pw patch
   #    -> Quit if there are local changes and remind to commit
   #    -> $ git checkout -b RAND_FOO master
   # User does stuff
   # possible "git commit"s
   # $ pw patch --push "svn commit message"
   #    -> if uncomitted changes:
   #       -> $ git add .
   #       -> $ git commit -a -m"svn commit message"
   #    -> $ pw push
   #    -> (svn add should be working eventually... In the meantime, break)
   #    -> $ svn commit -m"svn commit message"
   #    -> $ pw post_push
}

patchwork() {
   COMMAND=$1

   if [ -z "$COMMAND" ] || echo $COMMAND | egrep -i '^help$' > /dev/null; then
      echo "Currently available commands: branches, sync, pull"
      return 0
   fi

   if ! patchwork_$COMMAND ;then
      echo "Command not found: $COMMAND"
      return 1
   fi
}

pw() {
   patchwork "$@"
}

