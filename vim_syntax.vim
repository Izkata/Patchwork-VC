
if exists("b:current_syntax")
    finish
endif

syntax include @gitlog $VIMRUNTIME/syntax/git.vim
syntax include @gitdiff $VIMRUNTIME/syntax/diff.vim

syntax region pwPushLog
    \ start=/^# =*.* Log$/
    \ end=/^# =*.* End Log$/
    \ contains=@gitlog, pwPushLog

syntax region pwPushDiff
    \ start=/^# =*.* Diff$/
    \ end=/^# =*.* End Diff$/
    \ contains=@gitdiff, pwPushDiff

let b:current_syntax = "patchwork_push"

