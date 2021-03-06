#!/bin/bash
readonly sqlite=/opt/local/bin/sqlite3;
readonly ERR_NOSQLITE=1;
readonly ERR_TOUCH_DB_FILE=2;
readonly ERR_CREATE_TABLE=3;
readonly ERR_PARSE=4;
readonly PERMISSIONEXIT=200;
readonly HELPEXIT=201;
readonly ERR=255;
readonly DB_FILE=$HOME"/blog.db";
readonly POST_EXPORT_FILE=$HOME"/Desktop/post.csv";
readonly CATEGORY_EXPORT_FILE=$HOME"/Desktop/category.csv";
readonly LOG_FILE=$HOME"/.bash_blog_log.csv";

readonly INSERT_POST_QUERY="INSERT INTO post(timestamp,title,content,category_id) VALUES((SELECT strftime('%%s','now')),'%s','%s',(SELECT id from category where category.name='%s'));";
readonly SELECT_POSTS_QUERY="SELECT post.id as Id,  strftime('%d/%m/%Y %H:%M:%S',post.timestamp,'unixepoch','localtime') as Timestamp,post.title as Title,post.content Content, category.name as Category FROM post LEFT JOIN category ON post.category_id=category.id "
readonly ORDER_POST_DESC="ORDER BY post.timestamp DESC"
readonly POST_EXISTS_ID_QUERY="SELECT EXISTS(SELECT id FROM post where id=%d);";

readonly ADD_CATEGORY_QUERY="INSERT INTO category(name) VALUES('%s');";
readonly CATEGORY_EXISTS_NAME_QUERY="SELECT EXISTS(SELECT name FROM category WHERE category.name='%s');";
readonly CATEGORY_EXISTS_ID_QUERY="SELECT EXISTS(SELECT id FROM category WHERE category.id=%d);";
readonly SELECT_CATEGORY_QUERY="SELECT id as Id, name as Name from category;";



log(){
	if [[ ! -f "$LOG_FILE" ]]; then
		if ! touch "$LOG_FILE"; then
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
if [[ ! -f $sqlite ]] || [[ ! -x $sqlite ]]; then
	echo "sqlite not found/not enough permission" >&2 ;
	log "sqlite not found or no execute permission";
	exit $ERR_NOSQLITE;
else 
	sqlite_version=$($sqlite $DB_FILE "select sqlite_version()");
	if [[ $sqlite_version < 3 ]]; then
		echo "Please upgrade to sqlite version > 3" >&2;
		log "sqlite version error" "version found: $sqlite_version";
		exit $ERR_NOSQLITE;
	fi
fi

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
			#sqlite version < 3 does not support create if exists
			$sqlite "$DB_FILE" "\
			CREATE TABLE IF NOT EXISTS category(\
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
			);" 2>&1;
		)
		if [[ $? != 0 ]]; then
			echo "ERROR CREATING TABLE" >&2 ;
			rm "$DB_FILE";
			log "error creating table" "$err";
			exit $ERR_CREATE_TABLE;
		else 
			log "created database";
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
	printf "
blog \e[1mpost\e[0m|\e[1mcategory\e[0m|\e[1m--help\e[0m|\e[1m-h\e[0m

  \e[1mpost\e[0m \e[1madd\e[0m|\e[1mlist\e[0m|\e[1medit\e[0m|\e[1mdelete\e[0m|\e[1msearch\e[0m|\e[1mexport\e[0m
      \e[1madd\e[0m - add a new post
          add \e[4mtitle\e[0m \e[4mcontent\e[0m [--category \e[4mcategory_name\e[0m]
              \e[4mtitle\e[0m - title of the post (must not be empty)
            \e[4mcontent\e[0m - content of the post 
           \e[4mcategory\e[0m - add a tag of category_name to post
      \e[1mlist\e[0m - view posts, sorted by latest post first
          list [--offset \e[4moffset_value\e[0m] [--count \e[4mmax_count\e[0m]
             offset - exclude first \e[4moffset_value\e[0m number of posts
              count - display a maximum of \e[4mmax_count\e[0m posts
      \e[1medit\e[0m - edit a post
          edit \e[4mpost_id\e[0m \e[1mtitle\e[0m|\e[1mcontent\e[0m|\e[1mcategory\e[0m \e[4mnew_value\e[0m
            \e[4mpost_id\e[0m - Id of the post to edit
            If category is to be edited \e[4mnew_value\e[0m should be a valid category id.
      \e[1mdelete\e[0m - delete a post
          delete \e[4mpost_id\e[0m
            \e[4mpost_id\e[0m - id of the post to delete
      \e[1msearch\e[0m - search a keyword in post's title or content
          search \e[4msearch_key\e[0m [--offset \e[4moffset_value\e[0m] [--count \e[4mmax_count\e[0m]
            \e[4msearch_key\e[0m - string to search
      \e[1mexport\e[0m - export all posts in csv format
          A 'post.csv' file is saved to Desktop.

  \e[1mcategory\e[0m \e[1madd\e[0m|\e[1mlist\e[0m|\e[1massign\e[0m|\e[1medit\e[0m|\e[1mexport\e[0m
      \e[1madd\e[0m - add a new category
          \e[1madd\e[0m \e[4mcategory_name\e[0m
            \e[4mcategory_name\e[0m - Name of the new category
      \e[1mlist\e[0m - list all categories
      \e[1massign\e[0m - assign a category to a post
          assign \e[4mpost_id\e[0m \e[4mcategory_id\e[0m
            Assigns new category to post corresponding \e[4mpost_id\e[0m
      \e[1medit\e[0m - edit a category's name
          edit \e[4mcategory_id\e[0m \e[4mcategory_name\e[0m 
            assign \e[4mcategory_name\e[0m to post corresponding to \e[4mcategory_id\e[0m
      \e[1mexport\e[0m - export all categories in csv format
          A 'category.csv' file is saved to Desktop.

  \e[1m-h\e[0m,\e[1m--help\e[0m - View this message.

"
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
		printf -v query "$INSERT_POST_QUERY" "$title" "$content" "$category";
		err=$($sqlite "$DB_FILE" "$query" 2>&1;) #insert post
		if [[ $? == 0 ]]; then
			echo "Post successfull";
		else 
			echo "Post Failed" >&2;
			log "Post add failed" "$err";
			exit $ERR;
		fi
	elif [[ $cmd == 2 ]]; then #export posts to file
		err=$($sqlite -header -csv "$DB_FILE" ".once $POST_EXPORT_FILE" "$SELECT_POSTS_QUERY $ORDER_POST_DESC" 2>&1);
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
	local temp query  opt_search  search_key  offset count category;
	local desc_query=$SELECT_POSTS_QUERY$ORDER_POST_DESC;
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
		--category ) shift; category="$1"; shift;
			;;
		* ) shift; list_all=1;
			;;
	esac
	done;

	if [[ $opt_search == 1 ]]; then
		if [[ ! -z "$search_key" ]]; then
			printf -v query "%s WHERE post.title LIKE '%%%s%%' or post.content LIKE '%%%s%%' %s " "$SELECT_POSTS_QUERY" "$search_key" "$search_key" "$ORDER_POST_DESC";
		else
			query=$desc_query;
		fi
	elif [[ $list_all == 1 ]]; then
		query=$desc_query;
	fi

	#validate if count is given, is an integer
	if [[ ! -z "$count" ]] && [[ ! "$count" =~ ^[[:digit:]]+$ ]]; then
				echo "Invalid count" "$count" >&2;
				exit $ERR_PARSE;
	fi
	#validate if offset is give, is an integer
	if [[ ! -z "$offset" ]] && [[ ! "$offset" =~ ^[[:digit:]]+$ ]]; then
				echo "Invalid offset" "$offset" >&2;
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
	$sqlite -column "$DB_FILE" ".width 3 19 20 20 20 20" "$query";
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
		list=$($sqlite -column "$DB_FILE" ".width 3 20" "$SELECT_CATEGORY_QUERY" 2>&1);
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
		err=$($sqlite -header -csv "$DB_FILE" ".once $CATEGORY_EXPORT_FILE" "$SELECT_CATEGORY_QUERY" 2>&1);
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
	printf "\e[1mBash-Blog\e[0m: Blogging with (a) bash!"; #pun intended
	echo;
	exit;
fi

initdb;
parse_params "$@";