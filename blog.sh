#!/bin/bash
sqlite=/opt/local/bin/sqlite3;
ERR_NOSQLITE=1;
ERR_TOUCH_DB_FILE=2;
ERR_CREATE_TABLE=3;
ERR_PARSE=4;
PERMISSIONEXIT=200;
HELPEXIT=201;
ERR=255;
BOLD_TEXT="\e[1m";
RESET_TEXT_FMT="\e[0m";
DB_FILE=$HOME"/blog.db";
POST_EXPORT_FILE=$HOME"/Desktop/post.csv";
CATEGORY_EXPORT_FILE=$HOME"/Desktop/category.csv";
LOG_FILE=$HOME"/.bash_blog_log.csv";

SELECT_POST_QUERY="INSERT INTO post(timestamp,title,content,category_id) VALUES((SELECT strftime('%%s','now')),'%s','%s',(SELECT id from category where category.name='%s'));";
ADD_CATEGORY_QUERY="INSERT INTO category(name) VALUES('%s');";
CATEGORY_EXISTS_NAME_QUERY="SELECT EXISTS(SELECT name FROM category WHERE category.name='%s');";
CATEGORY_EXISTS_ID_QUERY="SELECT EXISTS(SELECT id FROM category WHERE category.id=%d);";
SELECT_POSTS_QUERY="SELECT post.id as Id,  strftime('%d/%m/%Y %H:%M:%S',post.timestamp,'unixepoch','localtime') as Timestamp,post.title as Title,post.content Content, category.name as Category FROM post LEFT JOIN category ON post.category_id=category.id "
ORDER_DESC="ORDER BY post.timestamp DESC"
SELECT_CATEGORY_QUERY="SELECT id as Id, name as Name from category;";
POST_EXISTS_ID_QUERY="SELECT EXISTS(SELECT id FROM post where id=%d);";

if [[ ! -f $sqlite ]] || [[ ! -x $sqlite ]]; then
	echo "sqlite not found/not enough permission" >&2 ;
	exit $ERR_NOSQLITE;
fi

log(){
	if [[ ! -f "$LOG_FILE" ]]; then
		if ! touch $LOG_FILE; then
			echo "Error creating log file" >&2;
			return 255;
		fi
		echo "timestamp,message,message" >> "$LOG_FILE";
	fi
	if [[ ! -w "$LOG_FILE" ]]; then
		echo "No write permission to log file" >&2;
		return 255;
	fi;
	local logtext
	logtext=$(date)",";
	while [[ $# != 0 ]]; do
		logtext=$logtext"\"$1\""','; #generate csv
		shift;
	done
	echo "$logtext" >> "$LOG_FILE";
}

initdb(){
	local err;
	#check directory w permission
	if [[ ! -w  "$HOME" ]]; then
		echo "Not enough permissions" >&2;
		log "No Write permissions in $HOME directory";
		exit $PERMISSIONEXIT;
	fi

	if [[ ! -f "$DB_FILE" ]]; then
		
		if ! touch "$DB_FILE"; then
			echo "ERROR CREATING DATABASE" >&2 ;
			log "Cannot create db file";
			exit $ERR_TOUCH_DB_FILE;
		fi
		err=$(
			$sqlite "$DB_FILE" \
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
			);"  2>&1;
		)
		if [[ $? != 0 ]]; then
			echo "ERROR CREATING TABLE" >&2 ;
			rm "$DB_FILE";
			log "error creating table" "$err";
			exit $ERR_CREATE_TABLE;
		fi

	else
		#check db file rw permission
		if [[ ! -r "$DB_FILE" || ! -w "$DB_FILE"  ]]; then
			echo "Not enough permissions" >&2;
			log  "no rw permission to DB file";
			exit $PERMISSIONEXIT;
		fi
	fi
}

show_help(){
	printf "\e[1mCommand%10cDescription\e[0m\n" " ";
}

post(){
	local cmd title content category search_key edit_what new_value query err;
	while [[ $# != 0 ]]; do
	case "$1" in
		list ) shift;list "all" "$@";
			;;
		add ) shift; cmd=1; title="$1"; shift; content="$1"; shift;
			;;
		export ) shift; cmd=2;
			;;
		edit ) shift; cmd=3; post_id=$1;shift; edit_what="$1";shift; new_value=$1;shift;
			;;
		delete ) shift; cmd=4; post_id=$1;shift;
			;;
		--category ) shift; category="$1"; shift;
			;;
		search ) shift; search_key="$1"; shift; list "search" "$search_key" "$@";
			;;
		* ) echo "Invalid option: $1"; show_help; exit $HELPEXIT;
			;;
	esac
	done;

	if [[ $cmd == 1 ]]; then #if add
		if [[ -z "$title" ]]; then
			echo "Title cannot be empty" >&2;
			exit $ERR;
		fi
		if [[ ! -z "$category" ]]; then #if category is not zero length
			printf -v query "$CATEGORY_EXISTS_NAME_QUERY" "$category";
			if [[ $($sqlite "$DB_FILE" "$query") == 0 ]]; then 
				printf -v query "$ADD_CATEGORY_QUERY" "$category";
				#create new category if does not exists
				if $sqlite "$DB_FILE" "$query" > /dev/null 2>&1; then 
					printf "New category: \e[1m%s\e[0m created\n" "$category";
				fi
			fi
		fi
		printf -v query "$SELECT_POST_QUERY" "$title" "$content" "$category";
		err=$($sqlite "$DB_FILE" "$query" 2>&1;) #insert post
		if [[ $? == 0 ]]; then
			echo "Post successfull";
		else 
			echo "Post Failed" >&2;
			log "Post add failed" "$err";
			exit $ERR;
		fi
	elif [[ $cmd == 2 ]]; then #export posts to file
		err=$($sqlite "$DB_FILE" ".headers ON" ".mode csv" ".once $POST_EXPORT_FILE" "$SELECT_POSTS_QUERY $ORDER_DESC" 2>&1);
		if [[ $? == 0 ]]; then
			echo "Posts exported to $POST_EXPORT_FILE";
		else
			echo "Error exporting." >&2;
			log "Error exporting posts" "$err";
		fi
	elif [[ $cmd == 3 ]]; then #edit
		if [[ -z "$post_id" ]] || [[ ! "$post_id" =~ ^[[:digit:]]+$ ]]; then
			echo "Invalid post_id: $post_id" >&2;
			exit $ERR_PARSE;
		fi
		printf -v query "$POST_EXISTS_ID_QUERY" "$post_id";
		if [[ $($sqlite "$DB_FILE" "$query") == 0 ]]; then
			echo "Post does not exist" >&2;
			exit $ERR;
		fi

		unset query;
		if [[ "$edit_what" == "title" ]]; then #edit title
			if [[ -z "$new_value" ]]; then
				echo "Title cannot be empty" >&2;
				exit $ERR;
			fi
			printf -v query "UPDATE post SET title='%s' WHERE id=%d" "$new_value" "$post_id";
		elif [[ "$edit_what" == "content" ]]; then #edit content
			printf -v query "UPDATE post SET content='%s' WHERE id=%d" "$new_value" "$post_id";
		elif [[ "$edit_what" == "category" ]]; then #edit category
			if [[ -z "$new_value" ]] || [[ ! "$new_value" =~ ^[[:digit:]]+$ ]]; then
				echo "Invalid category id: $new_value" >&2;
				exit $ERR_PARSE;
			fi
			printf -v query "$CATEGORY_EXISTS_ID_QUERY" "$new_value";
			if [[ $($sqlite "$DB_FILE" "$query") == 0 ]]; then
				echo "Category does not exist" >&2;
				exit $ERR;
			fi
			printf -v query "UPDATE post SET category_id=%d WHERE id=%d" "$new_value" "$post_id";
		else
			echo "Invalid edit field" >&2;
			exit $ERR;
		fi
		if [[ ! -z "$query" ]]; then #if query is not zero length
			err=$($sqlite "$DB_FILE" "$query");
			if [[ $? == 0 ]]; then
				echo "Post update successfull";
			else 
				echo "Post update FAILED" >&2;
				log "Post update failed" "$err";
				exit $ERR;
			fi
		fi
	elif [[ $cmd == 4 ]]; then # if delete post
		
		if [[ -z "$post_id" ]] || [[ ! "$post_id" =~ ^[[:digit:]]+$ ]]; then
			echo "Invalid post_id: $post_id" >&2; #error is invalid post id
			exit $ERR_PARSE;
		fi
		printf -v query "$POST_EXISTS_ID_QUERY" "$post_id";
		if [[ $($sqlite "$DB_FILE" "$query") == 0 ]]; then
			echo "Post does not exist" >&2; #error if post does not exist
			exit $ERR;
		fi
		printf -v query "DELETE from post where id=%d" "$post_id";
		err=$($sqlite "$DB_FILE" "$query" );
		if [[ $? == 0 ]]; then
			echo "Post delete successfull";
		else
			echo "Post delete failed" >&2;
			log "Post delete failed " "$err"
			exit $ERR;
		fi
	fi
}

list(){
	local list_all=1;
	local temp query  opt_search  search_key  offset count;
	local desc_query=$SELECT_POSTS_QUERY$ORDER_DESC;
	while [[ $# != 0 ]]; do
	case "$1" in
		all ) list_all=1; shift;
			;;
		search ) shift; opt_search=1; search_key="$1"; shift;
			;;
		--offset ) shift; offset="$1"; shift;
			;;
		--count ) shift; count="$1"; shift;
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
	printf "\e[1mID.%2cDate%17cTitle%17cContent%15cCategory\e[0m\n" ' ' ' ' ' ' ' ';
	$sqlite "$DB_FILE" ".mode column" ".width 3 19 20 20 20 20" "$query";
	exit;
}

category(){
	local cmd cat_name cat_id post_id query err list new_value err;
	cmd=0;
	while [[ $# != 0 ]]; do
		case "$1" in
			add ) shift; cmd=1; cat_name="$1";shift;
				;;
			list ) shift; cmd=2;
				;;
			assign ) shift; cmd=3; post_id="$1"; shift; cat_id="$1"; shift;
				;;
			export ) shift; cmd=4;
				;;
			edit ) shift; cmd=5; cat_id="$1";shift; new_value="$1";shift;
				;;
			* ) echo "Invalid option: " "$1"; exit $ERR_PARSE;
				;;
		esac
	done

	if [[ $cmd == 1 ]]; then #add category
		if [[ -z "$cat_name" ]]; then
			echo "Invalid category name" >&2;
			exit ERR_PARSE;
		fi
		printf -v query "$ADD_CATEGORY_QUERY" "$cat_name";
		err=$($sqlite "$DB_FILE" "$query" 2>&1);
		if [[ $? == 0 ]]; then
			echo "Error creating category" >&2;
			exit $ERR;
		else
			echo "Category added successfull";
		fi
	elif [[ $cmd == 2 ]]; then #list category
		list=$($sqlite "$DB_FILE" ".mode column" ".width 3 20" "$SELECT_CATEGORY_QUERY" 2>&1);
		if [[ $? != 0 ]]; then
			echo "Error retriving from database" >&2;
			log "Error reading categories" "$list";
			exit $ERR;
		fi
		printf "\e[1mID%3cName\e[0m\n" ' ';
		echo "$list";
	elif [[ $cmd == 3 ]]; then #assign category
		if [[ -z "$post_id" ]] || [[ ! "$post_id" =~ ^[[:digit:]]+$ ]]; then
			echo "Invalid Post id: $post_id"  >&2;
			exit $ERR_PARSE;
		fi
		if [[ -z "$cat_id" ]] || [[ ! "$cat_id" =~ ^[[:digit:]]+$ ]]; then
			echo "Invalid Category id: $cat_id" >&2;
			exit $ERR_PARSE;
		fi
		printf -v query "UPDATE post SET category_id=%d where id=%d and EXISTS(SELECT id FROM category WHERE category.id=%d)" "$cat_id" "$post_id" "$cat_id";
		err=$($sqlite "$DB_FILE" "$query" 2>&1;)

		if [[ $? == 0 ]]; then
			echo "ID assigned";
		else
			echo "ID assign failed" >&2;
			log "category assign failed" "$err";
			exit $ERR;
		fi
	elif [[ $cmd == 4 ]]; then #export categories to file
		err=$($sqlite "$DB_FILE" ".headers ON" ".mode csv" ".once $CATEGORY_EXPORT_FILE" "$SELECT_CATEGORY_QUERY" 2>&1);
		if [[ $? == 0 ]]; then
			echo "Categories exported to $CATEGORY_EXPORT_FILE";
		else
			echo "Error exporting." >&2;
			log "Error exporting categories to file" "$err";
			exit $ERR;
		fi
	elif [[ $cmd == 5 ]]; then #edit category name
		if [[ -z "$cat_id" ]] || [[ ! "$cat_id" =~ ^[[:digit:]]+$ ]]; then
			echo "Invalid Category Id: $cat_id" >&2;
			exit $ERR_PARSE;
		fi
		printf -v query "$CATEGORY_EXISTS_ID_QUERY" "$cat_id";
		if [[ $($sqlite "$DB_FILE" "$query") == 0 ]]; then
			echo "Category does not exist" >&2;
			exit $ERR;
		fi
		printf -v query "UPDATE category SET name='%s' where id=%d" "$new_value" "$cat_id";
		err=$($sqlite "$DB_FILE" "$query" 2>&1);
		if [[ $? == 0 ]]; then
			echo "Category update successfull";
		else 
			echo "Category update FAILED" >&2;
			log "Category update failed" "$err";
			exit $ERR;
		fi
	fi
}

parse_params(){
	while [[ $# != 0 ]]; do
		case "$1" in
			-h | --help ) show_help;exit;
				;;
			post ) shift; post "$@"; exit;
				;;
			category ) shift; category "$@"; exit;
				;;
			* ) printf "Invalid argument \e[1m%s\e[0m\n" "$1"; show_help;exit $HELPEXIT;
				;;
		esac
	done;
}

if [[ $# == 0 ]]; then
	echo "Bash-Blog: Blogging with (a) bash!"; #pun intended
	exit;
fi

initdb;
parse_params "$@";