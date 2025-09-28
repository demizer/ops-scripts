set -Ux VIRTUAL_ENV_DISABLE_PROMPT
set -Ux P4USER jesusa
set -Ux P4CLIENT {$P4USER}-dev-installer
set -Ux P4ROOT /data/work/perforce/{$P4CLIENT}
set -Ux P4PORT p4proxy-sc.nvidia.com:2006
set -Ux EDITOR nvim
set -Ux P4DIFF 'nvim -d'
