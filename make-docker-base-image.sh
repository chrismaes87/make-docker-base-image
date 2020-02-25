#!/usr/bin/env bash
#
# Create a base Docker image.
#
# inspired from https://github.com/moby/moby/blob/master/contrib/mkimage-yum.sh

set -e

usage() {
    cat <<EOOPTS
$(basename $0) [OPTIONS] <name[:version]>

SYNOPSIS
    Create an image from scratch with certain packages installed.
    The resulting image will be created with tag 'name:version' .
    If version is not specified, we will try to fetch it from /etc/{redhat,system}-release in the image.

OPTIONS:
    -c | --config-file <config_file>    The path to the pkg-manager config file.
                                        Default:
                                        - if <pkg-manager> = yum : /etc/yum.conf
                                        - if <pkg-manager> = zypper : /etc/zypp/zypp.conf
                                        - if <pkg-manager> = dnf : /etc/dnf/dnf.conf
    --filesystem-only                   Construct only the filesystem in <target-dir>.
                                        Don't create the docker image. Don't remove <target-dir> at the end.
    -g | --group <group>                Package group to install in the container.
                                        (example: Core for centos)
                                        Can be specified multiple times.
    -p | --package <package>            Package to install in the container.
                                        Can be specified multiple times.
    -t | --target-dir <target-dir>      Where to construct the image filesystem before importing
                                        Default: temporary directory in /tmp
EOOPTS
    exit 1
}

REARRANGED_OPTIONS=$(getopt -o c:g:hp:t: --long config-file:,filesystem-only,group:,help,package:,target-dir: -- "$@")
eval set -- "$REARRANGED_OPTIONS"

install_groups=()
install_packages=()
version=
while true
do
	case "$1" in
        -c | --config-file ) config_file=$2; shift 2;;
        --filesystem-only ) FILESYSTEM_ONLY=1; shift;;
        -g | --group ) install_groups+=("$2"); shift 2;;
        -h | --help ) usage ;;
        -p | --package ) install_packages+=("$2"); shift 2;;
        -t | --target-dir ) target=$2; shift 2;;
		-- )
			shift; # skip --
			if [ -n "$1" ]
			then
				docker_tag=$1
				shift # skip $1
				if [ -n "$1" ]
				then
					echo "$me : Unexpected arguments: \"$@\" . exiting."; exit 1 ;
				fi
            elif [[ -z $FILESYSTEM_ONLY ]]
            then
                # user needs to specify the name except when FILESYSTEM_ONLY is specified.
                usage
			fi
			break;;
		* ) echo "$me : Unexpected options: \"$@\" . exiting."; exit 1 ;;
	esac
done

for pkgm in zypper yum dnf
do
    if command -v $pkgm >/dev/null
    then
        pkg_manager=$pkgm
        break
    fi
done

if [[ -z $pkg_manager ]]
then
    echo "no valid package manager found. Exiting"
    exit 1
fi

if [[ -z $config_file ]]
then
    case $pkg_manager in
        yum)
            config_file=/etc/yum.conf ;;
        zypper)
            config_file=/etc/zypp/zypp.conf ;;
        dnf)
            config_file=/etc/dnf/dnf.conf ;;
    esac
    echo "auto-selected config_file: $config_file"
fi

if [[ ! -e $config_file ]]
then
    echo "$config_file does not exist"
    exit 1
fi

if [[ $pkg_manager != zypper ]]
then
    # default to Core group if not specified otherwise
    if [ ${#install_groups[@]} -eq 0 ]; then
        install_groups=('Core')
    fi
fi

if [[ -n $target ]]
then
    if [ ! -d $target ]
    then
        mkdir $target
    fi
else
    target=$(mktemp -d --tmpdir $(basename $0).XXXXXX)
fi

set -x

mkdir -m 755 "$target"/dev
mknod -m 600 "$target"/dev/console c 5 1
mknod -m 600 "$target"/dev/initctl p
mknod -m 666 "$target"/dev/full c 1 7
mknod -m 666 "$target"/dev/null c 1 3
mknod -m 666 "$target"/dev/ptmx c 5 2
mknod -m 666 "$target"/dev/random c 1 8
mknod -m 666 "$target"/dev/tty c 5 0
mknod -m 666 "$target"/dev/tty0 c 4 0
mknod -m 666 "$target"/dev/urandom c 1 9
mknod -m 666 "$target"/dev/zero c 1 5

# amazon linux yum will fail without vars set
if [ -d /etc/yum/vars ]; then
	mkdir -p -m 755 "$target"/etc/yum
	cp -a /etc/yum/vars "$target"/etc/yum/
fi

if [[ $pkg_manager = zypper ]]
then
    ZYPP_CONF="$config_file" $pkg_manager --root="$target" --gpg-auto-import-keys refresh
    if [[ -n "$install_groups" ]]
    then
        ZYPP_CONF="$config_file" $pkg_manager --root="$target" install -y -t pattern "${install_groups[@]}"
    fi

    if [[ -n "$install_packages" ]]
    then
        ZYPP_CONF="$config_file" $pkg_manager --root="$target" install -y "${install_packages[@]}"
    fi
    ZYPP_CONF="$config_file" $pkg_manager --root="$target" clean -a
else
    if [[ -n "$install_groups" ]]
    then
        $pkg_manager -c "$config_file" --installroot="$target" --releasever=/ --setopt=tsflags=nodocs \
            --setopt=group_package_types=mandatory -y groupinstall "${install_groups[@]}"
    fi

    if [[ -n "$install_packages" ]]
    then
        $pkg_manager -c "$config_file" --installroot="$target" --releasever=/ --setopt=tsflags=nodocs \
            --setopt=group_package_types=mandatory -y install "${install_packages[@]}"
    fi

    $pkg_manager -c "$config_file" --installroot="$target" -y clean all

    cat > "$target"/etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF
fi

# effectively: febootstrap-minimize --keep-zoneinfo --keep-rpmdb --keep-services "$target".
#  locales
rm -rf "$target"/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive}
#  docs and man pages
rm -rf "$target"/usr/share/{man,doc,info,gnome/help}
#  cracklib
rm -rf "$target"/usr/share/cracklib
#  i18n
rm -rf "$target"/usr/share/i18n
#  yum cache
rm -rf "$target"/var/cache/yum/*
#  sln
rm -rf "$target"/sbin/sln
#  ldconfig
rm -rf "$target"/etc/ld.so.cache "$target"/var/cache/ldconfig/*

if [[ $FILESYSTEM_ONLY ]]
then
    echo "filesystem constructed in directory $target . "
    exit 0
fi

if ! [[ $docker_tag =~ : ]]
then
    # docker_tag does not contain a version number, search it in the image.
    for file in "$target"/etc/{redhat,system}-release
    do
        if [ -r "$file" ]; then
            version="$(sed 's/^[^0-9\]*\([0-9.]\+\).*$/\1/' "$file")"
            break
        fi
    done
    docker_tag="$docker_tag:$version"
fi

tar --numeric-owner -c -C "$target" . | docker import - $docker_tag

rm -rf "$target"