
set base_repo_path "/mnt/arch_repo/"
set repo_path "$base_repo_path/alvaone"

alias pacu='sudo pacman -Syu'

alias repo="cd $base_repo_path"
alias srepo="cd $base_repo_path/sources"
alias arepo="cd $repo_path"

# System maintenance
alias pac-cache-clean-dryrun='paccache --keep 3 -v --dryrun'
alias pac-cache-clean='paccache --keep 3 -v --remove'
alias pacfiles='find /etc -regextype posix-extended -regex ".+\.pac(new|save|orig)" 2> /dev/null'
alias umirrors='sudo sh -c "/usr/bin/python3 -m Reflector -c US -l 5 -f 5 --sort rate 2>&1 | tee /etc/pacman.d/mirrorlist"'
alias umirrorss='sudo sh -c "/usr/bin/python3 -m Reflector -c US --sort score 2>&1 | tee /etc/pacman.d/mirrorlist"'

alias alvaone-unknown='grep -Fxvf <(aur pkglist) <(pacman -Slq alvaone)'
alias alvaone-aursync-all='sudo pacman -Sy; aur sync -d alvaone --chroot --pacman-conf /usr/share/devtools/pacman.conf.d/extra.conf --sign --tar --upgrades'
alias alvaone-list-installed='paclist alvaone'
alias alvaone-check='alvaone-list | aur vercmp'

#
# WARNING
# WARNING Requires symlink
# ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# WARNING
#

function alvaone-add
    if test (count $argv) -lt 1
        echo "alvaone-add"
        echo
        echo "Add a package to the alvaone repo."
        echo
        echo "usage: alvaone-add <pkg-name-in-current-directory-with-extension>"
        return
    end
    if test ! -f "$argv[1].sig"
        echo ">>> Signing package"
        GPG_TTY=(tty) gpg --batch --yes --detach-sign --use-agent -u 0EE7A126 $argv[1]
    end
    echo ">>> Removing old packages"
    rm -vrf "{$repo_path}"/x86_64/$argv1*
    echo ">>> Coping packages"
    cp $argv[1] $argv[1].sig {$repo_path}/x86_64/
    echo ">>> Adding to the repo"
    repo-add --new --remove --sign --verify "$repo_path/x86_64/alvaone.db.tar.xz" "$repo_path"/x86_64/$argv[1]
end

function alvaone-sign
    if test (count $argv) -lt 1
        echo "alvaone-sign"
        echo
        echo "Signs a compiled package that for whatever reason is not signed."
        echo
        echo "usage: alvaone-sign <pkg-name>"
        return
    end
    echo ">>> Signing package '(basename $argv[1])'"
    GPG_TTY=(tty) gpg --batch --yes --detach-sign --use-agent -u 0EE7A126 $argv[1]
end

function alvaone-repo-fix-sign
    repo-add {$repo_path}/x86_64/alvaone.db.tar.xz -s
end

function alvaone-remove
    repo-remove -s -v {$repo_path}/x86_64/alvaone.db.tar.xz $argv
    set -l arg
    for arg in "$argv"
        rm -vrf {$repo_path}/x86_64/$arg*
    end
end

function is-package
    # $argv[1] the expected name
    # $2 path to the package
    set -l name=(tar --xz -axf $2 .PKGINFO -O | grep pkgname | cut -f 2 -d = | tr -d '\ ') echo $name
    if test $name == $argv[1]
        return 0
    end
    return 1
end

function alvaone-list
    tar -xf {$repo_path}/x86_64/alvaone.db.tar.xz -O | grep "\(%NAME%\|%VERSION%\)" -A1 | grep -v "\(%NAME%\|--\|%VERSION%\)" | sed '$!N;s/\n/ /'
end

function archzfs-list
    tar -xf /repo/archzfs/x86_64/archzfs.db.tar.xz -O | grep "\(%NAME%\|%VERSION%\)" -A1 | grep -v "\(%NAME%\|--\|%VERSION%\)" | sed '$!N;s/\n/ /'
end

function mksrcinfo
    test -z $argv[1]; and cd (dirname $argv[1])
    makepkg --printsrcinfo > .SRCINFO
    test -z $argv[1]; and cd - > /dev/null
end

function alvaone-build
    if test (count $argv) -lt 1
        echo "alvaone-build"
        echo
        echo "Builds in a systemd-nspawn container using aurutils aur-build"
        echo
        echo "usage: alvaone-build <pkg-name>"
        return
    end

    # Need to copy a custom pacman.conf to include my local repository
    test -f /tmp/pacman.conf; and rm -rf /tmp/pacman.conf
    cp /usr/share/devtools/pacman.conf.d/extra.conf /tmp/pacman.conf
    cat /etc/pacman.d/alvaone >> /tmp/pacman.conf

    # Builds are end in /var/lib/aurbuild/x86_64/demizer
    aur sync --rebuild --sign --chroot --pacman-conf /tmp/pacman.conf $argv[1..-1]
end

function alvaone-build-no-chroot
    if test (count $argv) -lt 1
        echo "alvaone-build-no-chroot"
        echo
        echo "Builds a package using aurutils aur-build, dependencies automatically installed are removed."
        echo
        echo "usage: alvaone-build-no-chroot <pkg-name>"
        return
    end
    # Need to copy a custom pacman.conf to include my local repository
    test -f /tmp/pacman.conf; and rm -rf /tmp/pacman.conf
    cp /usr/share/devtools/pacman.conf.d/extra.conf /tmp/pacman.conf
    cat /etc/pacman.d/alvaone >> /tmp/pacman.conf

    # Builds are end in /var/lib/aurbuild/x86_64/demizer
    aur sync --rebuild --sign --rm-deps --pacman-conf /tmp/pacman.conf $argv[1..-1]
end

function alvaone-rebuild
    if test (count $argv) -lt 1
        echo "alvaone-rebuild"
        echo
        echo "DRY_RUN is optional. If used the command output will be shown, but no changes will be made."
        echo
        echo "usage: [DRY_RUN=1] alvaone-build <pkg-name>"
        return
    end
    rm -rf {$base_repo_path}/sources/$argv[1]; and mkdir -p {$base_repo_path}/sources/$argv[1]; and cd {$base_repo_path}/sources/$argv[1]
    aur sync --sign --chroot --pacman-conf /usr/share/devtools/pacman.conf.d/extra.conf --rebuild $argv[1..-1]
    cd - > /dev/null
end

function alvaone-build-pwd
    find -maxdepth 2 -name PKGBUILD | while read -l file; mksrcinfo $file; end
    test -f /tmp/pacman.conf; and rm -rf /tmp/pacman.conf
    cp /usr/share/devtools/pacman.conf.d/extra.conf /tmp/pacman.conf
    cat /etc/pacman.d/alvaone >> /tmp/pacman.conf

    # --force       Compiles the package even if one is found with the same name
    # --gpg-sign    Sign build packages and the database
    # --remove      Remove old packages files when updating their entry in the database
    # --verify      Verify the pgp signature of the database before updating
    # --chroot      Build in a systemd-nspawn container
    # --no-sync     Do not sync the local repository after building
    aur build --force --remove --verify --gpg-sign --database=alvaone --chroot --pacman-conf /tmp/pacman.conf --no-sync $argv[1..-1]
end

#
# 12:53 Sat Nov 13 2021: These next functions has been commented out because fish shell doesn't like the for loop
#                        Not sure how to work around that yet in fish land.
#
# function ensure-ccm64-local-repo-is-set
#   # if this is the first time package has been successfully built
#   # then append the local repo to the chroot's pacman.conf
#   if test -z (grep clean-chroot {$repo_path}x86_64/root/etc/pacman.conf)
#     # add a local repo to chroot
#     sudo sed -i '/\[testing\]/i \
#       # Added by clean-chroot-manager\n[chroot_local]\nSigLevel = Never\nServer = file://{$base_repo_path}\n' \
#       {$base_repo_path}/chroot/x86_64/root/etc/pacman.conf
#   end
# end

# function ccm64-alvaone-sync
#     if test (count $argv) -lt 1
#         echo "ccm64-alvaone-sync"
#         echo
#         echo "Add a package from the alvaone repo to the clean-chroot-manager repo."
#         echo
#         echo "Takes a single package name, and copies a single package."
#         echo
#         echo "DRY_RUN is optional. If used the command output will be shown, but no changes will be made."
#         echo
#         echo "usage: [DRY_RUN=1] ccm64-alvaone-sync <pkg-name>"
#         return
#     end
#     set pkgs=((alvaone-list | grep "$argv[1]"))
#     test ! -d /repo/chroot/x86_64/root/repo; and sudo mkdir /repo/chroot/x86_64/root/repo
#     set -l src=()
#     set -l dst=()
#     for (( i=1; i<${#pkgs[@]}; i+=2 )
#         if (is-package $argv[1] "/repo/alvaone/x86_64/${pkgs[i]}-${pkgs[i+1]}-x86_64.pkg.tar.zst")
#             src+=("/repo/alvaone/x86_64/${pkgs[i]}-${pkgs[i+1]}-x86_64.pkg.tar.zst")
#             dst+=("/repo/chroot/x86_64/root/repo/${pkgs[i]}-${pkgs[i+1]}-x86_64.pkg.tar.zst")
#         end
#     end
#     if test $DRY_RUN == 1
#         echo sudo cp "${src[@]}" "/repo/chroot/x86_64/root/repo/"
#         echo sudo repo-add /repo/chroot/x86_64/root/repo/chroot_local.db.tar.gz ${dst[@]}
#         return
#     end
#     sudo cp "${src[@]}" "/repo/chroot/x86_64/root/repo/"
#     sudo repo-add /repo/chroot/x86_64/root/repo/chroot_local.db.tar.gz ${dst[@]}
#     ensure-ccm64-local-repo-is-set
# end
#
# function ccm64-archzfs-sync
#     if test (count $argv) -lt 1
#         echo "ccm64-archzfs-sync"
#         echo
#         echo "Add a package from the archzfs repo to the clean-chroot-manager repo."
#         echo
#         echo "Takes a single package name, and copies a single package."
#         echo
#         echo "DRY_RUN is optional. If used the command output will be shown, but no changes will be made."
#         echo
#         echo "usage: [DRY_RUN=1] ccm64-alvaone-sync <pkg-name>"
#         return
#     end
#     pkgs=((archzfs-list | grep "$argv[1]"))
#     set -l src=()
#     set -l dst=()
#     for (( i=1; i<${#pkgs[@]}; i+=2 )
#         if (is-package $argv[1] "/repo/archzfs/x86_64/${pkgs[i]}-${pkgs[i+1]}-x86_64.pkg.tar.zst")
#             src+=("/repo/archzfs/x86_64/${pkgs[i]}-${pkgs[i+1]}-x86_64.pkg.tar.zst")
#             dst+=("/repo/chroot/x86_64/root/repo/${pkgs[i]}-${pkgs[i+1]}-x86_64.pkg.tar.zst")
#         end
#     end
#     if test $DRY_RUN == 1
#         echo sudo cp "${src[@]}" "/repo/chroot/x86_64/root/repo/"
#         echo sudo repo-add /repo/chroot/x86_64/root/repo/chroot_local.db.tar.gz ${dst[@]}
#         return
#     end
#     sudo cp "${src[@]}" "/repo/chroot/x86_64/root/repo/"
#     sudo repo-add /repo/chroot/x86_64/root/repo/chroot_local.db.tar.gz ${dst[@]}
#     ensure-ccm64-local-repo-is-set
# end
