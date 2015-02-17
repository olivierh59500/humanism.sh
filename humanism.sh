#!/usr/bin/env bash
# source $0                        loads all functions
# source $0 <func> [func ...]    load specific functions
# $0 help                        function list and description

#
# Common aliases
#
#shopt -s expand_aliases # NOT BSD COMPLIANT
# alias egrep='egrep --color=auto'
# alias fgrep='fgrep --color=auto'
# alias grep='grep --color=auto'
# alias ls='ls --color=auto'
alias s='sudo '
# pass our env through to sudo
ss () { /usr/bin/sudo --  bash -rcfile /home/user/bin/bash_util_functions -c "$*"; }
# carry aliases by adding space https://wiki.archlinux.org/index.php/Sudo#Passing_aliases
alias sudo='sudo '
alias ...='cd ../../'
alias ....='cd ../../../'
alias .....='cd ../../../../'

#
# Iterate over arguments and load each function
#

# If no argument defined load all
if [ $# -eq 0 ]; then
    set  -- c log history ps find usage_self ap dbg sshrc $@
fi


if readlink "$BASH_SOURCE" >/dev/null 2>&1; then
	export HUMANISM_BASE="$(dirname $(readlink $BASH_SOURCE))"
else
	export HUMANISM_BASE="$(dirname $BASH_SOURCE)"
fi
OS="$(uname)"

for arg in $*; do

 case "$arg" in
  ap)
  #
  #    unified apt-get, apt-cache and dpkg
  #
  #    ap 		   without arguments for argument list

    if command -v apt-get >/dev/null 2>&1 ; then
    	ap () {
			"$HUMANISM_BASE/ap.linux-apt" $*
		}
	elif command -v brew >/dev/null 2>&1 ; then
		ap () {
			"$HUMANISM_BASE/ap.osx-brew" $*
		}
	elif command -v pkg >/dev/null 2>&1 ; then
		ap () {
			"$HUMANISM_BASE/ap.freebsd-pkg" $*
		}
	fi
    ;;

  dbg)
  #
  #    unified strace, lsof
  #
  #    dbg 		   without arguments for argument list

    dbg () {
        "$HUMANISM_BASE/dbg" $*
    }
    ;;


  sshrc)
  #
  #    carry env through ssh sessions
  #

		sshrc () {
			"$HUMANISM_BASE/sshrc" $*
		}
		;;

  cd|c)
  #
  #   recursive cd  (source in .bash_aliases)
  #
  #   c            go to last dir
  #   c path       go to path, if not in cwd search forward and backward for
  #                *PaTh* in tree

    # (optional) use env var HUMANISM_CD_DEPTH for maxdepth
    if [ -z $HUMANISM_CD_DEPTH ]; then
        HUMANISM_CD_DEPTH=8
    fi
    dir_in_tree () {
        local BASEDIR="$1"
        local SEARCH="${@:2}"
        local DEPTH=1
        local DIR
        for DEPTH in $(seq 1 $HUMANISM_CD_DEPTH); do
            # timeout forces stop after one second
            if [ "Linux" = "$OS" ]; then
                DIR=$(timeout -s SIGKILL 1s \
                      /usr/bin/env find $BASEDIR -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                               -printf "%C@ %p\n" 2>/dev/null | sort -n | tail -1 | awk '{$1=""; print}' )
                            #-exec stat --format "%Y##%n" humanism.sh/dbg (NOTE ISSUE WITH SPACE)
            else
                DIR=$(/usr/bin/env find $BASEDIR -depth $DEPTH -iname "*$SEARCH*" -type d \
                           -exec stat -f "%m %N" {} 2>/dev/null \; | sort -n | tail -1 | awk '{$1=""; print}' \
                           & sleep 1; kill $!)
            fi

            if [[ $DIR ]]; then
                # remove trailing space
                echo "${DIR## }"
                break
            fi
            DEPTH=$(($DEPTH+1))
        done
    }
    c () {
        # no args: go to last dir
        if [ $# -eq 0 ]; then
            if [ -f ~/.cwd ]; then
                    builtin cd "`cat ~/.cwd`"
            else
                    builtin cd
            fi
            pwd > ~/.cwd
            return 0
        # arg1: if has a slash then assume its just a direct path we do not need to find
        # oh and, suck up all args as the path. hence no more: cd ./a\ dir\ with\ spaces/
        elif [[ "$1" == */* ]]; then
                builtin cd "$*"
                pwd > ~/.cwd
                return 0
        # arg1: has no slashes so find it in the cwd
        else
            D=$(dir_in_tree . "$*")
            if [[ "$D" ]]; then
                builtin cd "$D"
                pwd > ~/.cwd
                return 0
            fi
            # now search backward and upward
            echo "<>"
            local FINDBASEDIR=""
            for i in $(seq 1 $HUMANISM_CD_DEPTH); do
                    FINDBASEDIR="../$FINDBASEDIR"
                    D=$(dir_in_tree "$FINDBASEDIR" "$*")
                    if [[ "$D" ]]; then
                           builtin cd "$D"
                           pwd > ~/.cwd
                           break
                    fi
            done
        fi
        }
        cd () {
            builtin cd "$@"
            pwd > ~/.cwd
        }
        ;;

  log)
  #
  #   create run.sh from history (source in .bash_aliases)
  #
  #   log                  show recent commands and select which are recorded
  #   log some message    append echo message to run.sh
  #   log <N>              append Nth cmd from last. e.g. `log 1` adds last cmd

        log () {
                if [ "$HUMANISM_LOG" == "" ]; then
                        echo "setting LOG=./run.sh"
                        export HUMANISM_LOG="./run.sh"
                else
                        echo "LOG FILE: $HUMANISM_LOG"
                fi
                o=$IFS
                IFS=$'\n'
                H=$(builtin history | tail -20 | head -19 | sort -r  |cut -d " " -f 3- | sed 's/^  *//' )
                if [ $# -eq 0 ]; then
                        select CMD in $H; do
                            break;
                        done;
                elif [[ $# == 1 && "$1" =~ ^[0-9]+$ ]]; then
                        CMD=$(echo "$H" | head -$1 | tail -1)
                else
                        CMD="echo -e \"$@\""
                fi
                IFS=$o
                if [ "$CMD" != "" ]; then
                        echo "CMD \"$CMD\" recorded"
                        if [ ! -f $HUMANISM_LOG ]; then
                                echo "#!/bin/bash">$HUMANISM_LOG
                        fi
                        echo "$CMD" >> $HUMANISM_LOG
                fi
                chmod u+x "$HUMANISM_LOG"
        }
        ;;

  history)
  #
  #   history with grep
  #
  #   history            list
  #   history <filter>   greped history

        history () {
                if [ $# -eq 0 ]; then
                        builtin history
                else
                        builtin history | grep $@
                fi
        }
        ;;

  ps|pskill)
  #
  #   ps with grep + killps
  #
  #   ps                            list
  #   ps <filter>                   filtered
  #   ps <filter> | killps [-SIG]   kill procs

        # export PS=`which ps`
        if [ "$OS" = "Linux" ]; then
            FOREST="--forest"
        fi
        ps () {
                if [ $# -eq 0 ]; then
                        /usr/bin/env ps $FOREST -x -o pid,uid,user,command
                else
                        /usr/bin/env ps $FOREST -a -x -o pid,uid,user,command | grep -v grep | egrep $@
                fi
        }
        killps () {
                kill $@ $(awk '{print $1}')
        }
        ;;

  find)
  #
  #   find as it should be
  #
  #   find <filter>          find *FiLtEr* anywhere under cwd
  #   find <path> <filter>   find *FiLtEr* anywhere under path path
  #   find $1 $2 $3 ...       pass through to normal find

    FOLLOWSYMLNK="-L"
    find () {
        if [ $# -eq 1 ]; then
            # If it is a directory in cwd, file list
            if [ -d "$1" ]; then
                /usr/bin/env find $FOLLOWSYMLNK "$1"
                # else fuzzy find
            else
                /usr/bin/env find $FOLLOWSYMLNK ./ -iname "*$1*" 2>/dev/null
            fi
        elif [ $# -eq 2 ]; then
            /usr/bin/env find $FOLLOWSYMLNK "$1" -iname "*$2*" 2>/dev/null
        else
            /usr/bin/env find $@
        fi
    }
    ;;

  # wifi: Linux absolutely sucks at network management. Want two devices up,
  #       forget it Here we use networkmanager from cli because gnome sucks so
  #       hard at integrating. trust me, I've RTFM'ed aplenty
  #       We'd use wicd, which is much more stable, but it cannot support
  #       multiple interfaces at once. Hence... linuxsucks.sh
  wifi)
  #
  #   it is 2115 and linux still can't dynamicly select with multi interfaces.
  #
  #   wifi         list ssid's
  #   wifi <ssid>  connect to SSID. Use passwd in db else request passwd
  #   wifi <ssid> <passwd>

        # Wifi password db
        # Currentl I only use this script to connect to test networks,
        # hence, dont care about it being in plaintext. If you do, just
        # change the code to always ask for password
    shift 1
        declare -A WIFIPASSWD
        if [ -f "$HOME/.linuxsucks_wifipasswd" ]; then
                source ~/.linuxsucks_wifipasswd
        fi
        pgrep NetworkManager 1>/dev/null || (echo "starting NetworkManager" && sudo NetworkManager)
        if [ $# -eq 0 ] || [ "$1" == "list" ]; then
                nmcli dev wifi 2>/dev/null | awk 'NR == 1; NR > 1 {print $0 | "sort -n -r -k 8"}'
        else
                echo Connecting to SSID $1
                #if [ "${!WIFIPASSWD[@]+$1}" ]; then
                #if echo "${!WIFIPASSWD[@]}" | grep -q "$1"; then
        if [ "${WIFIPASSWD[$1]+ISSET}" == "ISSET" ]; then
                        echo "Have password"
                        PASSWORD="${WIFIPASSWD["$1"]}"
                else
                        read -s -p "Password for $1 (or none): " PASSWORD
                        WIFIPASSWD["$1"]=$PASSWORD
                        declare -p WIFIPASSWD > ~/.linuxsucks_wifipasswd
                fi

                if [ "$PASSWORD" == "" ]; then
                        echo -e "\nConnecting without password"
                        sudo nmcli dev wifi connect "$1"
                else
                        echo "Connecting with password " #\"$PASSWORD\""
                        sudo nmcli dev wifi connect "$1" password "$PASSWORD"
                fi
        fi
        ;;

  usage_self)
  #
  # read $0 script and print usage. Assumes $0 structure:
  #
  #   name1)
  #   # comment line1, exactly two spaces on left margin
  #   # comment line2 (up to 10 lines)
  #   <code>

    usage_self () {
            CMD=`basename "$0"`
            echo -en "usage: $CMD "
            # 1: print argument line
            # get args                | into one line | remove )     | aling spacing  | show they OR options
            grep '^  *[^ \(\*]*)' $0 | xargs         | sed 's/)//g' | sed 's/ +/ /g' | sed 's/ /\|/g' | sed 's/--//g'
            # 2: Print arguments with documentation
            echo ""
            grep -A 10 '^  *[^ \(\*]*)' $0 | egrep -B 1 '^  #' | sed 's/#//' | sed 's/--//g'
            echo ""
    }
    ;;

  help)
    # Get usage from comments
    . $0 usage_self
    usage_self
        ;;
 esac
done