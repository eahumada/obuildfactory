#!/bin/bash
#

PROJECT_NAME=openjdk8

export LC_ALL=C
export LANG=C

export DROP_DIR="$HOME/DROP_DIR"
mkdir -p $DROP_DIR

function cacerts_gen()
{
  local DESTCERTS=$1
  local TMPCERTSDIR=`mktemp -d`
  
  pushd $TMPCERTSDIR
  curl -L http://curl.haxx.se/ca/cacert.pem -o cacert.pem
  cat cacert.pem | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{ print $0; }' > cacert-clean.pem
  rm -f cacerts cert_*
# split  -p "-----BEGIN CERTIFICATE-----" cacert-clean.pem cert_
  csplit -k -f cert_ cacert-clean.pem "/-----BEGIN CERTIFICATE-----/" {*}

  for CERT_FILE in cert_*; do
    ALIAS=$(basename ${CERT_FILE})
    echo yes | keytool -import -alias ${ALIAS} -keystore cacerts -storepass 'changeit' -file ${CERT_FILE} || :
    rm -f $CERT_FILE
  done

  rm -f cacert.pem cacert-clean.pem
  mv cacerts $DESTCERTS

  popd
  rm -rf $TMPCERTSDIR
}

function ensure_ant()
{
  if [ ! -x $DROP_DIR/ant/bin/ant ]; then
    mkdir -p $DROP_DIR/ant
    pushd $DROP_DIR/ant
    curl -L http://mirrors.ircam.fr/pub/apache/ant/binaries/apache-ant-1.8.4-bin.tar.gz -o apache-ant-1.8.4-bin.tar.gz
    tar xzf apache-ant-1.8.4-bin.tar.gz
    mv apache-ant-1.8.4/* .
    rmdir apache-ant-1.8.4
    rm -f apache-ant-1.8.4-bin.tar.gz
    popd
  fi

  export PATH=$DROP_DIR/ant/bin:$PATH
}

ensure_cacert()
{
  if [ ! -f $DROP_DIR/cacerts ]; then
    echo "no cacerts found, regenerate it..."
    cacerts_gen $DROP_DIR/cacerts
  else
    if test `find "$DROP_DIR/cacerts" -mtime +7`
    then
      echo "cacerts older than one week, regenerate it..."
      cacerts_gen $DROP_DIR/cacerts
    fi
  fi
}

function check_version()
{
    local version=$1 check=$2
    local winner=$(echo -e "$version\n$check" | sed '/^$/d' | sort -nr | head -1)
    [[ "$winner" = "$version" ]] && return 0
    return 1
}

function ensure_freetype()
{
  FT_VER=`freetype-config --ftversion`
  check_version "2.3" $FT_VER

  if [ $? == 0 ]; then

    if [ ! -d $DROP_DIR/freetype ]; then
      pushd $DROP_DIR
      curl -L http://freefr.dl.sourceforge.net/project/freetype/freetype2/2.4.10/freetype-2.4.10.tar.bz2 -o freetype-2.4.10.tar.bz2
      tar xjf freetype-2.4.10.tar.bz2
      cd freetype-2.4.10
      mkdir -p $DROP_DIR/freetype
      ./configure --prefix=$DROP_DIR/freetype
      make 
      make install
      popd
    fi

    export ALT_FREETYPE_LIB_PATH=$DROP_DIR/freetype/lib
    export ALT_FREETYPE_HEADERS_PATH=$DROP_DIR/freetype/include

  fi
}

#
# Under RHEL/CentOS/Fedora, switch to dynamic linking for C++
# Andrew from RH recommand it for all Gnu/Linux distributions
#
function set_stdcpp_mode()
{
  if [ `uname` = "Linux" ]; then
      export STATIC_CXX=false
  fi
}

#
# Ensure cacerts are available
#
ensure_cacert

#
# Ensure Ant is available
#
ensure_ant

#
# Ensure freetype is correct one 
# 
ensure_freetype

#
#
#
set_stdcpp_mode

if [ -z "$MILESTONE" ]; then
  MILESTONE=`hg tags | grep lambda | head -n 1 | sed 's/lambda//' | cut -d ' ' -f 1 | sed 's/^-//'`
fi

echo "Calculated MILESTONE=$MILESTONE"

DATE_BUILD_NUMBER=`date +%Y%m%d`
CPU_BUILD_ARCH=`uname -p`

export BUILD_NUMBER="$DATE_BUILD_NUMBER"
export MILESTONE="$MILESTONE"
export JDK_BUNDLE_VENDOR="OBuildFactory project"
export BUNDLE_VENDOR="OBuildFactory project"

if [ "$CPU_BUILD_ARCH" = "x86_64" ]; then

    if [ -d /opt/obuildfactory/jdk-1.7.0-openjdk-x86_64 ]; then
      ALT_BOOTDIR=/opt/obuildfactory/jdk-1.7.0-openjdk-x86_64
    else
      echo "missing required Java 7, aborting..."
    fi
    
else

  if [ -d /opt/obuildfactory/jdk-1.7.0-openjdk-i686 ]; then
    ALT_BOOTDIR=/opt/obuildfactory/jdk-1.7.0-openjdk-i686
  else
    echo "missing required Java 7, aborting..."
  fi

fi

NUM_CPUS=`grep "processor" /proc/cpuinfo | sort -u | wc -l`

export LD_LIBRARY_PATH=
export JAVA_HOME=
export ALLOW_DOWNLOADS=true
export ALT_CACERTS_FILE=$DROP_DIR/cacerts
export ALT_BOOTDIR=$ALT_BOOTDIR
export ALT_DROPS_DIR=$DROP_DIR
export HOTSPOT_BUILD_JOBS=$NUM_CPUS
export PARALLEL_COMPILE_JOBS=$NUM_CPUS
export ANT_HOME=$ANT_HOME

make sanity
make all


if [ "$CPU_BUILD_ARCH" = "x86_64" ]; then
  
  if [ -x build/linux-amd64/j2sdk-image/bin/java ]; then
    build/linux-amd64/j2sdk-image/bin/java -version
    pushd build/linux-amd64
    mkdir -p $DROP_DIR/$PROJECT_NAME
    tar cjf $DROP_DIR/$PROJECT_NAME/j2sdk-image-$CPU_BUILD_ARCH.tar.bz2 j2sdk-image
    tar cjf $DROP_DIR/$PROJECT_NAME/j2re-image-$CPU_BUILD_ARCH.tar.bz2 j2re-image
    popd
  else
    echo "can't find java, build failed" 
    exit -1
  fi

else

  if [ -x build/linux-i586/j2sdk-image/bin/java ]; then
    build/linux-i586/j2sdk-image/bin/java -version
    pushd build/linux-i586
    mkdir -p $DROP_DIR/$PROJECT_NAME
    tar cjf $DROP_DIR/$PROJECT_NAME/j2sdk-image-$CPU_BUILD_ARCH.tar.bz2 j2sdk-image
    tar cjf $DROP_DIR/$PROJECT_NAME/j2re-image-$CPU_BUILD_ARCH.tar.bz2 j2re-image
    popd
  else
    echo "can't find java, build failed" 
    exit -1
  fi

fi