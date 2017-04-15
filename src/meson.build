sentry_sources = [
    'sentry-client.vala',
    'sentry-client-generate-stacktrace.c']
sentry_lib = library('sentry-glib', sentry_sources,
                     c_args: ['-DSENTRY_CLIENT_VERSION="@0@"'.format(meson.project_version()), '-DSENTRY_CLIENT_API_VERSION="@0@"'.format(api_version)],
                     dependencies: [glib_dep, gobject_dep, libsoup_dep, json_glib_dep, uuid_dep, libunwind_dep, libdwarf_dep, libelf_dep])
sentry_dep = declare_dependency(link_with: sentry_lib, include_directories: include_directories('.'))
