Docker & chroot working notes
*****************************

.. contents::
   :depth: 2
   :local:

..
  systemd Linux (Ubuntu Vivid); you can also do a lot of this on OS X
  Docker installed using a headless VirtualBox
  general approach
    build images using Docker (i.e., Linux containers)
    flatten them
    clusters run them with chroot (not containers)
  be aware of the security implications of Docker, in particular:
    Docker daemon and commands run as root
      anyone who can interact with Docker can trivially escalate to root on the host (http://reventlov.com/advisories/using-the-docker-command-to-root-the-host)
    images can contain bad stuff
      recommend use of official DockerHub repositories only
     Docker installation docs recommend piping web pages directly to your shell without inspection
       this is really stupid
       the script contains further invocations of web pages as root
       instead, download it, audit/harden, then run
     Docker entry points run as root by default
       don't run your science apps as root

  Step 1: install Docker
    Docker directions are at: http://docs.docker.com/linux/started/
      best to put this inside a VM, e.g. VirtualBox
      directions are for Linux, should be straightforward for OS X and Windows as well, but you won't be able to test under chroot
    download and save install script from https://get.docker.com
      audit it, especially $sh_c calls
    run it
      check output
      do not add user to docker group, as this will allow passwordless escalation to root
    check files it dropped (e.g., /etc/apt/sources.list.d/docker.list)

  Step 2: configure Docker
    Docker will install a service, which is started during installation
    examine what it did to the networking
      $ ifconfig (note docker0 interface)
      $ brctl show (note docker0 bridge)
      $ route -n
    verify that the service does not start automatically at boot
      $ systemctl is-enabled docker
      enabled
      $ systemctl disable docker
      $ systemctl is-enabled docker
      disabled
    the service does not work behind a proxy
      $ sudo docker run hello-world
      Unable to find image 'hello-world:latest' locally
      Pulling repository hello-world
      Get https://index.docker.io/v1/repositories/library/hello-world/images: dial tcp 54.152.161.54:443: connection refused
    configure an override file http-proxy.conf as documented at https://docs.docker.com/articles/systemd/
      or, /etc/default/docker? doesn't work for `-g`
    run the hello world image
      $ docker run hello-world
      [...]
      Hello from Docker.
      This message shows that your installation appears to be working correctly.
      [...]

   Step 3: build your own image
     write dockerfile with dependencies
     pull in user info from host
     entry point which drops privileges
       note that Charliecloud chroot does not use the Docker entry point
     do not install your app into the docker image (too volatile); use a volume
     start with `python` image, based on Debian Jessie, latest Python 3.4 from python.org

   Step 4: test app in Docker (1-node)
     run hello.py
     for your real app, this is a good place to run its test suite
     we try to make Docker behavior effectively identical to Charliecloud chroot behavior, but there might be edge cases. why do this?
       speed iteration by avoiding flattening step
       make it possible to prototype on non-Linux systems (but be aware of limitations on what you can export into the container)

   Step 5: flatten it
     $ ch-docker2tar

   Step 6: test it in Charliecloud chroot (1-node)
     $ ch-tar2img
     $ ch-mount
     $ ch-activate
     run test suite
     $ exit
     $ ch-umount

   Step 7: upload to Kugel and run multi-node
