# docker-agent

ssh auth forwarding to work around current limitations in Docker for Mac.

It will hopefully become irrelevant when this issue closes:
https://github.com/docker/for-mac/issues/410

### TL;DR

``` bash
# don't just trust me
docker run --rm dobbs/docker-agent

# invoke it
eval $(docker run --rm dobbs/docker-agent)

# confirm sshd is running
docker ps --filter=name=docker-agent

# confirm the tunnel is open
ps -x | grep SSH_AUTH_SOCK | grep -v grep

# enjoy your new-found, key-based ssh access
docker run \
  --volumes-from=docker-agent \
  --env SSH_AUTH_SOCK=/tmp/ssh-auth-sock \
  buildpack-deps:xenial \
  ssh -T git@github.com
```

# how it works

The image has sshd, a script, and /tmp exposed as a volume.

When you invoke the image with no other arguments, it shows you the
script.

When you eval that script:

1. any previous containers named `docker-agent` are removed
2. a new container named `docker-agent` launches `sshd`
3. an ssh tunnel is opened to that `sshd` with auth forwarding
   enabled, and the auth socket is symlinked to `/tmp/ssh-auth-sock`

Because the image exposes `/tmp` as a volume, and because the ssh
tunnel has created a socket and holds open a connection, other
containers can access the socket for their own auth forwarding.

Just run your container with `--volumes-from=docker-agent` and
`--env SSH_AUTH_SOCK=/tmp/ssh-auth-sock` to enable ssh auth forwarding
for any processes inside your container.
