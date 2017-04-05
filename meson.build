project('Sentry-GLib', 'c', 'vala',
        version: '1.0.0-dev')

add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi',
                      language: 'vala')

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
libsoup_dep = dependency('libsoup-2.4')
json_glib_dep = dependency('json-glib-1.0')
uuid_dep = dependency('uuid')
libunwind_dep = dependency('libunwind-generic')

subdir('src')
subdir('tests')
