pkg_name=omnitruck-poller
pkg_origin=chef-es
pkg_version="0.1.0"
pkg_maintainer="Chef Engineering Services <eng-services@chef.io>"
pkg_license=('Apache-2.0')

pkg_deps=(
  $HAB_ORIGIN/omnitruck
  core/coreutils
)

do_build() {
  return 0
}

do_install() {
  fix_interpreter "$(pkg_path_for $HAB_ORIGIN/omnitruck)/app/poller" core/coreutils bin/env
}
