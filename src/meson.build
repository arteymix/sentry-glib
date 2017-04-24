sentry_sources = [
    'sentry-client.vala',
    'sentry-context.vala',
    'sentry-user-context.vala',
    'sentry-http-context.vala']
sentry_lib = library('sentry-glib', sentry_sources,
                     c_args: ['-DSENTRY_CLIENT_VERSION="@0@"'.format(meson.project_version()), '-DSENTRY_CLIENT_API_VERSION="@0@"'.format(api_version)],
                     dependencies: [glib_dep, gobject_dep, libsoup_dep, json_glib_dep, uuid_dep, libunwind_dep])
sentry_dep = declare_dependency(link_with: sentry_lib, include_directories: include_directories('.'))
