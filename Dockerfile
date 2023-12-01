FROM devspaces/udi-rhel8:3.9 as devspaces

# FROM registry.access.redhat.com/ubi8/s2i-base:latest
FROM docker.io/brandnewbox/cola-ruby26-centos:v7

ENV \
    HOME=/home/user

USER root

EXPOSE 3000

COPY --from=devspaces $HOME/.config/containers/storage.conf $HOME/.config/containers/storage.conf
COPY --from=devspaces /entrypoint.sh /entrypoint.sh
COPY --from=devspaces $REMOTE_SOURCES $REMOTE_SOURCES_DIR
COPY --from=devspaces /usr/local/bin/docker /usr/local/bin/docker
COPY --from=devspaces /usr/bin/podman-wrapper.sh /usr/bin/
COPY --from=devspaces /etc/containers /etc/containers/
COPY --from=devspaces /usr/bin/podman.orig /usr/bin/

RUN RUBY_PKGS="ruby-devel rubygem-rake rubygem-bundler" && \
    NODE_PKGS="nodejs" && \
    IMAGEMAGICK_PKGS="autoconf libpng-devel libjpeg-devel librsvg2" && \
    STATIC_MAP_PKGS="python3 platform-python-devel python3-cairo" && \
    GEOS_PKGS="geos-devel libffi-devel proj-devel" && \
    OTHER_PKGS="libcurl-devel rubygem-mysql2 mariadb-connector-c mariadb-connector-c-devel rubygem-psych libyaml-devel libtool readline sudo" && \
    dnf update -y && \
    dnf -y --disableplugin=subscription-manager module enable ruby:2.6 && \
    dnf -y --disableplugin=subscription-manager module enable container-tools && \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    dnf -y --disableplugin=subscription-manager --setopt=tsflags=nodocs install \
    $RUBY_PKGS \
    $NODE_PKGS \
    $IMAGEMAGICK_PKGS \
    $STATIC_MAP_PKGS \
    $GEOS_PKGS \
    $OTHER_PKGS && \
    dnf autoremove -y && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

RUN gem install rvm && \
    sudo gpg2 --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB && \ 
    curl -sSL https://get.rvm.io | sudo bash -s stable && \
    source /etc/profile.d/rvm.sh && \
    echo "rvm mount command running..." && \
    /usr/local/rvm/bin/rvm mount -r https://rvm.io/binaries/centos/8/x86_64/ruby-3.1.3.tar.bz2 # && \
    # /usr/local/rvm/bin/rvm alias create default ruby-3.1.3

# Compile ImageMagick 6 from source.
RUN cd /tmp/ && \
    wget https://imagemagick.org/archive/releases/ImageMagick-6.9.12-89.tar.xz && \
    tar -xf ImageMagick-6.9.12-89.tar.xz && \
    cd ImageMagick-6.9.12-89 && \
    ./configure --prefix=/usr --disable-docs && \
    make install && \
    cd $WORKDIR && \
    rm -rvf /tmp/ImageMagick*

# The StaticMaps generator
RUN pip3 install py-staticmaps

 # add user and configure it
 RUN useradd -u 1000 -G wheel,root,rvm -d /home/user --shell /bin/bash -m user && \
    # Setup $PS1 for a consistent and reasonable prompt
    echo "export PS1='\W \`git branch --show-current 2>/dev/null | sed -r -e \"s@^(.+)@\(\1\) @\"\`$ '" >> "${HOME}"/.bashrc && \
    # Change permissions to let any arbitrary user
    mkdir -p /projects && \
    for f in "${HOME}" "/etc/passwd" "/etc/group" "/projects" "/usr/share/gems"; do \
        echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
        chmod -R g+rwX ${f}; \
    done && \
    # Generate passwd.template
    cat /etc/passwd | \
    sed s#user:x.*#user:x:\${USER_ID}:\${GROUP_ID}::\${HOME}:/bin/bash#g \
    > ${HOME}/passwd.template && \
    cat /etc/group | \
    sed s#root:x:0:#root:x:0:0,\${USER_ID}:#g \
    > ${HOME}/group.template

RUN \
    ## Rootless podman install #2: install podman buildah skopeo e2fsprogs (above)
    ## Rootless podman install #3: tweaks to make rootless buildah work
    touch /etc/subgid /etc/subuid  && \
    chmod g=u /etc/subgid /etc/subuid /etc/passwd  && \
    echo user:10000:65536 > /etc/subuid  && \
    echo user:10000:65536 > /etc/subgid && \
    ## Rootless podman install #4: adjust storage.conf to enable Fuse storage.
    sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf && \
    mkdir -p /var/lib/shared/overlay-images /var/lib/shared/overlay-layers; \
    touch /var/lib/shared/overlay-images/images.lock; \
    touch /var/lib/shared/overlay-layers/layers.lock && \
    ## Rootless podman install #5: but use VFS since we were not able to make Fuse work yet...
    # TODO switch this to fuse in OCP 4.12?
    mkdir -p "${HOME}"/.config/containers && \
    (echo '[storage]';echo 'driver = "vfs"') > "${HOME}"/.config/containers/storage.conf && \
    ## Rootless podman install #6: rename podman to allow the execution of 'podman run' using
    ##                             kubedock but 'podman build' using podman.orig
    # mv /usr/bin/podman /usr/bin/podman.orig && \
    # set up go/bin folder
    mkdir /home/user/go/bin -p

# A last pass to make sure that an arbitrary user can write in $HOME
RUN mkdir -p /home/user && chgrp -R 0 /home && chmod -R g=u /home

ENTRYPOINT [ "/entrypoint.sh" ]
WORKDIR /projects
CMD tail -f /dev/null