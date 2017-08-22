# docker-agent

ssh auth forwarding to work around current limitations in Docker for Mac.

It will hopefully become irrelevant when this issue closes:
https://github.com/docker/for-mac/issues/410

### TL;DR

``` bash
# don't just trust me
docker run --rm dobbs/docker-agent

# invoke it
docker run --rm dobbs/docker-agent | bash -ux

# enjoy your new-found, key-based ssh access
docker run \
  --volume docker-agent-tmp:/tmp \
  --env SSH_AUTH_SOCK=/tmp/ssh-auth-sock \
  buildpack-deps:xenial \
  ssh -T git@github.com
```

# Remember to lock the door before you leave:

``` bash
# let the --rm flag from docker run destroy the container
docker stop docker-agent

# also worth explicitly removing the named volume
# if only to see which other containers have it mounted  :-)
docker volume rm docker-agent-tmp
```

# how it works

The image has sshd, a script, and /tmp exposed as a volume.

When you invoke the image with no other arguments, it shows you the
script.

When you eval that script:

1. any previous containers named `docker-agent` are removed
2. a new container named `docker-agent` launches `sshd`
3. docker will create (or reuse) a volume named `docker-agent-tmp`
4. an ssh tunnel is opened to the `sshd` with auth forwarding
   enabled, and the auth socket is symlinked to `/tmp/ssh-auth-sock`

Because the image exposes `/tmp` as a volume, and because the ssh
tunnel creates a socket in that volume, other containers can mount the
volume to socket for their own auth forwarding for as long as the
tunnel remains open.

Run your container with `--volume docker-agent-tmp:/tmp` and
`--env SSH_AUTH_SOCK=/tmp/ssh-auth-sock` to enable ssh auth forwarding
for any processes inside your container.

# how it breaks

If you're doing The Right Thing, you've created an application user in
your container rather than run everything as `root`.  Sadly, The Right
Thing is always more work.

The ssh tunnel in step 4 creates a socket owned by `root`.  Your
container's app user doesn't have read access.  There are ways to fix
it.  Here are some examples:

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
