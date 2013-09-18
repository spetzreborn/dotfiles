#!/bin/bash
#
# Made by Bjorn Bohman 2010
# With help and suggestions from Martin Viklund and Niklas Wennerstrand

# Refactorded 2013 for git

# Exit on error
# set -e

# This functions starts the script so all functions don't need to be sourced before exiting.
depends() {
	for app in $@;do
		if ! which $app > /dev/null;then
			echo "Missing program \"$app\""
			exit 1
		fi
	done
}

depends wget logger tput cp rm cat ln unlink diff host mkdir grep egrep sed fold unzip


# Variables in capital are localstuffs, the lowercase regards the remote server

# The script name
MYNAME=$(basename $0)
MYBASENAME=$(echo $MYNAME | sed 's/\.sh$//')

# Repository configuration
gitserver=github.com
gituser=spetzreborn
r_repository=dotfiles

# The absolute script name, on server, and default name.
myabsolutename=get_env.sh

# Conffile
CONFFILE=~/${MYBASENAME}.conf

# TODO TODO; uncomment arrays when .testrc is working.
FILES2COPY[0]="etc $HOME .testrc"

# TODO: Skip design goal of all in one file and source "FILES2COPY"?
# Files to be copied to various dirs. Work like:
# [dir_the_file_lives_in_in_repo] [dir_the_file_shuld_go_to] [files]

# Files to be copied from [$L_REPO/${r_repository}/$VERSION/etc] to [homedir]
#FILES2COPY[0]="etc $HOME .bashrc .bash_logout .profile .xprofile .vimrc .screenrc .bashrc.functions .bashrc.alias .inputrc .pentadactylrc .gitconfig"

# Files to be copied from [$L_REPO/${r_repository}/$VERSION/work] to [homedir]
#FILES2COPY[1]="work $HOME connect_rdp.sh"

# Files to be copied from [$L_REPO/${r_repository}/$VERSION/scripts] to [homedir]
#FILES2COPY[2]="scripts $HOME .screen_ssh.sh radio.sh"

# Files to be copied from [$L_REPO/${r_repository}/$VERSION/etc] to [$HOME/.ssh]
#FILES2COPY[3]="etc $HOME/.ssh config known_hosts_fromrepo"

# Files to be copied from [$L_REPO/${r_repository}/$VERSION/etc/.vim/plugin] to [$HOME/.vim/plugin]
#FILES2COPY[4]="etc/.vim/plugin $HOME/.vim/plugin detectindent.vim SearchComplete.vim gnupg.vim"

# Files to be copied to some other dir
# FILES2COPY[ ]=""

# Colors
RED='\033[0;31m'
BOLD_RED='\033[1;31m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
END='\033[0m'

# Values for Warnings and Info text
TPUT=$(which tput)
POSITION=$(($($TPUT cols) - 10))
TPRINT="$TPUT hpa $POSITION"
# Colors for Info and Warning texts.
INFO=$YELLOW
WARNING=$RED

FAILEDFILE=$(mktemp)
DEBUG=""
ddate=$(date +'%Y-%m-%dT%H:%M:%S')

###  Functions

# Function for wordwrapping
foldit() {
	input="$@"
	maxwidth=$(($(tput cols) - 15))
	dbg "$(eval $input)"
	if [ -z $DEBUG ];then
		eval "$input" | fold -s -w $maxwidth
	fi
}

# Function to echo out a coloured bar between sections.
bar() {
	echo -e "${BLUE}*-----------*${END}"
	}

# Function to echo out coloured stars between sections.
stars() {
	echo -e "${BOLD_RED}*************${END}"
	}

# Function to echo out "ok" after a check
ok() {
	$TPRINT; echo -e "${GREEN}[OK]${END}"
	}

# Function to echo out "failed" after a check, and exit
failed() {
	$TPRINT; echo -e "${WARNING}[FAILED]${END}"
	echo -e "${WARNING}$@${END}"
	cat $FAILEDFILE
	dbg "$*" "FAILED FILE:" $(cat $FAILEDFILE)
	exit 1 
	}
	
# Non Critical failed.
ncfailed() {
	$TPRINT; echo -e "${WARNING}[FAILED]${END}"
	if [ ! -z $1 ]; then
		foldit echo -e "INFO: $@"
	fi
	}
	
# Debug function
dbg() {
	if [ X"$DEBUG" = X"1" ];then
		logger -t $0 DEBUG:: -s " $*"
		echo "$(date) $0 DEBUG:: $*" >>$DEBUGLOG
	fi
	}

# TODO: Make report() get host from conffile?

# Reports to webbserver
# Takes arguments in:  var0=value0 var1=value1
report() {
	dbg "${FUNCNAME}() was called."
	i=0
	args=$#
	while [ $args -gt $i ];do
		awn="${awn}$1&"
		shift
		((i++))
	done
	doReport='wget "http://internetz.se/get_env/report.php" -q -O /dev/null --post-data "
date=$(date +'%Y-%m-%dT%H:%M:%S')&
hostname=$HOSTNAME&
user=$USER&
version=$VERSION&
myname=$MYNAME&
L_REPO=$L_REPO&
NEW_FILES=$NEW_FILES&
UPDATED_FILES=$UPDATED_FILES&
CREATED_DIRS=$CREATED_DIRS&
${awn}"'
	echo -n "Reporting to webbserver"
	if eval $doReport; then
		ok
		dbg "Reported to webbserver"
	else
		ncfailed
	fi
}

error_exit() {
#	----------------------------------------------------------------
#	Function for exit due to fatal program error
#	Accepts 1 argument:
#	string containing descriptive error message
#	----------------------------------------------------------------
	dbg "${FUNCNAME}() was called."
	echo -e "${WARNING}${MYNAME}: ${1:-"Unknown Error"}${END}" 1>&2
	dbg  "${MYNAME}: ${1:-"Unknown Error"}"
	report "error=$1"
	exit 1
}

# Helpmeny when invoked with -h
helpmeny() {
cat <<EOF
"Useage: ./$0 arguments"
	options:
	-h	 This helptext
	-r repo  Dir to create and download repo to, default same name as my filename ($MYBASENAME)
	-d	 Debug - shows whats happening and saves debuglog in the form /tmp/$MYBASENAME.debuglog.2011-10-21T10:42:37.XXXXXXXXX
	-l	If debug is used, use this file as debuglog.

EOF
	exit 0
}


# Files that shall be copied
# Arg: dir_in_repo dir_to_be_moved_to _files_
copy_files() {
	dbg "${FUNCNAME}() was called, arg: $*"
	from_dir=$1
	shift
	to_dir=$1
	shift
# Test if $to_dir exists
	create_dir $to_dir

	for file in $*
	do
# If the destfile exist ...
		if [ -f ${to_dir}/${file} ]; then 
# .. diff it with the source file .. This magic diff ignore the two svn meta information lines, or comments. Both .vimrc and bash comments.
			if ! diff -q -I '^# .*' -I '^" .*' $L_REPO/${r_repository}/$from_dir/$file ${to_dir}/$file >/dev/null 2>&1; then
# .. And if it is not the same, copy to backup file:
				foldit echo -n "Found difference in ${to_dir}/${file}, making backup"
				if [ $(echo $file | cut -c1) == "." ];then
					if cp ${to_dir}/${file} ${to_dir}/${file}.old; then
						ok
						dbg "Backed up: ${to_dir}/${file}"
					else
						ncfailed
					fi
				else
					if cp ${to_dir}/${file} ${to_dir}/.${file}.old; then
						ok
						dbg "Backed up: ${to_dir}/${file}"
					else
						ncfailed
					fi
				fi
# .. Copy the new file
				foldit echo -n "Copy new ${to_dir}/$file"
				if cp $L_REPO/${r_repository}/$from_dir/$file ${to_dir}/$file; then
					ok
					dbg "Updated file: ${to_dir}/$file copied ok"
					UPDATED_FILES="${UPDATED_FILES}$file "
				else
					failed
				fi
			else
				dbg "$file are up to date"
			fi
# If the to_file dose not exist, just copy it.
		else
			foldit echo -n "Copy new ${to_dir}/$file"
			if cp $L_REPO/${r_repository}/$from_dir/$file ${to_dir}/$file >/dev/null 2>&1; then
				ok
				dbg "New file: ${to_dir}/$file copied ok"
				NEW_FILES="${NEW_FILES}$file "
			else
				failed
			fi
		fi
	done
}

# Number of variables that is supposed to be in confile, is used to check if new conffile will be written
gen_conffile() {
	dbg "${FUNCNAME}() was called, arg: $*"
	CONFFILECONTENT="\
# Path to local repo
L_REPO=$L_REPO
# Running version, master or other branch. 
VERSION=${VERSION:-"master"}"

	CONFFILEVARIBLES=$(echo "$CONFFILECONTENT" | egrep -c '^[^#]')
}

# Change the values in $CONFFILE
# Arg: variable value
change_conf() {
	dbg "${FUNCNAME}() was called, arg: $*"
	sed -i "s/\($1 *= *\).*/\1$2/" $CONFFILE
}


write_conffile() {
	dbg "${FUNCNAME}() was called, arg: $*"
	foldit echo -n "Saving default configuration in $CONFFILE"
	if echo "$CONFFILECONTENT" > $CONFFILE;then
		ok
	else
		failed "Could not write $CONFFILE"
	fi
}

# Creates a directory
create_dir() {
	dbg "${FUNCNAME}() was called, arg: $*"
	DIR=$1
	dbg "Test if $DIR exists"
	if [ ! -d $DIR ];then
		foldit echo -n "Creating dir $DIR"
		if mkdir -p $DIR;then
			dbg "Created $DIR"
			ok
			CREATED_DIRS="${CREATED_DIRS}$DIR "
		else
			failed "Failed to create $DIR"
		fi
	fi
}
### End of functions


# Make tput work in screen
if [ $TERM = screen ];then
	TERM=xterm
	dbg "\$TERM was screen, setting it to xterm for running in this script"
fi


while getopts ":hdr:l:" opt; do
	case $opt in
		r)	
		L_REPO=$(readlink -f $OPTARG)
		;;	
		d)
		DEBUG=1
		echo "Debug is set, saving debuglog to: $DEBUGLOG"
		;;
		l)
		DEBUGLOG=$(readlink -f $OPTARG)
		;;
		h) 
		helpmeny 
		;;	
		\?) 
		echo "Invalid option: -$OPTARG" >&2
		exit 1
		;;	
		:)	
		echo "Option -$OPTARG requires an argument." >&2
		exit 1
		;;	
	esac
done

# Only create a debuglog if there is not one.
if [ -n $DEBUG ];then
	if [ -z $DEBUGLOG ];then
		DEBUGLOG=$(mktemp /tmp/${MYBASENAME}.debuglog.${ddate}.XXXXXXXXX)
	fi
fi

# TODO: Fix gitvariables for verbose
dbg "I have started, read variables and functions and are on line:$LINENO"
dbg "Variables I have: "
dbg "\$MYNAME: $MYNAME"
dbg "\$gituser: $gituser"
dbg "\$gitserver: $gitserver"
dbg "\$r_repository: $r_repository"
dbg "\$L_REPO: $L_REPO"
# Call dbg() for all values in array $FILES2COPY
i=0
for array in "${FILES2COPY[@]}";do
	dbg "\$FILE2COPY[$i]: $array"
	((i++))
done
dbg "\$DEBUG:$DEBUG"
dbg "\$DEBUGLOG: $DEBUGLOG"

# Check for internet connection
dbg "Checking for internet connection . . ."
INETCON=$(host $gitserver)
INETERR=$?
dbg "Checked internet connection by 'host $gitserver' answer:${INETCON}"
if [ "$INETERR" != "0" ];then
	error_exit "No internet connection or none functional dns. Exiting"
fi

# Verify write permissions in homedir
if [ ! -w ~ ];then
	error_exit "Have no write permissions in $(echo ~)"
fi


# If argument -r was not given, set default $L_REPO to absolute path
if [ X"$L_REPO" == X"" ]; then
	L_REPO="$(echo ~/${MYBASENAME})"
	dbg 'Setting defult $L_REPO to absolut path: ' "$L_REPO"
fi

# gen_conffile() must be run before attempting to compare conffiles, but after $L_REPO is set.
gen_conffile
# Checks if conffile exists and have read and write permissions.
if [ -f $CONFFILE ];then
	if [ ! -w $CONFFILE ] || [ ! -r $CONFFILE ];then
		error_exit "No read or write permissions for $CONFFILE"
	fi
# Sanitize conffile so that only '^[A-Z_]+=[A-Za-z0-9/_~.]+$' and '^#' line exists. TODO: Only variables that we want?
	if BadContent=$(egrep -v -e '^[A-Z_]+=[A-Za-z0-9/_~.]+$' -e '^#' $CONFFILE);then
		dbg "$CONFFILE is not sanitized: $BadContent"
		error_exit "$CONFFILE contains bad things: $BadContent"
	fi
# Matches variables in default conffile and conffile. Only counts VARIABLE_NAME=variable. Variables must be set
	if [ "$(egrep -c '^[^#]' $CONFFILE)" -eq "$CONFFILEVARIBLES" ]; then
		dbg "Conffile ($CONFFILE) ok, using it."
	else
# Pre source conffile, to be able to use settings from the old conffile.
		. $CONFFILE
# Regenerate conffile, using sourced values.
		gen_conffile
		dbg "Pre sourced conffile: $CONFFILE"
		dbg "$CONFILE has not the same numer of values as built in, overwriting using the values from pre sourced conffile."
# Create configfile
		write_conffile
	fi
else
	dbg "\$CONFFILE ($CONFILE) does not exist, creating."
	write_conffile
fi

# Source conffile.
foldit echo -n "Loading configuration in $CONFFILE"
if . $CONFFILE;then
	ok
	dbg "Sourced conffile: $CONFFILE"
else
	failed "Could not source conffile: $CONFFILE"
fi

# Some verbose things
foldit echo ""
foldit echo "Using $L_REPO as repo."
foldit echo "Using version: $VERSION "

# Create download and unpack dir
DOWNLOADDIR=$(mktemp -d /tmp/${MYBASENAME}.XXXXXX)
DOWNLOADEDFILE="${DOWNLOADDIR}/${r_repository}_${VERSION}.zip"
create_dir ${DOWNLOADDIR}/unpack/
# Download zip from github
echo ""
	bar
	foldit echo -n "Downloading remote repository as zipfile."
	if [ X"$DEBUG" == X"" ];then
		if wget https://${gitserver}/${gituser}/${r_repository}/archive/${VERSION}.zip -O ${DOWNLOADEDFILE} -q; then
			ok
			dbg "Downloaded ${DOWNLOADEDFILE}"
		else
			failed "Clould not download zipfile"
		fi
	else
		if wget https://${gitserver}/${gituser}/${r_repository}/archive/${VERSION}.zip -O ${DOWNLOADEDFILE}.zip; then
			ok
			dbg "Downloaded ${DOWNLOADEDFILE}"
		else
			failed "Clould not download zipfile"
		fi
	fi

# Unzip
unzip ${DOWNLOADEDFILE} -d ${DOWNLOADDIR}/unpack/

# TODO: Better smarter move?
# Move files to unpack/
create_dir ${L_REPO}/${r_repository}
mv ${DOWNLOADDIR}/unpack/${r_repository}-${VERSION}/* ${L_REPO}/${r_repository}

# Test if there was a change in get_env.sh - and is needed to be run again.
# Need absolute name in from file, so it truly can make variable name.
# This diff dose not care about svn metadatalines or comments.
if ! diff -q -I '^# .*'  ~/$MYNAME ${L_REPO}/${r_repository}/${myabsolutename} >/dev/null 2>&1; then
	echo -e "" 
	foldit echo -e '${INFO}Found newer	 $MYNAME ${END}'
	foldit echo -en "Replacing	   $(echo ~)/${MYNAME}"
	if cp ${L_REPO}/${r_repository}/${myabsolutename} ~/${MYNAME}; then
		ok
		dbg "Replaced ${MYNAME} with newer succesfully."
	else
		failed "Could not copy the file ${myabsolutename} to ${MYNAME}"
	fi
	foldit echo -e '${INFO}Executing new $(echo ~)/${MYNAME}${END}'
	bar
	echo
	echo 
	stars
	echo 
	echo
# Makes next script start with debug if this instance was started with debug.
	if [ X"$DEBUG" == X"1" ];then
		if [ -f $DEBUGLOG ];then
			exec ~/${MYNAME} -r "$L_REPO" -d -l "$DEBUGLOG"
		else
			exec ~/${MYNAME} -r "$L_REPO" -d
		fi
	else
		exec ~/${MYNAME} -r "$L_REPO"
	fi
fi

# Creates dirs
create_dir $HOME/sshfs
# Makes a directory for local files in $L_REPO/local
create_dir $L_REPO/local 


# TODO: Fix where files will be copyied from
exit 0
# Call copy_files() for all values in array $FILES2COPY
for array in "${FILES2COPY[@]}";do
	copy_files $array
done

# Send to debug which files where new or updated
dbg "\$NEW_FILES: $NEW_FILES"
dbg "\$UPDATED_FILES: $UPDATED_FILES"


# Specific host configuration
# TODO: Have non yet.

# Special things for new or updated files:
for file in $NEW_FILES $UPDATED_FILES; do
	case $file in
		 .bashrc)
# There was a change in .bashrc and need to source.
			echo ""
			foldit echo -e '${INFO}Noticed change in $(echo ~)/.bashrc${END}'
			echo ""
			foldit echo -e '${INFO}You need to source .bashrc to get the new functions in this shell${END}'
			foldit echo "eg:  . ~/.bashrc"
			bar
			PROMPT_SOURCE=yes
			;;
		.bashrc.*)
# There was a change in one of .bashrc.{files} and need to source .bashrc 
			if [ X"$PROMPT_SOURCE" == X"" ]; then
				foldit echo ""
				foldit echo -e '${INFO}Noticed change in $(echo ~)/${file}${END}'
				foldit echo ""
				foldit echo -e '${INFO}You need to source .bashrc to get the new functions in this shell${END}'
				foldit echo "eg:  . ~/.bashrc"
				bar
				PROMPT_SOURCE=yes
			fi
		;;
	esac
done

# # Special things for new files:
# for file in $NEW_FILES; do
#	case $file in
#	)
#	;;
#	esac
# done
# 
# # Special things for updated files:
# for file in $UPDATED_FILES; do
#	case $file in
#	)
#	;;
#	esac
# done

if [ X"" == X"$NEW_FILES" ] && [ X"" == X"$UPDATED_FILES" ];then
	foldit echo "No new or changed files."
fi

# Report to webbserver my status
report

# Cleanup
# TOOD: remove downloaded zipfile

dbg "cat $FAILEDFILE: " $(cat $FAILEDFILE)

if [ -f $FAILEDFILE ];then
	rm $FAILEDFILE 
	dbg "Removed $FAILEDFILE"
fi

# End
dbg "End of script, debuglog saved in $DEBUGLOG"
foldit echo -e '${INFO}The environment is now up to date.${END}'
