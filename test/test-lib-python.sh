#!/bin/bash
#
# Functions for tests for the Python image in OpenShift.
#
# IMAGE_NAME specifies a name of the candidate image used for testing.
# The image has to be available before this script is executed.
#

THISDIR=$(dirname ${BASH_SOURCE[0]})

source "${THISDIR}/test-lib.sh"
source "${THISDIR}/test-lib-openshift.sh"

function ct_pull_or_import_postgresql() {
  if [[ "${VERSION}" == "3.11" ]]; then
    postgresql_image="quay.io/sclorg/postgresql-12-c8s"
    image_short="postgresql:12"
    image_tag="${image_short}"
  else
    postgresql_image="quay.io/centos7/postgresql-10-centos7"
    image_short="postgresql:10-centos7"
    image_tag="postgresql:10"
  fi
  # Variable CVP is set by CVP pipeline
  if [ "${CVP:-0}" -eq "0" ]; then
    # In case of container or OpenShift 4 tests
    # Pull image before going through tests
    # Exit in case of failure, because postgresql container is mandatory
    ct_pull_image "${postgresql_image}" "true"
  else
    # Import postgresql-10-centos7 image before running tests on CVP
    oc import-image "${image_short}:latest" --from="${postgresql_image}:latest" --insecure=true --confirm
    # Tag postgresql image to "postgresql:10" which is expected by test suite
    oc tag "${image_short}:latest" "${image_tag}"
  fi
}

# Check the imagestream
function test_python_imagestream() {
  local tag="-ubi7"
  if [ "${OS}" == "rhel8" ]; then
    tag="-ubi8"
  elif [ "${OS}" == "rhel9" ]; then
    tag="-ubi9"
  fi
  if [[ "${VERSION}" == *"minimal"* ]]; then
    VERSION=$(echo "${VERSION}" | cut -d "-" -f 1)
  fi
  if [[ "${VERSION}" == "3.11" ]]; then
    branch="4.2.x"
    postgresql_image="quay.io/sclorg/postgresql-12-c8s|postgresql:12"
    postgresql_version="12"
  else
    branch="master"
    postgresql_image="quay.io/centos7/postgresql-10-centos7|postgresql:10"
    postgresql_version="10"
  fi
  ct_os_test_image_stream_quickstart "${THISDIR}/imagestreams/python-${OS%[0-9]*}.json" \
                                     "https://raw.githubusercontent.com/sclorg/django-ex/${branch}/openshift/templates/django-postgresql.json" \
                                     "${IMAGE_NAME}" \
                                     'python' \
                                     'Welcome to your Django application on OpenShift' \
                                     8080 http 200 "-p SOURCE_REPOSITORY_REF=$branch -p PYTHON_VERSION=${VERSION}${tag} -p POSTGRESQL_VERSION=${postgresql_version} -p NAME=python-testing" \
                                     "$postgresql_image"
}

function test_python_s2i_app_ex_standalone() {
  ct_os_test_s2i_app "${IMAGE_NAME}" \
        "https://github.com/sclorg/s2i-python-container.git" \
        "examples/standalone-test-app" \
        "Hello World from standalone WSGI application!"
}

function test_python_s2i_app_ex() {
  if [[ ${VERSION} == "2.7" ]] || docker inspect ${IMAGE_NAME} --format "{{.Config.Env}}" | tr " " "\n" | grep -q "^PLATFORM=el7"; then
    django_example_repo_url="https://github.com/sclorg/django-ex.git"
  else
    django_example_repo_url="https://github.com/sclorg/django-ex.git#2.2.x"
  fi
  ct_os_test_s2i_app "${IMAGE_NAME}" \
        "${django_example_repo_url}" \
        . \
        'Welcome to your Django application on OpenShift'
}


function test_python_s2i_templates() {
  if [ -z "${EPHEMERAL_TEMPLATES:-}" ]; then
      EPHEMERAL_TEMPLATES="
https://raw.githubusercontent.com/sclorg/django-ex/master/openshift/templates/django-postgresql.json \
https://raw.githubusercontent.com/openshift/origin/master/examples/quickstarts/django-postgresql.json"
  fi
  if [[ "${VERSION}" == "3.11" ]]; then
    postgresql_image="quay.io/sclorg/postgresql-12-c8s|postgresql:12"
    postgresql_version="12"
  else
    postgresql_image="quay.io/centos7/postgresql-10-centos7|postgresql:10"
    postgresql_version="10"
  fi
  for template in $EPHEMERAL_TEMPLATES; do
      if [[ ${VERSION} == "2.7" ]] || docker inspect ${IMAGE_NAME} --format "{{.Config.Env}}" | tr " " "\n" | grep -q "^PLATFORM=el7"; then
        branch="master"
      else
        branch="2.2.x"
      fi
      ct_os_test_template_app "$IMAGE_NAME" \
                              "$template" \
                              python \
                              'Welcome to your Django application on OpenShift' \
                              8080 http 200 "-p SOURCE_REPOSITORY_REF=$branch -p PYTHON_VERSION=${VERSION} -p POSTGRESQL_VERSION=${postgresql_version} -p NAME=python-testing" \
                              "${postgresql_image}"
  done
}

# vim: set tabstop=2:shiftwidth=2:expandtab:

