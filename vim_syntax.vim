
if exists("b:current_syntax")
    finish
endif

syntax match pwSeparator "^# =.*$"
highlight link pwSeparator NonText

syntax include @gitlog $VIMRUNTIME/syntax/git.vim
syntax region pwPushLog
    \ start=/^commit/
    \ end=/\n\n/
    \ contains=@gitlog, pwPushLog

syntax include @gitdiff $VIMRUNTIME/syntax/diff.vim
syntax region pwPushDiff
    \ start=/^Index:/
    \ end=/^# =* (svn) End Diff/
    \ contains=@gitdiff, pwPushDiff

let b:current_syntax = "patchwork_push"

