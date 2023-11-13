FROM devspace/udi-rhel8:3.9

USER root

EXPOSE 3000

RUN RUBY_PKGS="ruby-devel rubygem-rake rubygem-bundler" && \
    NODE_PKGS="nodejs" && \
    IMAGEMAGICK_PKGS="autoconf libpng-devel libjpeg-devel librsvg2" && \
    STATIC_MAP_PKGS="python3 platform-python-devel python3-cairo" && \
    GEOS_PKGS="geos-devel libffi-devel proj-devel" && \
    dnf update -y && \
    dnf -y --disableplugin=subscription-manager module enable ruby:2.6 && \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    dnf -y --disableplugin=subscription-manager --setopt=tsflags=nodocs install \
    $RUBY_PKGS \
    $NODE_PKGS \
    $IMAGEMAGICK_PKGS \
    $STATIC_MAP_PKGS \
    $GEOS_PKGS && \
    dnf autoremove -y && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

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

# Copy extra files to the image.
COPY ./root/ /


# A last pass to make sure that an arbitrary user can write in $HOME
RUN mkdir -p /home/user && chgrp -R 0 /home && chmod -R g=u /home

ENTRYPOINT [ "/entrypoint.sh" ]
WORKDIR /projects
CMD tail -f /dev/null