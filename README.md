# docker-agent

ssh auth forwarding for containers.

### TL;DR

``` bash
# don't just trust me
docker run --rm dobbs/docker-agent

# invoke it
eval "$(docker run --rm dobbs/docker-agent)"

# this is leveraging ssh-agent, so maybe this too
ssh-add

# enjoy your new-found, key-based ssh access
IMAGE_OF_YOUR_CHOICE=buildpack-deps:xenial
docker run \
  --volume docker-agent-tmp:/tmp \
  --env SSH_AUTH_SOCK=/tmp/ssh-auth-sock \
  $IMAGE_OF_YOUR_CHOICE \
  ssh -T git@github.com
```

# remember to lock the door before you leave:

``` bash
# another case of look first
docker-agent-destroy

# and then leap
eval "$(docker-agent-destroy)"
```

# motivation

I have been experimenting with a pattern: I package a small collection
of shell scripts into container images for use as shell-based consoles
for supporting DevOps operations.  If you have used a rails console,
or IRB or pry in ruby, or use ipython, or lisp REPL, you'll have the
general idea of the UX.

Most of these collections need SSH access from inside the container.

An often suggested (but risky!) example:

```
docker run -v $HOME/.ssh:/home/app/.ssh SOME-UNTRUSTED-IMAGE ssh -T git@github.com
```

The risk: this untrusted image might have layers which, in addition to
their advertized function also helpfully scrape the .ssh folder to
harvest private keys and ship them to untrusted servers.

Cautious or especially security-minded developers may read the
Dockerfiles of the containers before running them, but most of us
don't really have time to audit All The Things for security.

I hope this container will become irrelevant when this issue closes:
https://github.com/docker/for-mac/issues/410

In the meantime, I will recommend people reduce the risk of exposing
private keys by useing this container or something like it.

# how it works

There are 3 essential parts:
1. sshd running inside the image
2. the /tmp folder which is exposed as a volume
3. a script to be eval'd on your mac

When you invoke the image with no other arguments, it shows you the
script.

When you eval that script:

1. a collection of bash functions are added to your shell
2. any previous containers named `docker-agent` are removed
3. a new container named `docker-agent` launches `sshd`
4. docker will create (or reuse) a volume named `docker-agent-tmp`
5. an ssh tunnel is opened to the `sshd` with auth forwarding enabled,
   and the auth socket inside the container is symlinked to
   `/tmp/ssh-auth-sock`

Step 5 there is a special piece of shell magic.  We establish a
persistent connection from MacOS into the sshd running inside the
container.  On the inside of that tunnel, that is, inside the
container we create a symlink of the SSH_AUTH_SOCK into the
volume-mounted /tmp folder.

Because the image exposes `/tmp` as a volume other containers can
mount that shared volume and thereby gain access to the symlink to
SSH_AUTH_SOCK for their own auth forwarding for as long as the tunnel
remains open.

For containers that want to use ssh, add these flags to your `docker run`:
 `--volume docker-agent-tmp:/tmp` and `--env SSH_AUTH_SOCK=/tmp/ssh-auth-sock`

# how it breaks (aka troubleshooting the docker-agent)

ssh auth forwarding needs all three of these things just right in
order to work.  If any one of them breaks, the ssh access will also
break.  That can make it feel a bit fragile.  The reader will be
rewarded for taking time to understand how the parts interact.

### `docker-agent-long-status`

check all three of the following status commands.

### `docker-agent-sshd-status`

Detects if `docker-agent` container is running.  Try
`docker-agent-sshd-start` if you find it is not running.  Might also
both `docker-agent-sshd-stop` and then start.

### `docker-agent-tunnel-status`

Detects if the ssh tunnel is still running.  Try
`docker-agent-tunnel-start` if you find the tunnel is not running.

### `docker-agent-ls-volume`

Lists the contents of the shared /tmp volume which can help diagnose
file permissions problems (see below).

### `docker-agent-destroy`

This one shows the commands that will tear down all the things.  Run
`eval "$(docker-agent-destroy)"` to tear it down.  The simplest way to
reset is maybe to nuke it from orbit and start over.

# doing The Right Thing is more work

If you're doing The Right Thing, you've created an application user in
your container rather than run everything as `root`.  Sadly, The Right
Thing is always more work.

The ssh tunnel destribed in step 5 above creates a socket owned by
`root`.  Your container's app user doesn't have read access.  There
are ways to fix it.  Here are some examples:

* kill the tunnel and create your own

    ```bash
    # make sure you're looking at the right tunnel:
    ps -x | grep SSH_AUTH_SOCK | grep -v grep

    # and then kill it:
    ps -x | grep SSH_AUTH_SOCK | grep -v grep \
      | head -1 | awk '{print $1}' | xargs kill

    # figure out your app user's UID:
    UID=$(docker run --rm \
          --entrypoint=/bin/sh YOUR_CONTAINER \
          id -u THE_APP_USER 2>/dev/null)

    # figure out which port to use
    PORT=$(docker port docker-agent 22/tcp | grep -oE '[[:digit:]]+$')

    # create your own tunnel which controls directory ownership
    ssh -f -A -p $PORT root@localhost \
      'ln -fs \$SSH_AUTH_SOCK /tmp/ssh-auth-sock; chown -R $UID \$(dirname \$SSH_AUTH_SOCK); tail -f /dev/null'"
    ```

* create a different tunnel and different socket for this container

    ```bash
    # figure out your app user's UID:
    UID=$(docker run --rm \
          --entrypoint=/bin/sh YOUR_CONTAINER \
          id -u THE_APP_USER 2>/dev/null)

    # figure out which port to use
    PORT=$(docker port docker-agent 22/tcp | grep -oE '[[:digit:]]+$')

    # create your own tunnel which controls directory ownership
    # and creates its own symlink
    ssh -f -A -p $PORT root@localhost \
      'ln -fs \$SSH_AUTH_SOCK /tmp/app-$UID-sock; chown -R $UID \$(dirname \$SSH_AUTH_SOCK); tail -f /dev/null'"

    # user the new symlink when you launch your container
    docker run \
      --volume docker-agent-tmp:/tmp \
      --env SSH_AUTH_SOCK=/tmp/app-$UID-sock \
      YOUR_CONTAINER \
      ssh -T git@github.com
    ```

# acknowledgements

A hacker can learn a lot trying to build tools around ssh auth
forwarding.  Here are a couple of fine sources for understanding how
all these parts work.

http://www.unixwiz.net/techtips/ssh-agent-forwarding.html

https://stackoverflow.com/a/26470428/1074208

A hacker can also learn a ton from the ways other hackers try to use
the tools.  Thanks to my coworkers for suffering through the rough
edges with me.
