#!/bin/bash
sqlite=/opt/local/bin/sqlite3;
ERR_NOSQLITE=1;
ERR_TOUCH_DB_FILE=2;
ERR_CREATE_TABLE=3;
ERR_PARSE=4;
PERMISSIONEXIT=254;
HELPEXIT=255;
DB_FILE="blog.db";
POST_QUERY="INSERT INTO post(timestamp,title,content,category_id) VALUES((SELECT strftime('%%s','now')),'%s','%s',(SELECT id from category where category.name='%s'));";
ADD_CATEGORY_QUERY="INSERT INTO category(name) VALUES('%s');";
CATEGORY_EXISTS_QUERY="SELECT EXISTS(SELECT name FROM category WHERE category.name='%s');";
SELECT_POSTS_QUERY="SELECT post.id,  strftime('%d/%m/%Y %H:%M:%S',post.timestamp,'unixepoch','localtime') as timestamp,post.title,post.content, category.name as category FROM post LEFT JOIN category ON post.category_id=category.id "
ORDER_DESC="ORDER BY post.timestamp DESC"

if [[ ! -f $sqlite ]] || [[ ! -x $sqlite ]]; then
	echo "sqlite not found/not enough permission" >&2 ;
	exit $ERR_NOSQLITE;
fi

initdb(){

	#check directory w permission
	if [[ ! -w  . ]]; then
		echo "Not enough permissions" >&2;
		exit $PERMISSIONEXIT;
	fi

	if [[ ! -f $DB_FILE ]]; then
		
		if ! touch $DB_FILE; then
			echo "ERROR CREATING DATABASE" >&2 ;
			exit $ERR_TOUCH_DB_FILE;
		fi

		if ! $sqlite $DB_FILE \
			"CREATE TABLE IF NOT EXISTS category(\
			id integer PRIMARY KEY,
			name TEXT UNIQUE NOT NULL\
			);\
			CREATE TABLE IF NOT EXISTS post(\
			id INTEGER PRIMARY KEY,
			timestamp INTEGER,\
			title TEXT,\
			content TEXT,\
			category_id INTEGER,
			FOREIGN KEY(category_id) REFERENCES category(id)\
			);" > /dev/null  2>&1; then

			echo "ERROR CREATING TABLE" >&2 ;
			rm $DB_FILE;
			exit $ERR_CREATE_TABLE;
		fi

	else
		#check db file rw permission
		if [[ ! -r $DB_FILE || ! -w $DB_FILE  ]]; then
			echo "Not enough permissions" >&2;
			exit $PERMISSIONEXIT;
		fi
	fi
}

show_help(){
	printf "\e[1mCommand%10cDescription\e[0m\n" " ";
}

post(){
	while [[ $# != 0 ]]; do
	case $1 in
		list ) shift;list "all" "$@"; exit;
			;;
		add ) shift; local opt_cmdadd=1; local title=$1; local content=$2; shift 2;
				if [[ -z "$title" ]]; then
					printf "no title\n" >&2;
					show_help;exit $HELPEXIT;
				fi
			;;
		--category ) shift; local category=$1; shift;
			;;
			search ) shift; local search_key=$1; shift; list "search" "$search_key" "$@"; exit;
			;;
		* ) echo "Invalid option: $1"; show_help; exit $HELPEXIT;
			;;
	esac
	done;

	if [[ $opt_cmdadd == 1 ]]; then
		if [[ ! -z "$category" ]]; then
			printf -v query "$CATEGORY_EXISTS_QUERY" "$category";
			if [[ $($sqlite $DB_FILE "$query") == 0 ]]; then
				printf -v query "$ADD_CATEGORY_QUERY" "$category";
				if $sqlite $DB_FILE "$query" > /dev/null 2>&1; then
					printf "New category: \e[1m%s\e[0m created\n" "$category";
				fi
			fi
		fi
		printf -v query "$POST_QUERY" "$title" "$content" "$category";
		if $sqlite $DB_FILE "$query"; then
			printf "Post Successfull\n";
		else 
			printf "Post Failed\n" >&2;
		fi
	fi
	exit;
}

list(){
	# echo "$@";
	local list_all=1;
	local temp query  opt_search  search_key  offset count;
	local desc_query=$SELECT_POSTS_QUERY$ORDER_DESC;
	while [[ $# != 0 ]]; do
	case $1 in
		all ) list_all=1; shift;
			;;
		search ) shift; opt_search=1; search_key=$1; shift;
			;;
		--offset ) shift; offset=$1; shift;
			;;
		--count ) shift; count=$1; shift;
			;;
		* ) shift; list_all=1;
			;;
	esac
	done;

	if [[ $opt_search == 1 ]]; then
		if [[ ! -z "$search_key" ]]; then
			printf -v query "%s WHERE post.title LIKE '%%%s%%' or post.content LIKE '%%%s%%' %s " "$SELECT_POSTS_QUERY" "$search_key" "$search_key" "$ORDER_DESC";
		else
			query=$desc_query;
		fi
	elif [[ $list_all == 1 ]]; then
		query=$desc_query;
	fi

	#validate if count is given, is an integer
	if [[ ! -z "$count" ]] && [[ ! "$count" =~ ^[[:digit:]]+$ ]]; then
				echo "Invalid count" $count >&2;
				exit $ERR_PARSE;
	fi
	#validate if offset is give, is an integer
	if [[ ! -z "$offset" ]] && [[ ! "$offset" =~ ^[[:digit:]]+$ ]]; then
				echo "Invalid offset" $offset >&2;
				exit $ERR_PARSE;
	fi

	if [[ ! -z "$count" ]]; then
			temp=" LIMIT $count";
			query=$query$temp;
			if [[ ! -z "$offset" ]]; then
				temp=" OFFSET $offset";
				query=$query$temp;
			fi
	elif [[ ! -z "$offset" ]]; then
		temp=" LIMIT -1 OFFSET $offset";
		query=$query$temp;
	fi
	# echo "$query";
	printf "\e[1mNo.%2cDate%17cTitle%17cContent%15cCategory\e[0m\n" ' ' ' ' ' ' ' ';
	$sqlite $DB_FILE ".mode column" ".width 3 19 20 20 20 20" "$query";
	exit;
}

parse_params(){
	while [[ $# != 0 ]]; do
		case $1 in
			-h | --help ) show_help;exit;
				;;
			post ) shift; post "$@"; shift; exit;
				;;
			* ) printf "Invalid argument \e[1m%s\e[0m\n" "$1"; show_help;exit $HELPEXIT;
				;;
		esac
	done;
}

if [[ $# == 0 ]]; then
	printf "Bash-Blog: Blogging with (a) bash!\n"; #pun intended
	exit;
fi

initdb;
parse_params "$@";