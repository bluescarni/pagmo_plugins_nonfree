#!/usr/bin/env bash

# Echo each command
set -x

# Exit on error.
set -e

CMAKE_VERSION="3.8.0"
EIGEN3_VERSION="3.3.3"
BOOST_VERSION="1.63.0"
NLOPT_VERSION="2.4.2"
PAGMO_VERSION="2.4"

if [[ ${PAGMO_PLUGINS_NONFREE_BUILD} == *36 ]]; then
	PYTHON_DIR="cp36-cp36m"
elif [[ ${PAGMO_PLUGINS_NONFREE_BUILD} == *35 ]]; then
	PYTHON_DIR="cp35-cp35m"
elif [[ ${PAGMO_PLUGINS_NONFREE_BUILD} == *34 ]]; then
	PYTHON_DIR="cp34-cp34m"
elif [[ ${PAGMO_PLUGINS_NONFREE_BUILD} == *27 ]]; then
	PYTHON_DIR="cp27-cp27mu"
else
	echo "Invalid build type: ${PAGMO_PLUGINS_NONFREE_BUILD}"
	exit 1
fi

# HACK: for python 3.x, the include directory
# is called 'python3.xm' rather than just 'python3.x'.
# This confuses the build system of Boost.Python, thus
# we create a symlink to 'python3.x'.
cd /opt/python/${PYTHON_DIR}/include
PY_INCLUDE_DIR_NAME=`ls`
# If the include dir ends with 'm', create a symlink
# without the 'm'.
if [[ $PY_INCLUDE_DIR_NAME == *m ]]; then
	ln -s $PY_INCLUDE_DIR_NAME `echo $PY_INCLUDE_DIR_NAME|sed 's/.$//'`
fi

cd
mkdir install
cd install

# CMake
wget https://github.com/Kitware/CMake/archive/v${CMAKE_VERSION}.tar.gz --no-verbose
tar xzf v${CMAKE_VERSION}
cd CMake-${CMAKE_VERSION}/
./configure > /dev/null
gmake -j2 > /dev/null
gmake install > /dev/null
cd ..

# Eigen
wget https://github.com/RLovelett/eigen/archive/${EIGEN3_VERSION}.tar.gz --no-verbose
tar xzf ${EIGEN3_VERSION}
cd eigen-${EIGEN3_VERSION}
mkdir build
cd build
cmake ../ > /dev/null
make install > /dev/null
cd ..
cd ..

# Boost (python, system, filesystem libs needed)
wget https://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION}/boost_`echo ${BOOST_VERSION}|tr "." "_"`.tar.bz2 --no-verbose
tar xjf boost_`echo ${BOOST_VERSION}|tr "." "_"`.tar.bz2
cd boost_`echo ${BOOST_VERSION}|tr "." "_"`
sh bootstrap.sh --with-python=/opt/python/${PYTHON_DIR}/bin/python > /dev/null
./bjam --toolset=gcc link=shared threading=multi cxxflags="-std=c++11" variant=release --with-python --with-system --with-filesystem -j2 install > /dev/null
cd ..

# NLopt
# NOTE: use alternative mirror as the one from the original webpage is faulty.
wget http://pkgs.fedoraproject.org/repo/pkgs/NLopt/NLopt-${NLOPT_VERSION}.tar.gz/d0b8f139a4acf29b76dbae69ade8ac54/NLopt-${NLOPT_VERSION}.tar.gz --no-verbose
tar xzf NLopt-${NLOPT_VERSION}.tar.gz
cd nlopt-${NLOPT_VERSION}
./configure --enable-shared --disable-static > /dev/null
make -j2 install > /dev/null
cd ..

# Python deps (numpy is needed to install pygmo)
/opt/python/${PYTHON_DIR}/bin/pip install cloudpickle numpy

# pagmo & pygmo wget https://github.com/esa/pagmo2/archive/v2.4.tar.gz
wget https://github.com/esa/pagmo2/archive/v${PAGMO_VERSION}.tar.gz -O pagmo2.tar.gz --no-verbose
tar xzf pagmo2.tar.gz
cd pagmo2-${PAGMO_VERSION}
mkdir build_pagmo
cd build_pagmo
cmake ../ -DPAGMO_WITH_EIGEN3=yes -DPAGMO_WITH_NLOPT=yes -DCMAKE_BUILD_TYPE=Release
make install
cd ..
mkdir build_pygmo 
cd build_pygmo
cmake -DCMAKE_BUILD_TYPE=Release -DPAGMO_BUILD_PYGMO=yes -DPAGMO_BUILD_PAGMO=no -DPYTHON_EXECUTABLE=/opt/python/${PYTHON_DIR}/bin/python ../;
make -j2 install

# pagmo_plugins_nonfree
cd /pagmo_plugins_nonfree
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DPAGMO_BUILD_PYTHON=yes -DPAGMO_BUILD_TEST=no -DPYTHON_EXECUTABLE=/opt/python/${PYTHON_DIR}/bin/python ../;
make -j2 install

cd wheel
# Copy the installed pygmo files, wherever they might be in /usr/local,
# into the current dir.
cp -a `find /usr/local/lib -type d -iname 'pygmo_plugins_nonfree'` ./
# Create the wheel and repair it.
/opt/python/${PYTHON_DIR}/bin/python setup.py bdist_wheel
auditwheel repair dist/pygmo_plugins_nonfree* -w ./dist2
# Try to install it and run the tests.
cd /
/opt/python/${PYTHON_DIR}/bin/pip install /pagmo2/build/wheel/dist2/pygmo_plugins_nonfree*
/opt/python/${PYTHON_DIR}/bin/python -c "import pygmo_plugins_nonfree; pygmo_plugins_nonfree.test.run_test_suite(1)"

# Upload to pypi. This variable will contain something if this is a tagged build (vx.y.z), otherwise it will be empty.
#export PAGMO_RELEASE_VERSION=`echo "${TRAVIS_TAG}"|grep -E 'v[0-9]+\.[0-9]+.*'|cut -c 2-`
#if [[ "${PAGMO_RELEASE_VERSION}" != "" ]]; then
#    echo "Release build detected, uploading to PyPi."
#    /opt/python/${PYTHON_DIR}/bin/pip install twine
#	/opt/python/${PYTHON_DIR}/bin/twine upload -u ci4esa /pagmo2/build/wheel/dist2/pygmo*
#fi