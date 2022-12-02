#!/bin/bash

#printf "COMM		USER		PID		READB		WRITEB		RATER		RATEW		DATE\\n"
comm_regex='.*'
# Intialize min_pid to zero to avoid checking if defined
min_pid=0
# Intialize max_pid (used my -M option) to maximum PID possible
max_pid=$(cat /proc/sys/kernel/pid_max)
user_name='.*'
min_date=0
max_date=99999999999999
sort_field=6
sort_order="-r"
proc_numb=
usage_str=

is_numb()
{
	[[ $1 =~ ^[0-9]+$ ]]
}

while getopts :c:s:e:u:m:M:p:rw opt
do
	case $opt in
	c)	comm_regex="$OPTARG";;
	s)	min_date=$(date -d "$OPTARG" +%s);;
	e)	max_date=$(date -d "$OPTARG" +%s);;
	u)	if ! id "$OPTARG" &>/dev/null; then
			printf "rwstat: Invalid user name: $OPTARG\n" >&2
			exit 1
		fi
		user_name="$OPTARG";;
	m)	if ! is_numb $OPTARG; then
			printf "rwstat: Invalid pid: $OPTARG\n" >&2
			exit 1
		fi
		min_pid=$OPTARG;;
	M)	if ! is_numb $OPTARG; then
			printf "rwstat: Invalid pid: $OPTARG\n" >&2
			exit 1
		fi
		max_pid=$OPTARG;;
	p)	if ! is_numb $OPTARG; then
			printf "rwstat: Invalid process number: $OPTARG\n" >&2
			exit 1
		fi
		proc_numb=$OPTARG;;
	r)	sort_order="";;
	w)	sort_field=7;;
	\?)	printf "Usage: $0: [-c comm_name] [-s min_date] args\n"
		exit 1;;
	esac
done

shift $(($OPTIND - 1))

if [[ "$max_pid" -lt "$min_pid" ]]; then
	printf "rwstat: Max pid is smaller than min pid\n" >&2
	exit 1
fi

if ! [[ -v 1 ]]; then
	printf "rwstat: No interval specified\n" >&2
	exit 1
elif ! is_numb $1; then
	printf "rwstat: Invalid read interval: $1\n" >&2
	exit 1
fi

interval=$1

procs=$(ps h -eo user,pid,comm \
	| awk -v uname="$user_name" -v comm="$comm_regex" -v mindate="$min_date" \
	-v maxdate="$max_date" -v minpid="$min_pid" -v maxpid="$max_pid" \
	'{
	if (system("test -a /proc/"$2) == 0){
		"date -r /proc/"$2" +\"%s\"" | getline etimes 
		if (($1 ~ uname) && ($3 ~ comm) && $2 >= minpid && $2 <= maxpid && etimes >= mindate && etimes <= maxdate)\
			print $2
		}
	}'
 )

declare -A rchar_stat
declare	-A wchar_stat
format_str="%-17.16s%-12s%10s%13s%13s%10s%10s%15s\n"

read_io_field()
{
	#awk -v field="$1" 'field {printf $2; exit}' $io_file
	grep $1 $io_file | cut -d " " -f 2
}

calc_rate_field()
{
	arrentry="${2}_stat[$1]"
	temp=$(read_io_field $2 )
	echo "scale=2; ($temp - ${!arrentry}) / $3" | bc
	arrentry=$temp
}

for proc_id in $procs;
do
	io_file="/proc/$proc_id/io"
	if [[ -r "$io_file" ]]; then
		rchar_stat["$proc_id"]=$(read_io_field "rchar" )
		wchar_stat["$proc_id"]=$(read_io_field "wchar" )
	else
		rchar_stat["$proc_id"]=0
		wchar_stat["$proc_id"]=0
	fi
done

sleep "$interval"

output="$(for proc_id in $procs;
do
	io_file="/proc/$proc_id/io"
	if [[ -r "$io_file" ]]; then
		rchar_rate=$(calc_rate_field "$proc_id" "rchar" $interval)
		wchar_rate=$(calc_rate_field "$proc_id" "wchar" $interval)
	else
		rchar_rate=0
		wchar_rate=0
	fi
	if [[ -f "$io_file" ]]; then
		info=($(ps h -p $proc_id -o user,pid,comm))
		start_date=$(date -r /proc/$proc_id +"%b %d %R")
		printf "$format_str" ${info[2]} ${info[0]} ${info[1]} ${rchar_stat[$proc_id]} ${wchar_stat[$proc_id]} $rchar_rate $wchar_rate "$start_date"
	fi
done | sort "$sort_order" -gk "$sort_field")"

printf "$format_str" COMM USER PID READB WRITEB RATER RATEW DATE
if ! [[ -z "$proc_numb" ]]; then
	echo "$output" | head -n "$proc_numb"
else
	echo "$output"
fi
