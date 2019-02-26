#!/bin/sh

set -e

aportsdir_base=${APORTSDIR}
repodir_base=${REPODIR}

repo=${1:-backports}


# Disable stack protection to improve performance

CFLAGS="-fno-stack-protector -fomit-frame-pointer -march=x86-64 -mtune=generic"
sudo sed -i "s/export CFLAGS=\".*\"/export CFLAGS=\"${CFLAGS}\"/" /etc/abuild.conf

echo "/etc/abuild.conf:"
head -n4 /etc/abuild.conf


# Overwrite make setting if provided

if [ ! -z "${JOBS}" ]; then
  sudo sed -i "s/export JOBS=.*/export JOBS=${JOBS}/" /etc/abuild.conf
fi

echo "/etc/abuild.conf:"
grep CFLAGS /etc/abuild.conf
grep JOBS /etc/abuild.conf
echo


# Normalize directory variables

basedir=.
if [ ${repo} != $(basename ${repo}) ]; then
  APORTSDIR=${APORTSDIR}/$(dirname ${repo})
  REPODIR=${REPODIR}/$(dirname ${repo})
  basedir=$(dirname ${repo})
  repo=$(basename ${repo})
fi
echo "APORTSDIR: ${APORTSDIR}"
echo "REPODIR: ${REPODIR}"
echo "target repository: ${repo}"
echo "base directory: ${basedir}"
echo

if [ ! -d ${SRCDIR}/${basedir}/${repo} ]; then
  echo "${repo} is not present. Skipping."
  exit 0;
fi


# Generate temporary private key if not present

if [ ! -f ${PACKAGER_PRIVKEY} ]; then
  abuild-keygen -a -i -n

  # Re-sign packages if private key is updated
  index=$(find ${REPODIR} -name APKINDEX.tar.gz || true)
  if [ -f "${index}" ]; then
    rm -f ${index}
    apk index -o ${index} `find $(dirname ${index}) -name '*.apk'`
    abuild-sign -k /home/builder/.abuild/*.rsa ${index}
  fi
fi


# Register existing local repositories

find ${repodir_base} -name APKINDEX.tar.gz | while read path; do
  arch_path=$(dirname ${path})
  repo_path=$(dirname ${arch_path})
  echo "${repo_path}" | sudo tee -a /etc/apk/repositories
done


# Build packages

mkdir -p ${aportsdir_base}
mkdir -p ${REPODIR}
cp -r ${SRCDIR}/* ${aportsdir_base}

sed -e 's/arch="noarch"/arch="all"/' -i `find ${aportsdir_base} -name APKBUILD`
sed -e 's/:noarch//' -i `find ${aportsdir_base} -name APKBUILD`

sudo apk update

(cd ${basedir} && \
  set -o pipefail && \
  buildrepo ${repo} -d ${REPODIR} -a ${APORTSDIR} 2>&1 | \
    grep --line-buffered \
      -v -e "([0-9]*/[0-9]*) Purging " \
      -v -e "([0-9]*/[0-9]*) Installing " \
      -v -e "remote: Counting objects: " \
      -v -e "remote: Compressing objects: " \
      -v -e "Receiving objects: " \
      -v -e "Resolving deltas: ")


# Re-sign packages

index=$(find ${REPODIR}/${repo} -name APKINDEX.tar.gz || true)
if [ ! -f "${index}" ]; then
  exit 1
fi
rm -f ${index}
apk index -o ${index} `find $(dirname ${index}) -name '*.apk'`
abuild-sign -k /home/builder/.abuild/*.rsa ${index}
