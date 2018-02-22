#
# hdf5.cmake  umbrella for HDF5 package
# 21-Feb-2018  chuck@ece.cmu.edu
#

#
# config:
#  HDF5_REPO - url of git repository
#  HDF5_TAG  - tag to checkout of git
#  HDF5_TAR  - cache tar file name (default should be ok)
#
#  HDF5_BUILD_TESTING - build hdf5 testing code
#  HDF5_BUILD_EXAMPLES - build hdf5 example code
#

if (NOT TARGET hdf5)

#
# umbrella option variables
# NOTE: hdf5 guys use "develop" for their main branch, not master
#
umbrella_defineopt (HDF5_REPO 
                    "https://bitbucket.hdfgroup.org/scm/hdffv/hdf5.git"
                    STRING "HDF5 GIT repository")
umbrella_defineopt (HDF5_TAG "develop" STRING "HDF5 GIT tag")
umbrella_defineopt (HDF5_TAR "hdf5-${HDF5_TAG}.tar.gz"
     STRING "HDF5 cache tar file")

#
# build options
#
umbrella_defineopt (HDF5_BUILD_EXAMPLES "ON" BOOL "Build HDF5 example code")
umbrella_defineopt (HDF5_BUILD_TESTING "${UMBRELLA_BUILD_TESTS}" 
                                       BOOL "Build HDF5 testing code")

# generic hdf5 cmake options
set (HDF5_CMAKE_ARGS -DHDF5_BUILD_EXAMPLES=${HDF5_BUILD_EXAMPLES}
                     -DBUILD_TESTING=${HDF5_BUILD_TESTING})

#
# report config to user
#
message (STATUS "  HDF5 config:")
message (STATUS "    build examples: ${HDF5_BUILD_EXAMPLES}")
message (STATUS "    build tests: ${HDF5_BUILD_TESTING}")

#
# generate parts of the ExternalProject_Add args...
#
umbrella_download (HDF5_DOWNLOAD hdf5 ${HDF5_TAR}
                   GIT_REPOSITORY ${HDF5_REPO}
                   GIT_TAG ${HDF5_TAG})
umbrella_patchcheck (HDF5_PATCHCMD hdf5)

#
# create mercury target
#
ExternalProject_Add (hdf5
    ${HDF5_DOWNLOAD} ${HDF5_PATCHCMD}
    CMAKE_ARGS ${HDF5_CMAKE_ARGS}
    CMAKE_CACHE_ARGS ${UMBRELLA_CMAKECACHE}
    UPDATE_COMMAND ""
)

endif (NOT TARGET hdf5)
