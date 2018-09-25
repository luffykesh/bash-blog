# bash-blog
Blog with (a) bash.

Dependencies:
sqlite, version > 3

usage:

set the variable [```sqlite```](https://github.com/luffykesh/bash-blog/blob/master/blog.sh#L2) to the path of your sqlite executable.

```declare sqlite=/path/to/sqlite```

make script executable: ``` chmod +x blog.sh ```

```./blog.sh -h``` to view available commands

A blog.db file is created in user's home directory.
A log file .bash_blog_log.csv is also created in user's home directory.
