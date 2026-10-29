# Local example

Applies circuit-pihole to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

Pi-hole runs under Podman inside that container, so the host container is privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The first apply takes a few minutes: it installs Podman, pulls Pi-hole's image and builds gravity from two blocklists. The second plan says `No changes.` To ask the new Pi-hole something, use the `dig` that ships in its image:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 \
  podman exec pihole dig +short @127.0.0.1 doubleclick.net nas.home.arpa example.com
```

`doubleclick.net` comes back as `0.0.0.0`, `nas.home.arpa` as `192.168.1.20` and `example.com` as its real address. The web interface listens on port 8080 inside the container; the example's password is `correct-horse-battery`, which you'd never keep on a real host.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
