#!/usr/bin/env bash

# ==================== Utils

current_branch() {
   echo "$(git branch | grep '\*' | awk '{ print $2 }')"
}

branch_exists() {
   git branch | grep " $1$" > /dev/null
   return $?
}
is_ancestor() {
   local BASE_REV=$(git rev-list "$1" -1)
   local BRANCH_REV=$(git merge-base "$1" "$2")
   [ "$BASE_REV" == "$BRANCH_REV" ]
   return $?
}

var_save() {
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
var_load() {
   local FILE=$1
   local NAME=$2

   local CUR_DIR=$(pwd)
   while ! [ -e '.git' ] && ! [ '/' == "$(pwd)" ];do cd ..;done

   source "$FILE"
   echo "${!NAME}"
   cd "$CUR_DIR"
}
var_clear() {
   local FILE=$1

   local CUR_DIR=$(pwd)
   while ! [ -e '.git' ] && ! [ '/' == "$(pwd)" ];do cd ..;done

   rm "$FILE"
   cd "$CUR_DIR"
}
# var_save .pw_pushing CUR_BRANCH "IE7_Fixes"
# local CUR_BRANCH=$(var_load .pw_pushing CUR_BRANCH)
# var_clear .pw_pushing

run_svn() {
   local SVN_USER_CMD=
   local SVN_PASS_CMD=
   local EXTRA=
   [ "$SVN_USER" ] && SVN_USER_CMD="--username $SVN_USER"
   [ "$SVN_PASS" ] && SVN_PASS_CMD="--password $SVN_PASS"
   [ "$SVN_USER" -o "$SVN_PASS" ] && EXTRA='--no-auth-cache'

   if [ -z "$EXTRA" ];then
      if ! svn --non-interactive "$@"; then
         [ -z "$SVN_USER" ] && read -p 'svn user: ' SVN_USER
         run_svn "$@"
      fi
   else
      svn $SVN_USER_CMD $SVN_PASS_CMD $EXTRA "$@"
   fi
}

last_changed_svn_rev() {
   run_svn info | grep '^Last Changed Rev: ' | egrep -o '[0-9]+'
}
# local REV=$(last_changed_svn_rev)

trim_head_tail() {
   tac | sed -e '/./,$!d' | tac | sed -e '/./,$!d'
}
copy_to() {
   awk " /$1/{lose = 1} (lose == 0) {print \$0} "
}
# cat file1 | trim_head_tail > file2
# cat file1 | copy_to '^#' > file2

# ==================== Currently in-use:

command_log() {
   if [ '--all' == "$1" ] && [ -z "$2" ];then
      git log --graph --decorate --oneline --color --first-parent --glob=refs/heads | less -SEXIER
      return 0
   fi
   if [ '--allall' == "$1" ] && [ -z "$2" ];then
      git log --graph --decorate --oneline --color --glob=refs/heads | less -SEXIER
      return 0
   fi
   if [ '--branches' == "$1" ];then
      git log --graph --decorate --oneline --color --glob=refs/heads master~1.. | less -SEXIER
      return 0
   fi
   if [ -z "$1" ];then
      git log --graph --decorate --oneline --color master~1.. | less -SEXIER
      return 0
   fi

   git log --graph --decorate --oneline --color "$@" | less -SEXIER
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

command_sync() {
   sanity_check_local_changes
   local START_BRANCH=$(current_branch)

   if ! branch_exists OLD_subversion; then
      git branch OLD_subversion subversion
   fi
   if ! branch_exists OLD_master; then
      git branch OLD_master master
   fi

   if ! git rebase --preserve-merges --onto subversion OLD_subversion master; then
      return 1
   fi
   git branch -D OLD_subversion  > /dev/null

   for BRANCH in $(git branch | egrep -v ' (OLD_.*)$' | egrep -v " (master|subversion)$"); do
      if is_ancestor OLD_master "$BRANCH"; then
         if ! git rebase --preserve-merges --onto master OLD_master "$BRANCH"; then
            return 1
         fi
      fi
   done
   git branch -D OLD_master      > /dev/null

   git checkout $START_BRANCH
   return 0
}

command_squash_svn() {
   sanity_check_local_changes
   local START_BRANCH=$(current_branch)

   local BASE=$(git rev-list --all | tail -1)
   local SVN_REV=$(last_changed_svn_rev)
   local SVN_DATE=$(run_svn info | egrep '^Last Changed Date' | awk '{ print $4,"/",$5 }')

   git checkout subversion
   git branch OLD_subversion
   git reset --soft $BASE
   git commit --amend -m"$SVN_REV: $SVN_DATE"

   git checkout $START_BRANCH
   command_sync
}

command_pull() {
   if [ '--prepare' == "$1" ]; then
      sanity_check_local_changes
      local CUR_BRANCH=$(current_branch)
      local START_REV=$(last_changed_svn_rev)

      var_save .pw_pulling CUR_BRANCH "$CUR_BRANCH"
      var_save .pw_pulling START_REV "$START_REV"
      git checkout subversion
      return 0
   fi
   if [ '--abort' == "$1" ]; then
      local CUR_BRANCH=$(var_load .pw_pulling CUR_BRANCH)
      if [ -z "$CUR_BRANCH" ];then
         echo "Error on 'pull --abort': No current branch"
         return 1
      fi
      var_clear .pw_pulling
      git checkout $CUR_BRANCH
      return 0
   fi
   if [ '--complete' == "$1" ];then
      local CUR_BRANCH=$(var_load .pw_pulling CUR_BRANCH)
      local START_REV=$(var_load .pw_pulling START_REV)
      if [ -z "$CUR_BRANCH" ];then
         echo "Error on 'pull --complete': No current branch"
         return 1
      fi
      if [ -z "$START_REV" ];then
         echo "Error on 'pull --complete': No initial revision"
         return 1
      fi
      var_clear .pw_pulling

      local END_REV=$(last_changed_svn_rev)

      # This is done because we want to both exclude START_REV (it was already pulled), and
      # list the specific revisions for us that apply:

      local LOGS=$(run_svn log -r$((START_REV + 1)):$END_REV )
      local REVS=$(echo "$LOGS" | egrep -o '^r[0-9]+' | sed -e 's/r//')

      local START=$(echo "$REVS" | head -1)
      local END=$(echo "$REVS" | tail -1)

      # For the new untracked files, have to add them all..
      local FILES=$(run_svn diff --summarize -r$((START - 1)):$END)
      if echo "$FILES" | grep '^ *M' > /dev/null; then
         echo "$FILES" | grep '^ *M' | awk '{ print $(NF) }' | xargs git add
      fi
      if echo "$FILES" | grep '^ *A' > /dev/null; then
         echo "$FILES" | grep '^ *A' | awk '{ print $(NF) }' | xargs git add
      fi
      if echo "$FILES" | grep '^ *D' > /dev/null; then
         echo "$FILES" | grep '^ *D' | awk '{ print $(NF) }' | xargs git rm
      fi

      git branch OLD_subversion
      git commit -a -m"svn log -r$END:$START" # This order is the same as "-l 4"

      git checkout $CUR_BRANCH
      command_sync
      return 0
   fi

   command_pull --prepare
   run_svn up
   command_pull --complete
   return 0
}

command_push() {
   local METHOD=
   local ANDREMOVE=
   local MESSAGE=
   local AUTO_MESSAGE=
   while [[ $# > 0 ]]; do
      ARG="$1"
      shift

      case "$ARG" in
         --prepare)  METHOD='prepare'
                     ;;
         --abort)    METHOD='abort'
                     ;;
         --complete) METHOD='complete'
                     ;;
         --remove)   ANDREMOVE='--remove'
                     ;;
         --auto-msg) AUTO_MESSAGE=1
                     ;;
         -m)         ;&
         --message)  MESSAGE="$1"
                     shift
                     ;;
      esac
   done

   if [ 'prepare' == "$METHOD" ]; then
      sanity_check_local_changes
      local CUR_BRANCH=$(current_branch)
      var_save .pw_pushing CUR_BRANCH "$CUR_BRANCH"

      git rebase --preserve-merges --onto subversion master $CUR_BRANCH

      local FILES=$(git diff --name-status --relative subversion..HEAD)
      if echo "$FILES" | grep '^ *A' > /dev/null; then
         echo "$FILES" | grep '^ *A' | awk '{ print $(NF) }' | xargs svn add
      fi
      if echo "$FILES" | grep '^ *D' > /dev/null; then
         echo "$FILES" | grep '^ *D' | awk '{ print $(NF) }' | xargs svn rm
      fi
      return 0
   fi
   if [ 'abort' == "$METHOD" ]; then
      sanity_check_local_changes
      local CUR_BRANCH=$(var_load .pw_pushing CUR_BRANCH)
      if [ -z "$CUR_BRANCH" ];then
         echo "Error on 'push --abort': No current branch"
         return 1
      fi
      var_clear .pw_pushing

      git rebase --preserve-merges --onto master subversion $CUR_BRANCH
      return 0
   fi
   if [ 'complete' == "$METHOD" ]; then
      local CUR_BRANCH=$(var_load .pw_pushing CUR_BRANCH)
      if [ -z "$CUR_BRANCH" ];then
         echo "Error on 'push --complete': No current branch"
         return 1
      fi
      var_clear .pw_pushing

      git checkout subversion
      git merge --no-ff $CUR_BRANCH
      git checkout $CUR_BRANCH
      if ! command_sync ;then
         return 1
      fi
      git merge master # Fast-forward, but only if sync succeeded

      if [[ "$ANDREMOVE" ]]; then
         git checkout master
         git branch -d $CUR_BRANCH
      fi
      return 0
   fi

   command_push --prepare

   > SVN_COMMIT_MESSAGE
   if [[ "$AUTO_MESSAGE" ]]; then
      git log subversion..HEAD --format=format:"%s%n" >> SVN_COMMIT_MESSAGE
   elif [[ "$MESSAGE" ]]; then
      echo "$MESSAGE" >> SVN_COMMIT_MESSAGE
   fi
   push_generate_message

   if push_confirm; then
      if run_svn commit -F SVN_COMMIT_MESSAGE ; then
         command_push --complete "$ANDREMOVE"
         echo ''
         echo 'Push complete'
      else
         command_push --abort
         echo ''
         echo 'Push aborted due to svn commit failure'
      fi
   else
      command_push --abort
      echo ''
      echo 'Push aborted'
   fi

   rm SVN_COMMIT_MESSAGE
   return 0
}
push_generate_message() {
   local CUR_BRANCH=$(current_branch)

   cat SVN_COMMIT_MESSAGE > PATCHWORK_PUSH
   echo -e '\n' >> PATCHWORK_PUSH
   echo '# All lines above this first comment will be used as your svn commit message' >> PATCHWORK_PUSH
   echo '# ==================== (git) Files' >> PATCHWORK_PUSH
   git diff --name-status --relative subversion..$CUR_BRANCH >> PATCHWORK_PUSH
   echo -e '\n' >> PATCHWORK_PUSH

   echo '# ==================== (git) Log' >> PATCHWORK_PUSH
   git log subversion..$CUR_BRANCH >> PATCHWORK_PUSH
   echo -e '\n' >> PATCHWORK_PUSH

   echo '# ==================== (svn) Diff' >> PATCHWORK_PUSH
   svn diff >> PATCHWORK_PUSH
   echo -e '\n' >> PATCHWORK_PUSH

   if [ -z "$EDITOR" ];then local EDITOR=vim;fi
   $EDITOR PATCHWORK_PUSH

   cat PATCHWORK_PUSH | copy_to '^#' | trim_head_tail > SVN_COMMIT_MESSAGE
   rm PATCHWORK_PUSH
}
push_confirm() {
   local CUR_BRANCH=$(var_load .pw_pushing CUR_BRANCH)

   # Seems that newlines are already empty, so also trim off trailing whitespace...
   if [ -z "$(cat SVN_COMMIT_MESSAGE | sed -e 's/ \+$//')" ] ;then
      return 1
   fi

   echo '--------------------'
   git diff --name-status --relative subversion..$CUR_BRANCH
   echo ''
   cat SVN_COMMIT_MESSAGE
   echo -n 'Okay to commit? [y/N] '
   read Q

   if echo $Q | grep '^y$'; then
      return 0
   else
      return 1
   fi
}

command_patch() {
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

# ==================== Init new must be run outside of primary options due to .git not existing
if [ "$1" == 'init' ]; then
   if [ -e '.git' ] || [ -e '.pw' ];then
      if ! cat .pw/stage | grep 'init' > /dev/null; then
         echo "Cannot init a repo here; .git and/or .pw already exist"
         exit 1
      fi
   fi

   if [ ! -e '.pw/' ]; then
      mkdir .pw/
      git init .

      echo 'Scanning for non-svn files...'
      SVN_IGNORE=$(svn stat --no-ignore | egrep '^(I|\?)' | awk '{ print $2 }' | sort)

      echo 'Collapsing list...'
      EXCLUDE=''
      for X in $SVN_IGNORE; do
         NEW_SVN_IGNORE=$(echo "$SVN_IGNORE" | grep -v "^$X")
         if [ "$SVN_IGNORE" != "$NEW_SVN_IGNORE" ]; then
            SVN_IGNORE="$NEW_SVN_IGNORE"
            EXCLUDE="$EXCLUDE $X"
         fi
      done

      echo '/.svn/' > .gitignore
      for FILE in $EXCLUDE; do
         FILE=$(echo $FILE | sed -e 's#^\./##')
         if [ -d "$FILE" ]; then
            echo "/$FILE/"
         else
            echo "/$FILE"
         fi
      done >> .gitignore

      echo ''
      echo 'Check .gitignore and add anything else that should not be version controlled,'
      echo 'then run "pw init" again.'
      echo ''

      echo 'init_1' > .pw/stage
      exit 0
   fi

   if [ 'init_1' == "$(cat .pw/stage)" ];then
      git add .

      echo 'init_2' > .pw/stage

      if [ ! -z "$(git status --porcelain | grep -v '^A ')" ]; then
         echo "There are untracked files that don't belong in subversion."
         echo "This must be resolved manually (likely need more .gitignore rules)."
         echo "Run 'pw init' again when done."
         exit 0
      fi
   fi

   if [ 'init_2' == "$(cat .pw/stage)" ];then
      git add .gitignore
      git commit -m'Subversion import'
      git branch subversion

      # This is temporary; there is a bug I have yet to bother tracking down
      touch 'local_change'
      git add local_change
      git commit -m"local_change so sync doesn't mess up"

      echo '' > .pw/stage
      exit 0
   fi

   if [ "$2" == 'undo' ]; then
      if [ 'init_2' == "$(cat .pw/stage)" ];then
         exit 0
      fi
      if [ 'init_1' == "$(cat .pw/stage)" ];then
         exit 0
      fi
   fi

   exit 0
fi

# ==================== Sanity checking
while ! [ -e '.git' ] && ! [ '/' == "$(pwd)" ];do cd ..;done
if [ ! -e '.git' ];then
   echo "Cannot be run outside of git repository"
   exit 2
fi

sanity_check_local_changes() {
   if git status --porcelain | egrep -v '^\?\?'; then
      echo "Cannot be run while the git repo is in a dirty state"
      exit 3
   fi
}

SVN_USER=''
SVN_PASS=''

while [[ $# > 0 ]]; do
   ARG="$1"
   shift

   case "$ARG" in
      -u)            ;&
      --username)    SVN_USER="$1"
                     shift
                     ;;
      -u*)           SVN_USER=$(echo "$ARG" | sed -e 's/^-u//')
                     ;;

      -p)            ;&
      --password)    SVN_PASS="$1"
                     shift
                     ;;
      -p*)           SVN_PASS=$(echo "$ARG" | sed -e 's/^-p//')
                     ;;

      pull)       ;&
      push)       ;&
      sync)       ;&
      squash_svn) ;&
      log)        command_$ARG "$@"
                  break
                  ;;
      branches)   command_log --branches
                  break
                  ;;
      *)          echo "Unknown command: $ARG"
                  break
                  ;;
   esac
done

