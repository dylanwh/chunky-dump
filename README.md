# Installing locally


```bash
cpanm --notest --installdeps .
```

# Running with docker

```bash
docker build -t dylanwh/chunky-dump .
docker run -it dylanwh/chunky-dump --url https://some-url/ --verbose
```

# Others Notes

This will always attempt an https connection, unless a host:port combo is passed to `--connect`,
in which case it will always be plain HTTP.

Note this doesn't fully conform to any HTTP spec, it's just a simple hack to debug chunked encoding.


# Author

Dylan William Hardison <dylan@hardison.net>
