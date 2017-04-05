sentry_sources = ['sentry-client.vala']
sentry_lib = library('sentry-glib', sentry_sources,
                     dependencies: [glib_dep, gobject_dep, libsoup_dep, json_glib_dep, uuid_dep, libunwind_dep])
sentry_dep = declare_dependency(link_with: sentry_lib, include_directories: include_directories('.'))
